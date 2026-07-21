import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/project_note_definition.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  test('all native project note types match Obsidian templates', () {
    final parser = ObsidianParser();
    expect(
      projectNoteDefinitions.map((item) => item.key),
      containsAll([
        'general',
        'meeting',
        'decision',
        'brief',
        'reference',
        'report',
      ]),
    );

    for (final definition in projectNoteDefinitions) {
      final file = File('../Templates/Projects/${definition.templateName}.md');
      expect(file.existsSync(), isTrue, reason: definition.templateName);
      final source = file
          .readAsStringSync()
          .replaceAll('{{project}}', 'Проект')
          .replaceAll('{{created}}', '2026-07-21')
          .replaceAll('{{title}}', 'Материал');
      final note = parser.parse(
        VaultDocument(
          path: 'Projects/Проект/Материал.md',
          bytes: parser.encode(source),
          modifiedAt: DateTime.utc(2026, 7, 21),
        ),
      );
      expect(note.type, VaultEntityType.projectNote);
      expect(note.frontmatter['note_type'], definition.key);
      for (final section in definition.sections) {
        expect(source, contains('## ${section.heading}'));
      }
    }
  });
}
