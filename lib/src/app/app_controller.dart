import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../core/crypto/credential_store.dart';
import '../core/crypto/encrypted_object_store.dart';
import '../core/cache/image_cache_service.dart';
import '../core/cache/storage_models.dart';
import '../core/markdown/obsidian_parser.dart';
import '../core/markdown/work_entry_codec.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_models.dart';
import '../core/sync/webdav_client.dart';
import '../core/sync/webdav_profile.dart';
import '../core/vault/encrypted_cached_repository.dart';
import '../core/vault/vault_index.dart';
import '../core/vault/vault_models.dart';
import '../core/vault/native_entity.dart';
import '../core/vault/project_note_definition.dart';
import '../core/vault/report_layout.dart';
import '../core/vault/training_definition.dart';
import '../shared/app_log.dart';

class AppController extends ChangeNotifier {
  AppController()
    : credentials = CredentialStore(),
      parser = ObsidianParser(),
      workCodec = WorkEntryCodec(),
      index = VaultIndex(ObsidianParser(), WorkEntryCodec());

  final CredentialStore credentials;
  final ObsidianParser parser;
  final WorkEntryCodec workCodec;
  late EncryptedObjectStore store;
  final VaultIndex index;
  late EncryptedCachedRepository cache;
  late ImageCacheService imageCache;
  SyncEngine? _syncEngine;

  bool initialized = false;
  bool locked = true;
  bool busy = false;
  String? error;
  String? syncMessage;
  List<SyncConflict> conflicts = const [];
  SyncProgress? syncProgress;
  String? operationNotice;
  bool operationNoticeIsError = false;
  bool operationNoticeInProgress = false;
  WebDavCredentials? webDav;
  List<WebDavProfile> webDavProfiles = const [];
  String? activeProfileId;
  ReportLayoutConfig reportLayout = ReportLayoutConfig.defaults();
  int imageCacheLimitBytes = 250 * 1024 * 1024;
  MotionPreference motionPreference = MotionPreference.expressive;
  Timer? _noticeTimer;

  Future<void> initialize() async {
    AppLog.info('App', 'Инициализация приложения');
    try {
      imageCacheLimitBytes = await credentials.readImageCacheLimit();
      motionPreference = await credentials.readMotionPreference();
      webDavProfiles = await credentials.readProfiles();
      activeProfileId = await credentials.readActiveProfileId();
      final active =
          webDavProfiles
              .where((item) => item.id == activeProfileId)
              .firstOrNull ??
          webDavProfiles.firstOrNull;
      if (active != null) {
        activeProfileId = active.id;
        await _activateProfile(active, migrateLegacy: true);
      } else {
        store = EncryptedObjectStore();
        cache = EncryptedCachedRepository(store);
        await cache.initialize();
        imageCache = ImageCacheService(
          store: store,
          vault: cache,
          maxBytes: imageCacheLimitBytes,
        );
        await imageCache.initialize();
      }
      await refreshIndex();
      AppLog.info(
        'App',
        'Инициализация завершена; WebDAV настроен: ${webDav != null}',
      );
    } catch (exception, stackTrace) {
      error = exception.toString();
      AppLog.error('App', 'Ошибка инициализации', exception, stackTrace);
    } finally {
      initialized = true;
      locked = await credentials.hasPin;
      notifyListeners();
    }
  }

  Future<bool> unlock({String? pin}) async {
    final lock = AppLockService(credentials);
    final success = pin == null
        ? await lock.unlockWithSystem()
        : await lock.unlockWithPin(pin);
    if (success) {
      locked = false;
      notifyListeners();
    }
    return success;
  }

  void lock() {
    locked = true;
    notifyListeners();
  }

