import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/markdown/work_entry_codec.dart';
import 'package:pavel_vault/src/core/vault/vault_index.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  test('resolves aliases and builds backlinks and related notes', () {
    final parser = ObsidianParser();
    final index = VaultIndex(parser, WorkEntryCodec());
    index.rebuild([
      _document(
        parser,
        'Projects/Alpha.md',
        '---\naliases: [A]\ntags: [work]\n---\n# Alpha',
      ),
      _document(
        parser,
        'Daily/Today.md',
        '---\ntags: [daily]\n---\n# Today\n[[A]]',
      ),
      _document(
        parser,
        'Notes/Related.md',
        '---\ntags: [work]\n---\n# Related',
      ),
    ]);

    final alpha = index.byPath('Projects/Alpha.md')!;
    expect(
      index.resolveLink('A', fromPath: 'Daily/Today.md')?.document.path,
      'Projects/Alpha.md',
    );
    expect(index.backlinks(alpha).map((item) => item.title), contains('Today'));
    expect(
      index.related(alpha).map((item) => item.title),
      containsAll(['Today', 'Related']),
    );
  });
}

VaultDocument _document(ObsidianParser parser, String path, String source) =>
    VaultDocument(
      path: path,
      bytes: parser.encode(source),
      modifiedAt: DateTime(2026),
    );
