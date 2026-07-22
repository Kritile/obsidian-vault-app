import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/app/report_controller.dart';
import 'package:pavel_vault/src/app/session_controller.dart';
import 'package:pavel_vault/src/app/settings_controller.dart';
import 'package:pavel_vault/src/app/sync_controller.dart';
import 'package:pavel_vault/src/app/vault_controller.dart';
import 'package:pavel_vault/src/core/crypto/credential_store.dart';

void main() {
  testWidgets('locks only after the configured background grace period', (
    tester,
  ) async {
    final credentials = _MemoryCredentialStore();
    final vault = VaultController();
    final controller = SessionController(
      credentials: credentials,
      vault: vault,
      sync: SyncController(vault),
      settings: SettingsController(credentials, vault),
      reports: ReportController(vault),
    );

    controller.enterBackground();
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(controller.locked, isFalse);

    await tester.pump(const Duration(seconds: 1));
    expect(controller.locked, isTrue);
    controller.dispose();
  });
}

class _MemoryCredentialStore extends CredentialStore {
  Duration delay = const Duration(minutes: 5);

  @override
  Future<bool> get hasPin async => false;

  @override
  Future<Duration> readAutoLockDelay() async => delay;

  @override
  Future<void> saveAutoLockDelay(Duration value) async => delay = value;
}
