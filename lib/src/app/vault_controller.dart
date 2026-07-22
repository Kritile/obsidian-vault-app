import 'package:flutter/foundation.dart';

import '../core/cache/image_cache_service.dart';
import '../core/crypto/encrypted_object_store.dart';
import '../core/markdown/obsidian_parser.dart';
import '../core/markdown/work_entry_codec.dart';
import '../core/sync/webdav_profile.dart';
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
}
