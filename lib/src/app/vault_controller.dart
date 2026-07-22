import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/cache/image_cache_service.dart';
import '../core/crypto/encrypted_object_store.dart';
import '../core/markdown/obsidian_parser.dart';
import '../core/markdown/work_entry_codec.dart';
import '../core/sync/webdav_profile.dart';
import '../core/sync/webdav_client.dart';
import '../core/sync/storage_capacity_service.dart';
import '../core/vault/encrypted_cached_repository.dart';
import '../core/vault/vault_index.dart';
import '../core/vault/vault_models.dart';
import '../shared/app_log.dart';

class VaultController extends ChangeNotifier {
  VaultController()
    : parser = ObsidianParser(),
      workCodec = WorkEntryCodec(),
      index = VaultIndex(ObsidianParser(), WorkEntryCodec());

  final ObsidianParser parser;
  final WorkEntryCodec workCodec;
  final VaultIndex index;

  late EncryptedObjectStore store;
  late EncryptedCachedRepository cache;
  late ImageCacheService imageCache;
  List<VaultDocument> documents = const [];
  bool ready = false;
  String? lastRecoveryBackupPath;

  Future<void> initializeLocal({required int imageCacheLimitBytes}) async {
    await _openStore(
      EncryptedObjectStore(),
      imageCacheLimitBytes: imageCacheLimitBytes,
    );
  }

  Future<void> activateProfile(
    WebDavProfile profile, {
    required int imageCacheLimitBytes,
    bool migrateLegacy = false,
  }) async {
    await _openStore(
      EncryptedObjectStore(namespace: profile.id, migrateLegacy: migrateLegacy),
      imageCacheLimitBytes: imageCacheLimitBytes,
    );
    AppLog.info('Profiles', 'Открыт локальный vault ${profile.name}');
  }

  Future<void> _openStore(
    EncryptedObjectStore value, {
    required int imageCacheLimitBytes,
  }) async {
    store = value;
    cache = EncryptedCachedRepository(store);
    await cache.initialize();
    imageCache = ImageCacheService(
      store: store,
      vault: cache,
      maxBytes: imageCacheLimitBytes,
    );
    await imageCache.initialize();
    ready = true;
    await refreshIndex();
  }

  Future<VaultDocument?> read(String path) => cache.read(path);

  Future<void> saveLocal(String path, String source) async {
    AppLog.info('Editor', 'Локальное сохранение $path');
    final current = await cache.read(path);
    await cache.write(
      VaultDocument(
        path: path,
        bytes: parser.encode(source),
        modifiedAt: DateTime.now().toUtc(),
        etag: current?.etag,
      ),
    );
    await refreshIndex();
  }

  Future<void> saveBytes(String path, Uint8List bytes) async {
    final current = await cache.read(path);
    await cache.write(
      VaultDocument(
        path: path,
        bytes: bytes,
        modifiedAt: DateTime.now().toUtc(),
        etag: current?.etag,
      ),
    );
    await refreshIndex();
  }

  Future<List<String>> moveNote(String from, String to) async {
    if (!to.toLowerCase().endsWith('.md')) {
      to = '$to.md';
    }
    if (await cache.read(to) != null) {
      throw StateError('Файл уже существует: $to');
    }
    final changed = <String>[];
    await cache.beginBatch();
    try {
      final notes = [...index.notes];
      await cache.move(from, to);
      changed.add(to);
      for (final note in notes.where((item) => item.document.path != from)) {
        final rewritten = _rewriteLinks(note, from, to);
        if (rewritten == note.document.text) continue;
        await cache.write(
          VaultDocument(
            path: note.document.path,
            bytes: parser.encode(rewritten),
            modifiedAt: DateTime.now().toUtc(),
            etag: note.document.etag,
          ),
        );
        changed.add(note.document.path);
      }
    } finally {
      await cache.endBatch();
    }
    await refreshIndex();
    return changed;
  }

  String _rewriteLinks(ParsedNote source, String from, String to) {
    var text = source.document.text.replaceAllMapped(
      RegExp(r'(!?\[\[)([^\]|#]+)(#[^\]|]+)?(\|[^\]]+)?(\]\])'),
      (match) {
        final resolved = index.resolveLink(
          match.group(2)!,
          fromPath: source.document.path,
        );
        if (resolved?.document.path != from) return match.group(0)!;
        final target = to.replaceFirst(RegExp(r'\.md$'), '');
        return '${match.group(1)}$target${match.group(3) ?? ''}${match.group(4) ?? ''}${match.group(5)}';
      },
    );
    text = text.replaceAllMapped(
      RegExp(r'(!?\[[^\]]*\]\()([^)#]+)(#[^)]*)?(\))'),
      (match) {
        final raw = match.group(2)!;
        if (Uri.tryParse(raw)?.hasScheme ?? false) return match.group(0)!;
        final resolved = index.resolveLink(raw, fromPath: source.document.path);
        if (resolved?.document.path != from) return match.group(0)!;
        return '${match.group(1)}$to${match.group(3) ?? ''}${match.group(4)}';
      },
    );
    return text;
  }

