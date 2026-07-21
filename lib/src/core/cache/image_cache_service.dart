import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../crypto/encrypted_object_store.dart';
import '../vault/encrypted_cached_repository.dart';
import '../../shared/app_log.dart';

class ImageCacheService {
  ImageCacheService({
    required EncryptedObjectStore store,
    required EncryptedCachedRepository vault,
    Dio? dio,
    this.maxBytes = 250 * 1024 * 1024,
  }) : _store = store,
       _vault = vault,
       _dio = dio ?? Dio();

  static const _manifestKey = '__image_cache_manifest_v1__';
  final EncryptedObjectStore _store;
  final EncryptedCachedRepository _vault;
  final Dio _dio;
  final _sha = Sha256();
  int maxBytes;
  final Map<String, _ImageEntry> _entries = {};

  Future<void> initialize() async {
    final bytes = await _store.read(_manifestKey);
    if (bytes == null) return;
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      for (final entry in json.entries) {
        _entries[entry.key] = _ImageEntry.fromJson(
          Map<String, Object?>.from(entry.value! as Map),
        );
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'Images',
        'Не удалось прочитать manifest изображений',
        error,
        stackTrace,
      );
    }
  }

  int get sizeBytes => _entries.values.fold(0, (sum, item) => sum + item.size);

  Future<Uint8List?> load(String source, {String? notePath}) async {
    final normalized = _normalizeReference(source);
    final uri = Uri.tryParse(normalized);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _loadNetwork(uri);
    }
    final path = _resolveVaultPath(normalized, notePath);
    final document = await _vault.read(path);
    if (document != null) return document.bytes;
    final byName = (await _vault.list())
        .where((item) => p.basename(item.path) == p.basename(path))
        .firstOrNull;
    return byName?.bytes;
  }

  Future<Uint8List?> _loadNetwork(Uri uri) async {
    final id = await _id(uri.toString());
    final cached = _entries[id];
    if (cached != null) {
      final bytes = await _store.read('__image__:$id');
      if (bytes != null) {
        _entries[id] = cached.copyWith(accessedAt: DateTime.now().toUtc());
        _saveManifest();
        _refresh(uri, id, cached);
        return bytes;
      }
    }
    try {
      final response = await _dio.get<List<int>>(
        uri.toString(),
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data ?? const []);
      if (bytes.isEmpty) return null;
      await _storeNetwork(uri, id, bytes, response.headers);
      return bytes;
    } catch (error) {
      AppLog.warning('Images', 'Изображение недоступно: ${uri.host} ($error)');
      return null;
    }
  }

  Future<void> _refresh(Uri uri, String id, _ImageEntry old) async {
    try {
      final response = await _dio.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            if (old.etag != null) 'If-None-Match': old.etag,
            if (old.lastModified != null) 'If-Modified-Since': old.lastModified,
          },
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        await _storeNetwork(
          uri,
          id,
          Uint8List.fromList(response.data!),
          response.headers,
        );
      }
    } catch (_) {
      // Stale cache remains available while offline.
    }
  }

  Future<void> _storeNetwork(
    Uri uri,
    String id,
    Uint8List bytes,
    Headers headers,
  ) async {
    await _store.write('__image__:$id', bytes);
    _entries[id] = _ImageEntry(
      url: uri.toString(),
      size: bytes.length,
      accessedAt: DateTime.now().toUtc(),
      etag: headers.value('etag'),
      lastModified: headers.value('last-modified'),
    );
    await _evict();
    await _saveManifest();
  }

  Future<void> _evict() async {
    if (maxBytes <= 0) return;
    final ordered = _entries.entries.toList()
      ..sort((a, b) => a.value.accessedAt.compareTo(b.value.accessedAt));
    while (sizeBytes > maxBytes && ordered.isNotEmpty) {
      final oldest = ordered.removeAt(0);
      _entries.remove(oldest.key);
      await _store.remove('__image__:${oldest.key}');
    }
  }

  Future<void> clear() async {
    for (final id in _entries.keys.toList()) {
      await _store.remove('__image__:$id');
    }
    _entries.clear();
    await _store.remove(_manifestKey);
  }

  Future<void> setLimit(int value) async {
    maxBytes = value;
    await _evict();
    await _saveManifest();
  }

  Future<void> _saveManifest() => _store.write(
    _manifestKey,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          for (final entry in _entries.entries) entry.key: entry.value.toJson(),
        }),
      ),
    ),
  );

  Future<String> _id(String value) async => base64Url
      .encode((await _sha.hash(utf8.encode(value))).bytes)
      .replaceAll('=', '');

  String _normalizeReference(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^!\[\['), '')
      .replaceFirst(RegExp(r'\]\]$'), '')
      .split('|')
      .first
      .trim();

  String _resolveVaultPath(String value, String? notePath) {
    if (value.startsWith('/')) return value.substring(1);
    if (value.contains('/')) return p.posix.normalize(value);
    if (notePath == null) return value;
    return p.posix.normalize(p.posix.join(p.posix.dirname(notePath), value));
  }
}

class _ImageEntry {
  const _ImageEntry({
    required this.url,
    required this.size,
    required this.accessedAt,
    this.etag,
    this.lastModified,
  });
  final String url;
  final int size;
  final DateTime accessedAt;
  final String? etag;
  final String? lastModified;

  _ImageEntry copyWith({DateTime? accessedAt}) => _ImageEntry(
    url: url,
    size: size,
    accessedAt: accessedAt ?? this.accessedAt,
    etag: etag,
    lastModified: lastModified,
  );

  Map<String, Object?> toJson() => {
    'url': url,
    'size': size,
    'accessedAt': accessedAt.toIso8601String(),
    if (etag != null) 'etag': etag,
    if (lastModified != null) 'lastModified': lastModified,
  };

  factory _ImageEntry.fromJson(Map<String, Object?> json) => _ImageEntry(
    url: json['url']!.toString(),
    size: (json['size'] as num).toInt(),
    accessedAt: DateTime.parse(json['accessedAt']!.toString()),
    etag: json['etag']?.toString(),
    lastModified: json['lastModified']?.toString(),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
