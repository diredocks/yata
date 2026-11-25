import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
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

    test('onAppResumed forces full task sync bypassing saved taskDeltaLinks even when coalesced with normal debounced sync', () async {
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
        accountId: 'acct_resume_full',
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

      h.container.read(syncProvider.notifier).onAppPaused();
      h.container.read(syncProvider.notifier).onAppResumed();
      // Sticky coalescing: a shorter normal debounced sync must keep forceFullSync=true.
      h.container
          .read(syncProvider.notifier)
          .scheduleDebouncedSync(
            delay: const Duration(milliseconds: 50),
            forceFullSync: false,
            reason: 'local_mutation',
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

      // accountChanged=true bypasses startupSyncEnabledProvider and runs full sync.
      notifier.syncOnSessionStart(accountChanged: true);
      await pumpEventQueue();
      expect(h.api.callLog, contains('GET taskfolders(null)'));
      expect(h.api.callLog, contains('GET tasks(rf-default,null)'));

      h.api.callLog.clear();
      await h.settings.saveTaskDeltaLinks({'rf-default': 'dl-tasks-2'});

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
            .commit(
              h.container
                  .read(todoProvider)
                  .copyWith(
                    tasks: [
                      h.container
                          .read(todoProvider)
                          .tasks
                          .single
                          .copyWith(title: 'Edited Right Before Pause'),
                    ],
                  ),
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
  });
}
