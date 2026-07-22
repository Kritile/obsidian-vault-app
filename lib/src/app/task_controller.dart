import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/tasks/task_models.dart';
import '../core/tasks/task_notification_service.dart';
import '../core/vault/vault_models.dart';
import 'sync_controller.dart';
import 'vault_controller.dart';

class TaskController extends ChangeNotifier {
  TaskController(this._vault, this._sync, this._notifications);

  final VaultController _vault;
  final SyncController _sync;
  final TaskNotificationScheduler _notifications;
  static const _captureChannel = MethodChannel('dev.pavelvault/quick_capture');
  String? pendingExternalSelection;

  Future<String?> takeExternalSelection() async {
    if (!Platform.isAndroid) return null;
    try {
      pendingExternalSelection =
          await _captureChannel.invokeMethod<String>('takeProcessText');
    } on PlatformException {
      pendingExternalSelection = null;
    }
    final value = pendingExternalSelection;
    pendingExternalSelection = null;
    return value?.trim().isEmpty == true ? null : value?.trim();
  }

  List<TaskDefinition> get tasks => _vault.index.tasks
      .map(TaskDefinition.fromNote)
      .toList(growable: false);

  List<EmbeddedTask> get embedded => [
    for (final note in _vault.index.notes)
      if (note.type != VaultEntityType.task)
        for (final task in note.tasks) EmbeddedTask(note: note, task: task),
  ];

  Future<void> initializeNotifications() async {
    await _notifications.initialize((_) {});
    await reconcileNotifications();
  }

  Future<void> reconcileNotifications() => _notifications.reconcile(tasks);

