import 'dart:convert';
import 'dart:typed_data';

import '../crypto/encrypted_object_store.dart';
import 'vault_models.dart';
import 'vault_repository.dart';
import '../../shared/app_log.dart';

class EncryptedCachedRepository implements VaultRepository, BatchableVaultRepository {
  EncryptedCachedRepository(this._store);
  final EncryptedObjectStore _store;
  static const _manifestKey = '__manifest__';
  final Map<String, _ManifestItem> _manifest = {};
  var _batchDepth = 0;
  var _manifestDirty = false;

  Future<void> initialize() async {
    await _store.initialize();
    final bytes = await _store.read(_manifestKey);
    if (bytes == null) {
      AppLog.info('Cache', 'Локальный manifest отсутствует; ожидается первая синхронизация');
      return;
    }
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    for (final entry in decoded.entries) {
      _manifest[entry.key] = _ManifestItem.fromJson(entry.value! as Map<String, Object?>);
    }
    AppLog.info('Cache', 'Загружен локальный manifest: ${_manifest.length} файлов');
  }

  @override
  Future<List<VaultDocument>> list() async {
    final documents = <VaultDocument>[];
    for (final path in _manifest.keys) {
      final document = await read(path);
      if (document != null) documents.add(document);
    }
    documents.sort((a, b) => a.path.compareTo(b.path));
    return documents;
  }

  @override
  Future<VaultDocument?> read(String path) async {
    final item = _manifest[path];
    if (item == null) return null;
    final bytes = await _store.read(path);
    if (bytes == null) return null;
    return VaultDocument(
      path: path,
      bytes: bytes,
      modifiedAt: item.modifiedAt,
      etag: item.etag,
    );
  }

  @override
  Future<void> write(VaultDocument document, {String? expectedEtag}) async {
    final current = _manifest[document.path];
    if (expectedEtag != null && current?.etag != expectedEtag) {
      throw StateError('Local revision changed for ${document.path}');
    }
    await _store.write(document.path, document.bytes);
    _manifest[document.path] = _ManifestItem(document.modifiedAt, document.etag);
    await _manifestChanged();
    AppLog.debug('Cache', 'Сохранён ${document.path} (${document.bytes.length} байт)');
  }

  @override
  Future<void> move(String from, String to, {String? expectedEtag}) async {
    final document = await read(from);
    if (document == null) throw StateError('File does not exist: $from');
    if (expectedEtag != null && document.etag != expectedEtag) {
      throw StateError('Local revision changed for $from');
    }
    await write(VaultDocument(
      path: to,
      bytes: document.bytes,
      modifiedAt: DateTime.now().toUtc(),
      etag: document.etag,
    ));
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
    final encoded = utf8.encode(jsonEncode({
      for (final entry in _manifest.entries) entry.key: entry.value.toJson(),
    }));
    await _store.write(_manifestKey, Uint8List.fromList(encoded));
    _manifestDirty = false;
  }

  @override
  Future<void> beginBatch() async {
    _batchDepth++;
    AppLog.debug('Cache', 'Начат пакет изменений, глубина $_batchDepth');
  }

  @override
  Future<void> endBatch() async {
    if (_batchDepth == 0) return;
    _batchDepth--;
    if (_batchDepth == 0 && _manifestDirty) await _saveManifest();
    AppLog.debug('Cache', 'Завершён пакет изменений, глубина $_batchDepth');
  }

  Future<void> _manifestChanged() async {
    _manifestDirty = true;
    if (_batchDepth == 0) await _saveManifest();
  }
}

class _ManifestItem {
  const _ManifestItem(this.modifiedAt, this.etag);
  final DateTime modifiedAt;
  final String? etag;

  factory _ManifestItem.fromJson(Map<String, Object?> json) => _ManifestItem(
        DateTime.parse(json['modifiedAt']! as String),
        json['etag'] as String?,
      );

  Map<String, Object?> toJson() => {
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
        'etag': etag,
      };
}
