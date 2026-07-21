import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/native_entity.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  test('book template uses fields expected by Obsidian Books base', () {
    final source = NativeEntityTemplate().build(NativeEntityKind.book, {
      'title': 'Тестовая книга',
      'author': 'Автор',
      'year': 2026,
      'genres': ['fantasy', 'test'],
      'status': 'reading',
      'rating': 8,
    });
    final note = ObsidianParser().parse(VaultDocument(
      path: 'Areas/Книги/Тестовая книга.md',
      bytes: ObsidianParser().encode(source),
      modifiedAt: DateTime.utc(2026),
    ));
    expect(note.frontmatter['title'], 'Тестовая книга');
    expect(note.frontmatter['author'], 'Автор');
    expect(note.frontmatter['status'], 'reading');
    expect(note.tags, ['book']);
  });

  test('recipe template calculates total time', () {
    final source = NativeEntityTemplate().build(NativeEntityKind.recipe, {
      'title': 'Суп',
      'prep_time': 10,
      'cook_time': 30,
      'ingredients': 'Вода\nОвощи',
    });
    final note = ObsidianParser().parse(VaultDocument(
      path: 'Areas/Recipes/Суп.md',
      bytes: ObsidianParser().encode(source),
      modifiedAt: DateTime.utc(2026),
    ));
    expect(note.frontmatter['type'], 'recipe');
    expect(note.frontmatter['total_time'], 40);
    expect(note.body, contains('- Вода\n- Овощи'));
  });

  test('medicine template keeps fields expected by Аптечка base', () {
    final source = NativeEntityTemplate().build(NativeEntityKind.medicine, {
      'title': 'Лекарство',
      'remainder': 12,
      'active': true,
      'dosagePerDay': 2,
    });
    final note = ObsidianParser().parse(VaultDocument(
      path: 'Areas/Аптечка/Лекарство.md',
      bytes: ObsidianParser().encode(source),
      modifiedAt: DateTime.utc(2026),
    ));
    expect(note.frontmatter['remainder'], 12);
    expect(note.frontmatter['active'], true);
    expect(note.frontmatter['dosagePerDay'], 2);
  });
}

