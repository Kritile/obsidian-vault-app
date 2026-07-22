import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/editor/note_editing_controller.dart';

void main() {
  test('draft survives controller recreation and can be restored', () async {
    final store = _MemoryStore();
    final first = NoteEditingController(
      path: 'Notes/Test.md',
      source: '# Original',
      baseHash: 'base',
      store: store,
    );
    first.text.text = '# Draft';
    await first.saveDraft();
    first.dispose();

    final second = NoteEditingController(
      path: 'Notes/Test.md',
      source: '# Original',
      baseHash: 'base',
      store: store,
    );
    await second.initialize();
    expect(second.recoveredSource, '# Draft');
    second.recoverDraft();
    expect(second.text.text, '# Draft');
    await second.markSaved();
    expect(store.values.keys, isNot(contains('__draft_v1__:Notes/Test.md')));
    second.dispose();
  });

  test('undo, redo, search, replacement and completions update text', () {
    final editor = NoteEditingController(
      path: 'note.md',
      source: 'Alpha [[Pro',
      baseHash: null,
      store: null,
    );
    editor.text.selection = TextSelection.collapsed(
      offset: editor.text.text.length,
    );
    expect(editor.wikiQuery, 'Pro');
    editor.completeWiki('Projects/Test');
    expect(editor.text.text, 'Alpha [[Projects/Test]]');
    editor.undo();
    expect(editor.text.text, 'Alpha [[Pro');
    editor.redo();
    expect(editor.text.text, 'Alpha [[Projects/Test]]');
    expect(editor.findNext('alpha'), 0);
    expect(editor.replaceCurrent('alpha', 'Beta'), isTrue);
    expect(editor.text.text, startsWith('Beta'));
    editor.dispose();
  });
}

class _MemoryStore extends EncryptedObjectStore {
  final Map<String, Uint8List> values = {};

  @override
  Future<Uint8List?> read(String key) async => values[key];

  @override
  Future<void> write(String key, Uint8List clearBytes) async {
    values[key] = Uint8List.fromList(clearBytes);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
