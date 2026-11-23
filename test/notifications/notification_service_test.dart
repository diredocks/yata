import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/notifications/notification_service.dart';
import 'package:yata/notifications/snooze_reminder_sheet.dart';
import 'package:yata/settings/settings_screen.dart';

class _FakeTransport implements NotificationTransport {
  final Map<int, _ScheduledCall> scheduled = {};
  final Map<int, _ShownCall> shown = {};
  final List<int> cancelled = [];
  bool permissionRequested = false;

  @override
  bool get supportsZonedSchedule => true;

  @override
  Future<void> initialize({
    required void Function(NotificationResponse response) onResponse,
  }) async {}

  @override
  Future<bool> requestPermissions() async {
    permissionRequested = true;
    return true;
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
    shown[id] = _ShownCall(
      id: id,
      title: title,
      body: body,
      ongoing: ongoing,
      payload: payload,
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
    scheduled[id] = _ScheduledCall(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      ongoing: ongoing,
      repeatDaily: repeatDaily,
      payload: payload,
      actions: actions,
    );
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    shown.remove(id);
    cancelled.add(id);
  }
}

class _ScheduledCall {
  const _ScheduledCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.ongoing,
    required this.repeatDaily,
    required this.payload,
    required this.actions,
  });

  final int id;
  final String title;
  final String body;
  final tz.TZDateTime scheduledDate;
  final bool ongoing;
  final bool repeatDaily;
  final String? payload;
  final List<AndroidNotificationAction> actions;
}

