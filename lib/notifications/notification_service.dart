import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

/// Action triggered when the user interacts with a notification or its buttons.
enum NotificationActionType {
  openTask,
  completeTask,
  snoozeTask,
  openMyDay,
  quickAdd,
}

@immutable
class NotificationActionEvent {
  const NotificationActionEvent({
    required this.type,
    this.taskId,
  });

  final NotificationActionType type;
  final String? taskId;
}

@immutable
class NotificationStrings {
  const NotificationStrings({
    required this.completeActionLabel,
    required this.snoozeActionLabel,
    required this.dueTodaySingleTitle,
    required this.dueTodayMultipleTitleBuilder,
    required this.routineTitle,
    required this.routineBody,
    required this.quickAddTitle,
    required this.quickAddBody,
    required this.defaultTasksListName,
  });

  factory NotificationStrings.fromLocalizations(AppLocalizations l10n) {
    return NotificationStrings(
      completeActionLabel: l10n.notificationCompleteAction,
      snoozeActionLabel: l10n.notificationSnoozeAction,
      dueTodaySingleTitle: l10n.dueTodayNotificationSingleTitle,
      dueTodayMultipleTitleBuilder: l10n.dueTodayNotificationMultipleTitle,
      routineTitle: l10n.routineNotificationTitle,
      routineBody: l10n.routineNotificationBody,
      quickAddTitle: l10n.quickAddNotificationTitle,
      quickAddBody: l10n.quickAddNotificationBody,
      defaultTasksListName: l10n.tasks,
    );
  }

  static NotificationStrings fallbackEnglish() {
    return NotificationStrings(
      completeActionLabel: 'Complete',
      snoozeActionLabel: 'Snooze 15m',
      dueTodaySingleTitle: 'You have a task due today',
      dueTodayMultipleTitleBuilder: (count) =>
          'You have $count tasks due today',
      routineTitle: 'What will you do today?',
      routineBody: 'What do you want to accomplish today? Plan it with YATA.',
      quickAddTitle: 'YATA Quick Add',
      quickAddBody: 'Tap to add a new task',
      defaultTasksListName: 'Tasks',
    );
  }

  final String completeActionLabel;
  final String snoozeActionLabel;
  final String dueTodaySingleTitle;
  final String Function(int count) dueTodayMultipleTitleBuilder;
  final String routineTitle;
  final String routineBody;
  final String quickAddTitle;
  final String quickAddBody;
  final String defaultTasksListName;
}

/// Abstract transport so tests can verify notification scheduling without OS channels.
abstract class NotificationTransport {
  bool get supportsZonedSchedule;

  Future<void> initialize({
    required void Function(NotificationResponse response) onResponse,
  });

  Future<bool> requestPermissions();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
    bool ongoing = false,
    bool highPriority = false,
    List<AndroidNotificationAction> actions = const [],
  });

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String channelId,
    required String channelName,
    String? payload,
    bool ongoing = false,
    bool highPriority = true,
    bool repeatDaily = false,
    List<AndroidNotificationAction> actions = const [],
  });

  Future<void> cancel(int id);
}

class FlutterLocalNotificationTransport implements NotificationTransport {
  FlutterLocalNotificationTransport([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  bool get supportsZonedSchedule =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  Future<T?> _guardPlatform<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      // In headless widget tests (no plugin registrant) or unsupported hosts,
      // FlutterLocalNotificationsPlatform.instance is uninitialized.
      return null;
    }
  }

