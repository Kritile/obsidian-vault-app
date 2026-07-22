import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../sync/webdav_client.dart';
import '../sync/webdav_profile.dart';
import '../cache/storage_models.dart';
import '../../shared/app_log.dart';

class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _profilesKey = 'webdav.profiles.v2';
  static const _activeProfileKey = 'webdav.activeProfile.v2';

  Future<List<WebDavProfile>> readProfiles() async {
    final encoded = await _storage.read(key: _profilesKey);
    if (encoded != null) {
      try {
        return (jsonDecode(encoded) as List)
            .whereType<Map>()
            .map(
              (item) => WebDavProfile.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false);
      } catch (error, stackTrace) {
        AppLog.error(
          'Credentials',
          'Список WebDAV-профилей повреждён',
          error,
          stackTrace,
        );
      }
    }
    final legacy = await _readLegacyWebDav();
    if (legacy == null) return const [];
    final profile = WebDavProfile(
      id: _profileId(legacy.baseUrl, legacy.username),
      name: legacy.baseUrl.host,
      baseUrl: legacy.baseUrl,
      username: legacy.username,
      password: legacy.password,
    );
    await saveProfile(profile);
    await setActiveProfile(profile.id);
    AppLog.info(
      'Credentials',
      'Старое WebDAV-подключение перенесено в профиль ${profile.name}',
    );
    return [profile];
  }

  Future<String?> readActiveProfileId() =>
      _storage.read(key: _activeProfileKey);

  Future<void> setActiveProfile(String id) =>
      _storage.write(key: _activeProfileKey, value: id);

  Future<void> saveProfile(WebDavProfile profile) async {
    final profiles = [...await readProfilesWithoutMigration()];
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _storage.write(
      key: _profilesKey,
      value: jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> deleteProfile(String id) async {
    final profiles = (await readProfilesWithoutMigration())
        .where((item) => item.id != id)
        .toList(growable: false);
    await _storage.write(
      key: _profilesKey,
      value: jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    if (await readActiveProfileId() == id) {
      await _storage.delete(key: _activeProfileKey);
    }
  }

  Future<List<WebDavProfile>> readProfilesWithoutMigration() async {
    final encoded = await _storage.read(key: _profilesKey);
    if (encoded == null) return const [];
    return (jsonDecode(encoded) as List)
        .whereType<Map>()
        .map((item) => WebDavProfile.fromJson(Map<String, Object?>.from(item)))
        .toList(growable: false);
  }

  Future<WebDavCredentials?> readWebDav() async {
    final profiles = await readProfiles();
    final activeId = await readActiveProfileId();
    final active =
        profiles.where((item) => item.id == activeId).firstOrNull ??
        profiles.firstOrNull;
    return active?.credentials;
  }

  Future<WebDavCredentials?> _readLegacyWebDav() async {
    AppLog.debug(
      'Credentials',
      'Чтение конфигурации WebDAV из системного secure storage',
    );
    final url = await _storage.read(key: 'webdav.url');
    final username = await _storage.read(key: 'webdav.username');
    final password = await _storage.read(key: 'webdav.password');
    if (url == null || username == null || password == null) {
      AppLog.info('Credentials', 'Сохранённая конфигурация WebDAV не найдена');
      return null;
    }
    final uri = WebDavPathCodec.parseBaseUrl(url);
    if (uri == null) {
      AppLog.warning('Credentials', 'Сохранённый WebDAV URL некорректен');
      return null;
    }
    AppLog.info(
      'Credentials',
      'Конфигурация найдена: ${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}',
    );
    return WebDavCredentials(
      baseUrl: uri,
      username: username,
      password: password,
    );
  }

  Future<void> saveWebDav(WebDavCredentials value) async {
    AppLog.info(
      'Credentials',
      'Сохранение WebDAV-конфигурации для ${value.baseUrl.host}; секреты в лог не выводятся',
    );
    await _storage.write(key: 'webdav.url', value: value.baseUrl.toString());
    await _storage.write(key: 'webdav.username', value: value.username);
    await _storage.write(key: 'webdav.password', value: value.password);
    final profile = WebDavProfile(
      id: _profileId(value.baseUrl, value.username),
      name: value.baseUrl.host,
      baseUrl: value.baseUrl,
      username: value.username,
      password: value.password,
    );
    await saveProfile(profile);
    await setActiveProfile(profile.id);
  }

  String _profileId(Uri url, String username) => base64Url
      .encode(utf8.encode('${url.toString().toLowerCase()}|$username'))
      .replaceAll('=', '')
      .substring(0, 16);

  Future<void> savePin(String pin) async {
    AppLog.debug('Credentials', 'Создание PBKDF2-хеша PIN');
    final salt = await _salt();
    final hash = await _pinHash(pin, salt);
    await _storage.write(key: 'lock.pinHash', value: base64UrlEncode(hash));
  }

  Future<int> readImageCacheLimit() async =>
      int.tryParse(
        await _storage.read(key: 'settings.imageCacheLimit') ?? '',
      ) ??
      250 * 1024 * 1024;

  Future<void> saveImageCacheLimit(int value) =>
      _storage.write(key: 'settings.imageCacheLimit', value: value.toString());

  Future<String> readAttachmentFolder() async =>
      await _storage.read(key: 'settings.attachmentFolder') ?? 'Attachments';

  Future<void> saveAttachmentFolder(String value) =>
      _storage.write(key: 'settings.attachmentFolder', value: value);

  Future<MotionPreference> readMotionPreference() async {
    final value = await _storage.read(key: 'settings.motion');
    return MotionPreference.values
            .where((item) => item.name == value)
            .firstOrNull ??
        MotionPreference.expressive;
  }

  Future<void> saveMotionPreference(MotionPreference value) =>
      _storage.write(key: 'settings.motion', value: value.name);

  Future<Duration> readAutoLockDelay() async {
    final seconds = int.tryParse(
      await _storage.read(key: 'settings.autoLockSeconds') ?? '',
    );
    return Duration(seconds: seconds ?? 5 * 60);
  }

  Future<void> saveAutoLockDelay(Duration value) => _storage.write(
    key: 'settings.autoLockSeconds',
    value: value.inSeconds.toString(),
  );

  Future<bool> verifyPin(String pin) async {
    final expected = await _storage.read(key: 'lock.pinHash');
    if (expected == null) return false;
    final actual = await _pinHash(pin, await _salt());
    return _constantTime(base64Url.decode(expected), actual);
  }

  Future<bool> get hasPin async =>
      await _storage.read(key: 'lock.pinHash') != null;

  Future<List<int>> _salt() async {
    final stored = await _storage.read(key: 'lock.pinSalt');
    if (stored != null) return base64Url.decode(stored);
    final salt = SecretKeyData.random(length: 16).bytes;
    await _storage.write(key: 'lock.pinSalt', value: base64UrlEncode(salt));
    return salt;
  }

  Future<List<int>> _pinHash(String pin, List<int> salt) async =>
      (await Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: 120000,
            bits: 256,
          ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt))
          .extractBytes();

  bool _constantTime(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class AppLockService {
  AppLockService(this._credentials, {LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();
  final CredentialStore _credentials;
  final LocalAuthentication _authentication;

  Future<bool> unlockWithSystem() async {
    try {
      if (!await _authentication.isDeviceSupported()) return false;
      return _authentication.authenticate(
        localizedReason: 'Разблокировать Vellum',
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithPin(String pin) => _credentials.verifyPin(pin);
}
