import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../shared/app_log.dart';

class EncryptedObjectStore {
  EncryptedObjectStore({
    FlutterSecureStorage? secureStorage,
    Cipher? cipher,
    this.namespace = 'default',
    this.migrateLegacy = false,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _cipher = cipher ?? AesGcm.with256bits();

  static const _masterKeyName = 'pavel_vault.master_key.v1';
  final FlutterSecureStorage _secureStorage;
  final Cipher _cipher;
  final String namespace;
  final bool migrateLegacy;
  SecretKey? _key;
  Directory? _root;

  Future<void> initialize() async {
    final support = await getApplicationSupportDirectory();
    final legacy = Directory(p.join(support.path, 'encrypted_vault'));
    _root = Directory(p.join(legacy.path, _safeNamespace(namespace)));
    if (migrateLegacy && !await _root!.exists() && await legacy.exists()) {
      final legacyFiles = await legacy
          .list(followLinks: false)
          .where((item) => item is File && item.path.endsWith('.pvo'))
          .toList();
      if (legacyFiles.isNotEmpty) {
        await _root!.create(recursive: true);
        for (final entity in legacyFiles) {
          final name = p.basename(entity.path);
          await (entity as File).rename(p.join(_root!.path, name));
        }
        AppLog.info(
          'EncryptedStore',
          'Старый кеш перенесён в профиль $namespace',
        );
      }
    }
    await _root!.create(recursive: true);
    await _removeStaleTemporaryFiles();
    AppLog.info(
      'EncryptedStore',
      'Локальный зашифрованный кэш: ${_root!.path}',
    );
    final stored = await _secureStorage.read(key: _masterKeyName);
    if (stored == null) {
      final key = await _cipher.newSecretKey();
      final bytes = await key.extractBytes();
      await _secureStorage.write(
        key: _masterKeyName,
        value: base64UrlEncode(bytes),
      );
      _key = key;
      AppLog.info('EncryptedStore', 'Создан новый мастер-ключ AES-256-GCM');
    } else {
      _key = SecretKey(base64Url.decode(stored));
      AppLog.debug(
        'EncryptedStore',
        'Мастер-ключ загружен из системного secure storage',
      );
    }
  }

  Future<void> write(String key, Uint8List clearBytes) async {
    _ensureReady();
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      clearBytes,
      secretKey: _key!,
      nonce: nonce,
    );
    final payload = <int>[
      1,
      nonce.length,
      ...nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ];
    final target = _file(key);
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
    );
    try {
      await temporary.writeAsBytes(payload, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uint8List?> read(String key) async {
    _ensureReady();
    final file = _file(key);
    if (!await file.exists()) return null;
    final payload = await file.readAsBytes();
    if (payload.length < 2 || payload.first != 1) {
      throw const FormatException('Unsupported encrypted object format');
    }
    final nonceLength = payload[1];
    final nonceEnd = 2 + nonceLength;
    final macEnd = nonceEnd + 16;
    if (payload.length < macEnd) {
      throw const FormatException('Corrupt encrypted object');
    }
    final box = SecretBox(
      payload.sublist(macEnd),
      nonce: payload.sublist(2, nonceEnd),
      mac: Mac(payload.sublist(nonceEnd, macEnd)),
    );
    return Uint8List.fromList(await _cipher.decrypt(box, secretKey: _key!));
  }

  Future<void> remove(String key) async {
    _ensureReady();
    final file = _file(key);
    if (await file.exists()) await file.delete();
  }

  Future<void> clear() async {
    _ensureReady();
    if (await _root!.exists()) await _root!.delete(recursive: true);
    await _root!.create(recursive: true);
  }

  Future<int> sizeBytes() async {
    _ensureReady();
    if (!await _root!.exists()) return 0;
    var total = 0;
    await for (final entity in _root!.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  Future<Set<String>> keys() async {
    _ensureReady();
    final result = <String>{};
    await for (final entity in _root!.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.pvo')) continue;
      final encoded = p.basenameWithoutExtension(entity.path);
      try {
        final padding = '=' * ((4 - encoded.length % 4) % 4);
        result.add(utf8.decode(base64Url.decode('$encoded$padding')));
      } catch (error) {
        AppLog.warning(
          'EncryptedStore',
          'Пропущено имя объекта, которое невозможно декодировать: $encoded',
        );
      }
    }
    return result;
  }

  Future<DateTime?> lastModified(String key) async {
    _ensureReady();
    final file = _file(key);
    return await file.exists() ? file.lastModified() : null;
  }

  File _file(String key) {
    final safe = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File(p.join(_root!.path, '$safe.pvo'));
  }

  void _ensureReady() {
    if (_root == null || _key == null) {
      throw StateError('EncryptedObjectStore.initialize() was not called');
    }
  }

  Future<void> _removeStaleTemporaryFiles() async {
    await for (final entity in _root!.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).contains('.pvo.tmp-')) {
        await entity.delete();
      }
    }
  }

  String _safeNamespace(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
