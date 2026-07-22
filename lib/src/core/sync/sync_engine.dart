// Named public constructor arguments intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import '../crypto/encrypted_object_store.dart';
import '../vault/vault_models.dart';
import '../vault/vault_repository.dart';
import 'sync_models.dart';
import 'storage_capacity_service.dart';
import 'webdav_client.dart';
import '../../shared/app_log.dart';

class SyncEngine {
  SyncEngine({
    required VaultRepository local,
    required EncryptedObjectStore store,
    required WebDavClient remote,
    void Function(SyncProgress progress)? onProgress,
    void Function(List<SyncQueueEntry> entries)? onQueueChanged,
    StorageCapacityService capacity = const StorageCapacityService(),
  }) : _local = local,
       _store = store,
       _remote = remote,
       _onProgress = onProgress,
       onQueueChanged = onQueueChanged,
       _capacity = capacity;

  static const _stateKey = '__sync_state__';
  static const _outboxKey = '__sync_outbox_v1__';
  final VaultRepository _local;
  final EncryptedObjectStore _store;
  final WebDavClient _remote;
  final StorageCapacityService _capacity;
  final void Function(SyncProgress progress)? _onProgress;
  void Function(List<SyncQueueEntry> entries)? onQueueChanged;
  final _sha256 = Sha256();
  final Queue<_QueueEntry> _operations = Queue<_QueueEntry>();
  final Map<String, _FileQueueEntry> _pendingFiles = {};
  final Map<String, SyncQueueEntry> _outbox = {};
  bool _outboxLoaded = false;
  Future<void> _outboxWrite = Future.value();
  bool _draining = false;
  bool _closed = false;
  Completer<void>? _idleCompleter;

  Future<SyncResult> synchronize() {
    if (_closed) return Future.error(_closedError());
    final operation = _QueuedOperation<SyncResult>(_synchronize);
    _enqueue(operation);
    return operation.future;
  }

  Future<SyncResult> synchronizeFile(String path) {
    if (_closed) return Future.error(_closedError());
    final pending = _pendingFiles[path];
    if (pending != null) return pending.future;
    _outbox[path] = SyncQueueEntry(
      path: path,
      state: SyncQueueState.waiting,
      updatedAt: DateTime.now().toUtc(),
    );
    _emitQueue();
    unawaited(_saveOutbox());
    final operation = _FileQueueEntry(path, () => _runTrackedFile(path));
    _pendingFiles[path] = operation;
    _enqueue(operation);
    return operation.future;
  }

  Future<SyncResult> synchronizeMove(String from, String to) {
    if (_closed) return Future.error(_closedError());
    final pending = _pendingFiles[from];
    if (pending != null) return pending.future;
    _outbox[from] = SyncQueueEntry(
      path: from,
      destinationPath: to,
      kind: SyncOperationKind.move,
      state: SyncQueueState.waiting,
      updatedAt: DateTime.now().toUtc(),
    );
    _emitQueue();
    unawaited(_saveOutbox());
    final operation = _FileQueueEntry(from, () => _runTrackedMove(from, to));
    _pendingFiles[from] = operation;
    _enqueue(operation);
    return operation.future;
  }

  Future<SyncResult> synchronizeDelete(String path) {
    if (_closed) return Future.error(_closedError());
    final pending = _pendingFiles[path];
    if (pending != null) return pending.future;
    _outbox[path] = SyncQueueEntry(
      path: path,
      kind: SyncOperationKind.delete,
      state: SyncQueueState.waiting,
      updatedAt: DateTime.now().toUtc(),
    );
    _emitQueue();
    unawaited(_saveOutbox());
    final operation = _FileQueueEntry(path, () => _runTrackedDelete(path));
    _pendingFiles[path] = operation;
    _enqueue(operation);
    return operation.future;
  }

  List<SyncQueueEntry> get queue => _orderedOutbox();

  Future<void> restorePending() async {
    if (_closed) return;
    await _loadOutbox();
    for (final entry in [..._outbox.values]) {
      if ((entry.state == SyncQueueState.waiting || entry.retryable) &&
          !_pendingFiles.containsKey(entry.path)) {
        final operation = _FileQueueEntry(
          entry.path,
          () =>
              entry.kind == SyncOperationKind.move &&
                  entry.destinationPath != null
              ? _runTrackedMove(entry.path, entry.destinationPath!)
              : entry.kind == SyncOperationKind.delete
              ? _runTrackedDelete(entry.path)
              : _runTrackedFile(entry.path),
        );
        _pendingFiles[entry.path] = operation;
        _enqueue(operation);
        unawaited(operation.future.then<void>((_) {}, onError: (_, _) {}));
      }
    }
  }