  @override
  Future<void> initialize({
    required void Function(NotificationResponse response) onResponse,
  }) async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open YATA',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
      macOS: darwinSettings,
      iOS: darwinSettings,
    );
    await _guardPlatform(
      () => _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: onResponse,
      ),
    );
  }

  @override
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    final result = await _guardPlatform<bool>(() async {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission();
        await android?.requestExactAlarmsPermission();
        return granted ?? true;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            true;
      }
      return true;
    });
    return result ?? true;
  }

  NotificationDetails _details({
    required String channelId,
    required String channelName,
    bool ongoing = false,
    bool highPriority = false,
    List<AndroidNotificationAction> actions = const [],
  }) {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: highPriority
          ? Importance.high
          : (ongoing ? Importance.low : Importance.defaultImportance),
      priority: highPriority
          ? Priority.high
          : (ongoing ? Priority.low : Priority.defaultPriority),
      ongoing: ongoing,
      autoCancel: !ongoing,
      onlyAlertOnce: ongoing,
      actions: actions,
    );
    const linuxDetails = LinuxNotificationDetails();
    const darwinDetails = DarwinNotificationDetails();
    return NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? payload,
    bool ongoing = false,
    bool highPriority = false,
    List<AndroidNotificationAction> actions = const [],
  }) async {
    if (kIsWeb) return;
    await _guardPlatform(
      () => _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: _details(
          channelId: channelId,
          channelName: channelName,
          ongoing: ongoing,
          highPriority: highPriority,
          actions: actions,
        ),
      ),
    );
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String channelId,
    required String channelName,
    String? payload,
    bool ongoing = false,
    bool highPriority = true,
    bool repeatDaily = false,
    List<AndroidNotificationAction> actions = const [],
  }) async {
    if (!supportsZonedSchedule) return;
    final details = _details(
      channelId: channelId,
      channelName: channelName,
      ongoing: ongoing,
      highPriority: highPriority,
      actions: actions,
    );
    final match = repeatDaily ? DateTimeComponents.time : null;
    await _guardPlatform(() async {
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: match,
          payload: payload,
        );
      } catch (_) {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: match,
          payload: payload,
        );
      }
    });
  }

  @override
  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await _guardPlatform(() => _plugin.cancel(id: id));
  }
}

/// Schedules task reminders, Due Today summary, Plan Your Day routine, and
/// Quick Add persistent notifications, matching `mstodo` reminder & notification
/// settings.
class NotificationService {
  NotificationService({
    NotificationTransport? transport,
    DateTime Function()? clock,
  })  : _transport = transport ?? FlutterLocalNotificationTransport(),
        _clock = clock ?? DateTime.now;

  static const dueTodayNotificationId = 1001;
  static const routineNotificationId = 1002;
  static const quickAddNotificationId = 1003;

  static const completeActionId = 'complete';
  static const snoozeActionId = 'snooze_15';

  final NotificationTransport _transport;
  final DateTime Function() _clock;
  final _eventsController =
      StreamController<NotificationActionEvent>.broadcast();

  final Set<int> _scheduledTaskIds = {};
  final Map<int, Timer> _fallbackTimers = {};
  bool _initialized = false;
  bool _tzInitialized = false;
  late tz.Location _localLocation;
  bool _quickAddShown = false;

  Stream<NotificationActionEvent> get events => _eventsController.stream;

  static int notificationIdForTask(String taskId) {
    // Deterministic positive 31-bit ID >= 100000 to avoid colliding with fixed IDs.
    var hash = 0;
    for (var i = 0; i < taskId.length; i++) {
      hash = (hash * 31 + taskId.codeUnitAt(i)) & 0x3FFFFFFF;
    }
    return 100000 + hash;
  }

