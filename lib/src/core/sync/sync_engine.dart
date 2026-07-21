import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/encrypted_object_store.dart';
import '../vault/vault_models.dart';
import '../vault/vault_repository.dart';
import 'sync_models.dart';
import 'webdav_client.dart';
import '../../shared/app_log.dart';

class SyncEngine {
  SyncEngine({
    required VaultRepository local,
    required EncryptedObjectStore store,
    required WebDavClient remote,
    void Function(SyncProgress progress)? onProgress,
  }) : _local = local,
       _store = store,
       _remote = remote,
       _onProgress = onProgress;

  static const _stateKey = '__sync_state__';
  final VaultRepository _local;
  final EncryptedObjectStore _store;
  final WebDavClient _remote;
  final void Function(SyncProgress progress)? _onProgress;
  final _sha256 = Sha256();
  bool _running = false;

  Future<SyncResult> synchronize() async {
    if (_running) throw StateError('Synchronization is already running');
    _running = true;
    final batch = _local is BatchableVaultRepository
        ? _local as BatchableVaultRepository
        : null;
    await batch?.beginBatch();
    final stopwatch = Stopwatch()..start();
    AppLog.info('Sync', 'Синхронизация начата');
    try {
      final state = await _loadState();
      final local = {for (final file in await _local.list()) file.path: file};
      _progress('Получение списка файлов с WebDAV');
      final remote = {
        for (final file in await _remote.listTree())
          if (!file.isDirectory && !_ignored(file.path)) file.path: file,
      };
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
            : await _hash(localFile.bytes);
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
      _running = false;
    }
  }

  Future<SyncResult> synchronizeFile(String path) async {
    if (_running) throw StateError('Synchronization is already running');
    _running = true;
    final stopwatch = Stopwatch()..start();
    AppLog.info('Sync', 'Точечная синхронизация начата: $path');
    try {
      final localFile = await _local.read(path);
      if (localFile == null) {
        throw StateError('Локальный файл не найден: $path');
      }
      final state = await _loadState();
      final old = state[path];
      final localHash = await _hash(localFile.bytes);
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
    } finally {
      _running = false;
    }
  }

  Future<void> resolve(
    SyncConflict conflict,
    ConflictResolution resolution, {
    Uint8List? merged,
  }) async {
    if (resolution == ConflictResolution.deferred) return;
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
