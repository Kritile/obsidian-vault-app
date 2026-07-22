import 'package:intl/intl.dart';

import '../../shared/app_log.dart';
import 'project_note_definition.dart';
import 'vault_creation_support.dart';
import 'vault_models.dart';

final class ProjectService extends VaultCreationService {
  ProjectService(super.vault, super.writeNote);

  Future<String> createProject({
    required String title,
    required String status,
    String description = '',
  }) async {
    final path = 'Projects/${safeFileName(title)}/_Project.md';
    if (await vault.read(path) != null) {
      throw StateError('Проект уже существует: $title');
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await writeNote(path, '''---
type: project
project: ${yamlScalar(title)}
status: $status
archived: ${status == 'archived'}
created: $today
due:
tags: [project]
---

# $title

```dataviewjs
await dv.view("Resources/Scripts/project-dashboard");
```

## Описание

$description

## Цели

- [ ]

## Ключевые ссылки

-
''');
    return path;
  }

  Future<String> createTask({
    required String project,
    required String title,
    required String priority,
    DateTime? due,
    String description = '',
  }) async {
    final folder = 'Projects/${safeFileName(project)}';
    final path = await uniquePath(folder, safeFileName(title));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await writeNote(path, '''---
type: task
project: ${yamlScalar(project)}
created: $today
status: todo
complete: false
priority: $priority
hours: 0
due: ${due == null ? '' : DateFormat('yyyy-MM-dd').format(due)}
tags: [task]
---

# $title

```dataviewjs
await dv.view("Resources/Scripts/project-note-card");
```

## Описание

$description

## Критерии готовности

- [ ]
''');
    return path;
  }

  Future<String> createNote({
    required String project,
    required String title,
    required String noteType,
    Map<String, String> sections = const {},
  }) async {
    final definition = projectNoteDefinition(noteType);
    final folder = 'Projects/${safeFileName(project)}';
    final path = await uniquePath(folder, safeFileName(title));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final template = await vault.read(
      'Templates/Projects/${definition.templateName}.md',
    );
    var source =
        template?.text ??
        '''---
type: project-note
note_type: ${definition.key}
project: {{project}}
created: {{created}}
tags: [${definition.key}]
aliases: []
---

# {{title}}

```dataviewjs
await dv.view("Resources/Scripts/project-note-card");
```
''';
    source = source
        .replaceAll('{{project}}', yamlScalar(project))
        .replaceAll('{{created}}', today)
        .replaceAll('{{title}}', title.trim());
    for (final entry in sections.entries) {
      if (entry.value.trim().isNotEmpty) {
        source = vault.parser.replaceSection(
          source,
          entry.key,
          entry.value.trim(),
        );
      }
    }
    await writeNote(path, source);
    return path;
  }

  Future<void> setArchived(ParsedNote project, bool archived) async {
    var source = project.document.text;
    source = vault.parser.updateFrontmatter(source, [
      'status',
    ], archived ? 'archived' : 'active');
    source = vault.parser.updateFrontmatter(source, ['archived'], archived);
    await writeNote(project.document.path, source);
    AppLog.info(
      'Project',
      '${archived ? 'Архивирован' : 'Восстановлен'} ${project.title}',
    );
  }

  Future<void> setTaskComplete(ParsedNote task, bool complete) async {
    var source = task.document.text;
    source = vault.parser.updateFrontmatter(source, ['complete'], complete);
    source = vault.parser.updateFrontmatter(source, [
      'status',
    ], complete ? 'done' : 'todo');
    await writeNote(task.document.path, source);
  }
}