  List<TaskDefinition> select(TaskView view, {DateTime? now}) {
    final today = taskDay(now ?? DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final values = tasks.where((task) {
      final date = task.scheduled ?? task.due;
      return switch (view) {
        TaskView.inbox => !task.completed &&
            task.project == null &&
            task.scheduled == null &&
            task.due == null,
        TaskView.today => !task.completed &&
            date != null &&
            taskDay(date) == today,
        TaskView.overdue => !task.completed &&
            task.due != null &&
            taskDay(task.due!).isBefore(today),
        TaskView.week => !task.completed &&
            date != null &&
            !taskDay(date).isBefore(weekStart) &&
            taskDay(date).isBefore(weekEnd),
        TaskView.all => !task.completed,
        TaskView.completed => task.completed,
      };
    }).toList();
    values.sort(_compare);
    return values;
  }

  bool isBlocked(TaskDefinition task) {
    final byId = {for (final item in tasks) item.id: item};
    return task.dependencies.any((id) => byId[id]?.completed != true);
  }

  Future<String> create({
    required String title,
    String? project,
    String priority = 'medium',
    DateTime? due,
    DateTime? scheduled,
    DateTime? remindAt,
    String? recurrence,
    String? description,
    String? source,
    String? daily,
    List<String> dependencies = const [],
    String? seriesId,
    String? previousOccurrence,
  }) async {
    final id = _newId();
    final folder = project == null || project.trim().isEmpty
        ? 'Tasks'
        : 'Projects/${_safeFileName(project)}';
    final path = await _uniquePath(folder, _safeFileName(title));
    final date = DateFormat('yyyy-MM-dd');
    final yamlList = dependencies.isEmpty
        ? '[]'
        : '[${dependencies.map(_yamlScalar).join(', ')}]';
    final text = '''---
type: task
id: $id
project: ${project == null ? '' : _yamlScalar(project)}
created: ${date.format(DateTime.now())}
status: todo
complete: false
priority: $priority
due: ${due == null ? '' : date.format(due)}
scheduled: ${scheduled == null ? '' : date.format(scheduled)}
remind_at: ${remindAt?.toIso8601String() ?? ''}
recurrence: ${recurrence == null ? '' : _yamlScalar(recurrence)}
series_id: ${seriesId ?? (recurrence == null ? '' : id)}
previous_occurrence: ${previousOccurrence ?? ''}
depends_on: $yamlList
daily: ${daily == null ? '' : _yamlScalar(daily)}
source: ${source == null ? '' : _yamlScalar(source)}
tags: [task]
---

# ${title.trim()}

## Описание

${description?.trim() ?? ''}

## Критерии готовности

- [ ]
''';
    await _sync.saveNote(path, text);
    await reconcileNotifications();
    notifyListeners();
    return path;
  }

  Future<void> setComplete(
    TaskDefinition task,
    bool complete, {
    bool force = false,
  }) async {
    if (complete && isBlocked(task) && !force) {
      throw StateError('Сначала завершите зависимости задачи');
    }
    var source = task.note.document.text;
    source = _vault.parser.updateFrontmatter(source, ['complete'], complete);
    source = _vault.parser.updateFrontmatter(
      source,
      ['status'],
      complete ? 'done' : 'todo',
    );
    await _sync.saveNote(task.path, source);
    if (complete && task.recurrence != null) await _createNext(task);
    await reconcileNotifications();
    notifyListeners();
  }

  Future<void> setStatus(TaskDefinition task, TaskStatus status) async {
    var source = task.note.document.text;
    final value = switch (status) {
      TaskStatus.todo => 'todo',
      TaskStatus.inProgress => 'in-progress',
      TaskStatus.blocked => 'blocked',
      TaskStatus.done => 'done',
    };
    source = _vault.parser.updateFrontmatter(source, ['status'], value);
    source = _vault.parser.updateFrontmatter(
      source,
      ['complete'],
      status == TaskStatus.done,
    );
    await _sync.saveNote(task.path, source);
    await reconcileNotifications();
    notifyListeners();
  }

  Future<void> assignProject(TaskDefinition task, String project) async {
    final source = _vault.parser.updateFrontmatter(
      task.note.document.text,
      ['project'],
      project,
    );
    await _sync.saveNote(task.path, source);
    final target =
        'Projects/${_safeFileName(project)}/${task.path.split('/').last}';
    if (target != task.path) await _sync.moveNote(task.path, target);
    await reconcileNotifications();
    notifyListeners();
  }

  Future<void> setDate(TaskDefinition task, DateTime? value) async {
    final source = _vault.parser.updateFrontmatter(
      task.note.document.text,
      ['due'],
      value == null ? null : DateFormat('yyyy-MM-dd').format(value),
    );
    await _sync.saveNote(task.path, source);
    await reconcileNotifications();
    notifyListeners();
  }

  Future<String> convertEmbedded(EmbeddedTask embedded) async => create(
    title: embedded.task.text,
    source: '[[${embedded.note.document.path.replaceFirst(RegExp(r'\.md$'), '')}]]',
  );

  Future<void> _createNext(TaskDefinition task) async {
    final recurrence = TaskRecurrence.parse(task.recurrence!);
    final basis = task.due ?? task.scheduled ?? DateTime.now();
    final next = recurrence.next(basis);
    final seriesId = task.seriesId ?? task.id;
    final alreadyExists = tasks.any(
      (item) => item.seriesId == seriesId && taskDay(item.due ?? item.scheduled ?? DateTime(0)) == next,
    );
    if (alreadyExists) return;
    await create(
      title: task.title,
      project: task.project,
      priority: task.priority,
      due: task.due == null ? null : next,
      scheduled: task.scheduled == null ? null : next,
      recurrence: task.recurrence,
      seriesId: seriesId,
      previousOccurrence: task.id,
      daily: task.daily,
      dependencies: task.dependencies,
    );
  }

  Future<String> _uniquePath(String folder, String name) async {
    var path = '$folder/$name.md';
    var suffix = 2;
    while (await _vault.read(path) != null) {
      path = '$folder/$name-$suffix.md';
      suffix++;
    }
    return path;
  }

  int _compare(TaskDefinition a, TaskDefinition b) {
    const priorities = {'high': 0, 'medium': 1, 'low': 2};
    final dateA = a.scheduled ?? a.due ?? DateTime(9999);
    final dateB = b.scheduled ?? b.due ?? DateTime(9999);
    final date = dateA.compareTo(dateB);
    if (date != 0) return date;
    return (priorities[a.priority] ?? 1).compareTo(priorities[b.priority] ?? 1);
  }

  String _newId() =>
      'task-${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}';

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'Без названия' : cleaned;
  }

  String _yamlScalar(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}