class _ShownCall {
  const _ShownCall({
    required this.id,
    required this.title,
    required this.body,
    required this.ongoing,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final bool ongoing;
  final String? payload;
}

TodoState _makeState({
  List<TaskItem> tasks = const [],
  bool remindersEnabled = true,
  bool pinReminders = false,
  bool dueTodayNotificationsEnabled = false,
  int dueTodayNotificationHour = 9,
  int dueTodayNotificationMinute = 0,
  bool routineNotificationEnabled = false,
  int routineNotificationHour = 8,
  int routineNotificationMinute = 30,
  bool quickAddNotificationEnabled = false,
}) {
  return TodoState(
    lists: defaultSmartLists(),
    groups: const [],
    tasks: tasks,
    selectedListId: 'my_day',
    remindersEnabled: remindersEnabled,
    pinReminders: pinReminders,
    dueTodayNotificationsEnabled: dueTodayNotificationsEnabled,
    dueTodayNotificationHour: dueTodayNotificationHour,
    dueTodayNotificationMinute: dueTodayNotificationMinute,
    routineNotificationEnabled: routineNotificationEnabled,
    routineNotificationHour: routineNotificationHour,
    routineNotificationMinute: routineNotificationMinute,
    quickAddNotificationEnabled: quickAddNotificationEnabled,
  );
}

void main() {
  test(
    'NotificationService schedules, pins, and cancels task reminders',
    () async {
      final now = DateTime(2026, 11, 22, 8, 0);
      final transport = _FakeTransport();
      final service = NotificationService(
        transport: transport,
        clock: () => now,
      );

      final activeTask = TaskItem(
        id: 'task_1',
        listId: 'tasks',
        title: 'Buy milk',
        reminderAt: DateTime(2026, 11, 22, 10, 0),
        createdAt: now,
      );
      final completedTask = TaskItem(
        id: 'task_2',
        listId: 'tasks',
        title: 'Already done',
        isCompleted: true,
        reminderAt: DateTime(2026, 11, 22, 11, 0),
        createdAt: now,
      );
      final pastTask = TaskItem(
        id: 'task_3',
        listId: 'tasks',
        title: 'Past reminder',
        reminderAt: DateTime(2026, 11, 22, 7, 0),
        createdAt: now,
      );

      await service.syncWithState(
        _makeState(
          tasks: [activeTask, completedTask, pastTask],
          pinReminders: true,
        ),
      );

      final task1Id = NotificationService.notificationIdForTask('task_1');
      expect(transport.scheduled.keys, [task1Id]);
      expect(transport.scheduled[task1Id]!.title, 'Buy milk');
      expect(transport.scheduled[task1Id]!.ongoing, isTrue);
      expect(transport.scheduled[task1Id]!.actions.length, 2);

      // Disabling reminders cancels the scheduled notification.
      await service.syncWithState(
        _makeState(tasks: [activeTask], remindersEnabled: false),
      );
      expect(transport.scheduled, isEmpty);
      expect(transport.cancelled, contains(task1Id));
    },
  );

  test('NotificationService manages Due Today, Routine, and Quick Add notifications', () async {
    final now = DateTime(2026, 11, 22, 8, 0);
    final transport = _FakeTransport();
    final service = NotificationService(transport: transport, clock: () => now);

    final dueTodayTask = TaskItem(
      id: 't_due',
      listId: 'tasks',
      title: 'Submit report',
      dueDate: DateTime(2026, 11, 22),
      createdAt: now,
    );

    await service.syncWithState(
      _makeState(
        tasks: [dueTodayTask],
        dueTodayNotificationsEnabled: true,
        dueTodayNotificationHour: 9,
        dueTodayNotificationMinute: 15,
        routineNotificationEnabled: true,
        routineNotificationHour: 8,
        routineNotificationMinute: 30,
        quickAddNotificationEnabled: true,
      ),
    );

    expect(
      transport
          .scheduled[NotificationService.dueTodayNotificationId]!
          .repeatDaily,
      isTrue,
    );
    expect(
      transport.scheduled[NotificationService.dueTodayNotificationId]!.body,
      'Submit report',
    );
    expect(
      transport
          .scheduled[NotificationService.routineNotificationId]!
          .repeatDaily,
      isTrue,
    );
    expect(
      transport.shown[NotificationService.quickAddNotificationId]!.ongoing,
      isTrue,
    );

    // Turning off Quick Add cancels the persistent notification.
    await service.syncWithState(
      _makeState(
        tasks: [dueTodayTask],
        dueTodayNotificationsEnabled: false,
        routineNotificationEnabled: false,
        quickAddNotificationEnabled: false,
      ),
    );
    expect(
      transport.shown.containsKey(NotificationService.quickAddNotificationId),
      isFalse,
    );
    expect(
      transport.cancelled,
      containsAll([
        NotificationService.dueTodayNotificationId,
        NotificationService.routineNotificationId,
        NotificationService.quickAddNotificationId,
      ]),
    );
  });

  test('NotificationService parses tap and action responses', () async {
    final transport = _FakeTransport();
    final service = NotificationService(transport: transport);
    final events = <NotificationActionEvent>[];
    final sub = service.events.listen(events.add);

    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: '{"type":"reminder","taskId":"task_42"}',
      ),
    );
    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: NotificationService.completeActionId,
        payload: '{"type":"reminder","taskId":"task_42"}',
      ),
    );
    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: NotificationService.snoozeActionId,
        payload: '{"type":"reminder","taskId":"task_42"}',
      ),
    );
    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: '{"type":"quick_add"}',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events.map((e) => e.type), [
      NotificationActionType.openTask,
      NotificationActionType.completeTask,
      NotificationActionType.snoozeTask,
      NotificationActionType.quickAdd,
    ]);
    expect(events.first.taskId, 'task_42');
    await sub.cancel();
  });

  testWidgets('SettingsScreen toggles and persists notification preferences', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final transport = _FakeTransport();
    final service = NotificationService(transport: transport);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          notificationServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Quick add notification'), 300);
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Pin Reminders'), findsOneWidget);
    expect(find.text('Due Today notifications'), findsOneWidget);
    expect(find.text('Plan your day reminders'), findsOneWidget);
    expect(find.text('Quick add notification'), findsOneWidget);

    // Enable Due Today notifications -> reveals time tile and requests permission.
    await tester.tap(find.text('Due Today notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Time of Due Today notifications'), findsOneWidget);
    expect(transport.permissionRequested, isTrue);

    // Verify persistence in TodoSettingsStore.
    final reloaded = TodoSettingsStore(prefs).load().fold(
      (snapshot) => snapshot,
      (error) => fail('local snapshot load failed: ${error.describe()}'),
    );
    expect(reloaded.dueTodayNotificationsEnabled, isTrue);
  });

  testWidgets(
    'showSnoozeReminderSheet shows all 5 options and returns chosen duration',
    (WidgetTester tester) async {
      Duration? chosen;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    chosen = await showSnoozeReminderSheet(
                      context,
                      taskTitle: 'Call doctor',
                    );
                  },
                  child: const Text('Open Snooze'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Snooze'));
      await tester.pumpAndSettle();

      expect(find.text('Snooze reminder'), findsOneWidget);
      expect(find.text('Call doctor'), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);
      expect(find.text('10 minutes'), findsOneWidget);
      expect(find.text('15 minutes'), findsOneWidget);
      expect(find.text('30 minutes'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);

      await tester.tap(find.text('30 minutes'));
      await tester.pumpAndSettle();

      expect(chosen, const Duration(minutes: 30));
    },
  );
}
