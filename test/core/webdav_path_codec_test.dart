import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/sync/webdav_client.dart';

void main() {
  final base = Uri.parse(
    'https://cloud.example.com/remote.php/dav/files/pavel/vault/',
  );

  test('does not decode valid percent sign twice', () {
    final path = WebDavPathCodec.relativePath(
      base,
      '/remote.php/dav/files/pavel/vault/Areas/%D0%90%D0%BF%D1%82%D0%B5%D1%87%D0%BA%D0%B0/%D0%9A%D0%B5%D1%82%D0%BE%D0%BF%D1%80%D0%BE%D1%84%D0%B5%D0%BD%202.5%25.md',
    );
    expect(path, 'Areas/Аптечка/Кетопрофен 2.5%.md');
  });

  test('accepts malformed raw percent returned by a WebDAV server', () {
    final path = WebDavPathCodec.relativePath(
      base,
      '/remote.php/dav/files/pavel/vault/Areas/Medicine 2.5%.md',
    );
    expect(path, 'Areas/Medicine 2.5%.md');
  });

  test('encodes percent and Cyrillic exactly once for requests', () {
    expect(
      WebDavPathCodec.childUrl(base, 'Areas/Аптечка/Кетопрофен 2.5%.md'),
      'https://cloud.example.com/remote.php/dav/files/pavel/vault/Areas/%D0%90%D0%BF%D1%82%D0%B5%D1%87%D0%BA%D0%B0/%D0%9A%D0%B5%D1%82%D0%BE%D0%BF%D1%80%D0%BE%D1%84%D0%B5%D0%BD%202.5%25.md',
    );
  });

  test('normalizes a user-entered URL with a literal percent', () {
    expect(
      WebDavPathCodec.parseBaseUrl(
        'https://cloud.example.com/My 2.5% vault',
      )?.toString(),
      'https://cloud.example.com/My%202.5%25%20vault/',
    );
  });

  test('rejects public HTTP WebDAV', () {
    expect(
      WebDavPathCodec.parseBaseUrl('http://cloud.example.com/vault'),
      isNull,
    );
  });

  test('allows HTTP only for local addresses with a warning', () {
    final localhost = WebDavPathCodec.parseBaseUrl(
      'http://localhost:8080/vault',
    );
    final lan = WebDavPathCodec.parseBaseUrl('http://192.168.1.20/vault');

    expect(localhost, isNotNull);
    expect(lan, isNotNull);
    expect(WebDavPathCodec.securityWarning(lan!), contains('без TLS'));
  });
}
