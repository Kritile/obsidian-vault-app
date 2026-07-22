import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/encrypted_object_store.dart';
import 'vault_models.dart';
import 'vault_repository.dart';
import '../../shared/app_log.dart';

class EncryptedCachedRepository
    implements VaultRepository, BatchableVaultRepository {
  EncryptedCachedRepository(this._store);
  final EncryptedObjectStore _store;
  static const _manifestKey = '__manifest__';
  static const _manifestBackupKey = '__manifest_backup__';
  static const _batchJournalKey = '__manifest_batch_v1__';
  static const _formatVersion = 2;
  final Map<String, _ManifestItem> _manifest = {};
  var _batchDepth = 0;
  var _manifestDirty = false;
  final _sha256 = Sha256();

  Future<void> initialize({bool verifyIntegrity = false}) async {
    await _store.initialize();
    final loaded = await _loadManifest();
    _manifest.addAll(loaded.entries);
    final journalPresent = await _safeRead(_batchJournalKey) != null;
    final requiresReconciliation =
        verifyIntegrity ||
        loaded.recoveredFromBackup ||
        loaded.legacy ||
        journalPresent;
    final repaired = requiresReconciliation
        ? await _reconcileWithStoredObjects()
        : false;
    if (loaded.recoveredFromBackup ||
        loaded.legacy ||
        repaired ||
        journalPresent) {
      await _saveManifest();
    }
    if (journalPresent) await _store.remove(_batchJournalKey);
    AppLog.info(
      'Cache',
      'Загружен локальный manifest v$_formatVersion: ${_manifest.length} файлов',
    );
  }

  Future<void> verifyIntegrity() async {
    final repaired = await _reconcileWithStoredObjects();
    if (repaired) await _saveManifest();
  }

  @override
  Future<List<VaultDocument>> list() async {
    final documents = <VaultDocument>[];
    for (final path in [..._manifest.keys]) {
      final document = await _read(path, saveHash: false);
      if (document != null) documents.add(document);
    }
    if (_manifestDirty && _batchDepth == 0) await _saveManifest();
    documents.sort((a, b) => a.path.compareTo(b.path));
    return documents;
  }

  @override
  Future<VaultDocument?> read(String path) async {
    return _read(path, saveHash: true);
  }

  Future<VaultDocument?> _read(String path, {required bool saveHash}) async {
    final item = _manifest[path];
    if (item == null) return null;
    Uint8List? bytes;
    try {
      bytes = await _store.read(path);
    } catch (error, stackTrace) {
      AppLog.error(
        'Cache',
        'Повреждён локальный объект $path',
        error,
        stackTrace,
      );
    }
    if (bytes == null) {
      _manifest.remove(path);
      await _manifestChanged();
      return null;
    }
    var hash = item.hash;
    if (hash == null) {
      hash = base64UrlEncode((await _sha256.hash(bytes)).bytes);
      _manifest[path] = item.copyWith(hash: hash);
      _manifestDirty = true;
      if (saveHash && _batchDepth == 0) await _saveManifest();
    }
    return VaultDocument(
      path: path,
      bytes: bytes,
      modifiedAt: item.modifiedAt,
      etag: item.etag,
      contentHash: hash,
    );
  }

  @override
  Future<void> write(VaultDocument document, {String? expectedEtag}) async {
    final current = _manifest[document.path];
    if (expectedEtag != null && current?.etag != expectedEtag) {
      throw StateError('Local revision changed for ${document.path}');
    }
    await _store.write(document.path, document.bytes);
    final hash =
        document.contentHash ??
        base64UrlEncode((await _sha256.hash(document.bytes)).bytes);
    _manifest[document.path] = _ManifestItem(
      document.modifiedAt,
      document.etag,
      hash,
    );
    await _manifestChanged();
    AppLog.debug(
      'Cache',
      'Сохранён ${document.path} (${document.bytes.length} байт)',
    );
  }

  @override
  Future<void> move(String from, String to, {String? expectedEtag}) async {
    final document = await read(from);
    if (document == null) throw StateError('File does not exist: $from');
    if (expectedEtag != null && document.etag != expectedEtag) {
      throw StateError('Local revision changed for $from');
    }
    await write(
      VaultDocument(
        path: to,
        bytes: document.bytes,
        modifiedAt: DateTime.now().toUtc(),
        etag: document.etag,
      ),
    );
    await delete(from);
  }

  @override
  Future<void> delete(String path, {String? expectedEtag}) async {
    final current = _manifest[path];
    if (expectedEtag != null && current?.etag != expectedEtag) {
      throw StateError('Local revision changed for $path');
    }
    _manifest.remove(path);
    await _store.remove(path);
    await _manifestChanged();
    AppLog.debug('Cache', 'Удалён локальный объект $path');
  }

  Future<void> _saveManifest() async {
    final current = await _safeRead(_manifestKey);
    if (current != null && await _isValidManifest(current)) {
      await _store.write(_manifestBackupKey, current);
    }
    await _store.write(_manifestKey, await _encodeManifest());
    _manifestDirty = false;
  }

  @override
  Future<void> beginBatch() async {
    if (_batchDepth == 0) {
      await _store.write(
        _batchJournalKey,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'formatVersion': 1,
              'startedAt': DateTime.now().toUtc().toIso8601String(),
            }),
          ),
        ),
      );
    }
    _batchDepth++;
    AppLog.debug('Cache', 'Начат пакет изменений, глубина $_batchDepth');
  }

  @override
  Future<void> endBatch() async {
    if (_batchDepth == 0) return;
    _batchDepth--;
    if (_batchDepth == 0 && _manifestDirty) await _saveManifest();
    if (_batchDepth == 0) await _store.remove(_batchJournalKey);
    AppLog.debug('Cache', 'Завершён пакет изменений, глубина $_batchDepth');
  }

  Future<void> _manifestChanged() async {
    _manifestDirty = true;
    if (_batchDepth == 0) await _saveManifest();
  }

  Future<_LoadedManifest> _loadManifest() async {
    final primary = await _safeRead(_manifestKey);
    if (primary != null) {
      try {
        return await _decodeManifest(primary);
      } catch (error) {
        AppLog.warning('Cache', 'Основной manifest повреждён: $error');
      }
    }
    final backup = await _safeRead(_manifestBackupKey);
    if (backup != null) {
      try {
        final decoded = await _decodeManifest(backup);
        AppLog.warning('Cache', 'Manifest восстановлен из резервной копии');
        return decoded.copyWith(recoveredFromBackup: true);
      } catch (error) {
        AppLog.warning('Cache', 'Резервный manifest повреждён: $error');
      }
    }
    AppLog.warning(
      'Cache',
      'Manifest отсутствует; выполняется сканирование кеша',
    );
    return const _LoadedManifest({}, legacy: true);
  }

  Future<_LoadedManifest> _decodeManifest(Uint8List bytes) async {
    final decoded = Map<String, Object?>.from(
      jsonDecode(utf8.decode(bytes)) as Map,
    );
    final version = decoded['formatVersion'];
    if (version == null) {
      return _LoadedManifest(_parseEntries(decoded), legacy: true);
    }
    if (version != _formatVersion) {
      throw FormatException('Неподдерживаемая версия manifest: $version');
    }
    final rawEntries = Map<String, Object?>.from(decoded['entries']! as Map);
    final expected = decoded['checksum']?.toString();
    final actual = await _entriesChecksum(rawEntries);
    if (expected == null || expected != actual) {
      throw const FormatException('Checksum manifest не совпадает');
    }
    return _LoadedManifest(_parseEntries(rawEntries));
  }

  Map<String, _ManifestItem> _parseEntries(Map<String, Object?> entries) => {
    for (final entry in entries.entries)
      entry.key: _ManifestItem.fromJson(
        Map<String, Object?>.from(entry.value! as Map),
      ),
  };

  Future<Uint8List> _encodeManifest() async {
    final entries = _orderedEntriesJson();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'formatVersion': _formatVersion,
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'checksum': await _entriesChecksum(entries),
          'entries': entries,
        }),
      ),
    );
  }

  Map<String, Object?> _orderedEntriesJson() {
    final paths = _manifest.keys.toList()..sort();
    return {for (final path in paths) path: _manifest[path]!.toJson()};
  }

  Future<String> _entriesChecksum(Map<String, Object?> entries) async {
    final paths = entries.keys.toList()..sort();
    final canonical = jsonEncode({
      for (final path in paths) path: entries[path],
    });
    return base64UrlEncode((await _sha256.hash(utf8.encode(canonical))).bytes);
  }

  Future<bool> _isValidManifest(Uint8List bytes) async {
    try {
      await _decodeManifest(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Uint8List?> _safeRead(String key) async {
    try {
      return await _store.read(key);
    } catch (error) {
      AppLog.warning('Cache', 'Не удалось прочитать $key: $error');
      return null;
    }
  }

  Future<bool> _reconcileWithStoredObjects() async {
    final storedKeys = await _store.keys();
    final vaultKeys = storedKeys.where(_isVaultObject).toSet();
    var changed = false;

    for (final path in [..._manifest.keys]) {
      if (!vaultKeys.contains(path)) {
        _manifest.remove(path);
        changed = true;
      }
    }

    for (final path in vaultKeys) {
      try {
        final bytes = await _store.read(path);
        if (bytes == null) continue;
        final hash = base64UrlEncode((await _sha256.hash(bytes)).bytes);
        final current = _manifest[path];
        if (current == null) {
          _manifest[path] = _ManifestItem(
            (await _store.lastModified(path))?.toUtc() ??
                DateTime.now().toUtc(),
            null,
            hash,
          );
          changed = true;
          AppLog.warning('Cache', 'В manifest возвращён объект-сирота: $path');
        } else if (current.hash != hash) {
          _manifest[path] = current.copyWith(hash: hash);
          changed = true;
          AppLog.warning(
            'Cache',
            'Обновлён hash восстановленного объекта: $path',
          );
        }
      } catch (error) {
        if (_manifest.remove(path) != null) changed = true;
        AppLog.warning('Cache', 'Повреждённый объект исключён: $path ($error)');
      }
    }
    return changed;
  }

  bool _isVaultObject(String key) =>
      key != _manifestKey &&
      key != _manifestBackupKey &&
      key != _batchJournalKey &&
      key != '__sync_state__' &&
      key != '__sync_outbox_v1__' &&
      key != '__image_cache_manifest_v1__' &&
      !key.startsWith('__draft_v1__:') &&
      !key.startsWith('__base__:') &&
      !key.startsWith('__image__:');
}

class _LoadedManifest {
  const _LoadedManifest(
    this.entries, {
    this.recoveredFromBackup = false,
    this.legacy = false,
  });

  final Map<String, _ManifestItem> entries;
  final bool recoveredFromBackup;
  final bool legacy;

  _LoadedManifest copyWith({bool? recoveredFromBackup}) => _LoadedManifest(
    entries,
    recoveredFromBackup: recoveredFromBackup ?? this.recoveredFromBackup,
    legacy: legacy,
  );
}

class _ManifestItem {
  const _ManifestItem(this.modifiedAt, this.etag, this.hash);
  final DateTime modifiedAt;
  final String? etag;
  final String? hash;

  factory _ManifestItem.fromJson(Map<String, Object?> json) => _ManifestItem(
    DateTime.parse(json['modifiedAt']! as String),
    json['etag'] as String?,
    json['hash'] as String?,
  );

  _ManifestItem copyWith({String? hash}) =>
      _ManifestItem(modifiedAt, etag, hash ?? this.hash);

  Map<String, Object?> toJson() => {
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    'etag': etag,
    'hash': hash,
  };
}
