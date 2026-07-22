import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/app/vault_controller.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/sync/storage_capacity_service.dart';
import 'package:pavel_vault/src/core/sync/sync_models.dart';
import 'package:pavel_vault/src/core/sync/webdav_client.dart';
import 'package:pavel_vault/src/core/sync/webdav_profile.dart';

void main() {
  test(
    'recovery reapplies pending delete and move without duplicates',
    () async {
      final root = await Directory.systemTemp.createTemp('vellum-recovery-');
      addTearDown(() => _removeGenerations(root));
      final vault = VaultController();
      await vault.initializeStoreForTesting(
        EncryptedObjectStore(rootDirectory: root),
      );
      await vault.saveBytes('Moved/New.md', _bytes('# local moved'));
      await vault.saveBytes('Local.md', _bytes('# local upload'));
      final pending = [
        SyncQueueEntry(
          path: 'Deleted.md',
          kind: SyncOperationKind.delete,
          state: SyncQueueState.error,
          updatedAt: DateTime(2026),
        ),
        SyncQueueEntry(
          path: 'Old.md',
          destinationPath: 'Moved/New.md',
          kind: SyncOperationKind.move,
          state: SyncQueueState.error,
          updatedAt: DateTime(2026),
        ),
        SyncQueueEntry(
          path: 'Local.md',
          state: SyncQueueState.error,
          updatedAt: DateTime(2026),
        ),
      ];
      await vault.store.write(
        '__sync_outbox_v1__',
        _bytes(jsonEncode(pending.map((item) => item.toJson()).toList())),
      );
      final remote = _RecoveryWebDav({
        'Deleted.md': '# server delete',
        'Old.md': '# server old',
        'Remote.md': '# server remote',
      });

      await vault.recoverFromWebDav(
        _profile,
        client: remote,
        capacity: _PlentyOfSpace(),
      );

      expect(await vault.read('Deleted.md'), isNull);
      expect(await vault.read('Old.md'), isNull);
      expect((await vault.read('Moved/New.md'))?.text, '# local moved');
      expect((await vault.read('Local.md'))?.text, '# local upload');
      expect((await vault.read('Remote.md'))?.text, '# server remote');
      expect(await vault.store.read('__sync_outbox_v1__'), isNotNull);
    },
  );

  test('invalid Markdown frontmatter cancels staging switch', () async {
    final root = await Directory.systemTemp.createTemp('vellum-recovery-md-');
    addTearDown(() => _removeGenerations(root));
    final vault = VaultController();
    await vault.initializeStoreForTesting(
      EncryptedObjectStore(rootDirectory: root),
    );
    await vault.saveBytes('Original.md', _bytes('# remains active'));
    final remote = _RecoveryWebDav({'Broken.md': '---\ntags: [\n---\n# bad'});

    await expectLater(
      vault.recoverFromWebDav(
        _profile,
        client: remote,
        capacity: _PlentyOfSpace(),
      ),
      throwsA(isA<FormatException>()),
    );

    expect((await vault.read('Original.md'))?.text, '# remains active');
    expect(await vault.read('Broken.md'), isNull);
  });

  test('recovery space estimate includes new files from outbox', () async {
    final root = await Directory.systemTemp.createTemp(
      'vellum-recovery-space-',
    );
    addTearDown(() => _removeGenerations(root));
    final vault = VaultController();
    await vault.initializeStoreForTesting(
      EncryptedObjectStore(rootDirectory: root),
    );
    await vault.saveBytes('New.bin', Uint8List(2048));
    final pending = SyncQueueEntry(
      path: 'New.bin',
      state: SyncQueueState.error,
      updatedAt: DateTime(2026),
    );
    await vault.store.write(
      '__sync_outbox_v1__',
      _bytes(jsonEncode([pending.toJson()])),
    );

    await expectLater(
      vault.recoverFromWebDav(
        _profile,
        client: _RecoveryWebDav({}),
        capacity: _LimitedSpace(),
      ),
      throwsA(isA<InsufficientSpaceException>()),
    );
  });
}

final _profile = WebDavProfile(
  id: 'test',
  name: 'Test',
  baseUrl: Uri.parse('https://example.test/vault/'),
  username: 'user',
  password: 'secret',
);

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

Future<void> _removeGenerations(Directory root) async {
  await for (final entity in root.parent.list()) {
    if (entity.path == root.path || entity.path.startsWith('${root.path}.')) {
      if (await entity.exists()) await entity.delete(recursive: true);
    }
  }
}

class _PlentyOfSpace extends StorageCapacityService {
  @override
  Future<int?> availableBytes(String? path) async => 1 << 40;
}

class _LimitedSpace extends StorageCapacityService {
  @override
  Future<int?> availableBytes(String? path) async => 128 * 1024 * 1024 + 1024;
}

class _RecoveryWebDav extends WebDavClient {
  _RecoveryWebDav(Map<String, String> values)
    : values = values.map((key, value) => MapEntry(key, _bytes(value))),
      super(_profile.credentials);

  final Map<String, Uint8List> values;

  @override
  Future<List<WebDavEntry>> listTree() async => values.entries
      .map(
        (entry) => WebDavEntry(
          path: entry.key,
          isDirectory: false,
          modifiedAt: DateTime(2026),
          size: entry.value.length,
          etag: 'etag-${entry.key}',
        ),
      )
      .toList(growable: false);

  @override
  Future<Uint8List> download(String path) async =>
      Uint8List.fromList(values[path]!);
}
