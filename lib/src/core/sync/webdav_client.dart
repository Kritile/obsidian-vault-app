import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

import '../../shared/app_log.dart';

class WebDavCredentials {
  const WebDavCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });
  final Uri baseUrl;
  final String username;
  final String password;
}

class WebDavPathCodec {
  const WebDavPathCodec._();

  static Uri? parseBaseUrl(String raw) {
    final sanitized = _sanitizePercent(raw.trim()).replaceAll(' ', '%20');
    final uri = Uri.tryParse(sanitized);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }

  static String relativePath(Uri base, String href) {
    final uri = Uri.parse(_sanitizePercent(href.trim()).replaceAll(' ', '%20'));
    final baseSegments = base.pathSegments
        .where((part) => part.isNotEmpty)
        .length;
    // Uri.pathSegments are already percent-decoded. Decoding them a second time
    // breaks valid Obsidian names such as "Кетопрофен 2.5%.md".
    return uri.pathSegments
        .skip(baseSegments)
        .where((part) => part.isNotEmpty)
        .join('/');
  }

  static String childUrl(Uri base, String path) {
    final encoded = path.split('/').map(Uri.encodeComponent).join('/');
    return base.resolve(encoded).toString();
  }

  static String _sanitizePercent(String value) =>
      value.replaceAllMapped(RegExp(r'%(?![0-9a-fA-F]{2})'), (_) => '%25');
}

class WebDavEntry {
  const WebDavEntry({
    required this.path,
    required this.isDirectory,
    required this.modifiedAt,
    required this.size,
    this.etag,
  });
  final String path;
  final bool isDirectory;
  final DateTime modifiedAt;
  final int size;
  final String? etag;
}

