import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;

import '../core/crypto/credential_store.dart';
import '../core/vault/daily_note_service.dart';
import '../core/vault/native_entity_service.dart';
import '../core/vault/project_service.dart';
import '../core/vault/training_service.dart';
import '../core/tasks/task_notification_service.dart';
import 'report_controller.dart';
import 'session_controller.dart';
import 'settings_controller.dart';
import 'sync_controller.dart';
import 'task_controller.dart';
import 'vault_controller.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => CredentialStore(),
);

final vaultControllerProvider = ChangeNotifierProvider<VaultController>(
  (ref) => VaultController(),
);

final settingsControllerProvider = ChangeNotifierProvider<SettingsController>((
  ref,
) {
  return SettingsController(
    ref.read(credentialStoreProvider),
    ref.read(vaultControllerProvider),
    ref.read(taskControllerProvider),
  );
});

final syncControllerProvider = ChangeNotifierProvider<SyncController>((ref) {
  return SyncController(ref.read(vaultControllerProvider));
});

final taskControllerProvider = ChangeNotifierProvider<TaskController>((ref) {
  return TaskController(
    ref.read(vaultControllerProvider),
    ref.read(syncControllerProvider),
    TaskNotificationService(),
  );
});

final reportControllerProvider = ChangeNotifierProvider<ReportController>((
  ref,
) {
  final controller = ReportController(ref.read(vaultControllerProvider));
  controller.noteWriter = ref.read(syncControllerProvider).saveNote;
  return controller;
});

final sessionControllerProvider = ChangeNotifierProvider<SessionController>((
  ref,
) {
  final controller = SessionController(
    credentials: ref.read(credentialStoreProvider),
    vault: ref.read(vaultControllerProvider),
    sync: ref.read(syncControllerProvider),
    settings: ref.read(settingsControllerProvider),
    reports: ref.read(reportControllerProvider),
    tasks: ref.read(taskControllerProvider),
  );
  controller.initialize();
  return controller;
});

final dailyNoteServiceProvider = Provider<DailyNoteService>((ref) {
  return DailyNoteService(
    ref.read(vaultControllerProvider),
    ref.read(syncControllerProvider).saveNote,
  );
});

final trainingServiceProvider = Provider<TrainingService>((ref) {
  return TrainingService(
    ref.read(vaultControllerProvider),
    ref.read(syncControllerProvider).saveNote,
  );
});

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(
    ref.read(vaultControllerProvider),
    ref.read(syncControllerProvider).saveNote,
  );
});

final nativeEntityServiceProvider = Provider<NativeEntityService>((ref) {
  return NativeEntityService(
    ref.read(vaultControllerProvider),
    ref.read(syncControllerProvider).saveNote,
  );
});
