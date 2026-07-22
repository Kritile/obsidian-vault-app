import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/app/sync_controller.dart';
import 'package:pavel_vault/src/app/vault_controller.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/sync/sync_engine.dart';
import 'package:pavel_vault/src/core/sync/webdav_client.dart';
import 'package:pavel_vault/src/core/sync/webdav_profile.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';
import 'package:pavel_vault/src/core/vault/vault_repository.dart';

void main() {
  test('busy remains true until every queued operation completes', () async {
    final vault = _TestVault()..ready = true;
    final remote = _GatedWebDav();
    final engine = SyncEngine(
      local: _EmptyVault(),
      store: _MemoryStore(),
      remote: remote,
    );
    final controller = SyncController(vault, engineFactory: (_, _) => engine);
    controller.configure(
      WebDavProfile(
        id: 'test',
        name: 'Test',
        baseUrl: Uri.parse('https://example.test/vault/'),
        username: 'user',
        password: 'secret',
      ),
    );

    final first = controller.synchronize();
    final second = controller.synchronize();
    expect(controller.busy, isTrue);

    await remote.firstStarted.future;
    remote.firstGate.complete();
    await remote.secondStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(controller.busy, isTrue);

    remote.secondGate.complete();
    await Future.wait([first, second]);
    expect(controller.busy, isFalse);
  });
}

class _TestVault extends VaultController {
  @override
  Future<void> refreshIndex() async {}
}

class _EmptyVault implements VaultRepository {
  @override
  Future<List<VaultDocument>> list() async => const [];

  @override
  Future<VaultDocument?> read(String path) async => null;

  @override
  Future<void> write(VaultDocument document, {String? expectedEtag}) async {}

  @override
  Future<void> delete(String path, {String? expectedEtag}) async {}

  @override
  Future<void> move(String from, String to, {String? expectedEtag}) async {}
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

class _GatedWebDav extends WebDavClient {
  _GatedWebDav()
    : super(
        WebDavCredentials(
          baseUrl: Uri.parse('https://example.test/vault/'),
          username: 'user',
          password: 'secret',
        ),
      );

  final firstStarted = Completer<void>();
  final secondStarted = Completer<void>();
  final firstGate = Completer<void>();
  final secondGate = Completer<void>();
  var calls = 0;

  @override
  Future<List<WebDavEntry>> listTree() async {
    calls++;
    if (calls == 1) {
      firstStarted.complete();
      await firstGate.future;
    } else {
      secondStarted.complete();
      await secondGate.future;
    }
    return const [];
  }
}
