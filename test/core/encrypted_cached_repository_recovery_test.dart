import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/vault/encrypted_cached_repository.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  test(
    'rebuilds a versioned manifest from orphaned encrypted objects',
    () async {
      final store = _MemoryStore()..put('Daily/22 July 2026.md', '# День');
      final repository = EncryptedCachedRepository(store);

      await repository.initialize();

      expect((await repository.list()).single.path, 'Daily/22 July 2026.md');
      final manifest = store.json('__manifest__');
      expect(manifest['formatVersion'], 2);
      expect(manifest['checksum'], isNotEmpty);
      expect(
        (manifest['entries']! as Map).keys,
        contains('Daily/22 July 2026.md'),
      );
    },
  );

  test(
    'uses manifest backup and removes references to missing objects',
    () async {
      final store = _MemoryStore()
        ..put('note.md', 'content')
        ..bytes['__manifest__'] = Uint8List.fromList([0, 1, 2])
        ..putJson('__manifest_backup__', {
          'note.md': {
            'modifiedAt': '2026-07-22T00:00:00.000Z',
            'etag': 'etag-old',
            'hash': null,
          },
          'missing.md': {
            'modifiedAt': '2026-07-22T00:00:00.000Z',
            'etag': null,
            'hash': null,
          },
        });
      final repository = EncryptedCachedRepository(store);

      await repository.initialize();

      expect((await repository.list()).map((item) => item.path), ['note.md']);
      expect(
        (store.json('__manifest__')['entries']! as Map).containsKey(
          'missing.md',
        ),
        isFalse,
      );
    },
  );

  test(
    'rolls an interrupted batch forward on the next initialization',
    () async {
      final store = _MemoryStore();
      final first = EncryptedCachedRepository(store);
      await first.initialize();
      await first.beginBatch();
      await first.write(
        VaultDocument(
          path: 'queued.md',
          bytes: Uint8List.fromList(utf8.encode('latest value')),
          modifiedAt: DateTime.utc(2026, 7, 22),
        ),
      );

      expect(store.bytes, contains('__manifest_batch_v1__'));

      final recovered = EncryptedCachedRepository(store);
      await recovered.initialize();

      expect((await recovered.read('queued.md'))?.text, 'latest value');
      expect(store.bytes, isNot(contains('__manifest_batch_v1__')));
    },
  );

  test('excludes an object that fails integrity verification', () async {
    final store = _MemoryStore()
      ..put('broken.md', 'unreadable')
      ..putJson('__manifest__', {
        'broken.md': {
          'modifiedAt': '2026-07-22T00:00:00.000Z',
          'etag': null,
          'hash': null,
        },
      })
      ..corrupted.add('broken.md');
    final repository = EncryptedCachedRepository(store);

    await repository.initialize();

    expect(await repository.list(), isEmpty);
  });

  test('normal v2 startup skips full object reconciliation', () async {
    final store = _MemoryStore()..put('note.md', 'content');
    await EncryptedCachedRepository(store).initialize();
    store.keysCalls = 0;

    await EncryptedCachedRepository(store).initialize();

    expect(store.keysCalls, 0);
  });
}

class _MemoryStore extends EncryptedObjectStore {
  final Map<String, Uint8List> bytes = {};
  final Set<String> corrupted = {};
  int keysCalls = 0;

  void put(String key, String value) {
    bytes[key] = Uint8List.fromList(utf8.encode(value));
  }

  void putJson(String key, Map<String, Object?> value) {
    put(key, jsonEncode(value));
  }

  Map<String, Object?> json(String key) =>
      Map<String, Object?>.from(jsonDecode(utf8.decode(bytes[key]!)) as Map);

  @override
  Future<void> initialize() async {}

  @override
  Future<Uint8List?> read(String key) async {
    if (corrupted.contains(key)) throw const FormatException('corrupt');
    final value = bytes[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List clearBytes) async {
    bytes[key] = Uint8List.fromList(clearBytes);
  }

  @override
  Future<void> remove(String key) async {
    bytes.remove(key);
  }

  @override
  Future<Set<String>> keys() async {
    keysCalls++;
    return bytes.keys.toSet();
  }

  @override
  Future<DateTime?> lastModified(String key) async => DateTime.utc(2026, 7, 22);
}