  Future<void> retry(String path) async {
    if (_closed) throw _closedError();
    await _loadOutbox();
    final current = _outbox[path];
    if (current == null || _pendingFiles.containsKey(path)) return;
    _outbox[path] = current.copyWith(
      state: SyncQueueState.waiting,
      clearError: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveOutbox();
    final operation = _FileQueueEntry(
      path,
      () =>
          current.kind == SyncOperationKind.move &&
              current.destinationPath != null
          ? _runTrackedMove(path, current.destinationPath!)
          : current.kind == SyncOperationKind.delete
          ? _runTrackedDelete(path)
          : _runTrackedFile(path),
    );
    _pendingFiles[path] = operation;
    _enqueue(operation);
    unawaited(operation.future.then<void>((_) {}, onError: (_, _) {}));
  }

  Future<void> retryPending({bool automatic = false}) async {
    await _loadOutbox();
    for (final entry in [..._outbox.values]) {
      if (entry.state != SyncQueueState.error ||
          automatic && !entry.retryable) {
        continue;
      }
      await retry(entry.path);
    }
  }

  Future<void> resolve(
    SyncConflict conflict,
    ConflictResolution resolution, {
    Uint8List? merged,
  }) {
    if (_closed) return Future.error(_closedError());
    if (resolution == ConflictResolution.deferred) return Future.value();
    final operation = _QueuedOperation<void>(
      () => _resolve(conflict, resolution, merged: merged),
    );
    _enqueue(operation);
    return operation.future;
  }

  Future<void> close() {
    _closed = true;
    if (!_draining && _operations.isEmpty) return Future.value();
    return (_idleCompleter ??= Completer<void>()).future;
  }

  StateError _closedError() => StateError('SyncEngine is closed');

  void _enqueue(_QueueEntry operation) {
    _operations.add(operation);
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_operations.isNotEmpty) {
        final operation = _operations.removeFirst();
        if (operation case final _FileQueueEntry file) {
          if (identical(_pendingFiles[file.path], file)) {
            _pendingFiles.remove(file.path);
          }
        }
        await operation.run();
      }
    } finally {
      _draining = false;
      if (_operations.isNotEmpty) {
        unawaited(_drain());
      } else {
        _idleCompleter?.complete();
        _idleCompleter = null;
      }
    }
  }

  Future<SyncResult> _runTrackedFile(String path) async {
    await _loadOutbox();
    final current =
        _outbox[path] ??
        SyncQueueEntry(
          path: path,
          state: SyncQueueState.waiting,
          updatedAt: DateTime.now().toUtc(),
        );
    _outbox[path] = current.copyWith(
      state: SyncQueueState.sending,
      attempts: current.attempts + 1,
      clearError: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveOutbox();
    try {
      final result = await _synchronizeFile(path);
      if (result.conflicts.isEmpty) _outbox.remove(path);
      if (result.conflicts.isNotEmpty) {
        _outbox[path] = _outbox[path]!.copyWith(
          state: SyncQueueState.error,
          error: 'Обнаружен конфликт',
          retryable: false,
          updatedAt: DateTime.now().toUtc(),
        );
      }
      await _saveOutbox();
      return result;
    } catch (error) {
      _outbox[path] = _outbox[path]!.copyWith(
        state: SyncQueueState.error,
        error: error.toString(),
        retryable: _isRetryable(error),
        updatedAt: DateTime.now().toUtc(),
      );
      await _saveOutbox();
      rethrow;
    }
  }

  Future<SyncResult> _runTrackedMove(String from, String to) async {
    await _loadOutbox();
    final current = _outbox[from]!;
    _outbox[from] = current.copyWith(
      state: SyncQueueState.sending,
      attempts: current.attempts + 1,
      clearError: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveOutbox();
    try {
      final document = await _local.read(to);
      if (document == null) {
        throw StateError('Перемещённый файл не найден: $to');
      }
      final state = await _loadState();
      final old = state[from];
      final remoteEntry = await _remote.entry(from);
      String? etag;
      if (remoteEntry == null) {
        etag = await _ensureRemotePathAndUpload(document);
      } else {
        final parts = to.split('/');
        for (var index = 1; index < parts.length; index++) {
          await _remote.createDirectory(parts.take(index).join('/'));
        }
        await _remote.move(
          from,
          to,
          expectedEtag: old?.etag ?? remoteEntry.etag,
        );
        etag = (await _remote.entry(to))?.etag;
      }
      state.remove(from);
      await _store.remove(_baseKey(from));
      await _record(to, document.bytes, etag, state);
      await _saveState(state);
      _outbox.remove(from);
      await _saveOutbox();
      return const SyncResult(downloaded: 0, uploaded: 1, conflicts: []);
    } catch (error) {
      _outbox[from] = _outbox[from]!.copyWith(
        state: SyncQueueState.error,
        error: error.toString(),
        retryable: _isRetryable(error),
        updatedAt: DateTime.now().toUtc(),
      );
      await _saveOutbox();
      rethrow;
    }
  }

  Future<SyncResult> _runTrackedDelete(String path) async {
    await _loadOutbox();
    final current = _outbox[path]!;
    _outbox[path] = current.copyWith(
      state: SyncQueueState.sending,
      attempts: current.attempts + 1,
      clearError: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveOutbox();
    try {
      final state = await _loadState();
      final old = state[path];
      final remoteEntry = await _remote.entry(path);
      if (remoteEntry != null) {
        await _remote.delete(path, expectedEtag: old?.etag ?? remoteEntry.etag);
      }
      state.remove(path);
      await _store.remove(_baseKey(path));
      await _saveState(state);
      _outbox.remove(path);
      await _saveOutbox();
      return const SyncResult(downloaded: 0, uploaded: 1, conflicts: []);
    } catch (error) {
      _outbox[path] = _outbox[path]!.copyWith(
        state: SyncQueueState.error,
        error: error.toString(),
        retryable: _isRetryable(error),
        updatedAt: DateTime.now().toUtc(),
      );
      await _saveOutbox();
      rethrow;
    }
  }

  bool _isRetryable(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    return status == null || status == 408 || status == 429 || status >= 500;
  }

  Future<void> _loadOutbox() async {
    if (_outboxLoaded) return;
    _outboxLoaded = true;
    final bytes = await _store.read(_outboxKey);
    if (bytes == null) {
      _emitQueue();
      return;
    }
    try {
      final values = jsonDecode(utf8.decode(bytes)) as List<Object?>;
      for (final value in values) {
        final item = SyncQueueEntry.fromJson(
          Map<String, Object?>.from(value! as Map),
        );
        if (_outbox.containsKey(item.path)) continue;
        _outbox[item.path] = item.state == SyncQueueState.sending
            ? item.copyWith(state: SyncQueueState.waiting)
            : item;
      }
    } catch (error) {
      AppLog.warning('Sync', 'Повреждён outbox, он будет пересоздан: $error');
      _outbox.clear();
    }
    _emitQueue();
  }

  Future<void> _saveOutbox() async {
    final payload = Uint8List.fromList(
      utf8.encode(jsonEncode(_orderedOutbox().map((e) => e.toJson()).toList())),
    );
    final write = _outboxWrite.then((_) => _store.write(_outboxKey, payload));
    _outboxWrite = write.then<void>((_) {}, onError: (_, _) {});
    await write;
    _emitQueue();
  }

  List<SyncQueueEntry> _orderedOutbox() {
    final values = [..._outbox.values]
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return List.unmodifiable(values);
  }

  void _emitQueue() => onQueueChanged?.call(_orderedOutbox());

  Future<SyncResult> _synchronize() async {
    final batch = _local is BatchableVaultRepository
        ? _local as BatchableVaultRepository
        : null;
    await batch?.beginBatch();
    final stopwatch = Stopwatch()..start();
    AppLog.info('Sync', 'Синхронизация начата');
    try {
      final state = await _loadState()
        ..removeWhere((path, _) => _ignored(path));
      final local = {
        for (final file in await _local.list())
          if (!_ignored(file.path)) file.path: file,
      };
      _progress('Получение списка файлов с WebDAV');
      final remote = {
        for (final file in await _remote.listTree())
          if (!file.isDirectory && !_ignored(file.path)) file.path: file,
      };
      await _preflight(local, remote, state);
      final paths = {...state.keys, ...local.keys, ...remote.keys}.toList()
        ..sort();
      AppLog.info(
        'Sync',
        'Состояние: ${local.length} локальных, ${remote.length} удалённых, ${state.length} известных ранее; проверяется ${paths.length} путей',
      );
      final conflicts = <SyncConflict>[];
      var downloaded = 0;
      var uploaded = 0;
      var processed = 0;

      for (final path in paths) {
        _progress('Проверка $path', completed: processed, total: paths.length);
        final old = state[path];
        final localFile = local[path];
        final remoteFile = remote[path];
        final localHash = localFile == null
            ? null
            : localFile.contentHash ?? await _hash(localFile.bytes);
        final localChanged = old != null && localHash != old.hash;
        final remoteChanged = old != null && remoteFile?.etag != old.etag;

        if (old == null) {
          if (localFile == null && remoteFile != null) {
            AppLog.debug('Sync', 'Новый удалённый файл → скачать: $path');
            final bytes = await _remote.download(path);
            await _acceptRemote(path, bytes, remoteFile, state);
            downloaded++;
          } else if (localFile != null && remoteFile == null) {
            AppLog.debug('Sync', 'Новый локальный файл → отправить: $path');
            final etag = await _ensureRemotePathAndUpload(localFile);
            await _record(path, localFile.bytes, etag, state);
            uploaded++;
          } else if (localFile != null && remoteFile != null) {
            final bytes = await _remote.download(path);
            if (await _hash(bytes) == localHash) {
              await _record(path, bytes, remoteFile.etag, state);
            } else {
              AppLog.warning(
                'Sync',
                'Конфликт при первичном сопоставлении: $path',
              );
              conflicts.add(
                SyncConflict(
                  path: path,
                  local: localFile.bytes,
                  remote: bytes,
                  base: null,
                ),
              );
            }
          }
          processed++;
          continue;
        }

        if (localFile == null && remoteFile == null) {
          state.remove(path);
          await _store.remove(_baseKey(path));
        } else if (localFile == null && remoteFile != null) {
          if (remoteChanged) {
            AppLog.warning(
              'Sync',
              'Конфликт удаления: локально удалён, удалённо изменён $path',
            );
            conflicts.add(
              SyncConflict(
                path: path,
                local: Uint8List(0),
                remote: await _remote.download(path),
                base: await _store.read(_baseKey(path)),
              ),
            );
          } else {
            AppLog.debug(
              'Sync',
              'Локальное удаление → удалить на сервере: $path',
            );
            await _remote.delete(path, expectedEtag: old.etag);
            state.remove(path);
            await _store.remove(_baseKey(path));
            uploaded++;
          }
        } else if (localFile != null && remoteFile == null) {
          if (localChanged) {
            AppLog.warning(
              'Sync',
              'Конфликт удаления: удалённо удалён, локально изменён $path',
            );
            conflicts.add(
              SyncConflict(
                path: path,
                local: localFile.bytes,
                remote: Uint8List(0),
                base: await _store.read(_baseKey(path)),
              ),
            );
          } else {
            AppLog.debug(
              'Sync',
              'Удалённое удаление → удалить локально: $path',
            );
            await _local.delete(path);
            state.remove(path);
            await _store.remove(_baseKey(path));
            downloaded++;
          }
        } else if (localChanged && remoteChanged) {
          AppLog.warning('Sync', 'Двустороннее изменение → конфликт: $path');
          conflicts.add(
            SyncConflict(
              path: path,
              local: localFile!.bytes,
              remote: await _remote.download(path),
              base: await _store.read(_baseKey(path)),
            ),
          );
        } else if (remoteChanged) {
          AppLog.debug('Sync', 'Удалённая версия новее → скачать: $path');
          final bytes = await _remote.download(path);
          await _acceptRemote(path, bytes, remoteFile!, state);
          downloaded++;
        } else if (localChanged) {
          AppLog.debug('Sync', 'Локальная версия изменена → отправить: $path');
          final etag = await _remote.upload(
            path,
            localFile!.bytes,
            expectedEtag: old.etag,
          );
          await _record(path, localFile.bytes, etag ?? remoteFile!.etag, state);
          uploaded++;
        }
        processed++;
      }
      _progress(
        'Сохранение состояния синхронизации',
        completed: paths.length,
        total: paths.length,
      );
      await _saveState(state);
      stopwatch.stop();
      AppLog.info(
        'Sync',
        'Синхронизация завершена за ${stopwatch.elapsedMilliseconds} мс: скачано $downloaded, отправлено $uploaded, конфликтов ${conflicts.length}',
      );
      return SyncResult(
        downloaded: downloaded,
        uploaded: uploaded,
        conflicts: conflicts,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      AppLog.error(
        'Sync',
        'Синхронизация прервана через ${stopwatch.elapsedMilliseconds} мс',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      await batch?.endBatch();
    }
  }

  Future<void> _preflight(
    Map<String, VaultDocument> local,
    Map<String, WebDavEntry> remote,
    Map<String, _SyncRecord> state,
  ) async {
    var downloadBytes = 0;
    for (final entry in remote.entries) {
      final known = state[entry.key];
      if (local[entry.key] == null || known?.etag != entry.value.etag) {
        downloadBytes += entry.value.size;
      }
    }
    final reserve = downloadBytes ~/ 10 > 64 * 1024 * 1024
        ? downloadBytes ~/ 10
        : 64 * 1024 * 1024;
    final requiredLocal = downloadBytes + reserve;
    final availableLocal = await _capacity.availableBytes(_store.rootPath);
    if (availableLocal != null && availableLocal < requiredLocal) {
      throw InsufficientSpaceException(
        requiredBytes: requiredLocal,
        availableBytes: availableLocal,
        location: 'устройство',
      );
    }

    var uploadBytes = 0;
    for (final entry in local.entries) {
      final known = state[entry.key];
      if (known == null || known.hash != entry.value.contentHash) {
        uploadBytes += entry.value.bytes.length;
      }
    }
    if (uploadBytes == 0) return;
    try {
      final quota = await _remote.quota();
      if (quota.availableBytes case final available?
          when available < uploadBytes) {
        throw InsufficientSpaceException(
          requiredBytes: uploadBytes,
          availableBytes: available,
          location: 'WebDAV',
        );
      }
      if (quota.availableBytes == null) {
        AppLog.warning('Sync', 'WebDAV не сообщает доступную квоту');
      }
    } on InsufficientSpaceException {
      rethrow;
    } catch (error) {
      AppLog.warning('Sync', 'Не удалось получить квоту WebDAV: $error');
    }
  }

  Future<SyncResult> _synchronizeFile(String path) async {
    final stopwatch = Stopwatch()..start();
    AppLog.info('Sync', 'Точечная синхронизация начата: $path');
    try {
      final localFile = await _local.read(path);
      if (localFile == null) {
        throw StateError('Локальный файл не найден: $path');
      }
      final state = await _loadState();
      final old = state[path];
      final localHash = localFile.contentHash ?? await _hash(localFile.bytes);
      if (old != null && old.hash == localHash) {
        AppLog.info('Sync', 'Файл не изменился, отправка не требуется: $path');
        return const SyncResult(downloaded: 0, uploaded: 0, conflicts: []);
      }

      _progress('Отправка $path', completed: 0, total: 1);
      try {
        final etag = old == null
            ? await _ensureRemotePathAndUpload(localFile)
            : await _remote.upload(
                path,
                localFile.bytes,
                expectedEtag: old.etag,
              );
        await _record(path, localFile.bytes, etag ?? old?.etag, state);
        await _saveState(state);
        _progress('Файл отправлен', completed: 1, total: 1);
        stopwatch.stop();
        AppLog.info(
          'Sync',
          'Точечная синхронизация завершена за ${stopwatch.elapsedMilliseconds} мс: отправлен $path',
        );
        return const SyncResult(downloaded: 0, uploaded: 1, conflicts: []);
      } on WebDavPreconditionFailed {
        final remoteBytes = await _remote.download(path);
        if (await _hash(remoteBytes) == localHash) {
          final remoteEntry = await _remote.entry(path);
          await _record(path, localFile.bytes, remoteEntry?.etag, state);
          await _saveState(state);
          _progress('Файл уже актуален', completed: 1, total: 1);
          return const SyncResult(downloaded: 0, uploaded: 0, conflicts: []);
        }
        final conflict = SyncConflict(
          path: path,
          local: localFile.bytes,
          remote: remoteBytes,
          base: await _store.read(_baseKey(path)),
        );
        AppLog.warning('Sync', 'Точечная отправка обнаружила конфликт: $path');
        return SyncResult(downloaded: 0, uploaded: 0, conflicts: [conflict]);
      }
    } catch (error, stackTrace) {
      stopwatch.stop();
      AppLog.error(
        'Sync',
        'Точечная синхронизация прервана через ${stopwatch.elapsedMilliseconds} мс: $path',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _resolve(
    SyncConflict conflict,
    ConflictResolution resolution, {
    Uint8List? merged,
  }) async {
    AppLog.info(
      'Sync',
      'Разрешение конфликта ${conflict.path}: ${resolution.name}',
    );
    final state = await _loadState();
    if (resolution == ConflictResolution.remote) {
      final entry = (await _remote.listTree())
          .where((item) => item.path == conflict.path)
          .firstOrNull;
      if (conflict.remote.isEmpty || entry == null) {
        await _local.delete(conflict.path);
        state.remove(conflict.path);
      } else {
        await _acceptRemote(conflict.path, conflict.remote, entry, state);
      }
    } else {
      final bytes = resolution == ConflictResolution.merged
          ? merged
          : conflict.local;
      if (bytes == null) throw ArgumentError('Merged content is required');
      final existing = (await _remote.listTree())
          .where((item) => item.path == conflict.path)
          .firstOrNull;
      if (bytes.isEmpty) {
        if (existing != null) {
          await _remote.delete(conflict.path, expectedEtag: existing.etag);
        }
        await _local.delete(conflict.path);
        state.remove(conflict.path);
      } else {
        final document = VaultDocument(
          path: conflict.path,
          bytes: bytes,
          modifiedAt: DateTime.now().toUtc(),
        );
        await _local.write(document);
        final etag = await _remote.upload(
          conflict.path,
          bytes,
          expectedEtag: existing?.etag,
        );
        await _record(conflict.path, bytes, etag, state);
      }
    }
    await _saveState(state);
    AppLog.info('Sync', 'Конфликт разрешён: ${conflict.path}');
  }

  Future<void> _acceptRemote(
    String path,
    Uint8List bytes,
    WebDavEntry entry,
    Map<String, _SyncRecord> state,
  ) async {
    await _local.write(
      VaultDocument(
        path: path,
        bytes: bytes,
        modifiedAt: entry.modifiedAt,
        etag: entry.etag,
      ),
    );
    await _record(path, bytes, entry.etag, state);
  }

  Future<String?> _ensureRemotePathAndUpload(VaultDocument document) async {
    final parts = document.path.split('/');
    for (var index = 1; index < parts.length; index++) {
      await _remote.createDirectory(parts.take(index).join('/'));
    }
    return _remote.upload(document.path, document.bytes);
  }

  Future<void> _record(
    String path,
    Uint8List bytes,
    String? etag,
    Map<String, _SyncRecord> state,
  ) async {
    state[path] = _SyncRecord(hash: await _hash(bytes), etag: etag);
    await _store.write(_baseKey(path), bytes);
  }

  Future<String> _hash(Uint8List bytes) async =>
      base64UrlEncode((await _sha256.hash(bytes)).bytes);
  String _baseKey(String path) => '__base__:$path';

  bool _ignored(String path) =>
      path == '.obsidian' ||
      path.startsWith('.obsidian/') ||
      path.contains('/.obsidian/') ||
      path.startsWith('.git/') ||
      path.startsWith('.trash/') ||
      path.endsWith('.tmp') ||
      path.contains('/.DS_Store');

  void _progress(String message, {int? completed, int? total}) =>
      _onProgress?.call(
        SyncProgress(message: message, completed: completed, total: total),
      );

  Future<Map<String, _SyncRecord>> _loadState() async {
    final bytes = await _store.read(_stateKey);
    if (bytes == null) return {};
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return {
      for (final entry in json.entries)
        entry.key: _SyncRecord.fromJson(entry.value! as Map<String, Object?>),
    };
  }

  Future<void> _saveState(Map<String, _SyncRecord> state) => _store.write(
    _stateKey,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          for (final entry in state.entries) entry.key: entry.value.toJson(),
        }),
      ),
    ),
  );
}

abstract interface class _QueueEntry {
  Future<void> run();
}

class _QueuedOperation<T> implements _QueueEntry {
  _QueuedOperation(this._action);

  final Future<T> Function() _action;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  @override
  Future<void> run() async {
    try {
      _completer.complete(await _action());
    } catch (error, stackTrace) {
      _completer.completeError(error, stackTrace);
    }
  }
}

final class _FileQueueEntry extends _QueuedOperation<SyncResult> {
  _FileQueueEntry(this.path, Future<SyncResult> Function() action)
    : super(action);

  final String path;
}

class _SyncRecord {
  const _SyncRecord({required this.hash, required this.etag});
  final String hash;
  final String? etag;
  factory _SyncRecord.fromJson(Map<String, Object?> json) =>
      _SyncRecord(hash: json['hash']! as String, etag: json['etag'] as String?);
  Map<String, Object?> toJson() => {'hash': hash, 'etag': etag};
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
