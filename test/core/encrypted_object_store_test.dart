import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';

void main() {
  test('atomically replaces an existing encrypted object', () async {
    final root = await Directory.systemTemp.createTemp('pavel-store-replace-');
    addTearDown(() => root.delete(recursive: true));
    final store = EncryptedObjectStore(rootDirectory: root);
    await store.initialize();

    await store.write('note.md', Uint8List.fromList([1, 2, 3]));
    await store.write('note.md', Uint8List.fromList([4, 5, 6]));

    expect(await store.read('note.md'), [4, 5, 6]);
    final files = await root.list().where((item) => item is File).toList();
    expect(files.where((item) => item.path.endsWith('.pvo')), hasLength(1));
    expect(files.where((item) => item.path.contains('.tmp-')), isEmpty);
  });

  test('failed rename preserves the previous complete object', () async {
    final root = await Directory.systemTemp.createTemp('pavel-store-failure-');
    addTearDown(() => root.delete(recursive: true));
    final original = EncryptedObjectStore(rootDirectory: root);
    await original.initialize();
    await original.write('note.md', Uint8List.fromList([1, 2, 3]));

    final interrupted = EncryptedObjectStore(
      rootDirectory: root,
      beforeAtomicRename: (_, _) async => throw const FileSystemException(
        'simulated interruption before rename',
      ),
    );
    await interrupted.initialize();

    await expectLater(
      interrupted.write('note.md', Uint8List.fromList([9, 9, 9])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.read('note.md'), [1, 2, 3]);
  });

  test('initialization removes temporary files left by a crash', () async {
    final root = await Directory.systemTemp.createTemp('pavel-store-cleanup-');
    addTearDown(() => root.delete(recursive: true));
    final stale = File(
      '${root.path}${Platform.pathSeparator}object.pvo.tmp-crash',
    );
    await stale.writeAsBytes([1, 2, 3], flush: true);

    final store = EncryptedObjectStore(rootDirectory: root);
    await store.initialize();

    expect(await stale.exists(), isFalse);
  });

  test(
    'verified staging store replaces current root and keeps backup',
    () async {
      final root = await Directory.systemTemp.createTemp('vellum-store-stage-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
        final parent = root.parent;
        await for (final entity in parent.list()) {
          if (entity.path.startsWith('${root.path}.backup-') ||
              entity.path.startsWith('${root.path}.restore-')) {
            await entity.delete(recursive: true);
          }
        }
      });
      final store = EncryptedObjectStore(rootDirectory: root);
      await store.initialize();
      await store.write('note.md', Uint8List.fromList(utf8.encode('old')));
      final staging = await store.createStaging();
      await staging.write('note.md', Uint8List.fromList(utf8.encode('new')));

      final backup = await store.replaceWith(staging);

      expect(utf8.decode((await store.read('note.md'))!), 'new');
      expect(await Directory(backup).exists(), isTrue);

      await store.rollbackFrom(backup);
      expect(utf8.decode((await store.read('note.md'))!), 'old');
      final failedCopies = await root.parent
          .list()
          .where((entity) => entity.path.startsWith('${root.path}.failed-'))
          .toList();
      expect(failedCopies, isEmpty);
    },
  );
}
