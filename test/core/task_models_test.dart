import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/tasks/task_models.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  test('reads the open Markdown task schema', () {
    final task = TaskDefinition.fromNote(_note('Tasks/Test.md', '''---
type: task
id: task-42
status: in-progress
priority: high
project: Vellum
due: 2026-07-23
scheduled: 2026-07-22
remind_at: 2026-07-22T09:30:00+03:00
recurrence: FREQ=WEEKLY;BYDAY=WE
series_id: series-1
depends_on: [task-1, task-2]
---
# Проверить задачи
'''));

    expect(task.id, 'task-42');
    expect(task.status, TaskStatus.inProgress);
    expect(task.project, 'Vellum');
    expect(task.due, DateTime(2026, 7, 23));
    expect(task.dependencies, ['task-1', 'task-2']);
    expect(task.completed, isFalse);
  });

  test('legacy task gets a stable path-derived id', () {
    final first = TaskDefinition.fromNote(_note('Tasks/Legacy.md', '''---
type: task
complete: false
---
# Legacy
'''));
    final second = TaskDefinition.fromNote(_note('Tasks/Legacy.md', '''---
type: task
complete: false
---
# Changed title
'''));
    expect(first.id, startsWith('legacy-'));
    expect(second.id, first.id);
  });

  test('recurrence calculates daily weekly and monthly occurrences', () {
    expect(
      TaskRecurrence.parse('FREQ=DAILY;INTERVAL=2').next(DateTime(2026, 7, 22)),
      DateTime(2026, 7, 24),
    );
    expect(
      TaskRecurrence.parse('FREQ=WEEKLY;BYDAY=FR').next(DateTime(2026, 7, 22)),
      DateTime(2026, 7, 24),
    );
    expect(
      TaskRecurrence.parse('FREQ=MONTHLY').next(DateTime(2026, 7, 22)),
      DateTime(2026, 8, 22),
    );
  });

  test('unsupported recurrence is rejected', () {
    expect(
      () => TaskRecurrence.parse('FREQ=YEARLY'),
      throwsFormatException,
    );
  });
}

ParsedNote _note(String path, String source) => ObsidianParser().parse(
  VaultDocument(
    path: path,
    bytes: Uint8List.fromList(utf8.encode(source)),
    modifiedAt: DateTime(2026, 7, 22),
  ),
);
