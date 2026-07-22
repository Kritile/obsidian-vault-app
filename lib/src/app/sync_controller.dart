import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/sync/sync_engine.dart';
import '../core/sync/sync_models.dart';
import '../core/sync/webdav_client.dart';
import '../core/sync/webdav_profile.dart';
import '../core/vault/report_layout.dart';
import '../shared/app_log.dart';
import 'vault_controller.dart';

typedef SyncEngineFactory =
    SyncEngine Function(
      WebDavProfile profile,
      ValueChanged<SyncProgress> onProgress,
    );

class SyncController extends ChangeNotifier {
  SyncController(VaultController vault, {SyncEngineFactory? engineFactory})
    : _vault = vault,
      _engineFactory =
          engineFactory ??
          ((profile, onProgress) => SyncEngine(
            local: vault.cache,
            store: vault.store,
            remote: WebDavClient(profile.credentials),
            onProgress: onProgress,
          ));

  final VaultController _vault;
  final SyncEngineFactory _engineFactory;
  SyncEngine? _engine;
  Timer? _noticeTimer;

  int _pendingOperations = 0;
  bool get busy => _pendingOperations > 0;
  String? error;
  String? syncMessage;
  List<SyncConflict> conflicts = const [];
  SyncProgress? progress;
  String? operationNotice;
  bool operationNoticeIsError = false;
  bool operationNoticeInProgress = false;
  WebDavProfile? activeProfile;
  Future<void> Function()? onVaultChanged;
  Future<void> Function(DateTime value)? onSynchronized;

  void configure(WebDavProfile? profile) {
    if (_engine != null) {
      throw StateError('Закройте текущий SyncEngine перед перенастройкой');
    }
    activeProfile = profile;
    if (profile == null || !_vault.ready) {
      _engine = null;
    } else {
      _engine = _engineFactory(profile, (value) {
        progress = value;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  Future<void> synchronize() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      await _run('Синхронизация', () async {
        final result = await engine.synchronize();
        final unresolved = <SyncConflict>[];
        for (final conflict in result.conflicts) {
          if (conflict.path != ReportLayoutConfig.path) {
            unresolved.add(conflict);
            continue;
          }
          try {
            final local = ReportLayoutConfig.decode(
              utf8.decode(conflict.local, allowMalformed: true),
            );
            final remote = ReportLayoutConfig.decode(
              utf8.decode(conflict.remote, allowMalformed: true),
            );
            await engine.resolve(
              conflict,
              ConflictResolution.merged,
              merged: _vault.parser.encode(
                ReportLayoutConfig.merge(local, remote).encode(),
              ),
            );
          } catch (mergeError, stackTrace) {
            AppLog.error(
              'Reports',
              'Не удалось объединить конфигурации',
              mergeError,
              stackTrace,
            );
            unresolved.add(conflict);
          }
        }
        conflicts = unresolved;
        syncMessage =
            'Загружено: ${result.downloaded} · отправлено: ${result.uploaded}'
            '${unresolved.isEmpty ? '' : ' · конфликтов: ${unresolved.length}'}';
        await _vault.refreshIndex();
        await onVaultChanged?.call();
        final now = DateTime.now().toUtc();
        await onSynchronized?.call(now);
      });
    } finally {
      progress = null;
      notifyListeners();
    }
  }

  Future<void> resolveConflict(
    SyncConflict conflict,
    ConflictResolution resolution, {
    String? merged,
  }) async {
    final engine = _engine;
    if (engine == null) return;
    await _run('Разрешение конфликта ${conflict.path}', () async {
      await engine.resolve(
        conflict,
        resolution,
        merged: merged == null ? null : _vault.parser.encode(merged),
      );
      conflicts = conflicts
          .where((item) => item.path != conflict.path)
          .toList(growable: false);
      await _vault.refreshIndex();
      await onVaultChanged?.call();
    });
  }

  Future<void> saveNote(String path, String source) async {
    _beginOperation();
    try {
      await _vault.saveLocal(path, source);
      await onVaultChanged?.call();
      final engine = _engine;
      if (engine == null) {
        _showNotice('Сохранено локально · WebDAV не настроен', isError: true);
        return;
      }
      error = null;
      _showNotice('Отправка в WebDAV…', inProgress: true);
      try {
        final result = await engine.synchronizeFile(path);
        conflicts = [
          ...conflicts.where((item) => item.path != path),
          ...result.conflicts,
        ];
        if (result.conflicts.isNotEmpty) {
          _showNotice('Сохранено локально · обнаружен конфликт', isError: true);
        } else {
          syncMessage = result.uploaded == 0
              ? 'Файл уже актуален: $path'
              : 'Отправлен: $path';
          _showNotice(
            result.uploaded == 0
                ? 'Сохранено · серверная версия уже актуальна'
                : 'Сохранено и отправлено в WebDAV',
          );
        }
      } catch (exception, stackTrace) {
        error = exception.toString();
        AppLog.error(
          'Editor',
          'Файл сохранён локально, но не отправлен: $path',
          exception,
          stackTrace,
        );
        _showNotice('Сохранено локально · ошибка WebDAV', isError: true);
      } finally {
        progress = null;
      }
    } finally {
      _endOperation();
    }
  }

  Future<void> close() async {
    final engine = _engine;
    _engine = null;
    notifyListeners();
    await engine?.close();
  }

  void resetForProfile(String message) {
    conflicts = const [];
    syncMessage = message;
    error = null;
    notifyListeners();
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    _beginOperation();
    error = null;
    try {
      await operation();
    } catch (exception, stackTrace) {
      error = exception.toString();
      AppLog.error('Operation', 'Ошибка: $label', exception, stackTrace);
    } finally {
      _endOperation();
    }
  }

  void _beginOperation() {
    _pendingOperations++;
    notifyListeners();
  }

  void _endOperation() {
    if (_pendingOperations > 0) _pendingOperations--;
    notifyListeners();
  }

  void _showNotice(
    String message, {
    bool isError = false,
    bool inProgress = false,
  }) {
    _noticeTimer?.cancel();
    operationNotice = message;
    operationNoticeIsError = isError;
    operationNoticeInProgress = inProgress;
    notifyListeners();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      operationNotice = null;
      operationNoticeInProgress = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    unawaited(_engine?.close());
    super.dispose();
  }
}
