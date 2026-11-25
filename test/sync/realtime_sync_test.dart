import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/todo_wire_codecs.dart';

import '../helpers/microsoft_sync_fakes.dart';

class _ReconnectFakeSubstrateApi extends FakeSubstrateApi {
  final Completer<void> secondConnected = Completer<void>();
  final StreamController<RealtimeEvent> secondStream =
      StreamController<RealtimeEvent>.broadcast();
  int connectCount = 0;

  @override
  Stream<RealtimeEvent> connectRealtime(SubstrateRequestContext ctx) {
    callLog.add('GET realtime');
    connectCount += 1;
    if (connectCount == 1) {
      return Stream<RealtimeEvent>.fromIterable(const [
        RealtimeEvent(type: 'KeepAlive'),
      ]);
    }
    if (!secondConnected.isCompleted) secondConnected.complete();
    return secondStream.stream;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Realtime sync', () {
    test(
      'ignores KeepAlive and own RequestId, and falls back to sync on missing-payload remote event',
      () async {
        var taskFetches = 0;
        final fakeApi = FakeSubstrateApi()
          ..ownRequestIds.add('my-req-id')
          ..onFetchTasksDelta = (folderId, dl) {
            taskFetches += 1;
            return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
          };

        final h = await createSyncTestHarness(
          api: fakeApi,
          realtimeSyncEnabled: true,
        );

        h.container.read(syncProvider);
        await pumpEventQueue();
        expect(h.api.callLog, contains('GET realtime'));

        h.api.realtimeController.add(const RealtimeEvent(type: 'KeepAlive'));
        h.api.realtimeController.add(
          const RealtimeEvent(
            id: 't1',
            type: 'Task',
            operation: 'Updated',
            requestId: 'my-req-id',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(taskFetches, 0);

        h.api.realtimeController.add(
          const RealtimeEvent(
            id: 't1',
            type: 'Task',
            operation: 'Created',
            requestId: 'other-device-req',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(taskFetches, greaterThanOrEqualTo(1));
      },
    );

    test(
      'direct Task realtime payload updates OrderDateTime and CommittedOrder without fetching delta, preserves missing Subtasks, and respects dirty tasks',
      () async {
        final today = DateTime.now();
        final tOld = DateTime.utc(2026, 11, 22, 8);
        final tMid = DateTime.utc(2026, 11, 22, 10);
        final tNewest = DateTime.utc(2026, 11, 22, 14);

        var taskFetches = 0;
        final fakeApi = FakeSubstrateApi()
          ..onFetchTasksDelta = (folderId, dl) {
            taskFetches += 1;
            return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
          };

        final h = await createSyncTestHarness(
          accountId: 'acct_rt_payload',
          api: fakeApi,
          realtimeSyncEnabled: true,
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'tasks',
              title: 'Task 1',
              createdAt: tOld,
              orderDateTime: tMid,
              isInMyDay: true,
              myDayDate: DateTime(today.year, today.month, today.day),
              committedOrder: tMid,
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-1',
              steps: const [
                TaskStep(id: 's_1', title: 'Local Step', remoteId: 'rs-1'),
              ],
            ),
            TaskItem(
              id: 't_2',
              listId: 'tasks',
              title: 'Task 2',
              createdAt: tOld,
              orderDateTime: tOld,
              isInMyDay: true,
              myDayDate: DateTime(today.year, today.month, today.day),
              committedOrder: tOld,
              remoteId: 'rt-2',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-2',
            ),
            TaskItem(
              id: 't_3',
              listId: 'tasks',
              title: 'Dirty Title',
              createdAt: tOld,
              orderDateTime: tOld,
              remoteId: 'rt-3',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-3',
            ),
          ],
          dirtyTaskIds: const {'t_3'},
        );

        h.container.read(syncProvider);
        await pumpEventQueue();
        expect(h.api.callLog, contains('GET realtime'));

        final initialMutationVersion = h.container
            .read(todoProvider)
            .mutationVersion;

        h.api.realtimeController.add(
          RealtimeEvent(
            id: 'rt-2',
            type: 'Task',
            operation: 'Updated',
            requestId: 'other-device-req',
            payload: {
              'Id': 'rt-2',
              'ChangeKey': 'ck-2-new',
              'ParentFolderId': 'rf-default',
              'Subject': 'Task 2',
              'OrderDateTime': formatSubstrateUtcTimestamp(tNewest),
              'CommittedDay': formatDayString(today),
              'CommittedOrder': formatSubstrateUtcTimestamp(tNewest),
            },
          ),
        );

        h.api.realtimeController.add(
          RealtimeEvent(
            id: 'rt-1',
            type: 'Task',
            operation: 'Updated',
            requestId: 'other-device-req-2',
            payload: {
              'Id': 'rt-1',
              'ChangeKey': 'ck-1-new',
              'ParentFolderId': 'rf-default',
              'Subject': 'Task 1',
              'OrderDateTime': formatSubstrateUtcTimestamp(tMid),
              'CommittedDay': formatDayString(today),
              'CommittedOrder': formatSubstrateUtcTimestamp(tMid),
            },
          ),
        );

        h.api.realtimeController.add(
          RealtimeEvent(
            id: 'rt-3',
            type: 'Task',
            operation: 'Updated',
            requestId: 'other-device-req-3',
            payload: {
              'Id': 'rt-3',
              'ChangeKey': 'ck-3-new',
              'ParentFolderId': 'rf-default',
              'Subject': 'Remote Overwrite',
              'OrderDateTime': formatSubstrateUtcTimestamp(tNewest),
            },
          ),
        );

        await pumpEventQueue();

        final todoState = h.container.read(todoProvider);
        final tasksList = todoState.lists.firstWhere((l) => l.id == 'tasks');
        final myDayList = todoState.lists.firstWhere((l) => l.id == 'my_day');
        expect(
          todoState.tasksForList(tasksList).map((t) => t.id).toList(),
          ['t_2', 't_1', 't_3'],
        );
        expect(
          todoState.tasksForList(myDayList).map((t) => t.id).toList(),
          ['t_2', 't_1'],
        );

        final updatedT1 = todoState.tasks.firstWhere((t) => t.id == 't_1');
        expect(updatedT1.steps.single.title, 'Local Step');

        final updatedT3 = todoState.tasks.firstWhere((t) => t.id == 't_3');
        expect(updatedT3.title, 'Dirty Title');
        expect(updatedT3.changeKey, 'ck-3-new');

        expect(taskFetches, 0);
        expect(todoState.mutationVersion, initialMutationVersion);
        expect(h.repository.loadDirtyTaskIds(), ['t_3']);
      },
    );

    test(
      'Task/Deleted removes non-dirty task and mid-sync Task/Updated is deferred without marking dirty',
      () async {
        final tOld = DateTime.utc(2026, 11, 22, 8);
        final tMid = DateTime.utc(2026, 11, 22, 10);
        final tNew = DateTime.utc(2026, 11, 22, 16);

        final taskFetchStarted = Completer<void>();
        final allowTaskFetchFinish = Completer<void>();
        final fakeApi = BlockingTasksDeltaApi(
          taskFetchStarted,
          allowTaskFetchFinish,
        );

        final h = await createSyncTestHarness(
          accountId: 'acct_rt_defer',
          api: fakeApi,
          realtimeSyncEnabled: true,
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'tasks',
              title: 'Task 1',
              createdAt: tOld,
              orderDateTime: tMid,
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-1',
            ),
            TaskItem(
              id: 't_2',
              listId: 'tasks',
              title: 'Task 2',
              createdAt: tOld,
              orderDateTime: tOld,
              remoteId: 'rt-2',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-2',
            ),
            TaskItem(
              id: 't_del',
              listId: 'tasks',
              title: 'To Delete Remotely',
              createdAt: tOld,
              orderDateTime: tOld,
              remoteId: 'rt-del',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-del',
            ),
          ],
          taskDeltaLinks: const {'rf-default': 'dl-1'},
        );

        h.container.read(syncProvider);
        await pumpEventQueue();

        h.api.realtimeController.add(
          const RealtimeEvent(
            id: 'rt-del',
            type: 'Task',
            operation: 'Deleted',
            requestId: 'other-device-req',
          ),
        );
        await pumpEventQueue();
        expect(
          h.container.read(todoProvider).tasks.any((t) => t.id == 't_del'),
          isFalse,
        );

        final syncFuture = h.container.read(syncProvider.notifier).syncNow();
        await taskFetchStarted.future;

        h.api.realtimeController.add(
          RealtimeEvent(
            id: 'rt-2',
            type: 'Task',
            operation: 'Updated',
            requestId: 'other-device-req-2',
            payload: {
              'Id': 'rt-2',
              'ChangeKey': 'ck-2-new',
              'ParentFolderId': 'rf-default',
              'Subject': 'Task 2',
              'OrderDateTime': formatSubstrateUtcTimestamp(tNew),
            },
          ),
        );
        await pumpEventQueue();

        allowTaskFetchFinish.complete();
        await syncFuture;

        final state = h.container.read(todoProvider);
        final tasksList = state.lists.firstWhere((l) => l.id == 'tasks');
        expect(state.tasksForList(tasksList).map((t) => t.id).toList(), [
          't_2',
          't_1',
        ]);
        expect(
          state.tasks.firstWhere((t) => t.id == 't_2').orderDateTime,
          tNew,
        );
        expect(h.repository.loadDirtyTaskIds(), isEmpty);
      },
    );

    test(
      'FolderGroup, TaskFolder, and Setting events apply directly and forceFullSync refreshes groups and folders',
      () async {
        final tOld = DateTime.utc(2026, 11, 22, 8);
        final tMid = DateTime.utc(2026, 11, 22, 10);
        final tNew = DateTime.utc(2026, 11, 22, 14);

        var groupFetches = 0;
        var folderFetches = 0;
        final fakeApi = FakeSubstrateApi()
          ..onFetchGroupsDelta = (dl) {
            groupFetches += 1;
            if (dl != null) return DeltaPageResult(items: const [], deltaLink: dl);
            return DeltaPageResult(
              items: [
                RemoteFolderGroup(
                  id: 'rg-1',
                  name: 'Group 1',
                  orderDateTime: tNew.add(const Duration(hours: 2)),
                ),
              ],
              deltaLink: 'dl-g-2',
            );
          }
          ..onFetchFoldersDelta = (dl) {
            folderFetches += 1;
            if (dl != null) return DeltaPageResult(items: const [], deltaLink: dl);
            return DeltaPageResult(
              items: [
                const RemoteTodoFolder(
                  id: 'rf-default',
                  name: 'Tasks',
                  isDefaultFolder: true,
                ),
                RemoteTodoFolder(
                  id: 'rf-1',
                  name: 'List 1 Full',
                  orderDateTime: tNew.add(const Duration(hours: 3)),
                ),
                RemoteTodoFolder(
                  id: 'rf-ungroup',
                  name: 'Ungrouped',
                  orderDateTime: tOld.subtract(const Duration(hours: 1)),
                ),
              ],
              deltaLink: 'dl-f-2',
            );
          };

        final h = await createSyncTestHarness(
          accountId: 'acct_multi_rt',
          api: fakeApi,
          realtimeSyncEnabled: true,
          groups: [
            ListGroup(
              id: 'g_1',
              title: 'Group 1',
              remoteId: 'rg-1',
              orderDateTime: tMid,
            ),
            ListGroup(
              id: 'g_2',
              title: 'Group 2',
              remoteId: 'rg-2',
              orderDateTime: tOld,
            ),
            ListGroup(
              id: 'g_rt_del',
              title: 'Temp Group',
              remoteId: 'rg-rt-del',
              orderDateTime: tOld.subtract(const Duration(hours: 1)),
            ),
          ],
          defaultTasksFolderRemoteId: 'rf-default',
          extraLists: [
            TodoList(
              id: 'l_1',
              title: 'List 1',
              remoteId: 'rf-1',
              groupId: 'g_1',
              orderDateTime: tMid,
            ),
            TodoList(
              id: 'l_2',
              title: 'List 2',
              remoteId: 'rf-2',
              groupId: 'g_2',
              orderDateTime: tOld,
            ),
            TodoList(
              id: 'l_ungroup',
              title: 'Ungrouped',
              remoteId: 'rf-ungroup',
              groupId: 'g_rt_del',
              orderDateTime: tOld.subtract(const Duration(hours: 1)),
            ),
          ],
          groupsDeltaLink: 'dl-g-1',
          foldersDeltaLink: 'dl-f-1',
        );

        h.container.read(syncProvider);
        await pumpEventQueue();
        final initialMutationVersion = h.container
            .read(todoProvider)
            .mutationVersion;

        h.api.realtimeController.add(
          RealtimeEvent(
            id: 'rg-2',
            type: 'FolderGroup',
            operation: 'Updated',
            requestId: 'other-req-1',
            payload: {
              'Id': 'rg-2',
              'Name': 'Group 2',
              'OrderDateTime': formatSubstrateUtcTimestamp(tNew),
            },
          ),
        );
        h.api.realtimeController.add(
          RealtimeEvent(
            id: 'rf-2',
            type: 'TaskFolder',
            operation: 'Updated',
            requestId: 'other-req-2',
            payload: {
              'Id': 'rf-2',
              'Name': 'List 2',
              'ThemeColor': 'dark_rose',
              'OrderDateTime': formatSubstrateUtcTimestamp(tNew),
            },
          ),
        );
        h.api.realtimeController.add(
          const RealtimeEvent(
            id: 'ConfirmOnDelete',
            type: 'Setting',
            operation: 'Updated',
            requestId: 'other-req-3',
            payload: {'Key': 'ConfirmOnDelete', 'Value': 'false'},
          ),
        );
        h.api.realtimeController.add(
          const RealtimeEvent(
            id: 'rg-rt-del',
            type: 'FolderGroup',
            operation: 'Deleted',
            requestId: 'other-req-4',
          ),
        );
        await pumpEventQueue();

        expect(groupFetches, 0);
        expect(folderFetches, 0);
        var todoState = h.container.read(todoProvider);
        expect(todoState.groups.map((g) => g.id).toList(), ['g_2', 'g_1']);
        expect(
          todoState.lists.firstWhere((l) => l.id == 'l_ungroup').groupId,
          isNull,
        );
        expect(
          todoState.lists.firstWhere((l) => l.id == 'l_2').themeColor,
          ListThemeColor.rose,
        );
        expect(
          todoState.lists
              .where((l) => !l.isSmartList)
              .map((l) => l.id)
              .toList(),
          ['l_2', 'l_1', 'l_ungroup'],
        );
        expect(todoState.confirmBeforeDeleting, isFalse);
        expect(todoState.mutationVersion, initialMutationVersion);

        await h.container
            .read(syncProvider.notifier)
            .syncNow(forceFullSync: true, reason: 'manual_header_sync');
        expect(h.api.callLog, contains('GET foldergroups(null)'));
        expect(h.api.callLog, contains('GET taskfolders(null)'));

        todoState = h.container.read(todoProvider);
        expect(todoState.groups.map((g) => g.id).toList(), ['g_1']);
        expect(
          todoState.lists
              .where((l) => !l.isSmartList)
              .map((l) => l.id)
              .toList(),
          ['l_1', 'l_ungroup'],
        );
        expect(
          todoState.lists.firstWhere((l) => l.id == 'l_1').title,
          'List 1 Full',
        );
      },
    );

    test(
      'realtime reconnect triggers incremental delta sync using saved deltaLinks instead of forceFullSync',
      () async {
        final fakeApi = _ReconnectFakeSubstrateApi();
        addTearDown(fakeApi.secondStream.close);
        final deltaSyncDone = Completer<void>();
        fakeApi.onFetchFoldersDelta = (dl) =>
            DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-f-new');
        fakeApi.onFetchTasksDelta = (folderId, dl) {
          if (!deltaSyncDone.isCompleted) deltaSyncDone.complete();
          return DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-t-new');
        };

        final h = await createSyncTestHarness(
          accountId: 'acct_rt_reconnect_delta',
          api: fakeApi,
          realtimeSyncEnabled: true,
          defaultTasksFolderRemoteId: 'rf-default',
          foldersDeltaLink: 'dl-folders-saved',
          taskDeltaLinks: const {'rf-default': 'dl-tasks-saved'},
        );

        h.container.read(syncProvider);
        await fakeApi.secondConnected.future.timeout(
          const Duration(seconds: 5),
        );
        fakeApi.secondStream.add(const RealtimeEvent(type: 'KeepAlive'));

        await deltaSyncDone.future.timeout(const Duration(seconds: 3));
        await pumpEventQueue();

        expect(
          fakeApi.callLog,
          contains('GET taskfolders(dl-folders-saved)'),
        );
        expect(
          fakeApi.callLog,
          contains('GET tasks(rf-default,dl-tasks-saved)'),
        );
        expect(fakeApi.callLog, isNot(contains('GET taskfolders(null)')));
        expect(
          fakeApi.callLog,
          isNot(contains('GET tasks(rf-default,null)')),
        );
      },
    );
  });
}