class WebDavClient {
  WebDavClient(WebDavCredentials credentials)
    : _base = credentials.baseUrl.path.endsWith('/')
          ? credentials.baseUrl
          : credentials.baseUrl.replace(path: '${credentials.baseUrl.path}/'),
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
          sendTimeout: const Duration(minutes: 2),
          headers: {
            'Authorization':
                'Basic ${base64Encode(utf8.encode('${credentials.username}:${credentials.password}'))}',
          },
        ),
      ) {
    AppLog.info('WebDAV', 'Клиент настроен: ${_displayUri(_base)}');
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          AppLog.debug(
            'WebDAV',
            '→ ${options.method} ${_displayUri(options.uri)}',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          AppLog.debug(
            'WebDAV',
            '← ${response.statusCode} ${response.requestOptions.method} ${_displayUri(response.requestOptions.uri)}',
          );
          handler.next(response);
        },
        onError: (error, handler) {
          AppLog.error(
            'WebDAV',
            'Сетевая ошибка ${error.requestOptions.method} ${_displayUri(error.requestOptions.uri)}; HTTP ${error.response?.statusCode ?? 'нет ответа'}',
            error.message,
          );
          handler.next(error);
        },
      ),
    );
  }

  final Uri _base;
  final Dio _dio;

  Future<List<WebDavEntry>> listTree() async {
    AppLog.info(
      'WebDAV',
      'Начато рекурсивное чтение дерева через PROPFIND Depth: 1',
    );
    final result = <WebDavEntry>[];
    final pending = <String>[''];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      final entries = await _listDirectory(directory);
      for (final entry in entries) {
        if (entry.path == directory || entry.path.isEmpty) continue;
        result.add(entry);
        if (entry.isDirectory) pending.add(entry.path);
      }
    }
    AppLog.info('WebDAV', 'Дерево получено: ${result.length} объектов');
    return result;
  }

  Future<List<WebDavEntry>> _listDirectory(String directory) async {
    final response = await _dio.request<String>(
      directory.isEmpty ? _base.toString() : _url('$directory/'),
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1', 'Content-Type': 'application/xml'},
        responseType: ResponseType.plain,
        validateStatus: (status) => status == 207,
      ),
      data:
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:getlastmodified/><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>',
    );
    final entries = _parseEntries(response.data ?? '');
    AppLog.debug('WebDAV', 'Каталог /$directory: ${entries.length} объектов');
    return entries;
  }

  Future<WebDavEntry?> entry(String path) async {
    final response = await _dio.request<String>(
      _url(path),
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '0', 'Content-Type': 'application/xml'},
        responseType: ResponseType.plain,
        validateStatus: (status) => status == 207 || status == 404,
      ),
      data:
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:getetag/><d:getlastmodified/><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>',
    );
    if (response.statusCode == 404) return null;
    final entries = _parseEntries(response.data ?? '');
    return entries.where((item) => item.path == path).firstOrNull;
  }

  List<WebDavEntry> _parseEntries(String source) {
    if (source.trim().isEmpty) return const [];
    final xml = XmlDocument.parse(source);
    final entries = <WebDavEntry>[];
    for (final item in xml.findAllElements('response', namespace: 'DAV:')) {
      final href = item.getElement('href', namespace: 'DAV:')?.innerText;
      if (href == null) continue;
      final path = WebDavPathCodec.relativePath(_base, href);
      if (path.isEmpty) continue;
      final property = item
          .findAllElements('prop', namespace: 'DAV:')
          .firstOrNull;
      if (property == null) continue;
      final isDirectory = property
          .findAllElements('collection', namespace: 'DAV:')
          .isNotEmpty;
      final modified =
          DateTime.tryParse(
            property
                    .getElement('getlastmodified', namespace: 'DAV:')
                    ?.innerText ??
                '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      entries.add(
        WebDavEntry(
          path: path,
          isDirectory: isDirectory,
          modifiedAt: modified,
          size:
              int.tryParse(
                property
                        .getElement('getcontentlength', namespace: 'DAV:')
                        ?.innerText ??
                    '',
              ) ??
              0,
          etag: property.getElement('getetag', namespace: 'DAV:')?.innerText,
        ),
      );
    }
    return entries;
  }

  Future<Uint8List> download(String path) async {
    final response = await _dio.get<List<int>>(
      _url(path),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    AppLog.info('WebDAV', 'Скачан $path (${bytes.length} байт)');
    return bytes;
  }

  Future<String?> upload(
    String path,
    Uint8List bytes, {
    String? expectedEtag,
  }) async {
    final response = await _dio.put<void>(
      _url(path),
      data: Stream.value(bytes),
      options: Options(
        headers: {
          'Content-Type': 'application/octet-stream',
          'If-Match': ?expectedEtag,
          if (expectedEtag == null) 'If-None-Match': '*',
        },
        validateStatus: (status) =>
            status != null && (status >= 200 && status < 300 || status == 412),
      ),
    );
    if (response.statusCode == 412) throw WebDavPreconditionFailed(path);
    var etag = response.headers.value('etag');
    etag ??= (await entry(path))?.etag;
    AppLog.info(
      'WebDAV',
      'Отправлен $path (${bytes.length} байт), HTTP ${response.statusCode}, ETag ${etag == null ? 'не получен' : 'обновлён'}',
    );
    return etag;
  }

  Future<void> createDirectory(String path) async {
    await _dio.request<void>(
      _url(path),
      options: Options(
        method: 'MKCOL',
        validateStatus: (status) => status == 201 || status == 405,
      ),
    );
    AppLog.debug('WebDAV', 'Каталог готов: $path');
  }

  Future<void> move(String from, String to, {String? expectedEtag}) async {
    final response = await _dio.request<void>(
      _url(from),
      options: Options(
        method: 'MOVE',
        headers: {
          'Destination': _url(to),
          'Overwrite': 'F',
          'If-Match': ?expectedEtag,
        },
        validateStatus: (status) =>
            status != null && (status >= 200 && status < 300 || status == 412),
      ),
    );
    if (response.statusCode == 412) throw WebDavPreconditionFailed(from);
    AppLog.info('WebDAV', 'Перемещён $from → $to');
  }

  Future<void> delete(String path, {String? expectedEtag}) async {
    final response = await _dio.delete<void>(
      _url(path),
      options: Options(
        headers: {'If-Match': ?expectedEtag},
        validateStatus: (status) =>
            status != null &&
            (status >= 200 && status < 300 || status == 404 || status == 412),
      ),
    );
    if (response.statusCode == 412) throw WebDavPreconditionFailed(path);
    AppLog.info(
      'WebDAV',
      'Удалён удалённый объект $path (HTTP ${response.statusCode})',
    );
  }

  String _url(String path) => WebDavPathCodec.childUrl(_base, path);

  static String _displayUri(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port${uri.path}';
  }
}

class WebDavPreconditionFailed implements Exception {
  const WebDavPreconditionFailed(this.path);
  final String path;
  @override
  String toString() => 'Remote file changed: $path';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
