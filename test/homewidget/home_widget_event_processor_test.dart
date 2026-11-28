import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/homewidget/home_widget_sync.dart';

import '../helpers/home_widget_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetEventProcessor', () {
    final localAccount = LocalAccount(
      id: 'acct_a',
      displayName: 'Alice',
      email: 'alice@example.com',
    );
    final msAccount = MicrosoftAccount(
      id: 'acct_ms',
      displayName: 'Bob',
      email: 'bob@outlook.com',
      microsoftUserId: 'ms_cid_1',
    );

    test('applies unacked ops, skips already-acked & cross-account ops, and handles recurrence', () async {
      final alreadyAckedTask = TaskItem(
        id: 't0',
        listId: 'tasks',
        title: 'Already acked',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final recurring = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Daily standup',
        createdAt: DateTime.utc(2026, 11, 24, 8),
        dueDate: DateTime(2026, 11, 24),
        recurrence: RecurrenceType.daily,
      );
      final otherTask = TaskItem(
        id: 't2',
        listId: 'tasks',
        title: 'Write docs',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final crossAcctTask = TaskItem(
        id: 't3',
        listId: 'tasks',
        title: 'Do not touch',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createWidgetTestHarness(
        accounts: [localAccount],
        activeAccountId: 'acct_a',
        initialTasks: [alreadyAckedTask, recurring, otherTask, crossAcctTask],
      );

      h.transport.storage[kWidgetAckedOpIdKey] = 1;
      h.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't0',
          value: true,
          accountId: 'acct_a',
        ),
        const WidgetPendingOp(
          opId: 2,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
          accountId: 'acct_a',
        ),
        const WidgetPendingOp(
          opId: 3,
          type: WidgetPendingOpType.toggleImportant,
          taskId: 't3',
          value: true,
          accountId: 'acct_other',
        ),
        const WidgetPendingOp(
          opId: 4,
          type: WidgetPendingOpType.toggleImportant,
          taskId: 't2',
          value: true,
          accountId: 'acct_a',
        ),
      ]);

      final result = await WidgetEventProcessor(
        widgetService: h.container.read(homeWidgetServiceProvider),
        read: h.container.read,
        strings: HomeWidgetStrings.fromLocale(const Locale('en')),
        isBackground: false,
        runCloudSync: () async {},
        scheduleBackgroundedAppCloudSync: () {},
      ).process();

      expect(result.didMutate, isTrue);
      final tasks = h.container.read(todoProvider).tasks;
      expect(tasks.firstWhere((t) => t.id == 't0').isCompleted, isFalse);
      expect(tasks.where((t) => t.title == 'Daily standup'), hasLength(2));
      expect(tasks.firstWhere((t) => t.id == 't1').isCompleted, isTrue);
      expect(tasks.firstWhere((t) => t.id == 't2').isImportant, isTrue);
      expect(tasks.firstWhere((t) => t.id == 't3').isImportant, isFalse);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 4);
      expect(h.transport.commits.single.ackedOpId, 4);
    });

    test('clears widget data when signed out', () async {
      final h = await createWidgetTestHarness();
      h.transport.storage[kWidgetSnapshotKey] = '{"version":1}';
      h.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
        ),
      ]);

      await WidgetEventProcessor(
        widgetService: h.container.read(homeWidgetServiceProvider),
        read: h.container.read,
        strings: HomeWidgetStrings.fromLocale(const Locale('en')),
        isBackground: false,
        runCloudSync: () async {},
        scheduleBackgroundedAppCloudSync: () {},
      ).process();

      expect(h.transport.storage[kWidgetSnapshotKey], isNull);
      expect(h.transport.storage[kWidgetPendingOpsKey], isNull);
      expect(h.transport.updateCalls, 1);
      expect(h.transport.commits, isEmpty);
    });

    test(
      'refreshRequested always clears refreshing even if cloud sync throws',
      () async {
        final h = await createWidgetTestHarness(
          accounts: [localAccount],
          activeAccountId: 'acct_a',
        );
        h.transport.storage[kWidgetRefreshRequestedKey] = true;
        h.transport.storage[kWidgetIsRefreshingKey] = true;

        final result = await WidgetEventProcessor(
          widgetService: h.container.read(homeWidgetServiceProvider),
          read: h.container.read,
          strings: HomeWidgetStrings.fromLocale(const Locale('en')),
          isBackground: true,
          runCloudSync: () async {
            throw StateError('network down');
          },
          scheduleBackgroundedAppCloudSync: () {},
        ).process();

        expect(result.didSync, isFalse);
        expect(h.transport.storage[kWidgetRefreshRequestedKey], isFalse);
        expect(h.transport.storage[kWidgetIsRefreshingKey], isFalse);
        expect(h.transport.commits.last.isRefreshing, isFalse);
      },
    );

    test('background mutation runs cloud sync while backgrounded foreground app schedules debounced sync', () async {
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Sync me',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );

      final hBg = await createWidgetTestHarness(
        accounts: [msAccount],
        activeAccountId: 'acct_ms',
        initialTasks: [task],
      );
      hBg.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
          accountId: 'acct_ms',
        ),
      ]);
      var bgCloudSyncCalls = 0;
      await WidgetEventProcessor(
        widgetService: hBg.container.read(homeWidgetServiceProvider),
        read: hBg.container.read,
        strings: HomeWidgetStrings.fromLocale(const Locale('en')),
        isBackground: true,
        runCloudSync: () async {
          bgCloudSyncCalls += 1;
        },
        scheduleBackgroundedAppCloudSync: () {},
      ).process();
      expect(bgCloudSyncCalls, 1);

      final hFgPaused = await createWidgetTestHarness(
        accounts: [msAccount],
        activeAccountId: 'acct_ms',
        initialTasks: [task],
      );
      hFgPaused.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
          accountId: 'acct_ms',
        ),
      ]);
      var scheduledDebouncedCalls = 0;
      var fgDirectSyncCalls = 0;
      await WidgetEventProcessor(
        widgetService: hFgPaused.container.read(homeWidgetServiceProvider),
        read: hFgPaused.container.read,
        strings: HomeWidgetStrings.fromLocale(const Locale('en')),
        isBackground: false,
        isAppForeground: false,
        runCloudSync: () async {
          fgDirectSyncCalls += 1;
        },
        scheduleBackgroundedAppCloudSync: () {
          scheduledDebouncedCalls += 1;
        },
      ).process();
      expect(fgDirectSyncCalls, 0);
      expect(scheduledDebouncedCalls, 1);
    });
  });
}
