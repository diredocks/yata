import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  group('Undo delete under Delete-Wins', () {
    test(
      'undo before push cancels pending delete and preserves remoteId',
      () async {
        final now = DateTime.utc(2026, 11, 27, 10, 0);
        final originalTask = TaskItem(
          id: 'task_undo_before_push',
          listId: 'tasks',
          title: 'Keep me before push',
          createdAt: now,
          remoteId: 'rt-undo-1',
          remoteParentFolderId: 'rf-default',
          changeKey: 'ck-1',
          steps: const [
            TaskStep(id: 'step_1', title: 'Step 1', remoteId: 'rs-1'),
          ],
          updatedAt: now,
        );

        final api = FakeSubstrateApi();
        final deletedRemoteIds = <String>[];
        api.onDeleteTask = (remoteId) async {
          deletedRemoteIds.add(remoteId);
        };

        final h = await createSyncTestHarness(
          accountId: 'acct_undo_before_push',
          api: api,
          tasks: [originalTask],
        );

        // Delete then immediately Undo before push runs.
        h.container.read(todoProvider.notifier).deleteTasks({originalTask.id});
        expect(h.container.read(todoProvider).tasks, isEmpty);
        expect(h.repository.outbox.ops, hasLength(1));
        expect(h.repository.outbox.ops.single.kind, SyncOpKind.delete);

        h.container
            .read(tasksViewPresenterProvider)
            .restoreTask(originalTask, index: 0);

        final restored = h.container.read(todoProvider).tasks.single;
        expect(restored.id, originalTask.id);
        expect(restored.remoteId, 'rt-undo-1');
        expect(restored.steps.single.remoteId, 'rs-1');
        expect(
          h.repository.outbox.ops.where((op) => op.kind == SyncOpKind.delete),
          isEmpty,
        );

        await h.container.read(syncProvider.notifier).syncNow();

        expect(deletedRemoteIds, isEmpty);
        expect(h.container.read(syncProvider).status, SyncStatus.success);
        final synced = h.container.read(todoProvider).tasks.single;
        expect(synced.remoteId, 'rt-undo-1');
      },
    );

    test('undo after delete push clears stale remoteId, recreates task and steps via POST, and survives old tombstone', () async {
      final now = DateTime.utc(2026, 11, 27, 10, 0);
      final originalTask = TaskItem(
        id: 'task_undo_after_push',
        listId: 'tasks',
        title: 'Recreate me after delete push',
        note: 'Important note',
        createdAt: now,
        remoteId: 'rt-deleted-1',
        remoteParentFolderId: 'rf-default',
        changeKey: 'ck-deleted-1',
        steps: const [
          TaskStep(id: 'step_1', title: 'Subtask A', remoteId: 'rs-old-1'),
        ],
        updatedAt: now,
      );

      final api = FakeSubstrateApi();
      final patchedIds = <String>[];
      final createdTitles = <String>[];
      var emitOldTombstone = false;

      api.onPatchTask = (remoteId, patch, changeKey) async {
        patchedIds.add(remoteId);
        throw const AppError.notFound(message: 'Item not found');
      };
      api.onCreateTask = (folderRemoteId, payload) async {
        createdTitles.add(payload['Subject'] as String);
        return RemoteTodoTask(
          id: 'rt-recreated-2',
          parentFolderId: folderRemoteId,
          subject: payload['Subject'] as String,
          status: 'NotStarted',
          changeKey: 'ck-recreated-2',
          createdDateTime: now,
        );
      };
      api.onFetchTasksDelta = (folderRemoteId, deltaLink) {
        return DeltaPageResult(
          items: emitOldTombstone
              ? const [
                  RemoteTodoTask(
                    id: 'rt-deleted-1',
                    subject: '',
                    isDeleted: true,
                  ),
                ]
              : const [],
          deltaLink: 'dl-next',
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_undo_after_push',
        api: api,
        tasks: [originalTask],
        taskDeltaLinks: const {'rf-default': 'dl-initial'},
      );

      // 1. Delete task and let push delete it on the server.
      h.container.read(todoProvider.notifier).deleteTasks({originalTask.id});
      await h.container.read(syncProvider.notifier).syncNow();
      expect(h.container.read(todoProvider).tasks, isEmpty);

      // 2. Tap Undo with the pre-delete snapshot.
      h.container
          .read(tasksViewPresenterProvider)
          .restoreTask(originalTask, index: 0);

      final restoredLocal = h.container.read(todoProvider).tasks.single;
      expect(restoredLocal.id, originalTask.id);
      expect(restoredLocal.remoteId, isNull);
      expect(restoredLocal.remoteParentFolderId, isNull);
      expect(restoredLocal.changeKey, isNull);
      expect(restoredLocal.steps.single.remoteId, isNull);

      // Emit a tombstone for the deleted old remoteId on the next delta pull.
      emitOldTombstone = true;

      // 3. Push + pull runs: must POST (not PATCH 404 -> Delete-Wins) and survive tombstone.
      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedIds, isEmpty);
      expect(createdTitles, ['Recreate me after delete push']);
      expect(h.container.read(syncProvider).status, SyncStatus.success);

      final tasksAfterSync = h.container.read(todoProvider).tasks;
      expect(tasksAfterSync, hasLength(1));
      final recreated = tasksAfterSync.single;
      expect(recreated.id, originalTask.id);
      expect(recreated.remoteId, 'rt-recreated-2');
      expect(recreated.steps, hasLength(1));
      expect(recreated.steps.single.title, 'Subtask A');
      expect(recreated.steps.single.remoteId, isNotNull);
      expect(recreated.steps.single.remoteId, isNot('rs-old-1'));
    });

    test('undo while delete is in-flight clears stale remoteId and recreates on next push', () async {
      final now = DateTime.utc(2026, 11, 27, 10, 0);
      final originalTask = TaskItem(
        id: 'task_undo_inflight',
        listId: 'tasks',
        title: 'In-flight delete undo',
        createdAt: now,
        remoteId: 'rt-inflight-1',
        remoteParentFolderId: 'rf-default',
        changeKey: 'ck-inflight-1',
        updatedAt: now,
      );

      final api = FakeSubstrateApi();
      final deleteStarted = Completer<void>();
      final allowDeleteFinish = Completer<void>();
      api.onDeleteTask = (remoteId) async {
        if (!deleteStarted.isCompleted) deleteStarted.complete();
        await allowDeleteFinish.future;
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_undo_inflight',
        api: api,
        tasks: [originalTask],
      );

      h.container.read(todoProvider.notifier).deleteTasks({originalTask.id});
      final inFlightSync = h.container.read(syncProvider.notifier).syncNow();
      await deleteStarted.future;

      // Undo while DELETE rt-inflight-1 is still in flight.
      h.container
          .read(tasksViewPresenterProvider)
          .restoreTask(originalTask, index: 0);

      final restored = h.container.read(todoProvider).tasks.single;
      expect(restored.remoteId, isNull);
      expect(h.repository.outbox.ops.length, 2);

      allowDeleteFinish.complete();
      await inFlightSync;

      // Next sync pushes the queued recreate upsert.
      await h.container.read(syncProvider.notifier).syncNow();

      final tasksAfter = h.container.read(todoProvider).tasks;
      expect(tasksAfter, hasLength(1));
      expect(tasksAfter.single.id, originalTask.id);
      expect(tasksAfter.single.remoteId, isNotNull);
      expect(tasksAfter.single.remoteId, isNot('rt-inflight-1'));
    });
  });
}
