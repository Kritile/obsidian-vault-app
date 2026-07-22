import 'package:flutter/foundation.dart';

import '../core/cache/storage_models.dart';
import '../core/crypto/credential_store.dart';
import '../core/crypto/encrypted_object_store.dart';
import '../core/sync/webdav_profile.dart';
import 'vault_controller.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._credentials, this._vault);

  final CredentialStore _credentials;
  final VaultController _vault;
  List<WebDavProfile> _profiles = const [];
  String? _activeProfileId;

  int imageCacheLimitBytes = 250 * 1024 * 1024;
  String attachmentFolder = 'Attachments';
  MotionPreference motionPreference = MotionPreference.expressive;
  bool initialized = false;

  Future<void> initialize() async {
    imageCacheLimitBytes = await _credentials.readImageCacheLimit();
    attachmentFolder = await _credentials.readAttachmentFolder();
    motionPreference = await _credentials.readMotionPreference();
    initialized = true;
    notifyListeners();
  }

  Future<void> setAttachmentFolder(String value) async {
    final normalized = value.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    attachmentFolder = normalized.isEmpty ? 'Attachments' : normalized;
    await _credentials.saveAttachmentFolder(attachmentFolder);
    notifyListeners();
  }

  void configureProfiles(List<WebDavProfile> profiles, String? activeId) {
    _profiles = profiles;
    _activeProfileId = activeId;
  }

  Future<void> setImageCacheLimit(int value) async {
    imageCacheLimitBytes = value;
    await _credentials.saveImageCacheLimit(value);
    if (_vault.ready) await _vault.imageCache.setLimit(value);
    notifyListeners();
  }

  Future<void> setMotionPreference(MotionPreference value) async {
    motionPreference = value;
    await _credentials.saveMotionPreference(value);
    notifyListeners();
  }

  Future<StorageUsage> storageUsage() async {
    if (!_vault.ready) {
      return const StorageUsage(
        currentVaultBytes: 0,
        inactiveVaultBytes: 0,
        imageBytes: 0,
      );
    }
    final currentTotal = await _vault.store.sizeBytes();
    var inactive = 0;
    for (final profile in _profiles.where(
      (item) => item.id != _activeProfileId,
    )) {
      final store = EncryptedObjectStore(namespace: profile.id);
      await store.initialize();
      inactive += await store.sizeBytes();
    }
    final images = _vault.imageCache.sizeBytes;
    return StorageUsage(
      currentVaultBytes: (currentTotal - images).clamp(0, currentTotal),
      inactiveVaultBytes: inactive,
      imageBytes: images,
    );
  }

  Future<void> clearImageCache() async {
    await _vault.imageCache.clear();
    notifyListeners();
  }

  Future<void> clearInactiveVaultCaches() async {
    for (final profile in _profiles.where(
      (item) => item.id != _activeProfileId,
    )) {
      final store = EncryptedObjectStore(namespace: profile.id);
      await store.initialize();
      await store.clear();
    }
    notifyListeners();
  }

  Future<void> clearCurrentVaultCache() =>
      _vault.clearCurrent(imageCacheLimitBytes: imageCacheLimitBytes);

  Future<void> verifyCurrentVaultCache() => _vault.verifyCacheIntegrity();
}
