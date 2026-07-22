// Named public constructor arguments intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/crypto/credential_store.dart';
import '../core/crypto/encrypted_object_store.dart';
import '../core/sync/webdav_client.dart';
import '../core/sync/webdav_profile.dart';
import '../shared/app_log.dart';
import 'report_controller.dart';
import 'settings_controller.dart';
import 'sync_controller.dart';
import 'task_controller.dart';
import 'vault_controller.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required CredentialStore credentials,
    required VaultController vault,
    required SyncController sync,
    required SettingsController settings,
    required ReportController reports,
    TaskController? tasks,
  }) : _credentials = credentials,
       _vault = vault,
       _sync = sync,
       _settings = settings,
       _reports = reports,
       _tasks = tasks {
    _sync.onVaultChanged = () async {
      await _reports.refresh();
      await _reports.ensurePeriodicReports();
      await _tasks?.reconcileNotifications();
    };
    _sync.onSynchronized = _markLastSync;
  }

  final CredentialStore _credentials;
  final VaultController _vault;
  final SyncController _sync;
  final SettingsController _settings;
  final ReportController _reports;
  final TaskController? _tasks;
  Timer? _lockTimer;
  DateTime? _backgroundedAt;

  bool initialized = false;
  bool busy = false;
  bool locked = false;
  String? error;
  Duration autoLockDelay = const Duration(minutes: 5);
  List<WebDavProfile> webDavProfiles = const [];
  String? activeProfileId;

  WebDavProfile? get activeProfile =>
      webDavProfiles.where((item) => item.id == activeProfileId).firstOrNull;
  WebDavCredentials? get webDav => activeProfile?.credentials;

  Future<void> initialize() async {
    AppLog.info('App', 'Инициализация сессии');
    try {
      await _settings.initialize();
      autoLockDelay = await _credentials.readAutoLockDelay();
      locked = await _credentials.hasPin;
      webDavProfiles = await _credentials.readProfiles();
      activeProfileId = await _credentials.readActiveProfileId();
      final active = activeProfile ?? webDavProfiles.firstOrNull;
      if (active == null) {
        await _vault.initializeLocal(
          imageCacheLimitBytes: _settings.imageCacheLimitBytes,
        );
      } else {
        activeProfileId = active.id;
        await _vault.activateProfile(
          active,
          imageCacheLimitBytes: _settings.imageCacheLimitBytes,
          migrateLegacy: true,
        );
        _sync.configure(active);
      }
      _settings.configureProfiles(webDavProfiles, activeProfileId);
      await _reports.refresh();
      if (active != null) await _reports.ensurePeriodicReports();
      await _tasks?.initializeNotifications();
    } catch (exception, stackTrace) {
      error = exception.toString();
      AppLog.error('App', 'Ошибка инициализации сессии', exception, stackTrace);
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> connect({
    required Uri url,
    required String username,
    required String password,
    required String pin,
  }) async {
    await _run('Проверка подключения WebDAV', () async {
      final credentials = WebDavCredentials(
        baseUrl: url,
        username: username,
        password: password,
      );
      await WebDavClient(credentials).listTree();
      final profile = WebDavProfile(
        id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
        name: url.host,
        baseUrl: url,
        username: username,
        password: password,
      );
      await _credentials.saveProfile(profile);
      await _credentials.setActiveProfile(profile.id);
      await _credentials.savePin(pin);
      webDavProfiles = [...webDavProfiles, profile];
      await _activateProfile(profile);
      markUnlocked();
      await _sync.synchronize();
    });
  }

  Future<WebDavProfile> saveWebDavProfile({
    String? id,
    required String name,
    required Uri url,
    required String username,
    required String password,
    bool activate = false,
  }) async {
    if (activate && activeProfileId != null && activeProfileId != id) {
      await _sync.synchronize();
      _throwIfSyncFailed();
    }
    final profile = WebDavProfile(
      id: id ?? 'profile-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? url.host : name.trim(),
      baseUrl: url,
      username: username,
      password: password,
      lastSyncAt: webDavProfiles
          .where((item) => item.id == id)
          .firstOrNull
          ?.lastSyncAt,
    );
    await _run('Проверка WebDAV-профиля', () async {
      await WebDavClient(profile.credentials).listTree();
      await _credentials.saveProfile(profile);
      webDavProfiles = [
        ...webDavProfiles.where((item) => item.id != profile.id),
        profile,
      ];
      if (activate ||
          activeProfileId == null ||
          activeProfileId == profile.id) {
        await _activateProfile(profile);
        await _credentials.setActiveProfile(profile.id);
      }
    });
    if (error != null) throw StateError(error!);
    if (activeProfileId == profile.id) await _sync.synchronize();
    return profile;
  }

  Future<void> switchWebDavProfile(String id, {bool syncCurrent = true}) async {
    if (id == activeProfileId) return;
    final target = webDavProfiles.where((item) => item.id == id).first;
    if (syncCurrent && webDav != null) {
      await _sync.synchronize();
      _throwIfSyncFailed();
    }
    await _run('Переключение хранилища', () async {
      await _activateProfile(target);
      await _credentials.setActiveProfile(target.id);
      _sync.resetForProfile('Выбрано хранилище ${target.name}');
    });
    if (error != null) throw StateError(error!);
    await _sync.synchronize();
  }

  Future<void> deleteWebDavProfile(
    String id, {
    required bool deleteCache,
  }) async {
    if (id == activeProfileId) {
      final replacement = webDavProfiles
          .where((item) => item.id != id)
          .firstOrNull;
      if (replacement == null) {
        throw StateError('Нельзя удалить единственное активное хранилище');
      }
      await switchWebDavProfile(replacement.id);
    }
    await _credentials.deleteProfile(id);
    if (deleteCache) {
      final store = EncryptedObjectStore(namespace: id);
      await store.initialize();
      await store.clear();
    }
    webDavProfiles = webDavProfiles
        .where((item) => item.id != id)
        .toList(growable: false);
    _settings.configureProfiles(webDavProfiles, activeProfileId);
    notifyListeners();
  }

  Future<void> _activateProfile(WebDavProfile profile) async {
    await _sync.close();
    activeProfileId = profile.id;
    await _vault.activateProfile(
      profile,
      imageCacheLimitBytes: _settings.imageCacheLimitBytes,
    );
    _sync.configure(profile);
    _settings.configureProfiles(webDavProfiles, activeProfileId);
    await _reports.refresh();
    notifyListeners();
  }

  Future<void> _markLastSync(DateTime value) async {
    final active = activeProfile;
    if (active == null) return;
    final updated = active.copyWith(lastSyncAt: value);
    await _credentials.saveProfile(updated);
    webDavProfiles = [
      for (final profile in webDavProfiles)
        if (profile.id == updated.id) updated else profile,
    ];
    _settings.configureProfiles(webDavProfiles, activeProfileId);
    notifyListeners();
  }

  void _throwIfSyncFailed() {
    if (_sync.error != null || _sync.conflicts.isNotEmpty) {
      throw StateError(
        _sync.error ?? 'Перед переключением необходимо разрешить конфликты',
      );
    }
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (exception, stackTrace) {
      error = exception.toString();
      AppLog.error('Session', 'Ошибка: $label', exception, stackTrace);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> unlock({String? pin}) async {
    final service = AppLockService(_credentials);
    final success = pin == null
        ? await service.unlockWithSystem()
        : await service.unlockWithPin(pin);
    if (success) markUnlocked();
    return success;
  }

  void markUnlocked() {
    _lockTimer?.cancel();
    _backgroundedAt = null;
    if (!locked) return;
    locked = false;
    notifyListeners();
  }

  void enterBackground() {
    if (locked || _backgroundedAt != null) return;
    _backgroundedAt = DateTime.now();
    _scheduleLock();
  }

  void resume() {
    final backgroundedAt = _backgroundedAt;
    _lockTimer?.cancel();
    _lockTimer = null;
    _backgroundedAt = null;
    unawaited(_sync.retryPending());
    if (backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt) >= autoLockDelay) {
      lock();
    }
  }

  Future<void> setAutoLockDelay(Duration value) async {
    autoLockDelay = value;
    await _credentials.saveAutoLockDelay(value);
    if (_backgroundedAt != null && !locked) _scheduleLock();
    notifyListeners();
  }

  void lock() {
    _lockTimer?.cancel();
    _lockTimer = null;
    _backgroundedAt = null;
    if (locked) return;
    locked = true;
    notifyListeners();
  }

  void _scheduleLock() {
    _lockTimer?.cancel();
    final started = _backgroundedAt;
    if (started == null) return;
    final remaining = autoLockDelay - DateTime.now().difference(started);
    if (remaining <= Duration.zero) {
      lock();
    } else {
      _lockTimer = Timer(remaining, lock);
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
