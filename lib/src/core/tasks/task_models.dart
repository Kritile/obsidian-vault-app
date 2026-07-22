import '../vault/vault_models.dart';

enum TaskView { inbox, today, overdue, week, all, completed }

enum TaskStatus { todo, inProgress, blocked, done }

class TaskDefinition {
  const TaskDefinition({
    required this.note,
    required this.id,
    required this.status,
    required this.statusId,
    required this.priority,
    required this.dependencies,
    this.project,
    this.daily,
    this.due,
    this.scheduled,
    this.remindAt,
    this.recurrence,
    this.seriesId,
  });

  final ParsedNote note;
  final String id;
  final TaskStatus status;
  final String statusId;
  final String priority;
  final String? project;
  final String? daily;
  final DateTime? due;
  final DateTime? scheduled;
  final DateTime? remindAt;
  final String? recurrence;
  final String? seriesId;
  final List<String> dependencies;

  String get title => note.title;
  String get path => note.document.path;
  bool get completed =>
      status == TaskStatus.done || note.frontmatter['complete'] == true;

  factory TaskDefinition.fromNote(ParsedNote note) {
    final yaml = note.frontmatter;
    return TaskDefinition(
      note: note,
      id: yaml['id']?.toString().trim().isNotEmpty == true
          ? yaml['id'].toString().trim()
          : legacyTaskId(note.document.path),
      status: switch (yaml['status']?.toString()) {
        'in-progress' => TaskStatus.inProgress,
        'blocked' => TaskStatus.blocked,
        'done' => TaskStatus.done,
        _ when yaml['complete'] == true => TaskStatus.done,
        _ => TaskStatus.todo,
      },
      statusId:
          yaml['status']?.toString() ??
          (yaml['complete'] == true ? 'done' : 'todo'),
      priority: yaml['priority']?.toString() ?? 'medium',
      project: _text(yaml['project']),
      daily: _text(yaml['daily']),
      due: taskDate(yaml['due']),
      scheduled: taskDate(yaml['scheduled']),
      remindAt: DateTime.tryParse(yaml['remind_at']?.toString() ?? ''),
      recurrence: _text(yaml['recurrence']),
      seriesId: _text(yaml['series_id']),
      dependencies: _strings(yaml['depends_on']),
    );
  }

  static String? _text(Object? value) {
    final result = value?.toString().trim();
    return result == null || result.isEmpty ? null : result;
  }

  static List<String> _strings(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = _text(value);
    return text == null ? const [] : [text];
  }
}

class EmbeddedTask {
  const EmbeddedTask({required this.note, required this.task});
  final ParsedNote note;
  final MarkdownTask task;
}

DateTime? taskDate(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw);
}

DateTime taskDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String legacyTaskId(String path) {
  var hash = 0x811c9dc5;
  for (final unit in path.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return 'legacy-${hash.toRadixString(16)}';
}

class TaskRecurrence {
  const TaskRecurrence({
    required this.frequency,
    this.interval = 1,
    this.days = const [],
  });

  final String frequency;
  final int interval;
  final List<int> days;

  factory TaskRecurrence.parse(String source) {
    final values = <String, String>{};
    for (final part in source.toUpperCase().split(';')) {
      final pair = part.split('=');
      if (pair.length == 2) values[pair.first.trim()] = pair.last.trim();
    }
    final frequency = values['FREQ'];
    if (!const {'DAILY', 'WEEKLY', 'MONTHLY'}.contains(frequency)) {
      throw FormatException('Unsupported recurrence: $source');
    }
    const weekDays = {
      'MO': 1,
      'TU': 2,
      'WE': 3,
      'TH': 4,
      'FR': 5,
      'SA': 6,
      'SU': 7,
    };
    return TaskRecurrence(
      frequency: frequency!,
      interval: int.tryParse(values['INTERVAL'] ?? '')?.clamp(1, 999) ?? 1,
      days: (values['BYDAY'] ?? '')
          .split(',')
          .map((item) => weekDays[item])
          .whereType<int>()
          .toList(growable: false),
    );
  }

  DateTime next(DateTime from) {
    final day = taskDay(from);
    if (frequency == 'DAILY') return day.add(Duration(days: interval));
    if (frequency == 'MONTHLY') {
      final targetMonth = DateTime(day.year, day.month + interval);
      final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
      return DateTime(
        targetMonth.year,
        targetMonth.month,
        day.day.clamp(1, lastDay),
      );
    }
    if (days.isEmpty) return day.add(Duration(days: 7 * interval));
    if (interval == 1) {
      for (var offset = 1; offset <= 7; offset++) {
        final candidate = day.add(Duration(days: offset));
        if (days.contains(candidate.weekday)) return candidate;
      }
    }
    final currentWeekStart = day.subtract(Duration(days: day.weekday - 1));
    final targetWeekStart = currentWeekStart.add(Duration(days: 7 * interval));
    final sortedDays = [...days]..sort();
    return targetWeekStart.add(Duration(days: sortedDays.first - 1));
  }
}
