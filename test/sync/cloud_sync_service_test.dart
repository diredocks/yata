import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_local_storage.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/core/result/app_result.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/sync/cloud_sync_service.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/todo_wire_codecs.dart';
import 'package:yata/tasksview/tasks_action_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CloudSyncService', () {
    test('pulls remote groups, emoji/theme folders, tasks, HTML notes, MyDay, recurrence, settings and deletes via delta', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_1');
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );

      final fakeApi = FakeSubstrateApi();
      fakeApi.remoteSettings.addAll({
        TodoSettingKeys.confirmOnDelete: 'false',
        TodoSettingKeys.smartListPlannedDueDateFilter: '1', // today
        TodoSettingKeys.smartListPlannedGroupType: '2', // byList
        TodoSettingKeys.myDayThemeColor: 'photo_tv_tower',
        TodoSettingKeys.smartListStarredSortType: '6', // importance
        TodoSettingKeys.smartListStarredSortAscending: 'false',
      });

      var folderDeltaStep = 0;
      fakeApi.onFetchGroupsDelta = (dl) => DeltaPageResult(
        items: [
          RemoteFolderGroup(
            id: 'rg-work',
            name: 'Work Group',
            orderDateTime: DateTime.utc(2026, 11, 22, 10),
          ),
        ],
        deltaLink: 'dl-groups-v1',
      );
      fakeApi.onFetchFoldersDelta = (dl) {
        folderDeltaStep += 1;
        if (folderDeltaStep == 1) {
          return DeltaPageResult(
            items: [
              const RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
                themeColor: 'light_purple',
              ),
              const RemoteTodoFolder(
                id: 'rf-flagged',
                name: 'Flagged Emails',
                folderType: 'com.microsoft.outlook.email.flagged',
              ),
              const RemoteTodoFolder(
                id: 'rf-planner',
                name: 'Assigned to me',
                folderType: 'com.microsoft.planner',
              ),
              RemoteTodoFolder(
                id: 'rf-shop',
                name: '🛒 Groceries',
                parentFolderGroupId: 'rg-work',
                themeColor: 'photo_beach',
                themeBackground: 'mountain',
                showCompletedTasks: false,
                sortOption: TaskSortOption.dueDate,
                sortAscending: true,
                orderDateTime: DateTime.utc(2026, 11, 22, 9),
              ),
            ],
            deltaLink: 'dl-folders-v1',
          );
        }
        return const DeltaPageResult(
          items: [RemoteTodoFolder(id: 'rf-shop', name: '', isDeleted: true)],
          deltaLink: 'dl-folders-v2',
        );
      };

      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-shop') {
          final today = DateTime.now();
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-milk',
                'ChangeKey': 'ck-milk-1',
                'ParentFolderId': 'rf-shop',
                'Subject': 'Buy milk',
                'Body': {
                  'Content': '<p>Organic<br/>2 cartons</p>',
                  'ContentType': 'HTML',
                },
                'DueDate': formatDayString(today),
                'CommittedDay': formatDayString(today),
                'CommittedOrder': '2026-11-22T12:00:00.0000000Z',
                'Importance': 'High',
                'Status': 'NotStarted',
                'Recurrence': {
                  'RecurrenceType': 'WeekDays',
                  'IntervalType': 'Weeks',
                  'Interval': 1,
                  'WeekDays': [
                    'Monday',
                    'Tuesday',
                    'Wednesday',
                    'Thursday',
                    'Friday',
                  ],
                },
                'Subtasks': [
                  {
                    'Id': 'rs-1',
                    'Subject': 'Check fridge',
                    'IsCompleted': true,
                  },
                ],
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-ignored',
                'ParentFolderId': 'rf-shop',
                'Subject': 'Hidden suggestion',
                'IsIgnored': true,
              }),
            ],
            deltaLink: 'dl-tasks-shop-1',
          );
        }
        return DeltaPageResult(
          items: const [],
          deltaLink: 'dl-tasks-$folderId',
        );
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await container.read(accountLocalStorageProvider).saveAccounts([account]);
      await container
          .read(accountLocalStorageProvider)
          .saveActiveAccountId('acct_1');
      container.invalidate(accountProvider);

      // Sync #1: initial full sync
      await container.read(syncProvider.notifier).syncNow();

      var state = container.read(todoProvider);
      expect(state.confirmBeforeDeleting, isFalse);
      expect(state.plannedDueDateFilter, PlannedDueDateFilter.today);
      expect(state.plannedGroupOption, PlannedGroupOption.byList);

      final myDay = state.lists.firstWhere((l) => l.id == 'my_day');
      expect(myDay.themePhoto, ListThemePhoto.tvTower);
      final important = state.lists.firstWhere((l) => l.id == 'important');
      expect(important.sortOption, TaskSortOption.importance);
      expect(important.sortAscending, isFalse);

      expect(state.groups.length, 1);
      expect(state.groups.first.title, 'Work Group');

      // Special folders are ignored
      expect(
        state.lists.where(
          (l) => l.remoteId == 'rf-flagged' || l.remoteId == 'rf-planner',
        ),
        isEmpty,
      );

      final tasksDefault = state.lists.firstWhere((l) => l.id == 'tasks');
      expect(tasksDefault.remoteId, 'rf-default');
      expect(tasksDefault.themeColor, ListThemeColor.lightPurple);

      final shop = state.lists.firstWhere((l) => l.remoteId == 'rf-shop');
      expect(shop.emoji, '🛒');
      expect(shop.title, 'Groceries');
      expect(shop.groupId, state.groups.first.id);
      expect(shop.themeColor, ListThemeColor.blue);
      expect(shop.themePhoto, ListThemePhoto.beach);
      expect(shop.showCompleted, isFalse);
      expect(state.isCompletedExpanded(shop.id), isFalse);
      expect(shop.sortOption, TaskSortOption.dueDate);

      expect(state.tasks.length, 1);
      final milk = state.tasks.first;
      expect(milk.title, 'Buy milk');
      expect(milk.note, 'Organic\n2 cartons');
      expect(milk.isImportant, isTrue);
      expect(milk.isInMyDay, isTrue);
      expect(milk.recurrence, RecurrenceType.weekdays);
      expect(milk.changeKey, 'ck-milk-1');
      expect(milk.steps.single.title, 'Check fridge');
      expect(milk.steps.single.isCompleted, isTrue);

      // Sync #2: Delta folder deletion removes 'rf-shop' using saved DeltaLink
      expect(storage.settings.loadFoldersDeltaLink(), 'dl-folders-v1');
      await container.read(syncProvider.notifier).syncNow();
      expect(fakeApi.callLog, contains('GET taskfolders(dl-folders-v1)'));
      state = container.read(todoProvider);
      expect(state.lists.where((l) => l.remoteId == 'rf-shop'), isEmpty);
      expect(state.tasks, isEmpty);
    });

    test(
      'ungroups folders before deleting folder group (prevents 9018)',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final tokenStorage = AuthTokenStorage(prefs);
        await tokenStorage.saveTokens(
          'acct_1',
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: 'cid1',
          ),
        );
        final account = MicrosoftAccount(
          id: 'acct_1',
          displayName: 'Alice',
          email: 'alice@outlook.com',
          createdAt: DateTime(2026, 11, 22),
          microsoftUserId: 'cid1',
        );
        await AccountLocalStorage(prefs).saveAccounts([account]);
        await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

        final storage = _session(prefs, 'acct_1');
        await storage.repository.saveGroups(const [
          ListGroup(id: 'grp_1', title: 'Work', remoteId: 'rg-1'),
        ]);
        await storage.repository.saveLists([
          ...defaultSmartLists().map(
            (l) => l.smartType == SmartListType.tasks
                ? l.copyWith(remoteId: 'rf-default')
                : l,
          ),
          const TodoList(
            id: 'list_1',
            title: 'Project',
            groupId: 'grp_1',
            remoteId: 'rf-1',
          ),
        ]);

        final fakeApi = FakeSubstrateApi();
        final remoteFolders = {'rf-1': 'rg-1'};
        fakeApi.onPatchFolder = (id, patch) async {
          if (patch.containsKey('ParentFolderGroupId') &&
              patch['ParentFolderGroupId'] == null) {
            remoteFolders.remove(id);
          }
          return RemoteTodoFolder(id: id, name: 'Project');
        };
        fakeApi.onDeleteGroup = (groupId) async {
          if (remoteFolders.values.contains(groupId)) {
            throw const AppError.network(
              statusCode: 400,
              code: 'FolderGroupNotEmpty',
              message: 'Group not empty',
            );
          }
        };

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
        );
        addTearDown(container.dispose);

        // Delete group locally: ungroups 'list_1' and queues 'rg-1' deletion.
        container.read(homeViewPresenterProvider).deleteGroup('grp_1');

        await container.read(syncProvider.notifier).syncNow();
        expect(container.read(syncProvider).status, SyncStatus.success);
        final patchIdx = fakeApi.callLog.indexWhere(
          (c) => c.startsWith('PATCH taskfolders/rf-1'),
        );
        final delIdx = fakeApi.callLog.indexOf('DELETE foldergroups/rg-1');
        expect(patchIdx, greaterThanOrEqualTo(0));
        expect(delIdx, greaterThan(patchIdx));
      },
    );

    test('handles 409 If-Match conflict retry, 410 delta reset, and cross-folder move safety', () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final storage = _session(prefs, 'acct_1');
      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-a')
              : l,
        ),
        const TodoList(id: 'list_b', title: 'List B', remoteId: 'rf-b'),
      ]);
      await storage.repository.saveTasks([
        TaskItem(
          id: 't_1',
          listId: 'tasks',
          title: 'Initial',
          createdAt: DateTime(2026, 11, 22),
          remoteId: 'rt-1',
          changeKey: 'ck-stale',
        ),
      ]);
      await storage.settings.saveTaskDeltaLinks({'rf-a': 'dl-expired'});

      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
        items: [
          RemoteTodoFolder(id: 'rf-a', name: 'Tasks', isDefaultFolder: true),
          RemoteTodoFolder(id: 'rf-b', name: 'List B'),
        ],
        deltaLink: 'dl-folders-ab',
      );
      var patchAttempts = 0;
      fakeApi.onPatchTask = (id, patch, ck) async {
        patchAttempts += 1;
        if (ck == 'ck-stale') {
          throw const AppError.network(
            statusCode: 409,
            code: 'ErrorIrresolvableConflict',
            message: 'stale',
          );
        }
        expect(ck, 'ck-fresh');
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-v3',
          parentFolderId: 'rf-a',
          subject: patch['Subject'] as String? ?? 'Updated',
        );
      };
      fakeApi.onGetTask = (id) async => RemoteTodoTask(
        id: id,
        changeKey: 'ck-fresh',
        parentFolderId: 'rf-a',
        subject: 'Remote',
      );

      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-a' && dl == 'dl-expired') {
          throw const AppError.network(
            statusCode: 410,
            code: 'SyncStateInvalid',
            message: 'expired',
          );
        }
        if (folderId == 'rf-a') {
          // Cross-folder move: rt-1 deleted from Folder A while active in Folder B
          return const DeltaPageResult(
            items: [RemoteTodoTask(id: 'rt-1', subject: '', isDeleted: true)],
            deltaLink: 'dl-a-fresh',
          );
        }
        if (folderId == 'rf-b') {
          return const DeltaPageResult(
            items: [
              RemoteTodoTask(
                id: 'rt-1',
                changeKey: 'ck-v4',
                parentFolderId: 'rf-b',
                subject: 'Moved Cleanly',
              ),
            ],
            deltaLink: 'dl-b-fresh',
          );
        }
        return const DeltaPageResult(items: []);
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Modify task locally so PATCH triggers with stale ChangeKey
      container
          .read(todoProvider.notifier)
          .commit(
            container
                .read(todoProvider)
                .copyWith(
                  tasks: [
                    container
                        .read(todoProvider)
                        .tasks
                        .first
                        .copyWith(title: 'Local Edit'),
                  ],
                ),
          );

      await container.read(syncProvider.notifier).syncNow();
      expect(patchAttempts, 2);
      expect(fakeApi.callLog, contains('GET tasks/rt-1'));
      // 410 recovered full sync
      expect(fakeApi.callLog, contains('GET tasks(rf-a,null)'));
      expect(storage.settings.loadTaskDeltaLinks()['rf-a'], 'dl-a-fresh');

      // Moved task MUST survive and belong to 'list_b'
      final tasks = container.read(todoProvider).tasks;
      expect(tasks.length, 1);
      expect(tasks.first.listId, 'list_b');
      expect(tasks.first.title, 'Moved Cleanly');
    });

    test('preserves concurrent local edits made during in-flight sync and syncs reorder OrderDateTime', () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final storage = _session(prefs, 'acct_1');
      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
      ]);
      final tOld = DateTime.utc(2026, 11, 22, 10);
      final tNew = DateTime.utc(2026, 11, 22, 12);
      await storage.repository.saveTasks([
        TaskItem(
          id: 't_1',
          listId: 'tasks',
          title: 'Task 1',
          createdAt: tOld,
          orderDateTime: tNew,
          remoteId: 'rt-1',
          changeKey: 'ck-1',
        ),
        TaskItem(
          id: 't_2',
          listId: 'tasks',
          title: 'Task 2',
          createdAt: tOld,
          orderDateTime: tOld,
          remoteId: 'rt-2',
          changeKey: 'ck-2',
        ),
      ]);

      final fakeApi = FakeSubstrateApi();
      final patchStarted = Completer<void>();
      final allowPatchFinish = Completer<void>();
      Map<String, dynamic>? capturedOrderPatch;

      fakeApi.onPatchTask = (id, patch, ck) async {
        capturedOrderPatch = Map<String, dynamic>.from(patch);
        if (!patchStarted.isCompleted) patchStarted.complete();
        await allowPatchFinish.future;
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-patched',
          parentFolderId: 'rf-default',
          subject: patch['Subject'] as String? ?? 'Task 1',
          orderDateTime: patch['OrderDateTime'] != null
              ? parseSubstrateTimestamp(patch['OrderDateTime'] as String)
              : tOld,
        );
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Reorder t_1 below t_2
      container.read(todoProvider.notifier).selectList('tasks');
      final initialOrdered = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(initialOrdered.first.id, 't_1');
      container
          .read(tasksViewPresenterProvider)
          .reorderActiveTasks(initialOrdered, 0, 1);

      final syncFuture = container.read(syncProvider.notifier).syncNow();
      await patchStarted.future;

      // Make concurrent local edit to t_1 while sync is in flight
      container
          .read(todoProvider.notifier)
          .commit(
            container
                .read(todoProvider)
                .copyWith(
                  tasks: [
                    for (final t in container.read(todoProvider).tasks)
                      if (t.id == 't_1')
                        t.copyWith(title: 'Edited Mid-Sync')
                      else
                        t,
                  ],
                ),
          );

      allowPatchFinish.complete();
      await syncFuture;

      expect(capturedOrderPatch?['OrderDateTime'], isNotNull);
      final updatedT1 = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_1');
      expect(updatedT1.title, 'Edited Mid-Sync');
      expect(updatedT1.changeKey, 'ck-patched');
      expect(storage.repository.loadDirtyTaskIds(), contains('t_1'));
    });

    test('realtime ignores KeepAlive and own RequestId, triggers sync on remote event, and handles settings/copy/reorder', () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final fakeApi = FakeSubstrateApi();
      addTearDown(fakeApi.realtimeController.close);
      fakeApi.ownRequestIds.add('my-req-id');
      var taskFetches = 0;
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        taskFetches += 1;
        return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncProvider);
      await pumpEventQueue();
      expect(fakeApi.callLog, contains('GET realtime'));

      // Own request echo & KeepAlive must NOT trigger sync
      fakeApi.realtimeController.add(const RealtimeEvent(type: 'KeepAlive'));
      fakeApi.realtimeController.add(
        const RealtimeEvent(
          id: 't1',
          type: 'Task',
          operation: 'Updated',
          requestId: 'my-req-id',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(taskFetches, 0);

      // External remote event triggers debounced sync
      fakeApi.realtimeController.add(
        const RealtimeEvent(
          id: 't1',
          type: 'Task',
          operation: 'Created',
          requestId: 'other-device-req',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(taskFetches, greaterThanOrEqualTo(1));

      // Changing settings marks dirty keys and pushes them cleanly
      container.read(settingsPresenterProvider).setConfirmBeforeDeleting(false);
      container
          .read(tasksViewPresenterProvider)
          .setPlannedDueDateFilter(PlannedDueDateFilter.thisWeek);
      container
          .read(tasksViewPresenterProvider)
          .setPlannedGroupOption(PlannedGroupOption.byList);

      // Copy / duplicate clears remoteId and changeKey
      final originalTask = TaskItem(
        id: 't_src',
        listId: 'tasks',
        title: 'Source',
        createdAt: DateTime(2026, 11, 22),
        remoteId: 'rt-src',
        changeKey: 'ck-src',
        steps: const [TaskStep(id: 's_1', title: 'Step 1', remoteId: 'rs-src')],
      );
      container
          .read(todoProvider.notifier)
          .commit(container.read(todoProvider).copyWith(tasks: [originalTask]));
      container.read(tasksActionPresenterProvider).batchCopyToList({
        't_src',
      }, 'tasks');
      final copied = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id != 't_src');
      expect(copied.remoteId, isNull);
      expect(copied.changeKey, isNull);
      expect(copied.steps.single.remoteId, isNull);

      await container.read(syncProvider.notifier).syncNow();
      expect(fakeApi.remoteSettings[TodoSettingKeys.confirmOnDelete], 'false');
      expect(
        fakeApi.remoteSettings[TodoSettingKeys.smartListPlannedDueDateFilter],
        '3',
      );
      expect(
        fakeApi.remoteSettings[TodoSettingKeys.smartListPlannedGroupType],
        '2',
      );
    });

    test('retries 401 with refreshed token and reports requiresRelogin when refresh fails', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_1');
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'expired-tok',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );

      final fakeApi = FakeSubstrateApi();
      var attempts = 0;
      fakeApi.onFetchFoldersDelta = (dl) {
        attempts += 1;
        if (attempts == 1) {
          throw const AppError.auth(
            message: 'Unauthorized',
            requiresReauth: true,
          );
        }
        return const DeltaPageResult(items: []);
      };

      final service = CloudSyncService(
        authClient: FakeAuthClient(),
        todoApi: fakeApi,
        tokenStorage: tokenStorage,
      );
      final notifierContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(notifierContainer.dispose);

      final outcome = await service
          .syncAccount(
            account: account,
            currentState: notifierContainer.read(todoProvider),
            repository: storage.repository,
            settings: storage.settings,
            idGenerator: notifierContainer.read(todoProvider.notifier).nextId,
          )
          .fold(
            (outcome) => outcome,
            (error) => fail('unexpected sync failure: ${error.describe()}'),
          );
      expect(attempts, 2);
      expect(outcome.syncedAt, isNotNull);

      // Now test unrecoverable refresh -> SyncStatus.requiresRelogin
      final failingAuth = FakeAuthClient(
        onRefreshTokens: (_) async => throw const AppError.auth(
          message: 'Token revoked',
          code: 'invalid_grant',
          requiresReauth: true,
        ),
      );
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'old',
          refreshToken: 'bad-rt',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(failingAuth),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container2.dispose);

      await container2.read(syncProvider.notifier).syncNow();
      expect(container2.read(syncProvider).status, SyncStatus.requiresRelogin);
      expect(container2.read(syncProvider).requiresRelogin, isTrue);
    });

    test(
      'backfills missing Microsoft displayName and avatar during syncNow',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final tokenStorage = AuthTokenStorage(prefs);
        await tokenStorage.saveTokens(
          'acct_bf',
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-bf',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: 'cidbf',
          ),
        );
        final account = MicrosoftAccount(
          id: 'acct_bf',
          displayName: 'Microsoft Account',
          email: '',
          createdAt: DateTime(2026, 11, 22),
          microsoftUserId: 'cidbf',
        );
        await AccountLocalStorage(prefs).saveAccounts([account]);
        await AccountLocalStorage(prefs).saveActiveAccountId('acct_bf');

        final avatar = base64Encode([0xFF, 0xD8, 0xFF, 0xE0]);
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(
              FakeAuthClient(
                onFetchUserProfile: (cid, rt, _) async => MicrosoftUserProfile(
                  id: cid,
                  displayName: 'Leo Zhang',
                  email: 'leo@outlook.com',
                  avatarBase64: avatar,
                ),
              ),
            ),
            microsoftTodoApiProvider.overrideWithValue(FakeSubstrateApi()),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
        );
        addTearDown(container.dispose);

        await container.read(syncProvider.notifier).syncNow();
        expect(container.read(syncProvider).status, SyncStatus.success);

        final updated =
            container.read(accountProvider).activeAccount as MicrosoftAccount?;
        expect(updated, isNotNull);
        expect(updated!.displayName, 'Leo Zhang');
        expect(updated.email, 'leo@outlook.com');
        expect(updated.avatarBase64, avatar);
      },
    );

    test('recovers from ErrorItemNotFound (404) on deleted/missing task PATCH and clears pending deletes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const accountId = 'acct_404';
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        accountId,
        MicrosoftAuthTokens(
          accessToken: 'at',
          refreshToken: 'rt',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid404',
        ),
      );
      final account = MicrosoftAccount(
        id: accountId,
        displayName: 'User',
        email: 'user@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid404',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(accountId);

      final session = _session(prefs, accountId);
      final repo = session.repository;
      final now = DateTime.utc(2026, 4, 15, 10, 0);

      final defaultTasksList = TodoList(
        id: 'tasks',
        title: 'Tasks',
        smartType: SmartListType.tasks,
        remoteId: 'rf-default',
      );
      // Task 1: present in both pendingDeletedTaskRemoteIds AND dirty tasks
      // with the same remoteId -> should NOT be patched or recreated.
      final deletedGhostTask = TaskItem(
        id: 't-ghost',
        listId: 'tasks',
        title: 'Ghost deleted task',
        remoteId: 'rt-ghost',
        changeKey: 'ck-ghost',
        createdAt: now,
        updatedAt: now,
      );
      // Task 2: dirty task whose remoteId returns 404 on PATCH -> should
      // recreate via createTask and recreate its steps via createStep.
      final missingRemoteTask = TaskItem(
        id: 't-recreate',
        listId: 'tasks',
        title: 'Edited after remote delete',
        remoteId: 'rt-missing',
        changeKey: 'ck-missing',
        steps: const [TaskStep(id: 's1', title: 'Step 1', remoteId: 'rs-old')],
        createdAt: now,
        updatedAt: now,
      );

      await repo.saveLists([defaultTasksList]);
      await repo.saveTasks([deletedGhostTask, missingRemoteTask]);
      await repo.savePendingDeletedTaskRemoteIds(['rt-ghost']);
      await repo.saveDirtyTaskIds({'t-ghost', 't-recreate'});

      final fakeApi = FakeSubstrateApi()
        ..onDeleteTask = (taskRemoteId) async {
          if (taskRemoteId == 'rt-ghost') {
            throw const AppError.notFound(
              message: 'Item not found',
              id: 'ErrorItemNotFound',
            );
          }
        }
        ..onPatchTask = (taskRemoteId, patch, changeKey) async {
          if (taskRemoteId == 'rt-missing') {
            throw const AppError.notFound(
              message: 'Item not found',
              id: 'ErrorItemNotFound',
            );
          }
          throw StateError('Unexpected PATCH for $taskRemoteId');
        };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncNow();

      expect(container.read(syncProvider).status, SyncStatus.success);
      expect(repo.loadPendingDeletedTaskRemoteIds(), isEmpty);
      expect(repo.loadDirtyTaskIds(), isEmpty);

      // Ghost task was never patched or recreated.
      expect(
        fakeApi.callLog.any((c) => c.contains('PATCH tasks/rt-ghost')),
        isFalse,
      );
      expect(
        fakeApi.callLog.any((c) => c.contains('Ghost deleted task')),
        isFalse,
      );

      // Missing task was recreated and its step was recreated on the new task.
      expect(
        fakeApi.callLog,
        contains(
          'POST taskfolders/rf-default/tasks Edited after remote delete',
        ),
      );
      final recreated = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't-recreate');
      expect(recreated.remoteId, isNot('rt-missing'));
      expect(recreated.steps.single.remoteId, isNot('rs-old'));
    });

    test('clearing photo background to solid color sends ThemeBackground=mountain and stays solid after delta sync', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final account = Account.microsoft(
        id: 'acct_theme',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_theme');

      final storage = _session(prefs, 'acct_theme');
      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
        const TodoList(
          id: 'list_shop',
          title: 'Shopping',
          remoteId: 'rf-shop',
          themeColor: ListThemeColor.rose,
          themePhoto: null,
        ),
      ]);
      await storage.repository.saveDirtyListIds({'list_shop'});

      final fakeApi = FakeSubstrateApi();
      var serverThemeColor = 'dark_blue';
      var serverThemeBackground = 'photo_beach';

      fakeApi.onPatchFolder = (id, patch) async {
        expect(id, 'rf-shop');
        expect(patch['ThemeColor'], 'dark_rose');
        // Substrate ignores null ThemeBackground; clearing requires 'mountain'.
        expect(patch['ThemeBackground'], 'mountain');
        serverThemeColor = patch['ThemeColor'] as String;
        if (patch['ThemeBackground'] != null) {
          serverThemeBackground = patch['ThemeBackground'] as String;
        }
        return RemoteTodoFolder(
          id: id,
          name: 'Shopping',
          themeColor: serverThemeColor,
          themeBackground: serverThemeBackground,
        );
      };
      fakeApi.onFetchFoldersDelta = (dl) => DeltaPageResult(
        items: [
          const RemoteTodoFolder(
            id: 'rf-default',
            name: 'Tasks',
            isDefaultFolder: true,
          ),
          RemoteTodoFolder(
            id: 'rf-shop',
            name: 'Shopping',
            themeColor: serverThemeColor,
            themeBackground: serverThemeBackground,
          ),
        ],
        deltaLink: 'dl-folders-1',
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncNow();

      final syncedShop = container
          .read(todoProvider)
          .lists
          .firstWhere((l) => l.id == 'list_shop');
      expect(syncedShop.themeColor, ListThemeColor.rose);
      expect(syncedShop.themePhoto, isNull);
    });

    test('setting photo background sends photo_* in both ThemeColor and ThemeBackground for MS To Do compatibility', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final account = Account.microsoft(
        id: 'acct_photo',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_photo');

      final storage = _session(prefs, 'acct_photo');
      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
        const TodoList(
          id: 'list_shop',
          title: 'Shopping',
          remoteId: 'rf-shop',
          themeColor: ListThemeColor.blue,
          themePhoto: ListThemePhoto.beach,
        ),
      ]);
      await storage.repository.saveDirtyListIds({'list_shop'});

      final fakeApi = FakeSubstrateApi();
      fakeApi.onPatchFolder = (id, patch) async {
        expect(id, 'rf-shop');
        expect(patch['ThemeColor'], 'photo_beach');
        expect(patch['ThemeBackground'], 'mountain');
        return const RemoteTodoFolder(
          id: 'rf-shop',
          name: 'Shopping',
          themeColor: 'photo_beach',
          themeBackground: 'mountain',
        );
      };
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
        items: [
          RemoteTodoFolder(
            id: 'rf-default',
            name: 'Tasks',
            isDefaultFolder: true,
          ),
          RemoteTodoFolder(
            id: 'rf-shop',
            name: 'Shopping',
            themeColor: 'photo_beach',
            themeBackground: 'mountain',
          ),
        ],
        deltaLink: 'dl-folders-photo',
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncNow();

      final syncedShop = container
          .read(todoProvider)
          .lists
          .firstWhere((l) => l.id == 'list_shop');
      expect(syncedShop.themePhoto, ListThemePhoto.beach);
    });

    test('realtime Task payload directly updates OrderDateTime and CommittedOrder without fetching delta, preserves missing Subtasks, and respects dirty tasks', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_rt_payload');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_rt_payload',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_rt_payload',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      final today = DateTime.now();
      final tOld = DateTime.utc(2026, 11, 22, 8);
      final tMid = DateTime.utc(2026, 11, 22, 10);
      final tNewest = DateTime.utc(2026, 11, 22, 14);

      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
      ]);
      await storage.repository.saveTasks([
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
      ]);
      await storage.repository.saveDirtyTaskIds({'t_3'});

      final fakeApi = FakeSubstrateApi();
      addTearDown(fakeApi.realtimeController.close);
      var taskFetches = 0;
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        taskFetches += 1;
        return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(true),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncProvider);
      await pumpEventQueue();
      expect(fakeApi.callLog, contains('GET realtime'));

      final initialMutationVersion = container
          .read(todoProvider)
          .mutationVersion;

      // Remote Task/Updated reorder for t_2 with full Payload (both OrderDateTime and CommittedOrder).
      fakeApi.realtimeController.add(
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

      // Remote update for t_1 without Subtasks key preserves existing steps.
      fakeApi.realtimeController.add(
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

      // Remote update for dirty task t_3 only updates ChangeKey, preserving local edits.
      fakeApi.realtimeController.add(
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

      final todoState = container.read(todoProvider);
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
      expect(storage.repository.loadDirtyTaskIds(), ['t_3']);
    });

    test('realtime Task/Deleted removes non-dirty task and mid-sync Task/Updated is deferred without marking dirty', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_rt_defer');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_rt_defer',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_rt_defer',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      final tOld = DateTime.utc(2026, 11, 22, 8);
      final tMid = DateTime.utc(2026, 11, 22, 10);
      final tNew = DateTime.utc(2026, 11, 22, 16);

      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
      ]);
      await storage.repository.saveTasks([
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
      ]);
      await storage.settings.saveTaskDeltaLinks({'rf-default': 'dl-1'});

      final taskFetchStarted = Completer<void>();
      final allowTaskFetchFinish = Completer<void>();
      final fakeApi = _BlockingTasksDeltaApi(
        taskFetchStarted,
        allowTaskFetchFinish,
      );
      addTearDown(fakeApi.realtimeController.close);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(true),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncProvider);
      await pumpEventQueue();

      // Immediate remote delete via realtime.
      fakeApi.realtimeController.add(
        const RealtimeEvent(
          id: 'rt-del',
          type: 'Task',
          operation: 'Deleted',
          requestId: 'other-device-req',
        ),
      );
      await pumpEventQueue();
      expect(
        container.read(todoProvider).tasks.any((t) => t.id == 't_del'),
        isFalse,
      );

      // Start a delta sync that blocks during Phase 10b and returns [] (omitting reorder).
      final syncFuture = container.read(syncProvider.notifier).syncNow();
      await taskFetchStarted.future;

      // Mid-sync realtime Task/Updated reorder arrives and must be deferred until sync ends.
      fakeApi.realtimeController.add(
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

      final state = container.read(todoProvider);
      final tasksList = state.lists.firstWhere((l) => l.id == 'tasks');
      expect(state.tasksForList(tasksList).map((t) => t.id).toList(), [
        't_2',
        't_1',
      ]);
      expect(
        state.tasks.firstWhere((t) => t.id == 't_2').orderDateTime,
        tNew,
      );
      expect(storage.repository.loadDirtyTaskIds(), isEmpty);
    });

    test('forceFullSync bypasses saved taskDeltaLinks, syncs reordered OrderDateTime, and prunes stale deleted tasks while keeping moved and dirty tasks', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_force_full');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_force_full',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_force_full',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      final t03 = DateTime.utc(2026, 11, 22, 3);
      final t04 = DateTime.utc(2026, 11, 22, 4);
      final t05 = DateTime.utc(2026, 11, 22, 5);
      final t10 = DateTime.utc(2026, 11, 22, 10);
      final t15 = DateTime.utc(2026, 11, 22, 15);
      final t20 = DateTime.utc(2026, 11, 22, 20);
      final t30 = DateTime.utc(2026, 11, 22, 23);

      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
        const TodoList(id: 'list_b', title: 'List B', remoteId: 'rf-b'),
      ]);
      await storage.repository.saveTasks([
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
      ]);
      await storage.settings.saveFoldersDeltaLink('dl-folders-1');
      await storage.settings.saveTaskDeltaLinks({
        'rf-default': 'dl-def-1',
        'rf-b': 'dl-b-1',
      });

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
        if (dl != null) {
          // Simulate Substrate delta bug omitting position-only reorder.
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

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Incremental delta sync returns empty, keeping old order and stale task.
      await container.read(syncProvider.notifier).syncNow();
      var state = container.read(todoProvider);
      final tasksList = state.lists.firstWhere((l) => l.id == 'tasks');
      expect(
        state.tasksForList(tasksList).take(2).map((t) => t.id).toList(),
        ['t_1', 't_2'],
      );
      expect(state.tasks.any((t) => t.id == 't_del'), isTrue);

      // Edit t_dirty locally right before forced full sync so it is dirty and
      // pushed in Phase 10a; Phase 10b full-sync pruning must keep it even if
      // the full snapshot omits it.
      container
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

      // Forced full sync bypasses saved deltaLinks and reconciles state.
      await container
          .read(syncProvider.notifier)
          .syncNow(forceFullSync: true, reason: 'test_force');

      expect(fakeApi.callLog, contains('GET tasks(rf-default,null)'));
      expect(fakeApi.callLog, contains('GET tasks(rf-b,null)'));

      state = container.read(todoProvider);
      expect(
        state.tasksForList(tasksList).map((t) => t.id).toList(),
        ['t_2', 't_1', 't_dirty'],
      );
      expect(state.tasks.any((t) => t.id == 't_del'), isFalse);

      final moved = state.tasks.firstWhere((t) => t.id == 't_moved');
      expect(moved.listId, 'list_b');
      expect(moved.orderDateTime, t15);

      expect(storage.settings.loadTaskDeltaLinks(), {
        'rf-default': 'dl-def-new',
        'rf-b': 'dl-b-new',
      });
    });

    test('completing synced recurring task on Microsoft account lets server spawn next occurrence without duplicate POST', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_recur_done');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_recur_done',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_recur_done',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
      ]);
      await storage.repository.saveTasks([
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
      ]);
      await storage.settings.saveFoldersDeltaLink('dl-f-1');
      await storage.settings.saveTaskDeltaLinks({'rf-default': 'dl-t-1'});

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

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(tasksViewPresenterProvider)
          .setTaskCompleted('t_rec', completed: true);

      // Only the completed task exists locally (no premature duplicate created).
      expect(container.read(todoProvider).tasks.length, 1);

      await container.read(syncProvider.notifier).syncNow();

      expect(
        fakeApi.callLog.any((c) => c.startsWith('POST taskfolders/')),
        isFalse,
      );
      expect(capturedPatch?.keys.toSet(), {'Status', 'CompletedDateTime'});
      expect(capturedPatch?['Status'], 'Completed');

      final finalTasks = container.read(todoProvider).tasks;
      expect(finalTasks.length, 2);
      expect(
        finalTasks.where((t) => !t.isCompleted).single.remoteId,
        'rt-rec-next',
      );
    });

    test('preserves custom Recurrence rawRecurrence across unrelated field PATCH and dueDate edits, clearing only when user changes recurrence', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_custom_recur');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_custom_recur',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_custom_recur',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

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

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Initial pull stores rawRecurrence.
      await container.read(syncProvider.notifier).syncNow();
      var task = container.read(todoProvider).tasks.single;
      expect(task.rawRecurrence?['Interval'], 2);
      expect(task.rawRecurrence?['WeekDays'], ['Monday', 'Wednesday']);

      // 1) Editing only title omits Recurrence, Body, Status, etc.
      final detail = container.read(detailViewPresenterProvider);
      detail.updateTaskTitle(task.id, 'Biweekly Sync Updated');
      await container.read(syncProvider.notifier).syncNow();
      expect(capturedPatches.last.keys.toSet(), {'Subject'});

      // 2) Editing dueDate keeps custom Interval=2 & WeekDays intact!
      detail.setTaskDueDate(task.id, DateTime(2026, 12, 2));
      await container.read(syncProvider.notifier).syncNow();
      expect(
        capturedPatches.last.keys.toSet(),
        containsAll(['DueDateTime', 'Recurrence']),
      );
      expect(capturedPatches.last['Recurrence'], customRule);
      expect(storage.repository.readCachedTasks().single.rawRecurrence, customRule);

      // 3) Explicitly choosing a preset clears rawRecurrence and encodes Daily.
      detail.setTaskRecurrence(task.id, RecurrenceType.daily);
      await container.read(syncProvider.notifier).syncNow();
      expect(capturedPatches.last['Recurrence']['RecurrenceType'], 'Daily');
      expect(capturedPatches.last['Recurrence']['Interval'], 1);
    });

    test('realtime FolderGroup/TaskFolder/Setting events apply directly and forceFullSync refreshes groups and folders', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_multi_rt');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_multi_rt',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_multi_rt',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      final tOld = DateTime.utc(2026, 11, 22, 8);
      final tMid = DateTime.utc(2026, 11, 22, 10);
      final tNew = DateTime.utc(2026, 11, 22, 14);

      await storage.repository.saveGroups([
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
      ]);
      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
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
      ]);
      await storage.settings.saveGroupsDeltaLink('dl-g-1');
      await storage.settings.saveFoldersDeltaLink('dl-f-1');

      final fakeApi = FakeSubstrateApi();
      addTearDown(fakeApi.realtimeController.close);
      var groupFetches = 0;
      var folderFetches = 0;
      fakeApi.onFetchGroupsDelta = (dl) {
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
      };
      fakeApi.onFetchFoldersDelta = (dl) {
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

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(true),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncProvider);
      await pumpEventQueue();
      final initialMutationVersion = container
          .read(todoProvider)
          .mutationVersion;

      // 1) FolderGroup reorder/delete + TaskFolder reorder/theme + Setting via realtime with 0 HTTP fetches.
      fakeApi.realtimeController.add(
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
      fakeApi.realtimeController.add(
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
      fakeApi.realtimeController.add(
        const RealtimeEvent(
          id: 'ConfirmOnDelete',
          type: 'Setting',
          operation: 'Updated',
          requestId: 'other-req-3',
          payload: {'Key': 'ConfirmOnDelete', 'Value': 'false'},
        ),
      );
      fakeApi.realtimeController.add(
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
      var todoState = container.read(todoProvider);
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

      // 2) forceFullSync bypasses groupsDeltaLink and foldersDeltaLink and prunes stale group/list.
      await container
          .read(syncProvider.notifier)
          .syncNow(forceFullSync: true, reason: 'manual_header_sync');
      expect(fakeApi.callLog, contains('GET foldergroups(null)'));
      expect(fakeApi.callLog, contains('GET taskfolders(null)'));

      todoState = container.read(todoProvider);
      expect(todoState.groups.map((g) => g.id).toList(), ['g_1']);
      expect(
        todoState.lists.where((l) => !l.isSmartList).map((l) => l.id).toList(),
        ['l_1', 'l_ungroup'],
      );
      expect(todoState.lists.firstWhere((l) => l.id == 'l_1').title, 'List 1 Full');
    });

    test('conflict 409/412 performs 3-way plain-text note merge and recurring status preservation, and step push skips unchanged steps', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = _session(prefs, 'acct_conflict_steps');
      await AuthTokenStorage(prefs).saveTokens(
        'acct_conflict_steps',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_conflict_steps',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      await storage.repository.saveLists([
        ...defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
      ]);
      await storage.repository.saveTasks([
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
      ]);
      await storage.settings.saveFoldersDeltaLink('dl-f-1');
      await storage.settings.saveTaskDeltaLinks({'rf-default': 'dl-t-1'});

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

      Map<String, dynamic>? retriedNotePatch;
      Map<String, dynamic>? retriedAdvPatch;
      Map<String, dynamic>? retriedStepsTaskPatch;
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

      final patchedSteps = <String>[];
      fakeApi.onPatchStep = (taskRemoteId, stepRemoteId, patch) async {
        patchedSteps.add(stepRemoteId);
        return RemoteTaskStep(id: stepRemoteId, subject: 'S2', isCompleted: true);
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Edit note (preserving base 'Line 1\nLine 2\nLine 3'), complete t_adv, toggle only s_2.
      container
          .read(detailViewPresenterProvider)
          .updateTaskNote('t_note', 'Line 1\nLine 2\nLine 3 (local)');
      container
          .read(tasksViewPresenterProvider)
          .setTaskCompleted('t_adv', completed: true);
      container
          .read(detailViewPresenterProvider)
          .toggleStepCompleted('t_steps', 's_2');

      await container.read(syncProvider.notifier).syncNow();

      // 3-way merged note sent on retry & persisted cleanly.
      expect(retriedNotePatch?.keys.toSet(), {'Body', 'BodyLastModifiedTime'});
      expect(
        (retriedNotePatch?['Body'] as Map)['Content'],
        'Line 1 (remote)\nLine 2\nLine 3 (local)',
      );
      final finalNoteTask = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_note');
      expect(finalNoteTask.note, 'Line 1 (remote)\nLine 2\nLine 3 (local)');
      expect(storage.repository.loadTaskBaseNotes(), isEmpty);

      // Server-advanced recurring task kept remote status/dueDate on 409.
      expect(retriedAdvPatch?['Status'], 'NotStarted');
      final finalAdvTask = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_adv');
      expect(finalAdvTask.isCompleted, isFalse);
      expect(finalAdvTask.dueDate, DateTime(2026, 11, 26));

      // Step-only edit skipped task PATCH completely and patched ONLY rs-2!
      expect(retriedStepsTaskPatch, isNull);
      expect(
        fakeApi.callLog.any((c) => c.startsWith('PATCH tasks/rt-steps(')),
        isFalse,
      );
      expect(patchedSteps, ['rs-2']);

      // Editing ONLY task title patches Subject and skips all PATCH subtasks.
      patchedSteps.clear();
      container
          .read(detailViewPresenterProvider)
          .updateTaskTitle('t_steps', 'Multi Step Task Renamed');
      await container.read(syncProvider.notifier).syncNow();
      expect(retriedStepsTaskPatch?.keys.toSet(), {'Subject'});
      expect(retriedStepsTaskPatch?['Subject'], 'Multi Step Task Renamed');
      expect(patchedSteps, isEmpty);
    });
  });
}

class _BlockingTasksDeltaApi extends FakeSubstrateApi {
  _BlockingTasksDeltaApi(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.fetchTasksDelta(
      ctx,
      folderRemoteId: folderRemoteId,
      deltaLink: deltaLink,
    );
  }
}

({TodoRepository repository, TodoSettingsStore settings}) _session(
  SharedPreferences prefs,
  String accountId,
) {
  final settings = TodoSettingsStore(prefs, accountId: accountId);
  return (
    repository: TodoRepository.forSession(sharedFallbackTodoDatabase, settings),
    settings: settings,
  );
}
