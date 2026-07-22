import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'task_models.dart';

abstract interface class TaskNotificationScheduler {
  Future<void> initialize(void Function(String taskId) onOpen);
  Future<void> reconcile(Iterable<TaskDefinition> tasks);
}

class TaskNotificationService implements TaskNotificationScheduler {
  TaskNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Map<int, Timer> _linuxTimers = {};
  final Set<String> _shown = {};
  void Function(String taskId)? _onOpen;
  bool _initialized = false;

  @override
  Future<void> initialize(void Function(String taskId) onOpen) async {
    if (_initialized) return;
    _onOpen = onOpen;
    tz_data.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      linux: LinuxInitializationSettings(defaultActionName: 'Открыть'),
      windows: WindowsInitializationSettings(
        appName: 'Vellum',
        appUserModelId: 'dev.pavelvault.Vellum',
        guid: '73e70e0c-fd2d-4d25-943d-f2055fc04acd',
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _onOpen?.call(payload);
      },
    );
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    _initialized = true;
  }

  @override
  Future<void> reconcile(Iterable<TaskDefinition> tasks) async {
    if (!_initialized) return;
    for (final timer in _linuxTimers.values) {
      timer.cancel();
    }
    _linuxTimers.clear();
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Portable Windows builds may not have package identity and cannot
      // enumerate/cancel notifications. Markdown remains the source of truth.
    }
    final now = DateTime.now();
    for (final task in tasks.where(
      (item) => !item.completed && item.remindAt != null,
    )) {
      final at = task.remindAt!;
      final id = _notificationId(task.id);
      if (!at.isAfter(now)) {
        if (now.difference(at) <= const Duration(days: 1) &&
            _shown.add(task.id)) {
          await _show(id, task);
        }
        continue;
      }
      if (Platform.isLinux) {
        final delay = at.difference(now);
        if (delay <= const Duration(days: 1)) {
          _linuxTimers[id] = Timer(delay, () => _show(id, task));
        }
        continue;
      }
      try {
        await _schedule(task, id, at, AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        await _schedule(task, id, at, AndroidScheduleMode.inexactAllowWhileIdle);
      }
    }
  }

  Future<void> _schedule(
    TaskDefinition task,
    int id,
    DateTime at,
    AndroidScheduleMode mode,
  ) => _plugin.zonedSchedule(
    id: id,
    title: task.title,
    body: task.project == null ? 'Задача Vellum' : task.project!,
    scheduledDate: tz.TZDateTime.from(at, tz.local),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'vellum_tasks',
        'Напоминания о задачах',
        channelDescription: 'Сроки Markdown-задач Vellum',
        importance: Importance.high,
        priority: Priority.high,
      ),
      windows: WindowsNotificationDetails(),
    ),
    androidScheduleMode: mode,
    payload: task.id,
  );

  Future<void> _show(int id, TaskDefinition task) => _plugin.show(
    id: id,
    title: task.title,
    body: task.project == null ? 'Задача Vellum' : task.project!,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'vellum_tasks',
        'Напоминания о задачах',
        channelDescription: 'Сроки Markdown-задач Vellum',
        importance: Importance.high,
        priority: Priority.high,
      ),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    ),
    payload: task.id,
  );

  int _notificationId(String value) {
    var hash = 0;
    for (final unit in value.codeUnits) {
      hash = ((hash * 31) + unit) & 0x7fffffff;
    }
    return hash;
  }
}