  Future<void> refreshIndex() async {
    documents = await cache.list();
    index.rebuild(documents);
    notifyListeners();
  }

  Future<void> clearCurrent({required int imageCacheLimitBytes}) async {
    await store.clear();
    cache = EncryptedCachedRepository(store);
    await cache.initialize();
    imageCache = ImageCacheService(
      store: store,
      vault: cache,
      maxBytes: imageCacheLimitBytes,
    );
    await imageCache.initialize();
    await refreshIndex();
  }

  Future<void> verifyCacheIntegrity() async {
    await cache.verifyIntegrity();
    await refreshIndex();
  }

  Future<void> recoverFromWebDav(WebDavProfile profile) async {
    final remote = WebDavClient(profile.credentials);
    final entries = (await remote.listTree())
        .where((item) => !item.isDirectory)
        .toList(growable: false);
    final remoteBytes = entries.fold<int>(0, (sum, item) => sum + item.size);
    final required =
        remoteBytes + (remoteBytes ~/ 10).clamp(128 * 1024 * 1024, 1 << 62);
    final available = await const StorageCapacityService().availableBytes(
      store.rootPath,
    );
    if (available != null && available < required) {
      throw InsufficientSpaceException(
        requiredBytes: required,
        availableBytes: available,
        location: 'восстановление кеша',
      );
    }

    final oldStore = store;
    final stagingStore = await oldStore.createStaging();
    String? backupPath;
    try {
      final staging = EncryptedCachedRepository(stagingStore);
      await staging.initialize();
      await staging.beginBatch();
      try {
        for (final entry in entries) {
          final bytes = await remote.download(entry.path);
          if (entry.size > 0 && bytes.length != entry.size) {
            throw StateError(
              'Размер ${entry.path} не совпадает: ${bytes.length} вместо ${entry.size}',
            );
          }
          await staging.write(
            VaultDocument(
              path: entry.path,
              bytes: bytes,
              modifiedAt: entry.modifiedAt,
              etag: entry.etag,
            ),
          );
        }

        final outboxBytes = await oldStore.read('__sync_outbox_v1__');
        if (outboxBytes != null) {
          final pending = jsonDecode(utf8.decode(outboxBytes)) as List<Object?>;
          for (final raw in pending) {
            final item = Map<String, Object?>.from(raw! as Map);
            final path = item['kind'] == 'move'
                ? item['destinationPath']?.toString()
                : item['path']?.toString();
            if (path == null) continue;
            final local = await cache.read(path);
            if (local == null) {
              throw StateError(
                'Не удалось сохранить локальное изменение $path; восстановление отменено',
              );
            }
            await staging.write(local);
          }
          await stagingStore.write('__sync_outbox_v1__', outboxBytes);
        }
        for (final key in await oldStore.keys()) {
          if (!key.startsWith('__draft_v1__:')) continue;
          final bytes = await oldStore.read(key);
          if (bytes != null) await stagingStore.write(key, bytes);
        }
      } finally {
        await staging.endBatch();
      }
      await staging.verifyIntegrity();
      for (final entry in await staging.list()) {
        if (await staging.read(entry.path) == null) {
          throw StateError('Не удалось проверить ${entry.path}');
        }
      }
      backupPath = await oldStore.replaceWith(stagingStore);
      lastRecoveryBackupPath = backupPath;
      cache = EncryptedCachedRepository(oldStore);
      await cache.initialize();
      imageCache = ImageCacheService(
        store: oldStore,
        vault: cache,
        maxBytes: imageCache.maxBytes,
      );
      await imageCache.initialize();
      await refreshIndex();
    } catch (_) {
      if (backupPath != null) {
        await oldStore.rollbackFrom(backupPath);
        lastRecoveryBackupPath = null;
        cache = EncryptedCachedRepository(oldStore);
        await cache.initialize();
      } else {
        await stagingStore.destroy();
      }
      rethrow;
    }
  }
}
