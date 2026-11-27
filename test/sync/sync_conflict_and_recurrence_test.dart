import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_dispatcher.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/text_merge.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Sync conflict, recurrence, and full-sync pruning', () {
    test('forceFullSync bypasses saved taskDeltaLinks, syncs reordered OrderDateTime, and prunes stale deleted tasks while keeping moved and dirty tasks', () async {
      final t03 = DateTime.utc(2026, 11, 22, 3);
      final t04 = DateTime.utc(2026, 11, 22, 4);
      final t05 = DateTime.utc(2026, 11, 22, 5);
      final t10 = DateTime.utc(2026, 11, 22, 10);
      final t15 = DateTime.utc(2026, 11, 22, 15);
      final t20 = DateTime.utc(2026, 11, 22, 20);
      final t30 = DateTime.utc(2026, 11, 22, 23);

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
                RemoteTodoFolder(id: 'rf-b', name: 'List B'),
              ],
              deltaLink: 'dl-folders-2',
            );
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (dl == 'dl-def-new') {
          return const DeltaPageResult(
            items: [
              RemoteTodoTask(
                id: 'rt-completed-kept',
                subject: '',
                isDeleted: true,
              ),
            ],
            deltaLink: 'dl-def-after-del',
          );
        }
        if (dl != null) {
          return DeltaPageResult(items: const [], deltaLink: dl);
        }
        if (folderId == 'rf-default') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask(
                id: 'rt-1',
                changeKey: 'ck-1-new',
                parentFolderId: 'rf-default',
                subject: 'Task 1',
                orderDateTime: t10,
              ),
              RemoteTodoTask(
                id: 'rt-2',
                changeKey: 'ck-2-new',
                parentFolderId: 'rf-default',
                subject: 'Task 2',
                orderDateTime: t30,
              ),
              RemoteTodoTask(
                id: 'rt-completed-kept',
                changeKey: 'ck-completed-kept',
                parentFolderId: 'rf-default',
                subject: 'Completed Task Kept',
                status: 'Completed',
                completedDateTime: t05,
                orderDateTime: t04,
              ),
            ],
            deltaLink: 'dl-def-new',
          );
        }
        if (folderId == 'rf-b') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask(
                id: 'rt-moved',
                changeKey: 'ck-moved-new',
                parentFolderId: 'rf-b',
                subject: 'Moved Remotely',
                orderDateTime: t15,
              ),
            ],
            deltaLink: 'dl-b-new',
          );
        }
        return const DeltaPageResult(items: []);
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_force_full',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        extraLists: const [
          TodoList(id: 'list_b', title: 'List B', remoteId: 'rf-b'),
        ],
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Task 1',
            createdAt: t03,
            orderDateTime: t20,
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
          TaskItem(
            id: 't_2',
            listId: 'tasks',
            title: 'Task 2',
            createdAt: t03,
            orderDateTime: t10,
            remoteId: 'rt-2',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-2',
          ),
          TaskItem(
            id: 't_del',
            listId: 'tasks',
            title: 'Deleted On Original App',
            createdAt: t03,
            orderDateTime: t05,
            remoteId: 'rt-del',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-del',
          ),
          TaskItem(
            id: 't_moved',
            listId: 'tasks',
            title: 'Moved Remotely',
            createdAt: t03,
            orderDateTime: t04,
            remoteId: 'rt-moved',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-moved',
          ),
          TaskItem(
            id: 't_dirty',
            listId: 'tasks',
            title: 'Locally Dirty Task',
            createdAt: t03,
            orderDateTime: t03,
            remoteId: 'rt-dirty',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-dirty',
          ),
          TaskItem(
            id: 't_completed_kept',
            listId: 'tasks',
            title: 'Completed Task Kept',
            createdAt: t03.subtract(const Duration(hours: 1)),
            isCompleted: true,
            completedAt: t05,
            orderDateTime: t04,
            remoteId: 'rt-completed-kept',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-completed-kept',
          ),
          TaskItem(
            id: 't_completed_old',
            listId: 'tasks',
            title: 'Older Deleted Completed Task',
            createdAt: t03.subtract(const Duration(hours: 2)),
            isCompleted: true,
            completedAt: t03,
            orderDateTime: t03.subtract(const Duration(hours: 2)),
            remoteId: 'rt-completed-old',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-completed-old',
          ),
        ],
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {'rf-default': 'dl-def-1', 'rf-b': 'dl-b-1'},
      );

      await h.container.read(syncProvider.notifier).syncNow();
      var state = h.container.read(todoProvider);
      final tasksList = state.lists.firstWhere((l) => l.id == 'tasks');
      expect(state.tasksForList(tasksList).take(2).map((t) => t.id).toList(), [
        't_1',
        't_2',
      ]);
      expect(state.tasks.any((t) => t.id == 't_del'), isTrue);

      h.container
          .read(todoProvider.notifier)
          .commit(
            state.copyWith(
              tasks: [
                for (final t in state.tasks)
                  if (t.id == 't_dirty')
                    t.copyWith(title: 'Locally Dirty Edited')
                  else
                    t,
              ],
            ),
          );

      await h.container
          .read(syncProvider.notifier)
          .syncNow(forceFullSync: true, reason: SyncReason.manual);

      expect(h.api.callLog, contains('GET tasks(rf-default,null)'));
      expect(h.api.callLog, contains('GET tasks(rf-b,null)'));

      state = h.container.read(todoProvider);
      expect(
        state
            .tasksForList(tasksList)
            .where((t) => !t.isCompleted)
            .map((t) => t.id)
            .toList(),
        ['t_2', 't_1', 't_dirty'],
      );
      expect(state.tasks.any((t) => t.id == 't_del'), isFalse);
      expect(state.tasks.any((t) => t.id == 't_completed_kept'), isTrue);
      expect(state.tasks.any((t) => t.id == 't_completed_old'), isFalse);

      final moved = state.tasks.firstWhere((t) => t.id == 't_moved');
      expect(moved.listId, 'list_b');
      expect(moved.orderDateTime, t15);

      expect(h.repository.loadTaskDeltaLinks(), {
        'rf-default': 'dl-def-new',
        'rf-b': 'dl-b-new',
      });

      // Explicit delta deletion removes a previously kept completed task.
      await h.container.read(syncProvider.notifier).syncNow();
      state = h.container.read(todoProvider);
      expect(state.tasks.any((t) => t.id == 't_completed_kept'), isFalse);
    });

    test('forceFullSync does not prune active or completed tasks when full fetch returns null deltaLink', () async {
      final t05 = DateTime.utc(2026, 11, 22, 5);
      final t10 = DateTime.utc(2026, 11, 22, 10);

      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
        items: [
          RemoteTodoFolder(
            id: 'rf-default',
            name: 'Tasks',
            isDefaultFolder: true,
          ),
        ],
        deltaLink: 'dl-folders-1',
      );
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        return DeltaPageResult(
          items: [
            RemoteTodoTask(
              id: 'rt-1',
              changeKey: 'ck-1',
              parentFolderId: 'rf-default',
              subject: 'Task 1',
              orderDateTime: t10,
            ),
          ],
          deltaLink: null,
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_null_dl_no_prune',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Task 1',
            createdAt: t05,
            orderDateTime: t10,
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
          TaskItem(
            id: 't_active_other',
            listId: 'tasks',
            title: 'Active Task Omitted From Incomplete Page',
            createdAt: t05,
            orderDateTime: t05,
            remoteId: 'rt-active-other',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-active-other',
          ),
          TaskItem(
            id: 't_completed_other',
            listId: 'tasks',
            title: 'Completed Task Omitted From Incomplete Page',
            createdAt: t05,
            isCompleted: true,
            completedAt: t05,
            orderDateTime: t05,
            remoteId: 'rt-completed-other',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-completed-other',
          ),
        ],
        taskDeltaLinks: const {'rf-default': 'dl-saved'},
      );

      await h.container
          .read(syncProvider.notifier)
          .syncNow(forceFullSync: true, reason: SyncReason.manual);

      final state = h.container.read(todoProvider);
      expect(state.tasks.any((t) => t.id == 't_1'), isTrue);
      expect(state.tasks.any((t) => t.id == 't_active_other'), isTrue);
      expect(state.tasks.any((t) => t.id == 't_completed_other'), isTrue);
    });

    test('forceFullSync does not prune custom lists when folders delta returns empty items', () async {
      final fakeApi = FakeSubstrateApi()
        ..onFetchFoldersDelta = (dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-folders-empty');

      final h = await createSyncTestHarness(
        accountId: 'acct_empty_folders',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        extraLists: const [
          TodoList(id: 'list_keep', title: 'Keep Me', remoteId: 'rf-keep'),
        ],
      );

      await h.container
          .read(syncProvider.notifier)
          .syncNow(forceFullSync: true, reason: SyncReason.manual);

      final lists = h.container.read(todoProvider).lists;
      expect(lists.any((l) => l.id == 'list_keep'), isTrue);
    });

    test('completing synced recurring task on Microsoft account lets server spawn next occurrence without duplicate POST', () async {
      Map<String, dynamic>? capturedPatch;
      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) =>
          const DeltaPageResult(items: [], deltaLink: 'dl-f-2');
      fakeApi.onPatchTask = (id, patch, ck) async {
        capturedPatch = Map<String, dynamic>.from(patch);
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-rec-done',
          parentFolderId: 'rf-default',
          subject: 'Daily Review',
          status: 'Completed',
        );
      };
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-default') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask(
                id: 'rt-rec',
                changeKey: 'ck-rec-done',
                parentFolderId: 'rf-default',
                subject: 'Daily Review',
                status: 'Completed',
                dueDate: DateTime(2026, 11, 25),
                recurrence: RecurrenceType.daily,
              ),
              RemoteTodoTask(
                id: 'rt-rec-next',
                changeKey: 'ck-rec-next',
                parentFolderId: 'rf-default',
                subject: 'Daily Review',
                status: 'NotStarted',
                dueDate: DateTime(2026, 11, 26),
                recurrence: RecurrenceType.daily,
              ),
            ],
            deltaLink: 'dl-t-2',
          );
        }
        return const DeltaPageResult(items: []);
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_recur_done',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_rec',
            listId: 'tasks',
            title: 'Daily Review',
            createdAt: DateTime.utc(2026, 11, 20),
            dueDate: DateTime(2026, 11, 25),
            recurrence: RecurrenceType.daily,
            remoteId: 'rt-rec',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-rec-1',
          ),
        ],
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      h.container
          .read(tasksViewPresenterProvider)
          .setTaskCompleted('t_rec', completed: true);

      expect(h.container.read(todoProvider).tasks.length, 1);

      await h.container.read(syncProvider.notifier).syncNow();

      expect(
        h.api.callLog.any((c) => c.startsWith('POST taskfolders/')),
        isFalse,
      );
      expect(capturedPatch?.keys.toSet(), {'Status', 'CompletedDateTime'});
      expect(capturedPatch?['Status'], 'Completed');

      final finalTasks = h.container.read(todoProvider).tasks;
      expect(finalTasks.length, 2);
      expect(
        finalTasks.where((t) => !t.isCompleted).single.remoteId,
        'rt-rec-next',
      );
    });

    test('preserves custom Recurrence rawRecurrence across unrelated field PATCH and dueDate edits, clearing only when user changes recurrence', () async {
      final customRule = {
        'RecurrenceType': 'Custom',
        'IntervalType': 'Weeks',
        'Interval': 2,
        'WeekDays': ['Monday', 'Wednesday'],
        'FirstDayOfWeek': 'Sunday',
      };
      final capturedPatches = <Map<String, dynamic>>[];
      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-f-2')
          : const DeltaPageResult(
              items: [
                RemoteTodoFolder(
                  id: 'rf-default',
                  name: 'Tasks',
                  isDefaultFolder: true,
                ),
              ],
              deltaLink: 'dl-f-1',
            );
      fakeApi.onFetchTasksDelta = (folderId, dl) => dl != null
          ? DeltaPageResult(items: const [], deltaLink: dl)
          : DeltaPageResult(
              items: [
                RemoteTodoTask.fromJson({
                  'Id': 'rt-custom',
                  'ChangeKey': 'ck-1',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Biweekly Sync',
                  'DueDate': '2026-11-25',
                  'Recurrence': customRule,
                }),
              ],
              deltaLink: 'dl-t-1',
            );
      fakeApi.onPatchTask = (id, patch, ck) async {
        capturedPatches.add(Map<String, dynamic>.from(patch));
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-${capturedPatches.length + 1}',
          parentFolderId: 'rf-default',
          subject: patch['Subject'] as String? ?? 'Biweekly Sync',
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_custom_recur',
        api: fakeApi,
      );

      await h.container.read(syncProvider.notifier).syncNow();
      final task = h.container.read(todoProvider).tasks.single;
      expect(task.rawRecurrence?['Interval'], 2);
      expect(task.rawRecurrence?['WeekDays'], ['Monday', 'Wednesday']);

      final detail = h.container.read(detailViewPresenterProvider);
      detail.updateTaskTitle(task.id, 'Biweekly Sync Updated');
      await h.container.read(syncProvider.notifier).syncNow();
      expect(capturedPatches.last.keys.toSet(), {'Subject'});

      detail.setTaskDueDate(task.id, DateTime(2026, 12, 2));
      await h.container.read(syncProvider.notifier).syncNow();
      expect(
        capturedPatches.last.keys.toSet(),
        containsAll(['DueDateTime', 'Recurrence']),
      );
      expect(capturedPatches.last['Recurrence'], customRule);
      expect(h.repository.readCachedTasks().single.rawRecurrence, customRule);

      detail.setTaskRecurrence(task.id, RecurrenceType.daily);
      await h.container.read(syncProvider.notifier).syncNow();
      expect(capturedPatches.last['Recurrence']['RecurrenceType'], 'Daily');
      expect(capturedPatches.last['Recurrence']['Interval'], 1);
    });

    test('conflict 409/412 performs 3-way plain-text note merge and recurring status preservation, and step push skips unchanged steps', () async {
      Map<String, dynamic>? retriedNotePatch;
      Map<String, dynamic>? retriedAdvPatch;
      Map<String, dynamic>? retriedStepsTaskPatch;
      final patchedSteps = <String>[];

      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) =>
          const DeltaPageResult(items: [], deltaLink: 'dl-f-2');
      fakeApi.onGetTask = (id) async {
        if (id == 'rt-note') {
          return const RemoteTodoTask(
            id: 'rt-note',
            changeKey: 'ck-note-remote',
            parentFolderId: 'rf-default',
            subject: 'Merge Note Task',
            bodyContent: 'Line 1 (remote)\nLine 2\nLine 3',
            bodyContentType: 'Text',
          );
        }
        return RemoteTodoTask(
          id: 'rt-adv',
          changeKey: 'ck-adv-remote',
          parentFolderId: 'rf-default',
          subject: 'Already Advanced Recur',
          status: 'NotStarted',
          dueDate: DateTime(2026, 11, 26),
          recurrence: RecurrenceType.daily,
        );
      };
      fakeApi.onPatchTask = (id, patch, ck) async {
        if (ck == 'ck-note-1' || ck == 'ck-adv-1') {
          throw const AppError.network(
            statusCode: 409,
            code: 'ErrorIrresolvableConflict',
            message: 'conflict',
          );
        }
        if (id == 'rt-note') {
          retriedNotePatch = Map<String, dynamic>.from(patch);
          return const RemoteTodoTask(
            id: 'rt-note',
            changeKey: 'ck-note-2',
            parentFolderId: 'rf-default',
            subject: 'Merge Note Task',
          );
        }
        if (id == 'rt-adv') {
          retriedAdvPatch = Map<String, dynamic>.from(patch);
          return RemoteTodoTask(
            id: 'rt-adv',
            changeKey: 'ck-adv-2',
            parentFolderId: 'rf-default',
            subject: 'Already Advanced Recur',
            status: 'NotStarted',
            dueDate: DateTime(2026, 11, 26),
            recurrence: RecurrenceType.daily,
          );
        }
        if (id == 'rt-steps') {
          retriedStepsTaskPatch = Map<String, dynamic>.from(patch);
          return RemoteTodoTask(
            id: 'rt-steps',
            changeKey: 'ck-steps-2',
            parentFolderId: 'rf-default',
            subject: patch['Subject'] as String? ?? 'Multi Step Task',
          );
        }
        throw StateError('Unexpected task PATCH on $id: $patch');
      };
      fakeApi.onPatchStep = (taskRemoteId, stepRemoteId, patch) async {
        patchedSteps.add(stepRemoteId);
        return RemoteTaskStep(
          id: stepRemoteId,
          subject: 'S2',
          isCompleted: true,
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_conflict_steps',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_note',
            listId: 'tasks',
            title: 'Merge Note Task',
            createdAt: DateTime.utc(2026, 11, 22),
            note: 'Line 1\nLine 2\nLine 3',
            remoteId: 'rt-note',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-note-1',
          ),
          TaskItem(
            id: 't_adv',
            listId: 'tasks',
            title: 'Already Advanced Recur',
            createdAt: DateTime.utc(2026, 11, 22),
            dueDate: DateTime(2026, 11, 25),
            recurrence: RecurrenceType.daily,
            remoteId: 'rt-adv',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-adv-1',
          ),
          TaskItem(
            id: 't_steps',
            listId: 'tasks',
            title: 'Multi Step Task',
            createdAt: DateTime.utc(2026, 11, 22),
            remoteId: 'rt-steps',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-steps-1',
            steps: const [
              TaskStep(id: 's_1', title: 'S1', remoteId: 'rs-1'),
              TaskStep(id: 's_2', title: 'S2', remoteId: 'rs-2'),
              TaskStep(id: 's_3', title: 'S3', remoteId: 'rs-3'),
            ],
          ),
        ],
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      h.container
          .read(detailViewPresenterProvider)
          .updateTaskNote('t_note', 'Line 1\nLine 2\nLine 3 (local)');
      h.container
          .read(tasksViewPresenterProvider)
          .setTaskCompleted('t_adv', completed: true);
      h.container
          .read(detailViewPresenterProvider)
          .toggleStepCompleted('t_steps', 's_2');

      await h.container.read(syncProvider.notifier).syncNow();

      expect(retriedNotePatch?.keys.toSet(), {'Body', 'BodyLastModifiedTime'});
      expect(
        (retriedNotePatch?['Body'] as Map)['Content'],
        'Line 1 (remote)\nLine 2\nLine 3 (local)',
      );
      final finalNoteTask = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_note');
      expect(finalNoteTask.note, 'Line 1 (remote)\nLine 2\nLine 3 (local)');
      expect(h.repository.outbox.ops, isEmpty);

      expect(retriedAdvPatch?['Status'], 'NotStarted');
      final finalAdvTask = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_adv');
      expect(finalAdvTask.isCompleted, isFalse);
      expect(finalAdvTask.dueDate, DateTime(2026, 11, 26));

      expect(retriedStepsTaskPatch, isNull);
      expect(
        h.api.callLog.any((c) => c.startsWith('PATCH tasks/rt-steps(')),
        isFalse,
      );
      expect(patchedSteps, ['rs-2']);

      patchedSteps.clear();
      h.container
          .read(detailViewPresenterProvider)
          .updateTaskTitle('t_steps', 'Multi Step Task Renamed');
      await h.container.read(syncProvider.notifier).syncNow();
      expect(retriedStepsTaskPatch?.keys.toSet(), {'Subject'});
      expect(retriedStepsTaskPatch?['Subject'], 'Multi Step Task Renamed');
      expect(patchedSteps, isEmpty);
    });

    test('mergeThreeWayNoteText preserves disjoint multi-line and single-line concurrent edits', () {
      expect(
        mergeThreeWayNoteText(
          base: 'Line 1\nLine 2\nLine 3',
          local: 'Line 1 (local)\nLine 2\nLine 3',
          remote: 'Line 1\nLine 2\nLine 3 (remote)',
        ),
        'Line 1 (local)\nLine 2\nLine 3 (remote)',
      );

      expect(
        mergeThreeWayNoteText(
          base: 'alpha middle omega',
          local: 'ALPHA middle omega',
          remote: 'alpha middle OMEGA',
        ),
        'ALPHA middle OMEGA',
      );

      expect(
        mergeThreeWayNoteText(
          base: null,
          local: 'Local thought',
          remote: 'Remote thought',
        ),
        'Local thought\nRemote thought',
      );

      expect(
        mergeThreeWayNoteText(
          base: 'A\nB\nC',
          local: 'A1\nShared\nC',
          remote: 'A2\nShared\nC',
        ),
        'A1\nShared\nA2\nC',
      );
    });

    test('createTask 409 conflict retries without CreatedWithLocalId and patchTask handles consecutive 409s', () async {
      final createPayloads = <Map<String, dynamic>>[];
      var getTaskCalls = 0;
      var patchCalls = 0;

      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) =>
          const DeltaPageResult(items: [], deltaLink: 'dl-f-2');
      fakeApi.onCreateTask = (folderId, payload) async {
        createPayloads.add(Map<String, dynamic>.from(payload));
        if (payload.containsKey('CreatedWithLocalId')) {
          throw const AppError.network(
            statusCode: 409,
            code: 'ErrorIrresolvableConflict',
            message: 'conflict on create',
          );
        }
        return RemoteTodoTask(
          id: 'rt-created-no-local-id',
          changeKey: 'ck-created-1',
          parentFolderId: folderId,
          subject: payload['Subject'] as String? ?? '',
        );
      };
      fakeApi.onGetTask = (id) async {
        getTaskCalls += 1;
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-remote-$getTaskCalls',
          parentFolderId: 'rf-default',
          subject: 'Multi 409 Task',
          bodyContent: getTaskCalls == 1
              ? 'Line 1 (remote1)\nLine 2'
              : 'Line 1 (remote2)\nLine 2',
          bodyContentType: 'Text',
        );
      };
      fakeApi.onPatchTask = (id, patch, ck) async {
        patchCalls += 1;
        if (patchCalls <= 2) {
          throw const AppError.network(
            statusCode: 409,
            code: 'ErrorIrresolvableConflict',
            message: 'concurrent conflict',
          );
        }
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-final',
          parentFolderId: 'rf-default',
          subject: patch['Subject'] as String? ?? 'Multi 409 Task',
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_multi_409',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_patch_multi',
            listId: 'tasks',
            title: 'Multi 409 Task',
            createdAt: DateTime.utc(2026, 11, 22),
            note: 'Line 1\nLine 2',
            remoteId: 'rt-patch-multi',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-initial',
          ),
        ],
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      h.container
          .read(tasksViewPresenterProvider)
          .addTask(targetListId: 'tasks', title: 'Created After 409');
      h.container
          .read(detailViewPresenterProvider)
          .updateTaskNote('t_patch_multi', 'Line 1\nLine 2 (local)');

      await h.container.read(syncProvider.notifier).syncNow();

      expect(createPayloads.length, 2);
      expect(createPayloads[0].containsKey('CreatedWithLocalId'), isTrue);
      expect(createPayloads[1].containsKey('CreatedWithLocalId'), isFalse);

      expect(getTaskCalls, 2);
      expect(patchCalls, 3);

      final tasks = h.container.read(todoProvider).tasks;
      final createdTask = tasks.firstWhere(
        (t) => t.title == 'Created After 409',
      );
      expect(createdTask.remoteId, 'rt-created-no-local-id');
      final patchedTask = tasks.firstWhere((t) => t.id == 't_patch_multi');
      expect(patchedTask.changeKey, 'ck-final');
      expect(patchedTask.note, 'Line 1 (remote2)\nLine 2 (local)');
    });
  });
}