  Future<void> connect({
    required Uri url,
    required String username,
    required String password,
    required String pin,
  }) async {
    await _run('Проверка подключения WebDAV', () async {
      final value = WebDavCredentials(
        baseUrl: url,
        username: username,
        password: password,
      );
      AppLog.info(
        'Connect',
        'Проверка ${url.scheme}://${url.host}${url.path}; логин и пароль скрыты',
      );
      await WebDavClient(value).listTree();
      AppLog.info('Connect', 'WebDAV доступен, чтение дерева успешно');
      final profile = WebDavProfile(
        id: 'profile-${DateTime.now().microsecondsSinceEpoch}',
        name: url.host,
        baseUrl: url,
        username: username,
        password: password,
      );
      await credentials.saveProfile(profile);
      await credentials.setActiveProfile(profile.id);
      await credentials.savePin(pin);
      webDavProfiles = [...webDavProfiles, profile];
      await _activateProfile(profile);
      locked = false;
      await synchronize();
    });
  }

  WebDavProfile? get activeProfile =>
      webDavProfiles.where((item) => item.id == activeProfileId).firstOrNull;

  Future<WebDavProfile> saveWebDavProfile({
    String? id,
    required String name,
    required Uri url,
    required String username,
    required String password,
    bool activate = false,
  }) async {
    if (activate && activeProfileId != null && activeProfileId != id) {
      await synchronize();
      if (error != null || conflicts.isNotEmpty) {
        throw StateError(
          error ?? 'Перед переключением необходимо разрешить конфликты',
        );
      }
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
      await credentials.saveProfile(profile);
      webDavProfiles = [
        ...webDavProfiles.where((item) => item.id != profile.id),
        profile,
      ];
      if (activate ||
          activeProfileId == null ||
          activeProfileId == profile.id) {
        await _activateProfile(profile);
        await credentials.setActiveProfile(profile.id);
      }
    });
    if (error != null) throw StateError(error!);
    if (activeProfileId == profile.id) await synchronize();
    notifyListeners();
    return profile;
  }

  Future<void> switchWebDavProfile(String id, {bool syncCurrent = true}) async {
    if (id == activeProfileId) return;
    final target = webDavProfiles.where((item) => item.id == id).first;
    if (syncCurrent && webDav != null) {
      await synchronize();
      if (error != null || conflicts.isNotEmpty) {
        throw StateError(
          error ?? 'Перед переключением необходимо разрешить конфликты',
        );
      }
    }
    await _run('Переключение хранилища', () async {
      await _activateProfile(target);
      await credentials.setActiveProfile(target.id);
      await refreshIndex();
      conflicts = const [];
      syncMessage = 'Выбрано хранилище ${target.name}';
    });
    if (error != null) throw StateError(error!);
    await synchronize();
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
    await credentials.deleteProfile(id);
    if (deleteCache) {
      final oldStore = EncryptedObjectStore(namespace: id);
      await oldStore.initialize();
      await oldStore.clear();
    }
    webDavProfiles = webDavProfiles
        .where((item) => item.id != id)
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> setImageCacheLimit(int value) async {
    imageCacheLimitBytes = value;
    await credentials.saveImageCacheLimit(value);
    await imageCache.setLimit(value);
    notifyListeners();
  }

  Future<void> setMotionPreference(MotionPreference value) async {
    motionPreference = value;
    await credentials.saveMotionPreference(value);
    notifyListeners();
  }

  Future<StorageUsage> storageUsage() async {
    final currentTotal = await store.sizeBytes();
    var inactive = 0;
    for (final profile in webDavProfiles.where(
      (item) => item.id != activeProfileId,
    )) {
      final profileStore = EncryptedObjectStore(namespace: profile.id);
      await profileStore.initialize();
      inactive += await profileStore.sizeBytes();
    }
    final images = imageCache.sizeBytes;
    return StorageUsage(
      currentVaultBytes: (currentTotal - images).clamp(0, currentTotal),
      inactiveVaultBytes: inactive,
      imageBytes: images,
    );
  }

  Future<void> clearImageCache() async {
    await imageCache.clear();
    notifyListeners();
  }

  Future<void> clearInactiveVaultCaches() async {
    for (final profile in webDavProfiles.where(
      (item) => item.id != activeProfileId,
    )) {
      final profileStore = EncryptedObjectStore(namespace: profile.id);
      await profileStore.initialize();
      await profileStore.clear();
    }
    notifyListeners();
  }

  Future<void> clearCurrentVaultCache() async {
    await store.clear();
    cache = EncryptedCachedRepository(store);
    await cache.initialize();
    imageCache = ImageCacheService(
      store: store,
      vault: cache,
      maxBytes: imageCacheLimitBytes,
    );
    await imageCache.initialize();
    if (webDav != null) _configureSync(webDav!);
    await refreshIndex();
    notifyListeners();
  }

  Future<void> synchronize() async {
    final engine = _syncEngine;
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
            final merged = ReportLayoutConfig.merge(local, remote).encode();
            await engine.resolve(
              conflict,
              ConflictResolution.merged,
              merged: parser.encode(merged),
            );
            AppLog.info(
              'Reports',
              'Конфигурации блоков объединены автоматически',
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
        await refreshIndex();
        final active = activeProfile;
        if (active != null) {
          final updated = active.copyWith(lastSyncAt: DateTime.now().toUtc());
          await credentials.saveProfile(updated);
          webDavProfiles = [
            for (final profile in webDavProfiles)
              if (profile.id == updated.id) updated else profile,
          ];
        }
      });
    } finally {
      syncProgress = null;
      notifyListeners();
    }
  }

  Future<void> resolveConflict(
    SyncConflict conflict,
    ConflictResolution resolution, {
    String? merged,
  }) async {
    final engine = _syncEngine;
    if (engine == null) return;
    await _run('Разрешение конфликта ${conflict.path}', () async {
      await engine.resolve(
        conflict,
        resolution,
        merged: merged == null ? null : parser.encode(merged),
      );
      conflicts = conflicts
          .where((item) => item.path != conflict.path)
          .toList(growable: false);
      await refreshIndex();
    });
  }

  Future<void> saveNote(String path, String source) async {
    AppLog.info('Editor', 'Сохранение $path (${source.length} символов)');
    final current = await cache.read(path);
    final bytes = parser.encode(source);
    await cache.write(
      VaultDocument(
        path: path,
        bytes: bytes,
        modifiedAt: DateTime.now().toUtc(),
        etag: current?.etag,
      ),
    );
    await refreshIndex();
    notifyListeners();
    final engine = _syncEngine;
    if (engine == null) {
      AppLog.warning(
        'Editor',
        'WebDAV не настроен: $path сохранён только локально',
      );
      _showNotice('Сохранено локально · WebDAV не настроен', isError: true);
      return;
    }
    AppLog.info(
      'Editor',
      'Локальное сохранение завершено; запускается отправка $path в WebDAV (${bytes.length} байт)',
    );
    error = null;
    _showNotice('Отправка в WebDAV…', inProgress: true);
    try {
      final result = await engine.synchronizeFile(path);
      conflicts = [
        ...conflicts.where((conflict) => conflict.path != path),
        ...result.conflicts,
      ];
      if (result.conflicts.isNotEmpty) {
        AppLog.warning(
          'Editor',
          'Автосинхронизация $path требует разрешения конфликта',
        );
        _showNotice('Сохранено локально · обнаружен конфликт', isError: true);
      } else {
        syncMessage = result.uploaded == 0
            ? 'Файл уже актуален: $path'
            : 'Отправлен: $path';
        AppLog.info(
          'Editor',
          'Автосинхронизация после сохранения завершена: $path',
        );
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
      syncProgress = null;
      notifyListeners();
    }
  }

  Future<void> saveReportLayout(ReportLayoutConfig value) async {
    reportLayout = value;
    notifyListeners();
    await saveNote(ReportLayoutConfig.path, value.encode());
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
    super.dispose();
  }

  Future<void> addWorkEntry({
    required DateTime date,
    required String description,
    required double hours,
    required List<String> projects,
  }) async {
    final path = 'Daily/${DateFormat('dd MMMM yyyy', 'en').format(date)}.md';
    final current = await cache.read(path);
    var source = current?.text ?? await _dailyTemplateFromVault(date);
    final note = current == null ? null : parser.parse(current);
    final oldSection = note == null
        ? ''
        : _section(note.body, 'Что было сделано');
    final line = workCodec.encode(description, hours, projects);
    source = parser.replaceSection(
      source,
      'Что было сделано',
      '${oldSection.trimRight()}${oldSection.trim().isEmpty ? '' : '\n'}$line',
    );
    await saveNote(path, source);
  }

  Future<String> createDailyNote({
    required DateTime date,
    String steps = '',
    String sleep = '',
    String calories = '',
    String completed = '',
    String tomorrow = '',
  }) async {
    final path = 'Daily/${DateFormat('dd MMMM yyyy', 'en').format(date)}.md';
    final existing = await cache.read(path);
    if (existing != null) {
      AppLog.info('Daily', 'Заметка уже существует, создание пропущено: $path');
      return path;
    }
    var source = await _dailyTemplateFromVault(date);
    if (steps.trim().isNotEmpty) {
      source = parser.updateFrontmatter(source, ['step'], steps.trim());
    }
    if (sleep.trim().isNotEmpty) {
      source = parser.updateFrontmatter(source, ['sleep'], sleep.trim());
    }
    if (calories.trim().isNotEmpty) {
      source = parser.updateFrontmatter(source, ['calories'], calories.trim());
    }
    if (completed.trim().isNotEmpty) {
      source = parser.replaceSection(
        source,
        'Что было сделано',
        completed.trim(),
      );
    }
    if (tomorrow.trim().isNotEmpty) {
      source = parser.replaceSection(
        source,
        'Что нужно сделать завтра',
        tomorrow.trim(),
      );
    }
    AppLog.info('Daily', 'Создание ежедневной заметки: $path');
    await saveNote(path, source);
    return path;
  }

  Future<void> addTraining({
    required DateTime date,
    required String sportKey,
    required Map<String, double?> metrics,
    String mood = 'good',
    String analysis = '',
  }) async {
    final sport = trainingDefinition(sportKey);
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final folder = 'Areas/Health/Traning/$dateValue';
    var suffix = '';
    var index = 2;
    while (await cache.read('$folder/$sportKey$suffix.md') != null) {
      suffix = '-${index++}';
    }
    final duration = metrics['duration'] ?? 0;
    final heartRate = metrics['avg_hr'] ?? 0;
    // Keep the same 190 bpm estimate and bands as scripts/sport.js so a
    // workout created here produces the same assessment as in Obsidian.
    final heartRatePercent = heartRate / 190 * 100;
    final intensity = heartRatePercent < 50
        ? 0.3
        : heartRatePercent < 60
        ? 0.5
        : heartRatePercent < 70
        ? 0.7
        : heartRatePercent < 80
        ? 1.0
        : heartRatePercent < 90
        ? 1.5
        : 2.0;
    final trimp = duration * intensity;
    final load = ((trimp / 150) * 100).clamp(0, 100).round();
    final calculatedRecovery = ((load / 25) * 24).round();
    final recovery = calculatedRecovery < 12 ? 12 : calculatedRecovery;
    final metricYaml = sport.metrics
        .map((field) => '  ${field.key}: ${metrics[field.key] ?? ''}')
        .join('\n');
    final source =
        '''---
created: $dateValue
date: $dateValue
time: "${DateFormat('HH:mm').format(date)}"
type: training-log
tags: [${sport.tags.join(', ')}]
sport:
  - ${sport.name}
sport_key: $sportKey
mood: $mood
metrics:
$metricYaml
assessment:
  trimp: ${trimp.toStringAsFixed(1)}
  load: $load
  recovery_hours: $recovery
  joint_risk: ${sport.jointRisk}
  cardio: improving
---

# ${sport.icon} Тренировка — ${DateFormat('d MMMM yyyy', 'ru').format(date)} в ${DateFormat('HH:mm').format(date)}

```dataviewjs
await dv.view("Resources/Scripts/training-card");
```

## 📝 Анализ

${analysis.trim().isEmpty ? '> Заполнить после тренировки.' : analysis.trim()}

## 📌 Вывод

-
''';
    await saveNote('$folder/$sportKey$suffix.md', source);
  }

  Future<String> createNativeEntity(
    NativeEntityKind kind,
    Map<String, Object?> values,
  ) async {
    final definition = nativeEntityDefinitions.firstWhere(
      (item) => item.kind == kind,
    );
    final title = values['title']?.toString().trim();
    if (title == null || title.isEmpty) {
      throw ArgumentError('Название обязательно');
    }
    final path = await _uniquePath(definition.folder, _safeFileName(title));
    await saveNote(path, NativeEntityTemplate().build(kind, values));
    AppLog.info('Create', 'Создана сущность ${kind.name}: $path');
    return path;
  }

  Future<String> createProject({
    required String title,
    required String status,
    String description = '',
  }) async {
    final name = _safeFileName(title);
    final path = 'Projects/$name/_Project.md';
    if (await cache.read(path) != null) {
      throw StateError('Проект уже существует: $title');
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await saveNote(path, '''---
type: project
project: ${_yamlScalar(title)}
status: $status
archived: ${status == 'archived'}
created: $today
due:
tags: [project]
---

# $title

```dataviewjs
await dv.view("Resources/Scripts/project-dashboard");
```

## Описание

$description

## Цели

- [ ]

## Ключевые ссылки

-
''');
    AppLog.info('Create', 'Создан проект: $path');
    return path;
  }

  Future<String> createProjectTask({
    required String project,
    required String title,
    required String priority,
    DateTime? due,
    String description = '',
  }) async {
    final folder = 'Projects/${_safeFileName(project)}';
    final path = await _uniquePath(folder, _safeFileName(title));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await saveNote(path, '''---
type: task
project: ${_yamlScalar(project)}
created: $today
status: todo
complete: false
priority: $priority
hours: 0
due: ${due == null ? '' : DateFormat('yyyy-MM-dd').format(due)}
tags: [task]
---

# $title

```dataviewjs
await dv.view("Resources/Scripts/project-note-card");
```

## Описание

$description

## Критерии готовности

- [ ]
''');
    AppLog.info('Create', 'Создана задача: $path');
    return path;
  }

  Future<String> createProjectNote({
    required String project,
    required String title,
    required String noteType,
    Map<String, String> sections = const {},
  }) async {
    final definition = projectNoteDefinition(noteType);
    final folder = 'Projects/${_safeFileName(project)}';
    final path = await _uniquePath(folder, _safeFileName(title));
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final template = await cache.read(
      'Templates/Projects/${definition.templateName}.md',
    );
    var source =
        template?.text ??
        '''---
type: project-note
note_type: ${definition.key}
project: {{project}}
created: {{created}}
tags: [${definition.key}]
aliases: []
---

# {{title}}

```dataviewjs
await dv.view("Resources/Scripts/project-note-card");
```
''';
    source = source
        .replaceAll('{{project}}', _yamlScalar(project))
        .replaceAll('{{created}}', today)
        .replaceAll('{{title}}', title.trim());
    for (final entry in sections.entries) {
      if (entry.value.trim().isNotEmpty) {
        source = parser.replaceSection(source, entry.key, entry.value.trim());
      }
    }
    AppLog.info(
      'Project',
      'Создание материала ${definition.key} для $project: $path',
    );
    await saveNote(path, source);
    return path;
  }

  Future<void> setProjectArchived(ParsedNote project, bool archived) async {
    var source = project.document.text;
    source = parser.updateFrontmatter(source, [
      'status',
    ], archived ? 'archived' : 'active');
    source = parser.updateFrontmatter(source, ['archived'], archived);
    await saveNote(project.document.path, source);
    AppLog.info(
      'Project',
      '${archived ? 'Архивирован' : 'Восстановлен'} проект ${project.title}',
    );
  }

  Future<void> setTaskComplete(ParsedNote task, bool complete) async {
    var source = task.document.text;
    source = parser.updateFrontmatter(source, ['complete'], complete);
    source = parser.updateFrontmatter(source, [
      'status',
    ], complete ? 'done' : 'todo');
    await saveNote(task.document.path, source);
    AppLog.info(
      'Task',
      '${complete ? 'Завершена' : 'Возвращена'} задача ${task.title}',
    );
  }

  Future<void> refreshIndex() async {
    final documents = await cache.list();
    index.rebuild(documents);
    final layout = documents
        .where((item) => item.path == ReportLayoutConfig.path)
        .firstOrNull;
    if (layout == null) {
      reportLayout = ReportLayoutConfig.defaults();
      return;
    }
    try {
      reportLayout = ReportLayoutConfig.decode(layout.text);
    } catch (error, stackTrace) {
      reportLayout = ReportLayoutConfig.defaults();
      AppLog.error(
        'Reports',
        'Конфигурация блоков повреждена; используется стандартная',
        error,
        stackTrace,
      );
    }
  }

  void _configureSync(WebDavCredentials value) {
    _syncEngine = SyncEngine(
      local: cache,
      store: store,
      remote: WebDavClient(value),
      onProgress: (progress) {
        syncProgress = progress;
        notifyListeners();
      },
    );
  }

  Future<void> _activateProfile(
    WebDavProfile profile, {
    bool migrateLegacy = false,
  }) async {
    activeProfileId = profile.id;
    webDav = profile.credentials;
    store = EncryptedObjectStore(
      namespace: profile.id,
      migrateLegacy: migrateLegacy,
    );
    cache = EncryptedCachedRepository(store);
    await cache.initialize();
    imageCache = ImageCacheService(
      store: store,
      vault: cache,
      maxBytes: imageCacheLimitBytes,
    );
    await imageCache.initialize();
    _configureSync(profile.credentials);
    AppLog.info('Profiles', 'Активирован WebDAV-профиль ${profile.name}');
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    busy = true;
    error = null;
    AppLog.debug('Operation', 'Начало: $label');
    notifyListeners();
    try {
      await operation();
      AppLog.debug('Operation', 'Успешно: $label');
    } catch (exception, stackTrace) {
      error = exception.toString();
      AppLog.error('Operation', 'Ошибка: $label', exception, stackTrace);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _dailyTemplate(DateTime date) {
    final isoWeek = _isoWeek(date);
    return '''---
tags:
  - Ежедневник
created: ${DateFormat('yyyy-MM-dd').format(date)}
week: "$isoWeek"
step:
sleep:
calories:
---

# ${DateFormat('d MMMM yyyy', 'ru').format(date)}

### Что было сделано

### Что нужно сделать завтра

### Тренировки

```dataviewjs
// Pavel Vault keeps this section compatible with Obsidian.
await dv.view("Resources/Scripts/training-card");
```
''';
  }

  Future<String> _dailyTemplateFromVault(DateTime date) async {
    final template = await cache.read('Templates/Daily note.md');
    if (template == null) return _dailyTemplate(date);
    final body = template.text.replaceFirst(RegExp(r'^<%\*[\s\S]*?-%>\s*'), '');
    final source =
        '''---
tags: [Ежедневник]
created: ${DateFormat('yyyy-MM-dd').format(date)}
week: "${_isoWeek(date)}"
step:
sleep:
calories:
---

$body''';
    AppLog.debug(
      'Daily',
      'Использован Obsidian-шаблон Templates/Daily note.md',
    );
    return source;
  }

  String _isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week =
        1 +
        thursday
                .difference(
                  firstThursday.subtract(
                    Duration(days: firstThursday.weekday - 1),
                  ),
                )
                .inDays ~/
            7;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  String _section(String body, String heading) =>
      RegExp(
        '^#{1,6}\\s+${RegExp.escape(heading)}\\s*\\r?\\n([\\s\\S]*?)(?=^#{1,6}\\s+|\\z)',
        multiLine: true,
      ).firstMatch(body)?.group(1) ??
      '';

  Future<String> _uniquePath(String folder, String name) async {
    var path = '$folder/$name.md';
    var suffix = 2;
    while (await cache.read(path) != null) {
      path = '$folder/$name-${suffix++}.md';
    }
    return path;
  }

  String _safeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return cleaned.isEmpty ? 'Без названия' : cleaned;
  }

  String _yamlScalar(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
