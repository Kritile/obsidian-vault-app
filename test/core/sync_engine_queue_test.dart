import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/sync/sync_engine.dart';
import 'package:pavel_vault/src/core/sync/webdav_client.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';
import 'package:pavel_vault/src/core/vault/vault_repository.dart';

void main() {
  test(
    'file sync waits for full sync and queued saves coalesce by path',
    () async {
      final local = _MemoryVault()..put('note.md', 'version 1');
      final remote = _FakeWebDav()..listGate = Completer<void>();
      final engine = SyncEngine(
        local: local,
        store: _MemoryStore(),
        remote: remote,
      );

      final full = engine.synchronize();
      await remote.listStarted.future;

      local.put('note.md', 'version 2');
      final firstSave = engine.synchronizeFile('note.md');
      local.put('note.md', 'version 3');
      final secondSave = engine.synchronizeFile('note.md');

      expect(identical(firstSave, secondSave), isTrue);
      remote.listGate!.complete();
      await full;
      await firstSave;

      expect(remote.uploads.map(utf8.decode), ['version 1', 'version 3']);
    },
  );

  test(
    'save during active file upload schedules one fresh follow-up',
    () async {
      final local = _MemoryVault()..put('note.md', 'version 1');
      final remote = _FakeWebDav()..firstUploadGate = Completer<void>();
      final engine = SyncEngine(
        local: local,
        store: _MemoryStore(),
        remote: remote,
      );

      final activeSave = engine.synchronizeFile('note.md');
      await remote.uploadStarted.future;

      local.put('note.md', 'version 2');
      final followUp = engine.synchronizeFile('note.md');
      local.put('note.md', 'version 3');
      final coalesced = engine.synchronizeFile('note.md');

      expect(identical(followUp, coalesced), isTrue);
      remote.firstUploadGate!.complete();
      await activeSave;
      await followUp;

      expect(remote.uploads.map(utf8.decode), ['version 1', 'version 3']);
    },
  );
}

class _MemoryVault implements VaultRepository {
  final Map<String, VaultDocument> _documents = {};

  void put(String path, String source) {
    _documents[path] = VaultDocument(
      path: path,
      bytes: Uint8List.fromList(utf8.encode(source)),
      modifiedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<VaultDocument>> list() async => [..._documents.values];

  @override
  Future<VaultDocument?> read(String path) async => _documents[path];

  @override
  Future<void> write(VaultDocument document, {String? expectedEtag}) async {
    _documents[document.path] = document;
  }

  @override
  Future<void> delete(String path, {String? expectedEtag}) async {
    _documents.remove(path);
  }

  @override
  Future<void> move(String from, String to, {String? expectedEtag}) async {
    final document = _documents.remove(from)!;
    _documents[to] = VaultDocument(
      path: to,
      bytes: document.bytes,
      modifiedAt: document.modifiedAt,
      etag: document.etag,
    );
  }
}

class _MemoryStore extends EncryptedObjectStore {
  final Map<String, Uint8List> _values = {};

  @override
  Future<Uint8List?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, Uint8List clearBytes) async {
    _values[key] = Uint8List.fromList(clearBytes);
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

class _FakeWebDav extends WebDavClient {
  _FakeWebDav()
    : super(
        WebDavCredentials(
          baseUrl: Uri.parse('https://example.test/vault/'),
          username: 'user',
          password: 'secret',
        ),
      );

  Completer<void>? listGate;
  Completer<void>? firstUploadGate;
  final listStarted = Completer<void>();
  final uploadStarted = Completer<void>();
  final List<Uint8List> uploads = [];

  @override
  Future<List<WebDavEntry>> listTree() async {
    if (!listStarted.isCompleted) listStarted.complete();
    await listGate?.future;
    return const [];
  }

  @override
  Future<String?> upload(
    String path,
    Uint8List bytes, {
    String? expectedEtag,
  }) async {
    uploads.add(Uint8List.fromList(bytes));
    if (!uploadStarted.isCompleted) uploadStarted.complete();
    if (uploads.length == 1) await firstUploadGate?.future;
    return 'etag-${uploads.length}';
  }

  @override
  Future<void> createDirectory(String path) async {}
}