  void _ensureTimeZone() {
    if (_tzInitialized) return;
    _tzInitialized = true;
    tz_data.initializeTimeZones();
    final offset = _clock().timeZoneOffset;
    tz.Location? matched;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.currentTimeZone.offset == offset) {
        matched = loc;
        break;
      }
    }
    _localLocation = matched ?? tz.UTC;
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    _ensureTimeZone();
    await _transport.initialize(onResponse: handleNotificationResponse);
  }

  Future<bool> requestPermissions() async {
    await ensureInitialized();
    return _transport.requestPermissions();
  }

  @visibleForTesting
  void handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      final type = decoded['type'] as String?;
      final taskId = decoded['taskId'] as String?;

      if (type == 'quick_add') {
        _eventsController.add(
          const NotificationActionEvent(type: NotificationActionType.quickAdd),
        );
        return;
      }
      if (type == 'due_today' || type == 'routine') {
        _eventsController.add(
          const NotificationActionEvent(type: NotificationActionType.openMyDay),
        );
        return;
      }
      if (type == 'reminder' && taskId != null) {
        if (response.actionId == completeActionId) {
          _eventsController.add(
            NotificationActionEvent(
              type: NotificationActionType.completeTask,
              taskId: taskId,
            ),
          );
        } else if (response.actionId == snoozeActionId) {
          _eventsController.add(
            NotificationActionEvent(
              type: NotificationActionType.snoozeTask,
              taskId: taskId,
            ),
          );
        } else {
          _eventsController.add(
            NotificationActionEvent(
              type: NotificationActionType.openTask,
              taskId: taskId,
            ),
          );
        }
      }
    } catch (_) {
      // Ignore malformed payloads.
    }
  }

  void _cancelFallbackTimer(int id) {
    _fallbackTimers.remove(id)?.cancel();
  }

  void _scheduleFallbackTimer({
    required int id,
    required DateTime target,
    required VoidCallback onFire,
  }) {
    _cancelFallbackTimer(id);
    final delay = target.difference(_clock());
    if (delay <= Duration.zero || delay > const Duration(days: 7)) return;
    _fallbackTimers[id] = Timer(delay, () {
      _fallbackTimers.remove(id);
      onFire();
    });
  }

  DateTime _nextDailyOccurrence(int hour, int minute, DateTime now) {
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }

  String _resolveListName(
    TaskItem task,
    List<TodoList> lists,
    String defaultTasksName,
  ) {
    if (task.listId == 'tasks') return defaultTasksName;
    for (final list in lists) {
      if (list.id == task.listId) return list.title;
    }
    return defaultTasksName;
  }

  Future<void> syncWithState(
    TodoState state, {
    NotificationStrings? strings,
  }) async {
    await ensureInitialized();
    final l10n = strings ?? NotificationStrings.fallbackEnglish();
    final now = _clock();

    // 1. Task reminder notifications.
    final nextTaskIds = <int>{};
    if (state.remindersEnabled) {
      for (final task in state.tasks) {
        final reminderAt = task.reminderAt;
        if (task.isCompleted || reminderAt == null || !reminderAt.isAfter(now)) {
          continue;
        }
        final id = notificationIdForTask(task.id);
        nextTaskIds.add(id);
        final listName = _resolveListName(
          task,
          state.lists,
          l10n.defaultTasksListName,
        );
        final payload = jsonEncode({'type': 'reminder', 'taskId': task.id});
        final actions = [
          AndroidNotificationAction(
            completeActionId,
            l10n.completeActionLabel,
            showsUserInterface: true,
          ),
          AndroidNotificationAction(
            snoozeActionId,
            l10n.snoozeActionLabel,
            showsUserInterface: true,
          ),
        ];

        if (_transport.supportsZonedSchedule) {
          await _transport.schedule(
            id: id,
            title: task.title,
            body: listName,
            scheduledDate: tz.TZDateTime.from(reminderAt, _localLocation),
            channelId: 'reminders',
            channelName: 'Task Reminders',
            payload: payload,
            ongoing: state.pinReminders,
            highPriority: true,
            actions: actions,
          );
        } else {
          _scheduleFallbackTimer(
            id: id,
            target: reminderAt,
            onFire: () {
              unawaited(
                _transport.show(
                  id: id,
                  title: task.title,
                  body: listName,
                  channelId: 'reminders',
                  channelName: 'Task Reminders',
                  payload: payload,
                  ongoing: state.pinReminders,
                  highPriority: true,
                  actions: actions,
                ),
              );
            },
          );
        }
      }
    }

    for (final oldId in _scheduledTaskIds.difference(nextTaskIds)) {
      _cancelFallbackTimer(oldId);
      await _transport.cancel(oldId);
    }
    _scheduledTaskIds
      ..clear()
      ..addAll(nextTaskIds);

    // 2. Due Today daily summary notification.
    final dueTodayTasks = state.tasks.where((t) {
      return !t.isCompleted &&
          t.dueDate != null &&
          TodoNotifier.isSameDay(t.dueDate!, now);
    }).toList(growable: false);

    if (state.dueTodayNotificationsEnabled && dueTodayTasks.isNotEmpty) {
      final target = _nextDailyOccurrence(
        state.dueTodayNotificationHour,
        state.dueTodayNotificationMinute,
        now,
      );
      final title = dueTodayTasks.length == 1
          ? l10n.dueTodaySingleTitle
          : l10n.dueTodayMultipleTitleBuilder(dueTodayTasks.length);
      final body = dueTodayTasks.take(3).map((t) => t.title).join(', ');
      final payload = jsonEncode({'type': 'due_today'});

      if (_transport.supportsZonedSchedule) {
        await _transport.schedule(
          id: dueTodayNotificationId,
          title: title,
          body: body,
          scheduledDate: tz.TZDateTime.from(target, _localLocation),
          channelId: 'due_today',
          channelName: 'Due Today',
          payload: payload,
          highPriority: false,
          repeatDaily: true,
        );
      } else {
        _scheduleFallbackTimer(
          id: dueTodayNotificationId,
          target: target,
          onFire: () {
            unawaited(
              _transport.show(
                id: dueTodayNotificationId,
                title: title,
                body: body,
                channelId: 'due_today',
                channelName: 'Due Today',
                payload: payload,
              ),
            );
          },
        );
      }
    } else {
      _cancelFallbackTimer(dueTodayNotificationId);
      await _transport.cancel(dueTodayNotificationId);
    }

    // 3. Plan Your Day (Routine) daily notification.
    if (state.routineNotificationEnabled) {
      final target = _nextDailyOccurrence(
        state.routineNotificationHour,
        state.routineNotificationMinute,
        now,
      );
      final payload = jsonEncode({'type': 'routine'});

      if (_transport.supportsZonedSchedule) {
        await _transport.schedule(
          id: routineNotificationId,
          title: l10n.routineTitle,
          body: l10n.routineBody,
          scheduledDate: tz.TZDateTime.from(target, _localLocation),
          channelId: 'routine',
          channelName: 'Plan Your Day',
          payload: payload,
          highPriority: false,
          repeatDaily: true,
        );
      } else {
        _scheduleFallbackTimer(
          id: routineNotificationId,
          target: target,
          onFire: () {
            unawaited(
              _transport.show(
                id: routineNotificationId,
                title: l10n.routineTitle,
                body: l10n.routineBody,
                channelId: 'routine',
                channelName: 'Plan Your Day',
                payload: payload,
              ),
            );
          },
        );
      }
    } else {
      _cancelFallbackTimer(routineNotificationId);
      await _transport.cancel(routineNotificationId);
    }

    // 4. Quick Add persistent notification.
    if (state.quickAddNotificationEnabled) {
      if (!_quickAddShown) {
        _quickAddShown = true;
        await _transport.show(
          id: quickAddNotificationId,
          title: l10n.quickAddTitle,
          body: l10n.quickAddBody,
          channelId: 'quick_add',
          channelName: 'Quick Add',
          payload: jsonEncode({'type': 'quick_add'}),
          ongoing: true,
          highPriority: false,
        );
      }
    } else if (_quickAddShown) {
      _quickAddShown = false;
      await _transport.cancel(quickAddNotificationId);
    }
  }

  void dispose() {
    for (final timer in _fallbackTimers.values) {
      timer.cancel();
    }
    _fallbackTimers.clear();
    unawaited(_eventsController.close());
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.dispose);
  return service;
});
