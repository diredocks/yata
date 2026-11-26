import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/homeview/home_view_ordering.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/microsoft/todo_wire_codecs.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Manual reorder sync', () {
    test('HomeViewPresenter manual reorder updates descending OrderDateTime, marks moved items dirty, and PATCHes remote', () async {
      final patchedGroups = <String, Map<String, dynamic>>{};
      final patchedFolders = <String, Map<String, dynamic>>{};
      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchGroupsDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-groups-2')
          : DeltaPageResult(
              items: [
                RemoteFolderGroup(
                  id: 'rg-work',
                  name: 'Work Group',
                  orderDateTime: DateTime.utc(2026, 11, 22, 10),
                ),
              ],
              deltaLink: 'dl-groups-1',
            );
      fakeApi.onFetchFoldersDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-folders-2')
          : DeltaPageResult(
              items: [
                const RemoteTodoFolder(
                  id: 'rf-default',
                  name: 'Tasks',
                  isDefaultFolder: true,
                ),
                RemoteTodoFolder(
                  id: 'rf-alpha',
                  name: 'Alpha',
                  orderDateTime: DateTime.utc(2026, 11, 22, 12),
                ),
                RemoteTodoFolder(
                  id: 'rf-beta',
                  name: 'Beta',
                  orderDateTime: DateTime.utc(2026, 11, 22, 8),
                ),
                RemoteTodoFolder(
                  id: 'rf-m1',
                  name: 'Member 1',
                  parentFolderGroupId: 'rg-work',
                  orderDateTime: DateTime.utc(2026, 11, 22, 11),
                ),
                RemoteTodoFolder(
                  id: 'rf-m2',
                  name: 'Member 2',
                  parentFolderGroupId: 'rg-work',
                  orderDateTime: DateTime.utc(2026, 11, 22, 9),
                ),
              ],
              deltaLink: 'dl-folders-1',
            );
      fakeApi.onPatchGroup = (remoteId, patch) async {
        patchedGroups[remoteId] = Map<String, dynamic>.from(patch);
        return RemoteFolderGroup(
          id: remoteId,
          name: patch['Name'] as String? ?? 'Work Group',
          orderDateTime: parseSubstrateTimestamp(
            patch['OrderDateTime'] as String?,
          ),
        );
      };
      fakeApi.onPatchFolder = (remoteId, patch) async {
        patchedFolders[remoteId] = Map<String, dynamic>.from(patch);
        return RemoteTodoFolder(
          id: remoteId,
          name: patch['Name'] as String? ?? 'List',
          parentFolderGroupId: patch['ParentFolderGroupId'] as String?,
          orderDateTime: parseSubstrateTimestamp(
            patch['OrderDateTime'] as String?,
          ),
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_reorder_sync',
        api: fakeApi,
      );

      await h.container.read(syncProvider.notifier).syncNow();

      final homePresenter = h.container.read(homeViewPresenterProvider);
      var state = h.container.read(todoProvider);
      var entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      expect(entries.map((e) => e.stableKey).toList(), [
        'list_${state.lists.firstWhere((l) => l.remoteId == 'rf-alpha').id}',
        'group_${state.groups.first.id}',
        'list_${state.lists.firstWhere((l) => l.remoteId == 'rf-beta').id}',
      ]);

      homePresenter.reorderTopLevelEntries(entries, 0, 2);
      state = h.container.read(todoProvider);
      entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      final alpha = state.lists.firstWhere((l) => l.remoteId == 'rf-alpha');
      final beta = state.lists.firstWhere((l) => l.remoteId == 'rf-beta');
      expect(alpha.orderDateTime!.isBefore(beta.orderDateTime!), isTrue);
      expect(entries.map((e) => e.stableKey).toList(), [
        'group_${state.groups.first.id}',
        'list_${beta.id}',
        'list_${alpha.id}',
      ]);

      homePresenter.reorderTopLevelEntries(entries, 1, 0);
      state = h.container.read(todoProvider);
      final workGroupEntry = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      ).whereType<HomeGroupEntry>().single;
      homePresenter.reorderGroupLists(
        workGroupEntry.group.id,
        workGroupEntry.lists,
        1,
        0,
      );
      state = h.container.read(todoProvider);
      entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      homePresenter.reorderTopLevelEntries(entries, 1, 0);

      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedGroups['rg-work']?['OrderDateTime'], isNotNull);
      expect(patchedGroups['rg-work']?['Name'], 'Work Group');
      expect(patchedFolders['rf-alpha']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-alpha']?['Name'], 'Alpha');
      expect(patchedFolders['rf-beta']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-beta']?['Name'], 'Beta');
      expect(patchedFolders['rf-m2']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-m2']?['Name'], 'Member 2');
      expect(patchedFolders['rf-m1']?['OrderDateTime'], isNull);

      state = h.container.read(todoProvider);
      final syncedM1 = state.lists.firstWhere((l) => l.remoteId == 'rf-m1');
      final syncedM2 = state.lists.firstWhere((l) => l.remoteId == 'rf-m2');
      expect(syncedM2.orderDateTime!.isAfter(syncedM1.orderDateTime!), isTrue);
    });

    test('Task manual reorder pushes OrderDateTime / CommittedOrder cleanly without Reminder or stale ParentFolderId, retries 412 conflicts, and sends ParentFolderId on cross-list move', () async {
      final today = DateTime.now();
      final patchedPayloads = <String, List<Map<String, dynamic>>>{};
      final patchedChangeKeys = <String, List<String?>>{};
      var return412Once = true;

      final tWide1 = DateTime.utc(2026, 11, 22, 12);
      final tWide2 = DateTime.utc(2026, 11, 22, 10);
      final tTightBase = DateTime.utc(2026, 11, 22, 9, 0, 10);
      final tTightSecond = DateTime.utc(2026, 11, 22, 9, 0, 0);

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
                RemoteTodoFolder(id: 'rf-work', name: 'Work'),
              ],
              deltaLink: 'dl-folders-1',
            );
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (dl != null) {
          return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId-2');
        }
        if (folderId == 'rf-default') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-w1',
                'ChangeKey': 'ck-w1',
                'ParentFolderId': 'rf-default',
                'Subject': 'Wide Top',
                'OrderDateTime': formatSubstrateUtcTimestamp(tWide1),
                'CommittedDay': formatDayString(today),
                'CommittedOrder': '2026-11-22T12:00:00.0000000Z',
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-w2',
                'ChangeKey': 'ck-w2',
                'ParentFolderId': 'rf-default',
                'Subject': 'Wide Bottom',
                'OrderDateTime': formatSubstrateUtcTimestamp(tWide2),
              }),
            ],
            deltaLink: 'dl-default-1',
          );
        }
        if (folderId == 'rf-work') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-tight-1',
                'ChangeKey': 'ck-t1',
                'ParentFolderId': 'rf-work',
                'Subject': 'Tight First',
                'OrderDateTime': formatSubstrateUtcTimestamp(tTightBase),
                'DueDate': formatDayString(today),
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-tight-2',
                'ChangeKey': 'ck-t2',
                'ParentFolderId': 'rf-work',
                'Subject': 'Tight Second',
                'OrderDateTime': formatSubstrateUtcTimestamp(tTightSecond),
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-tight-3',
                'ChangeKey': 'ck-t3',
                'ParentFolderId': 'rf-work',
                'Subject': 'Tight Third',
                'OrderDateTime': formatSubstrateUtcTimestamp(tTightSecond),
              }),
            ],
            deltaLink: 'dl-work-1',
          );
        }
        return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
      };
      fakeApi.onGetTask = (taskRemoteId) async => RemoteTodoTask(
        id: taskRemoteId,
        changeKey: 'ck-refreshed',
        parentFolderId: 'rf-default',
        subject: 'Wide Top',
        orderDateTime: tWide1,
      );
      fakeApi.onPatchTask = (taskRemoteId, patch, changeKey) async {
        (patchedChangeKeys[taskRemoteId] ??= []).add(changeKey);
        if (taskRemoteId == 'rt-w1' && return412Once) {
          return412Once = false;
          throw const AppError.network(
            statusCode: 412,
            message: 'Precondition Failed',
          );
        }
        (patchedPayloads[taskRemoteId] ??= []).add(
          Map<String, dynamic>.from(patch),
        );
        return RemoteTodoTask(
          id: taskRemoteId,
          changeKey: 'ck-patched-$taskRemoteId',
          parentFolderId: (patch['ParentFolderId'] as String?) ?? 'rf-default',
          subject: patch['Subject'] as String? ?? 'Task',
          orderDateTime: parseSubstrateTimestamp(
            patch['OrderDateTime'] as String?,
          ),
          committedDay: parseSubstrateDay(patch['CommittedDay']),
          committedOrder: parseSubstrateTimestamp(
            patch['CommittedOrder'] as String?,
          ),
        );
      };

      final h = await createSyncTestHarness(
        accountId: 'acct_task_push_order',
        api: fakeApi,
      );

      await h.container.read(syncProvider.notifier).syncNow();

      final presenter = h.container.read(tasksViewPresenterProvider);
      final detailPresenter = h.container.read(detailViewPresenterProvider);

      // 1) Wide-gap single move in Tasks (rt-w1 from index 0 to index 1)
      h.container.read(todoProvider.notifier).selectList('tasks');
      final tasksVisible = h.container
          .read(todoProvider)
          .tasksForList(h.container.read(todoProvider).selectedList);
      expect(tasksVisible.map((t) => t.remoteId), ['rt-w1', 'rt-w2']);
      presenter.reorderActiveTasks(tasksVisible, 0, 1);

      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads.keys, contains('rt-w1'));
      expect(patchedPayloads.containsKey('rt-w2'), isFalse);
      expect(patchedChangeKeys['rt-w1'], [null, 'ck-refreshed']);
      final w1Patch = patchedPayloads['rt-w1']!.single;
      expect(w1Patch.keys.toSet(), {'Subject', 'OrderDateTime'});
      expect(w1Patch['Subject'], 'Wide Top');
      expect(w1Patch['OrderDateTime'], isNotNull);
      final w1Updated = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-w1');
      expect(w1Updated.changeKey, 'ck-patched-rt-w1');
      expect(w1Updated.orderDateTime!.isBefore(tWide2), isTrue);

      // 2) Tight <= 16s / equal timestamps in Work custom list trigger full re-space
      patchedPayloads.clear();
      patchedChangeKeys.clear();
      final workList = h.container
          .read(todoProvider)
          .lists
          .firstWhere((l) => l.remoteId == 'rf-work');
      h.container.read(todoProvider.notifier).selectList(workList.id);
      final workVisible = h.container.read(todoProvider).tasksForList(workList);
      expect(workVisible.map((t) => t.remoteId), [
        'rt-tight-1',
        'rt-tight-2',
        'rt-tight-3',
      ]);
      presenter.reorderActiveTasks(workVisible, 2, 1);

      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads.containsKey('rt-tight-1'), isFalse);
      expect(patchedPayloads.containsKey('rt-tight-2'), isTrue);
      expect(patchedPayloads.containsKey('rt-tight-3'), isTrue);
      expect(patchedChangeKeys['rt-tight-2'], [null]);
      expect(patchedChangeKeys['rt-tight-3'], [null]);
      for (final pList in patchedPayloads.values) {
        expect(pList.single.keys.toSet(), {'Subject', 'OrderDateTime'});
      }
      final afterTight = h.container
          .read(todoProvider)
          .tasksForList(
            h.container
                .read(todoProvider)
                .lists
                .firstWhere((l) => l.remoteId == 'rf-work'),
          );
      expect(afterTight.map((t) => t.remoteId), [
        'rt-tight-1',
        'rt-tight-3',
        'rt-tight-2',
      ]);
      expect(
        afterTight[0].orderDateTime!.isAfter(afterTight[1].orderDateTime!),
        isTrue,
      );
      expect(
        afterTight[1].orderDateTime!.isAfter(afterTight[2].orderDateTime!),
        isTrue,
      );

      // 3) Reorder due-today uncommitted task above committed task in My Day
      patchedPayloads.clear();
      patchedChangeKeys.clear();
      h.container.read(todoProvider.notifier).selectList('my_day');
      final myDayVisible = h.container
          .read(todoProvider)
          .tasksForList(h.container.read(todoProvider).selectedList);
      expect(myDayVisible.map((t) => t.remoteId), ['rt-w1', 'rt-tight-1']);
      presenter.reorderActiveTasks(myDayVisible, 1, 0);

      final tightAfterLocalReorder = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-tight-1');
      expect(tightAfterLocalReorder.myDayDate, isNotNull);
      expect(
        TodoNotifier.isSameDay(tightAfterLocalReorder.myDayDate!, today),
        isTrue,
      );

      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-tight-1'], isNotNull);
      expect(patchedChangeKeys['rt-tight-1'], [null]);
      final tightMyDayPatch = patchedPayloads['rt-tight-1']!.single;
      expect(tightMyDayPatch.keys.toSet(), {
        'Subject',
        'CommittedDay',
        'CommittedOrder',
      });
      expect(tightMyDayPatch['Subject'], 'Tight First');
      expect(tightMyDayPatch['CommittedDay'], formatDayString(today));
      expect(tightMyDayPatch['CommittedOrder'], isNotNull);
      final syncedMyDay = h.container
          .read(todoProvider)
          .tasksForList(h.container.read(todoProvider).selectedList);
      expect(syncedMyDay.map((t) => t.remoteId), ['rt-tight-1', 'rt-w1']);

      // 3b) Reorder already-committed task back to top in My Day
      patchedPayloads.clear();
      patchedChangeKeys.clear();
      presenter.reorderActiveTasks(syncedMyDay, 1, 0);
      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-w1'], isNotNull);
      expect(patchedChangeKeys['rt-w1'], [null]);
      final w1MyDayPatch = patchedPayloads['rt-w1']!.single;
      expect(w1MyDayPatch.keys.toSet(), {
        'Subject',
        'CommittedDay',
        'CommittedOrder',
      });
      expect(w1MyDayPatch['Subject'], 'Wide Top');
      expect(w1MyDayPatch['CommittedDay'], formatDayString(today));
      expect(w1MyDayPatch['CommittedOrder'], isNotNull);

      // 4) Cross-list move includes ParentFolderId; subsequent same-folder edit omits it
      patchedPayloads.clear();
      final w2 = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-w2');
      detailPresenter.moveTaskToList(w2.id, workList.id);
      await h.container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-w2']!.single['ParentFolderId'], 'rf-work');

      patchedPayloads.clear();
      detailPresenter.updateTaskTitle(w2.id, 'Wide Bottom Renamed');
      await h.container.read(syncProvider.notifier).syncNow();

      expect(
        patchedPayloads['rt-w2']!.single.containsKey('ParentFolderId'),
        isFalse,
      );
      expect(
        patchedPayloads['rt-w2']!.single['Subject'],
        'Wide Bottom Renamed',
      );
    });
  });
}
