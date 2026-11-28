import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yata/data/account_provider.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/homewidget/home_widget_sync.dart';

import '../helpers/home_widget_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeWidgetSyncController & homeWidgetAutoSyncProvider', () {
    test('autoSync clears when signed out without loading tasks, syncs on task mutation and account switch, and clears on sign-out', () async {
      final h = await createWidgetTestHarness();
      h.container.listen<void>(homeWidgetAutoSyncProvider, (_, _) {});
      await pumpEventQueue();

      expect(h.container.read(todoProvider.exists), isFalse);
      expect(h.transport.updateCalls, 1);
      expect(h.transport.storage[kWidgetSnapshotKey], isNull);

      final accounts = h.container.read(accountProvider.notifier);
      final alice = await accounts.signInLocal(
        'Alice',
        fallbackName: 'Alice',
        fallbackEmail: 'alice@example.com',
      );
      await pumpEventQueue();
      h.container.read(tasksViewPresenterProvider).addTask(title: 'Alice task');
      await pumpEventQueue();

      final aliceSnapshot = jsonDecode(
        h.transport.storage[kWidgetSnapshotKey]! as String,
      ) as Map<String, dynamic>;
      expect(aliceSnapshot['accountName'], 'Alice');
      expect((aliceSnapshot['tasks'] as List).map((t) => t['title']), [
        'Alice task',
      ]);

      final bob = await accounts.signInLocal(
        'Bob',
        fallbackName: 'Bob',
        fallbackEmail: 'bob@example.com',
      );
      await pumpEventQueue();

      final bobSnapshot = jsonDecode(
        h.transport.storage[kWidgetSnapshotKey]! as String,
      ) as Map<String, dynamic>;
      expect(bobSnapshot['accountName'], 'Bob');
      expect(bobSnapshot['tasks'], isEmpty);

      await accounts.switchAccount(alice.id);
      await pumpEventQueue();
      final backToAliceSnapshot = jsonDecode(
        h.transport.storage[kWidgetSnapshotKey]! as String,
      ) as Map<String, dynamic>;
      expect(backToAliceSnapshot['accountName'], 'Alice');
      expect((backToAliceSnapshot['tasks'] as List).map((t) => t['title']), [
        'Alice task',
      ]);

      await accounts.signOut(alice.id);
      await accounts.signOut(bob.id);
      await pumpEventQueue();

      expect(h.transport.storage[kWidgetSnapshotKey], isNull);
    });

    test('bootstrap drains pending ops, pushes snapshot, and consumes initial URI once', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
      );
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Buy coffee',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createWidgetTestHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [task],
      );
      h.transport
        ..setPendingOps([
          const WidgetPendingOp(
            opId: 3,
            type: WidgetPendingOpType.toggleComplete,
            taskId: 't1',
            value: true,
            accountId: 'acct_a',
          ),
        ])
        ..initialLaunchUri = Uri.parse('yata://widget/open_list?listId=tasks');

      final controller = h.container.read(homeWidgetSyncProvider);
      final action = await controller.bootstrap();

      expect(action?.type, HomeWidgetActionType.openList);
      expect(action?.listId, 'tasks');
      expect(h.container.read(todoProvider).tasks.single.isCompleted, isTrue);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 3);
      expect(h.transport.commits, isNotEmpty);

      final secondAction = await controller.bootstrap();
      expect(secondAction, isNull);
    });

    test('widgetClicked drains pending ops before emitting action, and widgetSyncRequests runs sync', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
      );
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Review PR',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createWidgetTestHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [task],
      );
      final controller = h.container.read(homeWidgetSyncProvider);

      h.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleImportant,
          taskId: 't1',
          value: true,
          accountId: 'acct_a',
        ),
      ]);
      h.transport.syncRequestsController.add('toggle');
      await pumpEventQueue();

      expect(h.container.read(todoProvider).tasks.single.isImportant, isTrue);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 1);

      h.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 2,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
          accountId: 'acct_a',
        ),
      ]);
      final emittedFuture = controller.actions.first;
      h.transport.clickedController.add(
        Uri.parse('yata://widget/open_task?taskId=t1'),
      );
      final emitted = await emittedFuture;

      expect(emitted.type, HomeWidgetActionType.openTask);
      expect(emitted.taskId, 't1');
      expect(h.container.read(todoProvider).tasks.single.isCompleted, isTrue);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 2);
    });

    test('syncFromWidget reloads prefs and invalidates todoProvider when background mutated', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
      );
      final initialTask = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Before bg update',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createWidgetTestHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [initialTask],
        extraPrefs: {kWidgetLastMutationMsKey: 100},
      );
      final controller = h.container.read(homeWidgetSyncProvider);
      expect(
        h.container.read(todoProvider).tasks.single.title,
        'Before bg update',
      );

      // Simulate another isolate persisting a modified task row and bumping timestamp.
      final bgRepo = TodoRepository.forAccount(
        h.prefs,
        accountId: 'acct_a',
        database: h.db,
      );
      await bgRepo.saveTasks([
        initialTask.copyWith(title: 'Updated in background'),
      ]);
      await bgRepo.flushPendingWrites();
      await h.prefs.setInt(kWidgetLastMutationMsKey, 200);

      await controller.syncFromWidget(reason: 'resume');

      expect(
        h.container.read(todoProvider).tasks.single.title,
        'Updated in background',
      );
      final snapshot = jsonDecode(
        h.transport.storage[kWidgetSnapshotKey]! as String,
      ) as Map<String, dynamic>;
      expect(
        (snapshot['tasks'] as List).single['title'],
        'Updated in background',
      );
    });

    test('swallows transport errors in bootstrap/syncFromWidget, still emits click actions, and keeps sync chain healthy', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
      );
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Survive widget errors',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createWidgetTestHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [task],
      );
      final controller = h.container.read(homeWidgetSyncProvider);

      h.transport
        ..getDataError = StateError('read failed')
        ..initialLaunchUriError = StateError('uri failed');

      final bootstrapAction = await controller.bootstrap();
      expect(bootstrapAction, isNull);

      await controller.syncFromWidget(reason: 'resume');

      final emittedFuture = controller.actions.first;
      h.transport.clickedController.add(
        Uri.parse('yata://widget/open_list?listId=tasks'),
      );
      final emitted = await emittedFuture;
      expect(emitted.type, HomeWidgetActionType.openList);
      expect(emitted.listId, 'tasks');

      h.transport
        ..getDataError = null
        ..setPendingOps([
          const WidgetPendingOp(
            opId: 1,
            type: WidgetPendingOpType.toggleComplete,
            taskId: 't1',
            value: true,
            accountId: 'acct_a',
          ),
        ]);
      await controller.syncFromWidget(reason: 'resume');

      expect(h.container.read(todoProvider).tasks.single.isCompleted, isTrue);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 1);
    });
  });
}
