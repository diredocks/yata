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
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
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
                themeColor: 'light_teal',
                themeBackground: 'photo_beach',
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
      expect(shop.themeColor, ListThemeColor.lightTeal);
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
  });
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
