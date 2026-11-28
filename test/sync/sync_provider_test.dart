import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart';
import 'package:yata/core/result/app_result.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_dispatcher.dart';
import 'package:yata/sync/sync_provider.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncNotifier scheduling & lifecycle', () {
    test('concurrent syncNow calls share the in-flight sync future', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final fakeApi = BlockingFoldersApi(started, release);

      final h = await createSyncTestHarness(
        accountId: 'acct_shared_sync',
        api: fakeApi,
      );

      final first = h.container.read(syncProvider.notifier).syncNow();
      await started.future;
      expect(h.container.read(syncProvider).isSyncing, isTrue);

      var secondCompleted = false;
      unawaited(
        h.container.read(syncProvider.notifier).syncNow().whenComplete(() {
          secondCompleted = true;
        }),
      );
      await pumpEventQueue();

      expect(secondCompleted, isFalse);
      expect(h.container.read(syncProvider).isSyncing, isTrue);

      release.complete();
      await first;
      await pumpEventQueue();

      expect(secondCompleted, isTrue);
      expect(h.container.read(syncProvider).status, SyncStatus.success);
      expect(fakeApi.folderFetchCount, greaterThanOrEqualTo(2));
    });

    test(
      'onAppResumed uses incremental delta sync with saved deltaLinks',
      () async {
        final fakeApi = FakeSubstrateApi()
          ..onFetchGroupsDelta = ((dl) => DeltaPageResult(
            items: const [],
            deltaLink: dl ?? 'dl-groups-new',
          ))
          ..onFetchFoldersDelta = ((dl) => DeltaPageResult(
            items: const [],
            deltaLink: dl ?? 'dl-folders-new',
          ))
          ..onFetchTasksDelta = ((folderId, dl) => DeltaPageResult(
            items: const [],
            deltaLink: dl ?? 'dl-tasks-new',
          ));

        final h = await createSyncTestHarness(
          accountId: 'acct_resume_delta',
          lastSyncedAt: DateTime(2026, 11, 22, 12, 0),
          api: fakeApi,
          defaultTasksFolderRemoteId: 'rf-default',
          groupsDeltaLink: 'dl-groups-1',
          foldersDeltaLink: 'dl-folders-1',
          taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
        );

        h.container.read(syncProvider);

        h.container.read(syncProvider.notifier).onAppPaused();
        h.container.read(syncProvider.notifier).onAppResumed();

        await Future<void>.delayed(const Duration(milliseconds: 600));

        expect(h.api.callLog, contains('GET foldergroups(dl-groups-1)'));
        expect(h.api.callLog, contains('GET taskfolders(dl-folders-1)'));
        expect(h.api.callLog, contains('GET tasks(rf-default,dl-tasks-1)'));
        expect(h.api.callLog, isNot(contains('GET foldergroups(null)')));
        expect(h.api.callLog, isNot(contains('GET taskfolders(null)')));
        expect(h.api.callLog, isNot(contains('GET tasks(rf-default,null)')));
      },
    );

    test('debounced full sync keeps forceFullSync=true when coalesced with shorter delta sync', () async {
      final tOld = DateTime.utc(2026, 11, 22, 8);
      final tMid = DateTime.utc(2026, 11, 22, 10);
      final tNew = DateTime.utc(2026, 11, 22, 14);

      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-folders-2')
          : const DeltaPageResult(
              items: [
                RemoteTodoFolder(
                  id: 'rf-default',
                  name: 'Tasks',
                  isDefaultFolder: true,
                ),
              ],
              deltaLink: 'dl-folders-2',
            );
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (dl != null) {
          return DeltaPageResult(items: const [], deltaLink: dl);
        }
        return DeltaPageResult(
          items: [
            RemoteTodoTask(
              id: 'rt-1',
              changeKey: 'ck-1-new',
              parentFolderId: 'rf-default',
              subject: 'Task One',
              orderDateTime: tOld,
            ),
            RemoteTodoTask(
              id: 'rt-2',
              changeKey: 'ck-2-new',
              parentFolderId: 'rf-default',
              subject: 'Task Two',
              orderDateTime: tNew,
            ),
          ],
          deltaLink: 'dl-tasks-2',
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_sticky_full',
        lastSyncedAt: DateTime(2026, 11, 22, 12, 0),
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Task One',
            createdAt: tOld,
            orderDateTime: tMid,
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
          TaskItem(
            id: 't_2',
            listId: 'tasks',
            title: 'Task Two',
            createdAt: tOld,
            orderDateTime: tOld,
            remoteId: 'rt-2',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-2',
          ),
        ],
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
      );

      h.container.read(syncProvider);

      h.container
          .read(syncProvider.notifier)
          .scheduleDebouncedSync(
            delay: const Duration(milliseconds: 200),
            forceFullSync: true,
            reason: SyncReason.manual,
          );
      // Sticky coalescing: a shorter normal debounced sync must keep forceFullSync=true.
      h.container
          .read(syncProvider.notifier)
          .scheduleDebouncedSync(
            delay: const Duration(milliseconds: 50),
            forceFullSync: false,
            reason: SyncReason.localMutation,
          );

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(h.api.callLog, contains('GET tasks(rf-default,null)'));
      final todoState = h.container.read(todoProvider);
      final tasksList = todoState.lists.firstWhere((l) => l.id == 'tasks');
      expect(todoState.tasksForList(tasksList).map((t) => t.id).toList(), [
        't_2',
        't_1',
      ]);
    });

    test('refresh() forces full sync and syncOnSessionStart() respects startupSyncEnabledProvider', () async {
      final h = await createSyncTestHarness(
        accountId: 'acct_refresh_api',
        defaultTasksFolderRemoteId: 'rf-default',
        foldersDeltaLink: 'dl-folders-saved',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-saved'},
        startupSyncEnabled: false,
      );

      final notifier = h.container.read(syncProvider.notifier);

      // With startupSyncEnabled=false, non-accountChanged start is a no-op.
      notifier.syncOnSessionStart();
      await pumpEventQueue();
      expect(h.api.callLog, isEmpty);

      // accountChanged=true bypasses startupSyncEnabledProvider and runs a single full sync.
      notifier.syncOnSessionStart(accountChanged: true);
      await pumpEventQueue();
      expect(h.api.callLog, contains('GET taskfolders(null)'));
      expect(
        h.api.callLog.where((c) => c.startsWith('GET foldergroups')).length,
        1,
      );
      expect(h.api.callLog, contains('GET tasks(rf-default,null)'));

      h.api.callLog.clear();
      await h.repository.saveSyncMetaBatch(
        taskDeltaLinks: const {'rf-default': 'dl-tasks-2'},
      );

      // Manual refresh() bypasses saved deltaLinks.
      await notifier.refresh();
      expect(h.api.callLog, contains('GET taskfolders(null)'));
      expect(h.api.callLog, contains('GET tasks(rf-default,null)'));
    });

    test(
      'onAppPaused immediately flushes an active debounced local_mutation sync',
      () async {
        final patchCompleted = Completer<void>();
        final fakeApi = FakeSubstrateApi()
          ..onPatchTask = (taskRemoteId, patch, changeKey) async {
            if (!patchCompleted.isCompleted) patchCompleted.complete();
            return RemoteTodoTask(
              id: taskRemoteId,
              changeKey: 'ck-after-pause',
              parentFolderId: 'rf-default',
              subject: patch['Subject'] as String? ?? 'Task',
            );
          };

        final h = await createSyncTestHarness(
          accountId: 'acct_pause_flush',
          api: fakeApi,
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'tasks',
              title: 'Before Pause',
              createdAt: DateTime.utc(2026, 11, 22, 8),
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-1',
            ),
          ],
          foldersDeltaLink: 'dl-folders-1',
          taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
        );

        h.container.read(syncProvider);
        h.container
            .read(todoProvider.notifier)
            .mutateTask(
              't_1',
              (t) => t.copyWith(title: 'Edited Right Before Pause'),
            );
        await pumpEventQueue();
        expect(fakeApi.callLog, isEmpty);

        h.container.read(syncProvider.notifier).onAppPaused();
        await patchCompleted.future.timeout(const Duration(seconds: 2));
        await pumpEventQueue();

        expect(
          fakeApi.callLog.any((c) => c.startsWith('PATCH tasks/rt-1')),
          isTrue,
        );
      },
    );

    test(
      'a local edit during an in-flight sync queues a push-only pass',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final fakeApi = BlockingFoldersApi(started, release)
          ..onPatchTask = (taskRemoteId, patch, changeKey) async =>
              RemoteTodoTask(
                id: taskRemoteId,
                subject: patch['Subject'] as String? ?? 'Task',
                parentFolderId: 'rf-default',
                changeKey: 'ck-after',
              );

        final h = await createSyncTestHarness(
          accountId: 'acct_queued_push_only',
          api: fakeApi,
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'tasks',
              title: 'Before',
              createdAt: DateTime.utc(2026, 11, 22, 8),
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-1',
            ),
          ],
          foldersDeltaLink: 'dl-folders-1',
          taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
        );

        final notifier = h.container.read(syncProvider.notifier);
        final inFlight = notifier.syncNow(reason: SyncReason.manual);
        await started.future;

        // Edit while the delta sync is blocked on its folder pull.
        h.container
            .read(todoProvider.notifier)
            .mutateTask('t_1', (t) => t.copyWith(title: 'Edited During Sync'));
        // Let the coalescing window elapse so the edit is queued.
        await Future<void>.delayed(const Duration(milliseconds: 400));

        release.complete();
        await inFlight;
        await pumpEventQueue();

        // The queued pass only pushed; it did not repeat the global pulls.
        expect(
          fakeApi.callLog.where((c) => c == 'GET settings').length,
          1,
          reason: fakeApi.callLog.join(', '),
        );
        expect(
          fakeApi.callLog
              .where((c) => c.startsWith('GET foldergroups('))
              .length,
          1,
          reason: fakeApi.callLog.join(', '),
        );
        expect(
          fakeApi.callLog.where((c) => c.startsWith('PATCH tasks/rt-1')).length,
          1,
          reason: fakeApi.callLog.join(', '),
        );
      },
    );

    test(
      'continuous local edits still flush within the coalescing cap',
      () async {
        final fakeApi = FakeSubstrateApi()
          ..onPatchTask = (taskRemoteId, patch, changeKey) async =>
              RemoteTodoTask(
                id: taskRemoteId,
                subject: patch['Subject'] as String? ?? 'Task',
                parentFolderId: 'rf-default',
                changeKey: 'ck-after',
              );

        final h = await createSyncTestHarness(
          accountId: 'acct_coalesce_cap',
          api: fakeApi,
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'tasks',
              title: 'Before',
              createdAt: DateTime.utc(2026, 11, 22, 8),
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-1',
            ),
          ],
          foldersDeltaLink: 'dl-folders-1',
          taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
        );

        h.container.read(syncProvider.notifier);
        fakeApi.callLog.clear();

        final stopwatch = Stopwatch()..start();
        Duration? firstPushAt;
        while (stopwatch.elapsed < const Duration(milliseconds: 1600)) {
          h.container
              .read(todoProvider.notifier)
              .mutateTask(
                't_1',
                (t) =>
                    t.copyWith(title: 'Edit ${stopwatch.elapsedMilliseconds}'),
              );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          firstPushAt ??=
              fakeApi.callLog.any((c) => c.startsWith('PATCH tasks/rt-1'))
              ? stopwatch.elapsed
              : null;
        }

        // Only the 1 s coalescing cap can flush this, not the 300 ms window.
        expect(firstPushAt, isNotNull);
        expect(firstPushAt!.inMilliseconds, lessThan(1300));
      },
    );

    test('syncOnSessionStart runs incremental delta sync first and then full sync when deltaLinks exist', () async {
      final fakeApi = FakeSubstrateApi()
        ..onFetchGroupsDelta = ((dl) =>
            DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-groups-new'))
        ..onFetchFoldersDelta = ((dl) =>
            DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-folders-new'))
        ..onFetchTasksDelta = ((folderId, dl) =>
            DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-tasks-new'));

      final h = await createSyncTestHarness(
        accountId: 'acct_startup_delta',
        lastSyncedAt: DateTime(2026, 11, 22, 12, 0),
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        groupsDeltaLink: 'dl-groups-saved',
        foldersDeltaLink: 'dl-folders-saved',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-saved'},
        startupSyncEnabled: true,
      );

      h.container.read(syncProvider.notifier).syncOnSessionStart();
      await pumpEventQueue();

      final groupsDeltaIdx = h.api.callLog.indexOf(
        'GET foldergroups(dl-groups-saved)',
      );
      final groupsFullIdx = h.api.callLog.indexOf('GET foldergroups(null)');
      expect(groupsDeltaIdx, greaterThanOrEqualTo(0));
      expect(groupsFullIdx, greaterThan(groupsDeltaIdx));

      expect(h.api.callLog, contains('GET taskfolders(dl-folders-saved)'));
      expect(h.api.callLog, contains('GET tasks(rf-default,dl-tasks-saved)'));
      expect(h.api.callLog, contains('GET taskfolders(null)'));
      expect(h.api.callLog, contains('GET tasks(rf-default,null)'));
    });

    test('delete push runs immediately without waiting for blocked full pull, and onAppPaused cancels in-flight pull', () async {
      final pullStarted = Completer<void>();
      final pullRelease = Completer<void>();
      final deleteCompleted = Completer<void>();
      final fakeApi = BlockingFoldersApi(pullStarted, pullRelease)
        ..onDeleteTask = (taskRemoteId) async {
          if (!deleteCompleted.isCompleted) deleteCompleted.complete();
        };

      final h = await createSyncTestHarness(
        accountId: 'acct_parallel_delete',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Delete Me Quickly',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
        ],
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
      );

      final notifier = h.container.read(syncProvider.notifier);
      final fullSyncFuture = notifier.refresh(reason: SyncReason.startup);
      await pullStarted.future;

      // Delete task while full pull is still blocked, then exit immediately.
      h.container.read(todoProvider.notifier).deleteTasks(const {'t_1'});
      notifier.onAppPaused();

      // DELETE must complete immediately without waiting for pullRelease.
      await deleteCompleted.future.timeout(const Duration(seconds: 2));
      expect(fakeApi.callLog, contains('DELETE tasks/rt-1'));
      expect(pullRelease.isCompleted, isFalse);

      // Release blocked HTTP call; cancelled full pull must not fetch tasks.
      pullRelease.complete();
      await fullSyncFuture;
      await pumpEventQueue();

      expect(fakeApi.callLog.any((c) => c.startsWith('GET tasks(')), isFalse);
      expect(h.container.read(todoProvider).tasks, isEmpty);
    });

    test('tombstone barrier prevents stale in-flight pull from resurrecting concurrently deleted task', () async {
      final folder1Pulled = Completer<void>();
      final folder2Release = Completer<void>();
      final deleteCompleted = Completer<void>();
      final fakeApi = _BlockingSecondFolderApi(folder1Pulled, folder2Release)
        ..onFetchFoldersDelta = ((dl) => const DeltaPageResult(
          items: [
            RemoteTodoFolder(
              id: 'rf-default',
              name: 'Tasks',
              isDefaultFolder: true,
            ),
            RemoteTodoFolder(id: 'rf-second', name: 'Second'),
          ],
          deltaLink: 'dl-folders-new',
        ))
        ..onFetchTasksDelta = ((folderId, dl) => const DeltaPageResult(
          items: [
            RemoteTodoTask(
              id: 'rt-1',
              changeKey: 'ck-1',
              parentFolderId: 'rf-default',
              subject: 'Task One',
            ),
            RemoteTodoTask(
              id: 'rt-2',
              changeKey: 'ck-2',
              parentFolderId: 'rf-default',
              subject: 'Task Two',
            ),
          ],
          deltaLink: 'dl-tasks-default',
        ))
        ..onDeleteTask = ((taskRemoteId) async {
          if (!deleteCompleted.isCompleted) deleteCompleted.complete();
        });

      final h = await createSyncTestHarness(
        accountId: 'acct_tombstone_barrier',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Task One',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
          TaskItem(
            id: 't_2',
            listId: 'tasks',
            title: 'Task Two',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-2',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-2',
          ),
        ],
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
      );

      final notifier = h.container.read(syncProvider.notifier);
      final fullSyncFuture = notifier.refresh(reason: SyncReason.manual);

      // Wait until rf-default (containing rt-1 & rt-2) is fetched, while rf-second is still blocked.
      await folder1Pulled.future;

      // Delete t_1 locally and wait for concurrent push to DELETE and ackOp it.
      h.container.read(todoProvider.notifier).deleteTasks(const {'t_1'});

      await deleteCompleted.future.timeout(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(
        h.container.read(todoProvider.notifier).repository.outbox.isEmpty,
        isTrue,
      );

      // Now let full pull finish reconciling the stale snapshot containing rt-1.
      folder2Release.complete();
      await fullSyncFuture;
      await pumpEventQueue();

      final taskIds = h.container
          .read(todoProvider)
          .tasks
          .map((t) => t.id)
          .toList();
      expect(taskIds, ['t_2']);
    });

    test('delta pull does not resurrect task deleted and acked concurrently while pull was in flight', () async {
      final pullStarted = Completer<void>();
      final pullRelease = Completer<void>();
      final deleteCompleted = Completer<void>();
      final fakeApi = BlockingFoldersApi(pullStarted, pullRelease)
        ..onFetchTasksDelta = ((folderId, dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-tasks-2'))
        ..onDeleteTask = ((taskRemoteId) async {
          if (!deleteCompleted.isCompleted) deleteCompleted.complete();
        });

      final h = await createSyncTestHarness(
        accountId: 'acct_delta_concurrent_delete',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Delete During Delta',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
          TaskItem(
            id: 't_2',
            listId: 'tasks',
            title: 'Keep Me',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-2',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-2',
          ),
        ],
        groupsDeltaLink: 'dl-groups-1',
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
      );

      final notifier = h.container.read(syncProvider.notifier);
      // Start an incremental delta pull; it snapshots workingTasks = [t_1, t_2].
      final deltaFuture = notifier.syncNow(
        forceFullSync: false,
        reason: SyncReason.manual,
      );
      await pullStarted.future;

      // Delete t_1 while delta pull is in flight and wait for DELETE + ackOp.
      h.container.read(todoProvider.notifier).deleteTasks(const {'t_1'});

      await deleteCompleted.future.timeout(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(
        h.container.read(todoProvider.notifier).repository.outbox.isEmpty,
        isTrue,
      );

      // Finish the delta pull; stale workingTasks must not resurrect t_1.
      pullRelease.complete();
      await deltaFuture;
      await pumpEventQueue();

      expect(h.container.read(todoProvider).tasks.map((t) => t.id).toList(), [
        't_2',
      ]);
    });

    test('cancelling an in-flight pull via onAppPaused does not advance saved deltaLinks', () async {
      final pullStarted = Completer<void>();
      final pullRelease = Completer<void>();
      final fakeApi = BlockingFoldersApi(pullStarted, pullRelease)
        ..onFetchGroupsDelta = ((dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-groups-advanced'))
        ..onFetchFoldersDelta = ((dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-folders-advanced'));

      final h = await createSyncTestHarness(
        accountId: 'acct_cancel_no_advance_dl',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        groupsDeltaLink: 'dl-groups-orig',
        foldersDeltaLink: 'dl-folders-orig',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-orig'},
      );

      final notifier = h.container.read(syncProvider.notifier);
      final deltaFuture = notifier.syncNow(
        forceFullSync: false,
        reason: SyncReason.manual,
      );
      await pullStarted.future;

      notifier.onAppPaused();
      pullRelease.complete();
      await deltaFuture;
      await pumpEventQueue();

      expect(h.repository.loadGroupsDeltaLink(), 'dl-groups-orig');
      expect(h.repository.loadFoldersDeltaLink(), 'dl-folders-orig');
      expect(h.repository.loadTaskDeltaLinks(), const {
        'rf-default': 'dl-tasks-orig',
      });
    });
  });
}

class _BlockingSecondFolderApi extends FakeSubstrateApi {
  _BlockingSecondFolderApi(this.folder1Pulled, this.folder2Release);

  final Completer<void> folder1Pulled;
  final Completer<void> folder2Release;

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta({
    required String folderRemoteId,
    String? deltaLink,
  }) async {
    if (folderRemoteId == 'rf-second') {
      await folder2Release.future;
      return const Success(
        DeltaPageResult(items: [], deltaLink: 'dl-tasks-second'),
      );
    }
    final res = await super.fetchTasksDelta(
      folderRemoteId: folderRemoteId,
      deltaLink: deltaLink,
    );
    if (folderRemoteId == 'rf-default' && !folder1Pulled.isCompleted) {
      folder1Pulled.complete();
    }
    return res;
  }
}
