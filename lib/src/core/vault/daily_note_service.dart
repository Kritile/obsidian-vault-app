import 'package:intl/intl.dart';

import '../../shared/app_log.dart';
import 'vault_creation_support.dart';

final class DailyNoteService extends VaultCreationService {
  DailyNoteService(super.vault, super.writeNote);

  Future<void> addWorkEntry({
    required DateTime date,
    required String description,
    required double hours,
    required List<String> projects,
  }) async {
    final path = _path(date);
    final current = await vault.read(path);
    var source = current?.text ?? await _templateFromVault(date);
    final note = current == null ? null : vault.parser.parse(current);
    final oldSection = note == null
        ? ''
        : _section(note.body, 'Что было сделано');
    final line = vault.workCodec.encode(description, hours, projects);
    source = vault.parser.replaceSection(
      source,
      'Что было сделано',
      '${oldSection.trimRight()}${oldSection.trim().isEmpty ? '' : '\n'}$line',
    );
    await writeNote(path, source);
  }

  Future<String> create({
    required DateTime date,
    String steps = '',
    String sleep = '',
    String calories = '',
    String completed = '',
    String tomorrow = '',
  }) async {
    final path = _path(date);
    if (await vault.read(path) != null) return path;
    var source = await _templateFromVault(date);
    if (steps.trim().isNotEmpty) {
      source = vault.parser.updateFrontmatter(source, ['step'], steps.trim());
    }
    if (sleep.trim().isNotEmpty) {
      source = vault.parser.updateFrontmatter(source, ['sleep'], sleep.trim());
    }
    if (calories.trim().isNotEmpty) {
      source = vault.parser.updateFrontmatter(source, [
        'calories',
      ], calories.trim());
    }
    if (completed.trim().isNotEmpty) {
      source = vault.parser.replaceSection(
        source,
        'Что было сделано',
        completed.trim(),
      );
    }
    if (tomorrow.trim().isNotEmpty) {
      source = vault.parser.replaceSection(
        source,
        'Что нужно сделать завтра',
        tomorrow.trim(),
      );
    }
    await writeNote(path, source);
    return path;
  }

  String _path(DateTime date) =>
      'Daily/${DateFormat('dd MMMM yyyy', 'en').format(date)}.md';

  Future<String> _templateFromVault(DateTime date) async {
    final template = await vault.read('Templates/Daily note.md');
    if (template == null) return _defaultTemplate(date);
    final body = template.text.replaceFirst(RegExp(r'^<%\*[\s\S]*?-%>\s*'), '');
    AppLog.debug('Daily', 'Использован шаблон Templates/Daily note.md');
    return '''---
tags: [Ежедневник]
created: ${DateFormat('yyyy-MM-dd').format(date)}
week: "${_isoWeek(date)}"
step:
sleep:
calories:
---

$body''';
  }

  String _defaultTemplate(DateTime date) =>
      '''---
tags:
  - Ежедневник
created: ${DateFormat('yyyy-MM-dd').format(date)}
week: "${_isoWeek(date)}"
step:
sleep:
calories:
---

# ${DateFormat('d MMMM yyyy', 'ru').format(date)}

### Что было сделано

### Что нужно сделать завтра

### Тренировки

```dataviewjs
await dv.view("Resources/Scripts/training-card");
```
''';

  String _isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week =
        1 +
        thursday
                .difference(
                  firstThursday.subtract(
                    Duration(days: firstThursday.weekday - 1),
                  ),
                )
                .inDays ~/
            7;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  String _section(String body, String heading) =>
      RegExp(
        '^#{1,6}\\s+${RegExp.escape(heading)}\\s*\\r?\\n([\\s\\S]*?)(?=^#{1,6}\\s+|\\z)',
        multiLine: true,
      ).firstMatch(body)?.group(1) ??
      '';
}
