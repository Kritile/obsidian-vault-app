import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';
import 'package:pavel_vault/src/shared/obsidian_markdown_view.dart';

void main() {
  final parser = ObsidianParser();

  VaultDocument document(
    String source, {
    String path = 'Daily/21 July 2026.md',
  }) => VaultDocument(
    path: path,
    bytes: Uint8List.fromList(utf8.encode(source)),
    modifiedAt: DateTime.utc(2026, 7, 21),
  );

  test('parses Obsidian YAML, wiki links, tasks and daily type', () {
    final note = parser.parse(
      document('''---
tags: [Ежедневник, Отчёт]
created: 2026-07-21
sleep: "6"
---
# День
- [x] Готово
См. [[Projects/Letech/_Project|Letech]] и ![[photo.png]].
'''),
    );

    expect(note.type, VaultEntityType.daily);
    expect(note.tags, ['Ежедневник', 'Отчёт']);
    expect(note.frontmatter['sleep'], '6');
    expect(note.tasks.single.completed, isTrue);
    expect(note.links.map((link) => link.target), [
      'Projects/Letech/_Project',
      'photo.png',
    ]);
    expect(note.links.last.embedded, isTrue);
  });

  test('document source editor text decodes and re-encodes UTF-8', () {
    const source = '''---
title: Кириллическая заметка
---
# Проверка

Текст, ёлка и эмодзи 🌲
''';
    final original = document(source);

    expect(original.text, source);
    expect(parser.encode(original.text), original.bytes);
  });

  test('frontmatter edit preserves unrelated formatting and body', () {
    const source = '''---
# important comment
created: 2026-07-21
sleep: "6"
custom: untouched
---

# Body
```dataviewjs
doNotChange();
```
''';
    final updated = parser.updateFrontmatter(source, ['sleep'], '7.5');

    expect(updated, contains('# important comment'));
    expect(updated, contains('custom: untouched'));
    expect(updated, contains('sleep: "7.5"'));
    expect(updated, endsWith('```dataviewjs\ndoNotChange();\n```\n'));
  });

  test('section edit changes only the selected section', () {
    const source =
        '# Day\n\n### Что было сделано\n\n- old\n\n### Tomorrow\n\n- keep\n';
    final updated = parser.replaceSection(source, 'Что было сделано', '- new');
    expect(updated, contains('### Что было сделано\n\n- new'));
    expect(updated, contains('### Tomorrow\n\n- keep'));
    expect(updated, isNot(contains('- old')));
  });

  test('embedded Obsidian images are routed through the vault image cache', () {
    final markdown = convertObsidianMarkdown(
      'Фото ![[Assets/Фикус крупный.jpg|Фикус]] и [[Projects/Test]].',
    );

    expect(
      markdown,
      contains(
        '![Фикус](vault-image:Assets%2F%D0%A4%D0%B8%D0%BA%D1%83%D1%81%20%D0%BA%D1%80%D1%83%D0%BF%D0%BD%D1%8B%D0%B9.jpg)',
      ),
    );
    expect(markdown, contains('[Test](vault:Projects%2FTest)'));
  });
}
