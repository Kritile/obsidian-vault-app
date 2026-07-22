import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/app/sync_controller.dart';
import 'package:pavel_vault/src/app/task_controller.dart';
import 'package:pavel_vault/src/app/vault_controller.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/tasks/task_models.dart';
import 'package:pavel_vault/src/core/tasks/task_notification_service.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
    'done status uses dependency checks and creates next occurrence',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.vault.saveLocal(
        'Tasks/Dependency.md',
        _task(id: 'dependency', title: 'Dependency'),
      );
      await fixture.vault.saveLocal(
        'Tasks/Recurring.md',
        _task(
          id: 'recurring',
          title: 'Recurring',
          recurrence: 'FREQ=DAILY',
          due: '2026-07-22',
          dependsOn: '[dependency]',
        ),
      );
      final recurring = fixture.task('recurring');

      await expectLater(
        fixture.controller.setStatusId(recurring, 'done'),
        throwsStateError,
      );
      await fixture.controller.setComplete(fixture.task('dependency'), true);
      await fixture.controller.setStatusId(recurring, 'done');

      expect(fixture.task('recurring').completed, isTrue);
      final next = fixture.controller.tasks.singleWhere(
        (task) => task.seriesId == 'recurring' && !task.completed,
      );
      expect(next.due, DateTime(2026, 7, 23));
    },
  );

  test(
    'next occurrence preserves scheduled-to-due and reminder offsets',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.vault.saveLocal(
        'Tasks/Window.md',
        _task(
          id: 'window',
          title: 'Window',
          recurrence: 'FREQ=MONTHLY',
          scheduled: '2026-01-31',
          due: '2026-02-02',
          remindAt: '2026-01-31T09:30:00',
        ),
      );

      await fixture.controller.setComplete(fixture.task('window'), true);

      final next = fixture.controller.tasks.singleWhere(
        (task) => task.seriesId == 'window' && !task.completed,
      );
      expect(next.scheduled, DateTime(2026, 2, 28));
      expect(next.due, DateTime(2026, 3, 2));
      expect(next.remindAt, DateTime(2026, 2, 28, 9, 30));
      expect(next.due!.difference(next.scheduled!), const Duration(days: 2));
    },
  );

  test('legacy task id is persisted before a project move', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.vault.saveLocal('Tasks/Legacy.md', '''---
type: task
status: todo
complete: false
---
# Legacy
''');
    final before = fixture.controller.tasks.single;

    await fixture.controller.assignProject(before, 'Vellum');

    final after = fixture.controller.tasks.single;
    expect(after.path, 'Projects/Vellum/Legacy.md');
    expect(after.id, before.id);
    expect(after.note.frontmatter['id'], before.id);
  });

  test('notification payload resolves and is consumed as a task', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.vault.saveLocal(
      'Tasks/Open.md',
      _task(id: 'open-me', title: 'Open me'),
    );
    await fixture.controller.initializeNotifications();

    fixture.notifications.open('open-me');

    expect(fixture.controller.takeOpenedTask()?.title, 'Open me');
    expect(fixture.controller.takeOpenedTask(), isNull);
  });

  test('timezone initialization sets the resolved IANA location', () async {
    await configureTaskTimezone(() async => 'Europe/Moscow');
    addTearDown(() => tz.setLocalLocation(tz.UTC));

    expect(tz.local.name, 'Europe/Moscow');
  });

  test('Linux notification delay is retained beyond 24 hours', () {
    final now = DateTime(2026, 7, 22, 12);
    final note = _Fixture.parse(
      _task(id: 'future', title: 'Future', remindAt: '2026-07-29T12:00:00'),
    );
    final task = TaskDefinition.fromNote(note);

    expect(taskNotificationDelay(task, now), const Duration(days: 7));
  });
}

class _Fixture {
  _Fixture(this.root, this.vault, this.notifications, this.controller);

  final Directory root;
  final VaultController vault;
  final _FakeNotifications notifications;
  final TaskController controller;

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('vellum-tasks-');
    final vault = VaultController();
    await vault.initializeStoreForTesting(
      EncryptedObjectStore(rootDirectory: root),
    );
    final notifications = _FakeNotifications();
    final controller = TaskController(
      vault,
      SyncController(vault),
      notifications,
    );
    return _Fixture(root, vault, notifications, controller);
  }

  TaskDefinition task(String id) =>
      controller.tasks.singleWhere((task) => task.id == id);

  Future<void> dispose() async {
    controller.dispose();
    if (await root.exists()) await root.delete(recursive: true);
  }

  static ParsedNote parse(String source) {
    return ObsidianParser().parse(
      VaultDocument(
        path: 'Tasks/Test.md',
        bytes: Uint8List.fromList(utf8.encode(source)),
        modifiedAt: DateTime(2026, 7, 22),
      ),
    );
  }
}

class _FakeNotifications implements TaskNotificationScheduler {
  void Function(String taskId)? onOpen;

  @override
  Future<void> initialize(void Function(String taskId) value) async {
    onOpen = value;
  }

  @override
  Future<void> reconcile(Iterable<TaskDefinition> tasks) async {}

  void open(String id) => onOpen?.call(id);

  @override
  void dispose() {}
}

String _task({
  required String id,
  required String title,
  String recurrence = '',
  String due = '',
  String scheduled = '',
  String remindAt = '',
  String dependsOn = '[]',
}) =>
    '''---
type: task
id: $id
status: todo
complete: false
due: $due
scheduled: $scheduled
remind_at: $remindAt
recurrence: $recurrence
series_id: ${recurrence.isEmpty ? '' : id}
depends_on: $dependsOn
---
# $title
''';
