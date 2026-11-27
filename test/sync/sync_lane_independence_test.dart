import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/sync/sync_dispatcher.dart';
import 'package:yata/sync/sync_provider.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TaskItem newTask(String id) => TaskItem(
    id: id,
    listId: 'tasks',
    title: id,
    createdAt: DateTime.utc(2026, 11, 25, 8),
  );

  test('scheduled push runs while a pull is blocked', () async {
    final pullStarted = Completer<void>();
    final releasePull = Completer<void>();
    final fakeApi = BlockingFoldersApi(pullStarted, releasePull);

    final h = await createSyncTestHarness(
      accountId: 'acct_lane_push',
      api: fakeApi,
      defaultTasksFolderRemoteId: 'rf-default',
      taskDeltaLinks: const {'rf-default': 'dl-tasks'},
    );

    final notifier = h.container.read(syncProvider.notifier);
    final pullFuture = notifier.syncNow(forceFullSync: true);
    await pullStarted.future;

    h.container
        .read(todoProvider.notifier)
        .commit(
          h.container.read(todoProvider).copyWith(tasks: [newTask('t_1')]),
        );
    notifier.schedulePush(delay: Duration.zero);
    await pumpEventQueue();

    expect(h.api.callLog, contains('POST taskfolders/rf-default/tasks t_1'));
    expect(releasePull.isCompleted, isFalse);

    releasePull.complete();
    await pullFuture;
  });

  test(
    'syncNow pushes concurrently instead of queueing behind a pull',
    () async {
      final pullStarted = Completer<void>();
      final releasePull = Completer<void>();
      final fakeApi = BlockingFoldersApi(pullStarted, releasePull);

      final h = await createSyncTestHarness(
        accountId: 'acct_lane_concurrent_push',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        taskDeltaLinks: const {'rf-default': 'dl-tasks'},
      );

      final notifier = h.container.read(syncProvider.notifier);
      final pullFuture = notifier.syncNow(forceFullSync: true);
      await pullStarted.future;

      h.container
          .read(todoProvider.notifier)
          .commit(
            h.container.read(todoProvider).copyWith(tasks: [newTask('t_2')]),
          );

      final secondSync = notifier.syncNow(reason: SyncReason.localMutation);
      await pumpEventQueue();

      expect(h.api.callLog, contains('POST taskfolders/rf-default/tasks t_2'));
      expect(releasePull.isCompleted, isFalse);

      releasePull.complete();
      await pullFuture;
      await secondSync;
    },
  );
}
