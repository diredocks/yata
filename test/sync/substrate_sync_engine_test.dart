import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/sync_dirty_fields.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/microsoft/substrate_pull_engine.dart';
import 'package:yata/sync/microsoft/substrate_push_engine.dart';
import 'package:yata/sync/microsoft/substrate_sync_mappers.dart';
import 'package:yata/sync/microsoft/todo_wire_codecs.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/tasksview/tasks_action_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Substrate sync engine', () {
    test('pulls remote groups, emoji/theme folders, tasks, HTML notes, MyDay, recurrence, settings and deletes via delta', () async {
      final h = await createSyncTestHarness();
      h.api.remoteSettings.addAll({
        TodoSettingKeys.confirmOnDelete: 'false',
        TodoSettingKeys.smartListPlannedDueDateFilter: '1',
        TodoSettingKeys.smartListPlannedGroupType: '2',
        TodoSettingKeys.myDayThemeColor: 'photo_tv_tower',
        TodoSettingKeys.smartListStarredSortType: '6',
        TodoSettingKeys.smartListStarredSortAscending: 'false',
      });

      var folderDeltaStep = 0;
      h.api.onFetchGroupsDelta = (dl) => DeltaPageResult(
        items: [
          RemoteFolderGroup(
            id: 'rg-work',
            name: 'Work Group',
            orderDateTime: DateTime.utc(2026, 11, 22, 10),
          ),
        ],
        deltaLink: 'dl-groups-v1',
      );
      h.api.onFetchFoldersDelta = (dl) {
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

      h.api.onFetchTasksDelta = (folderId, dl) {
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

      // Sync #1: initial full sync
      await h.container.read(syncProvider.notifier).syncNow();

      var state = h.container.read(todoProvider);
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
      expect(h.repository.loadFoldersDeltaLink(), 'dl-folders-v1');
      await h.container.read(syncProvider.notifier).syncNow();
      expect(h.api.callLog, contains('GET taskfolders(dl-folders-v1)'));
      state = h.container.read(todoProvider);
      expect(state.lists.where((l) => l.remoteId == 'rf-shop'), isEmpty);
      expect(state.tasks, isEmpty);
    });

    test(
      'ungroups folders before deleting folder group (prevents 9018)',
      () async {
        final remoteFolders = {'rf-1': 'rg-1'};
        final fakeApi = FakeSubstrateApi()
          ..onPatchFolder = (id, patch) async {
            if (patch.containsKey('ParentFolderGroupId') &&
                patch['ParentFolderGroupId'] == null) {
              remoteFolders.remove(id);
            }
            return RemoteTodoFolder(id: id, name: 'Project');
          }
          ..onDeleteGroup = (groupId) async {
            if (remoteFolders.values.contains(groupId)) {
              throw const AppError.network(
                statusCode: 400,
                code: 'FolderGroupNotEmpty',
                message: 'Group not empty',
              );
            }
          };

        final h = await createSyncTestHarness(
          api: fakeApi,
          groups: const [
            ListGroup(id: 'grp_1', title: 'Work', remoteId: 'rg-1'),
          ],
          defaultTasksFolderRemoteId: 'rf-default',
          extraLists: const [
            TodoList(
              id: 'list_1',
              title: 'Project',
              groupId: 'grp_1',
              remoteId: 'rf-1',
            ),
          ],
        );

        h.container.read(homeViewPresenterProvider).deleteGroup('grp_1');

        await h.container.read(syncProvider.notifier).syncNow();
        expect(h.container.read(syncProvider).status, SyncStatus.success);
        final patchIdx = h.api.callLog.indexWhere(
          (c) => c.startsWith('PATCH taskfolders/rf-1'),
        );
        final delIdx = h.api.callLog.indexOf('DELETE foldergroups/rg-1');
        expect(patchIdx, greaterThanOrEqualTo(0));
        expect(delIdx, greaterThan(patchIdx));
      },
    );

    test('handles 409 If-Match conflict retry, 410 delta reset, and cross-folder move safety', () async {
      var patchAttempts = 0;
      final fakeApi = FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
        items: [
          RemoteTodoFolder(id: 'rf-a', name: 'Tasks', isDefaultFolder: true),
          RemoteTodoFolder(id: 'rf-b', name: 'List B'),
        ],
        deltaLink: 'dl-folders-ab',
      );
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

      final h = await createSyncTestHarness(
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-a',
        extraLists: const [
          TodoList(id: 'list_b', title: 'List B', remoteId: 'rf-b'),
        ],
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Initial',
            createdAt: DateTime(2026, 11, 22),
            remoteId: 'rt-1',
            changeKey: 'ck-stale',
          ),
        ],
        taskDeltaLinks: const {'rf-a': 'dl-expired'},
      );

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
                        .first
                        .copyWith(title: 'Local Edit'),
                  ],
                ),
          );

      await h.container.read(syncProvider.notifier).syncNow();
      expect(patchAttempts, 2);
      expect(h.api.callLog, contains('GET tasks/rt-1'));
      expect(h.api.callLog, contains('GET tasks(rf-a,null)'));
      expect(h.repository.loadTaskDeltaLinks()['rf-a'], 'dl-a-fresh');

      final tasks = h.container.read(todoProvider).tasks;
      expect(tasks.length, 1);
      expect(tasks.first.listId, 'list_b');
      expect(tasks.first.title, 'Moved Cleanly');
    });

    test('preserves concurrent local edits made during in-flight sync and syncs reorder OrderDateTime', () async {
      final tOld = DateTime.utc(2026, 11, 22, 10);
      final tNew = DateTime.utc(2026, 11, 22, 12);
      final patchStarted = Completer<void>();
      final allowPatchFinish = Completer<void>();
      Map<String, dynamic>? capturedOrderPatch;

      final fakeApi = FakeSubstrateApi()
        ..onPatchTask = (id, patch, ck) async {
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

      final h = await createSyncTestHarness(
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
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
        ],
      );

      h.container.read(todoProvider.notifier).selectList('tasks');
      final initialOrdered = h.container
          .read(todoProvider)
          .tasksForList(h.container.read(todoProvider).selectedList);
      expect(initialOrdered.first.id, 't_1');
      h.container
          .read(tasksViewPresenterProvider)
          .reorderActiveTasks(initialOrdered, 0, 1);

      final syncFuture = h.container.read(syncProvider.notifier).syncNow();
      await patchStarted.future;

      h.container
          .read(todoProvider.notifier)
          .commit(
            h.container
                .read(todoProvider)
                .copyWith(
                  tasks: [
                    for (final t in h.container.read(todoProvider).tasks)
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
      final updatedT1 = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_1');
      expect(updatedT1.title, 'Edited Mid-Sync');
      expect(updatedT1.changeKey, 'ck-patched');
      expect(
        h.repository.outbox.pendingLocalIds(SyncEntityType.task),
        contains('t_1'),
      );
    });

    test(
      'pushes dirty settings and clears remoteId/changeKey when copying tasks',
      () async {
        final h = await createSyncTestHarness();

        h.container
            .read(settingsPresenterProvider)
            .setConfirmBeforeDeleting(false);
        h.container
            .read(tasksViewPresenterProvider)
            .setPlannedDueDateFilter(PlannedDueDateFilter.thisWeek);
        h.container
            .read(tasksViewPresenterProvider)
            .setPlannedGroupOption(PlannedGroupOption.byList);

        final originalTask = TaskItem(
          id: 't_src',
          listId: 'tasks',
          title: 'Source',
          createdAt: DateTime(2026, 11, 22),
          remoteId: 'rt-src',
          changeKey: 'ck-src',
          steps: const [
            TaskStep(id: 's_1', title: 'Step 1', remoteId: 'rs-src'),
          ],
        );
        h.container
            .read(todoProvider.notifier)
            .commit(
              h.container.read(todoProvider).copyWith(tasks: [originalTask]),
            );
        h.container.read(tasksActionPresenterProvider).batchCopyToList({
          't_src',
        }, 'tasks');
        final copied = h.container
            .read(todoProvider)
            .tasks
            .firstWhere((t) => t.id != 't_src');
        expect(copied.remoteId, isNull);
        expect(copied.changeKey, isNull);
        expect(copied.steps.single.remoteId, isNull);

        await h.container.read(syncProvider.notifier).syncNow();
        expect(h.api.remoteSettings[TodoSettingKeys.confirmOnDelete], 'false');
        expect(
          h.api.remoteSettings[TodoSettingKeys.smartListPlannedDueDateFilter],
          '3',
        );
        expect(
          h.api.remoteSettings[TodoSettingKeys.smartListPlannedGroupType],
          '2',
        );
      },
    );

    test('retries 401 with refreshed token and reports requiresRelogin when refresh fails', () async {
      final h1 = await createSyncTestHarness();
      var settingsAttempts = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/settings')) {
          settingsAttempts += 1;
          if (settingsAttempts == 1) {
            expect(request.headers['Authorization'], 'Bearer tok-1');
            return http.Response(
              jsonEncode({
                'error': {'message': 'Unauthorized'},
              }),
              401,
            );
          }
          expect(request.headers['Authorization'], 'Bearer refreshed-access');
          return http.Response(jsonEncode({'Value': const []}), 200);
        }
        expect(request.headers['Authorization'], 'Bearer refreshed-access');
        final hasDelta = request.url.queryParameters.containsKey('deltatoken');
        return http.Response(
          jsonEncode({
            'Value': const [],
            'DeltaLink':
                '${request.url.path}?deltatoken=${hasDelta ? "final" : "p1"}',
          }),
          200,
        );
      });

      final realApi = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
        contextResolver: ({bool forceRefreshToken = false}) =>
            resolveSubstrateContext(
              authClient: h1.authClient,
              tokenStorage: AuthTokenStorage(h1.prefs),
              account: h1.account,
              repository: h1.repository,
              forceRefreshToken: forceRefreshToken,
            ),
      );

      final outcome = await SubstratePullEngine(realApi)
          .pull(
            repository: h1.repository,
            readState: () => h1.container.read(todoProvider),
            idGenerator: h1.container.read(todoProvider.notifier).nextId,
          )
          .fold(
            (outcome) => outcome,
            (error) => fail('unexpected sync failure: ${error.describe()}'),
          );
      expect(settingsAttempts, 2);
      expect(outcome.syncedAt, isNotNull);

      final failingAuth = FakeAuthClient(
        onRefreshTokens: (_) async => throw const AppError.auth(
          message: 'Token revoked',
          code: 'invalid_grant',
          requiresReauth: true,
        ),
      );
      final s2 = await seedMicrosoftSyncSession(
        accountId: 'acct_reauth',
        tokens: MicrosoftAuthTokens(
          accessToken: 'old',
          refreshToken: 'bad-rt',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final c2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(s2.prefs),
          microsoftAuthClientProvider.overrideWithValue(failingAuth),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
          startupSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c2.dispose);

      await c2.read(syncProvider.notifier).syncNow();
      expect(c2.read(syncProvider).status, SyncStatus.requiresRelogin);
      expect(c2.read(syncProvider).requiresRelogin, isTrue);
    });

    test(
      'backfills missing Microsoft displayName and avatar during syncNow',
      () async {
        final avatar = base64Encode([0xFF, 0xD8, 0xFF, 0xE0]);
        final h = await createSyncTestHarness(
          accountId: 'acct_bf',
          displayName: 'Microsoft Account',
          email: '',
          microsoftUserId: 'cidbf',
          authClient: FakeAuthClient(
            onFetchUserProfile: (cid, rt, _) async => MicrosoftUserProfile(
              id: cid,
              displayName: 'Leo Zhang',
              email: 'leo@outlook.com',
              avatarBase64: avatar,
            ),
          ),
        );

        await h.container.read(syncProvider.notifier).syncNow();
        expect(h.container.read(syncProvider).status, SyncStatus.success);

        final updated =
            h.container.read(accountProvider).activeAccount
                as MicrosoftAccount?;
        expect(updated, isNotNull);
        expect(updated!.displayName, 'Leo Zhang');
        expect(updated.email, 'leo@outlook.com');
        expect(updated.avatarBase64, avatar);
      },
    );

    test('recovers from ErrorItemNotFound (404) on deleted/missing task PATCH and clears pending deletes', () async {
      final now = DateTime.utc(2026, 4, 15, 10, 0);
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

      final h = await createSyncTestHarness(
        accountId: 'acct_404',
        microsoftUserId: 'cid404',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't-ghost',
            listId: 'tasks',
            title: 'Ghost deleted task',
            remoteId: 'rt-ghost',
            changeKey: 'ck-ghost',
            createdAt: now,
            updatedAt: now,
          ),
          TaskItem(
            id: 't-recreate',
            listId: 'tasks',
            title: 'Edited after remote delete',
            remoteId: 'rt-missing',
            changeKey: 'ck-missing',
            steps: const [
              TaskStep(id: 's1', title: 'Step 1', remoteId: 'rs-old'),
            ],
            createdAt: now,
            updatedAt: now,
          ),
        ],
        pendingDeletedTaskRemoteIds: const ['rt-ghost'],
        dirtyTaskIds: const {'t-ghost', 't-recreate'},
      );

      await h.container.read(syncProvider.notifier).syncNow();

      expect(h.container.read(syncProvider).status, SyncStatus.success);
      expect(
        h.repository.outbox.pendingDeletedRemoteIds(SyncEntityType.task),
        isEmpty,
      );
      expect(h.repository.outbox.pendingLocalIds(SyncEntityType.task), isEmpty);

      expect(
        h.api.callLog.any((c) => c.contains('PATCH tasks/rt-ghost')),
        isFalse,
      );
      expect(
        h.api.callLog.any((c) => c.contains('Ghost deleted task')),
        isFalse,
      );
      expect(
        h.api.callLog,
        contains(
          'POST taskfolders/rf-default/tasks Edited after remote delete',
        ),
      );
      final recreated = h.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't-recreate');
      expect(recreated.remoteId, isNot('rt-missing'));
      expect(recreated.steps.single.remoteId, isNot('rs-old'));
    });

    test('folder theme PATCH and delta merge round-trip solid <-> photo backgrounds', () {
      const solidList = TodoList(
        id: 'list_shop',
        title: 'Shopping',
        remoteId: 'rf-shop',
        themeColor: ListThemeColor.rose,
        themePhoto: null,
      );
      final clearPatch = buildFolderPatchPayload(
        solidList,
        parentGroupRemoteId: null,
        dirtyFields: {ListDirtyField.theme},
      );
      expect(clearPatch['ThemeColor'], 'dark_rose');
      expect(clearPatch['ThemeBackground'], 'mountain');

      final afterClear = mergeFoldersDelta(
        localLists: [solidList],
        remoteDelta: [
          RemoteTodoFolder(
            id: 'rf-shop',
            name: 'Shopping',
            themeColor: clearPatch['ThemeColor'] as String,
            themeBackground: clearPatch['ThemeBackground'] as String,
          ),
        ],
        dirtyListIds: const {},
        groupLocalIdByRemoteId: const {},
        idGenerator: (p) => '${p}_gen',
      ).single;
      expect(afterClear.themeColor, ListThemeColor.rose);
      expect(afterClear.themePhoto, isNull);

      final photoList = afterClear.copyWith(
        themeColor: ListThemeColor.blue,
        themePhoto: ListThemePhoto.beach,
      );
      final photoPatch = buildFolderPatchPayload(
        photoList,
        parentGroupRemoteId: null,
        dirtyFields: {ListDirtyField.theme},
      );
      expect(photoPatch['ThemeColor'], 'photo_beach');
      expect(photoPatch['ThemeBackground'], 'mountain');

      final afterPhoto = mergeFoldersDelta(
        localLists: [photoList],
        remoteDelta: [
          RemoteTodoFolder(
            id: 'rf-shop',
            name: 'Shopping',
            themeColor: photoPatch['ThemeColor'] as String,
            themeBackground: photoPatch['ThemeBackground'] as String,
          ),
        ],
        dirtyListIds: const {},
        groupLocalIdByRemoteId: const {},
        idGenerator: (p) => '${p}_gen',
      ).single;
      expect(afterPhoto.themePhoto, ListThemePhoto.beach);
    });

    test('follow-up folder pull triggers only on recurring completion (not normal edits) and pulls only that folder', () async {
      final h = await createSyncTestHarness(
        accountId: 'acct_push_only',
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_normal',
            listId: 'tasks',
            title: 'One-off',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-normal',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-normal',
          ),
          TaskItem(
            id: 't_rec',
            listId: 'tasks',
            title: 'Daily Standup',
            createdAt: DateTime.utc(2026, 11, 22, 7),
            dueDate: DateTime(2026, 11, 22),
            recurrence: RecurrenceType.daily,
            remoteId: 'rt-rec',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-rec',
          ),
        ],
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
      );

      final pushEngine = SubstratePushEngine(h.api);
      final pullEngine = SubstratePullEngine(h.api);
      final todoNotifier = h.container.read(todoProvider.notifier);

      // 1) Non-recurring completion produces NO follow-up folder pull.
      h.container
          .read(tasksViewPresenterProvider)
          .setTaskCompleted('t_normal', completed: true);
      h.api.callLog.clear();

      final normalPush = await pushEngine
          .pushOutbox(
            readState: () => h.container.read(todoProvider),
            outbox: h.repository.outbox,
            nowUtc: DateTime.now().toUtc(),
            onItemCommitted: todoNotifier.commitPushBatch,
          )
          .fold(
            (outcome) => outcome,
            (error) => fail('unexpected push failure: ${error.describe()}'),
          );
      expect(normalPush.pushedTasks, contains('t_normal'));
      expect(normalPush.followUpPullFolderRemoteIds, isEmpty);
      expect(h.api.callLog, ['PATCH tasks/rt-normal(ifMatch=ck-normal)']);

      // 2) Recurring task completion flags its folder for a selective pull.
      h.container
          .read(tasksViewPresenterProvider)
          .setTaskCompleted('t_rec', completed: true);
      h.api.callLog.clear();

      final recPush = await pushEngine
          .pushOutbox(
            readState: () => h.container.read(todoProvider),
            outbox: h.repository.outbox,
            nowUtc: DateTime.now().toUtc(),
            onItemCommitted: todoNotifier.commitPushBatch,
          )
          .fold(
            (outcome) => outcome,
            (error) => fail('unexpected push failure: ${error.describe()}'),
          );
      expect(recPush.pushedTasks, contains('t_rec'));
      expect(recPush.followUpPullFolderRemoteIds, {'rf-default'});

      final pullOutcome = await pullEngine
          .pull(
            repository: h.repository,
            readState: () => h.container.read(todoProvider),
            idGenerator: todoNotifier.nextId,
            onlyFolderRemoteIds: recPush.followUpPullFolderRemoteIds,
          )
          .fold(
            (outcome) => outcome,
            (error) => fail('unexpected pull failure: ${error.describe()}'),
          );

      expect(h.api.callLog, [
        'PATCH tasks/rt-rec(ifMatch=ck-rec)',
        'GET tasks(rf-default,dl-tasks-1)',
      ]);
      expect(pullOutcome.isSelective, isTrue);
      expect(pullOutcome.remoteSettings, isNull);
      expect(
        pullOutcome.tasks.firstWhere((t) => t.id == 't_rec').isCompleted,
        isTrue,
      );
    });

    test(
      'selective pull tolerates a folder that disappeared remotely',
      () async {
        final h = await createSyncTestHarness(
          accountId: 'acct_push_only_missing_folder',
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'tasks',
              title: 'One',
              createdAt: DateTime.utc(2026, 11, 22, 8),
              dueDate: DateTime(2026, 11, 22),
              recurrence: RecurrenceType.daily,
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-1',
            ),
          ],
          foldersDeltaLink: 'dl-folders-1',
          taskDeltaLinks: const {'rf-default': 'dl-tasks-1'},
        );
        h.api.onFetchTasksDelta = (folderRemoteId, deltaLink) =>
            throw const AppError.notFound(
              message: 'Folder is gone',
              id: 'folder_gone',
            );

        h.container
            .read(tasksViewPresenterProvider)
            .setTaskCompleted('t_1', completed: true);

        final todoNotifier = h.container.read(todoProvider.notifier);
        final pushOutcome = await SubstratePushEngine(h.api)
            .pushOutbox(
              readState: () => h.container.read(todoProvider),
              outbox: h.repository.outbox,
              nowUtc: DateTime.now().toUtc(),
              onItemCommitted: todoNotifier.commitPushBatch,
            )
            .fold(
              (outcome) => outcome,
              (error) => fail('unexpected push failure: ${error.describe()}'),
            );
        final pullOutcome = await SubstratePullEngine(h.api)
            .pull(
              repository: h.repository,
              readState: () => h.container.read(todoProvider),
              idGenerator: todoNotifier.nextId,
              onlyFolderRemoteIds: pushOutcome.followUpPullFolderRemoteIds,
            )
            .fold(
              (outcome) => outcome,
              (error) => fail('unexpected pull failure: ${error.describe()}'),
            );

        expect(pullOutcome.isSelective, isTrue);
        expect(pullOutcome.tasks.single.id, 't_1');
      },
    );

    test(
      'mergeFoldersDelta does not hijack dirty unpushed list with same title',
      () {
        const dirtyCopy = TodoList(
          id: 'list_new_copy',
          title: 'Shopping (1)',
          remoteId: null,
        );
        final merged = mergeFoldersDelta(
          localLists: const [dirtyCopy],
          remoteDelta: const [
            RemoteTodoFolder(id: 'rf-old-copy', name: 'Shopping (1)'),
          ],
          dirtyListIds: const {'list_new_copy'},
          groupLocalIdByRemoteId: const {},
          idGenerator: (p) => '${p}_gen',
        );

        final localCopy = merged.firstWhere((l) => l.id == 'list_new_copy');
        expect(localCopy.remoteId, isNull);
        expect(
          merged.any(
            (l) => l.remoteId == 'rf-old-copy' && l.id != 'list_new_copy',
          ),
          isTrue,
        );
      },
    );

    test(
      'deleteList deletes folder without issuing per-task DELETE requests',
      () async {
        final h = await createSyncTestHarness(
          accountId: 'acct_delete_list_batch',
          defaultTasksFolderRemoteId: 'rf-default',
          lists: const [
            TodoList(
              id: 'list_copy_1',
              title: 'Work (1)',
              remoteId: 'rf-copy-1',
            ),
          ],
          tasks: [
            TaskItem(
              id: 't_1',
              listId: 'list_copy_1',
              title: 'Task 1',
              createdAt: DateTime.utc(2026, 11, 22, 8),
              remoteId: 'rt-1',
              remoteParentFolderId: 'rf-copy-1',
            ),
            TaskItem(
              id: 't_2',
              listId: 'list_copy_1',
              title: 'Task 2',
              createdAt: DateTime.utc(2026, 11, 22, 9),
              remoteId: 'rt-2',
              remoteParentFolderId: 'rf-copy-1',
            ),
          ],
        );

        h.container.read(tasksViewPresenterProvider).deleteList('list_copy_1');

        h.api.callLog.clear();

        await SubstratePushEngine(h.api)
            .pushOutbox(
              readState: () => h.container.read(todoProvider),
              outbox: h.repository.outbox,
              nowUtc: DateTime.now().toUtc(),
              onItemCommitted: (o) async {
                h.repository.outbox.ackBatch(
                  o.ackedSeqs,
                  o.clearedRemoteIdKeys,
                );
                await h.repository.saveOutbox();
              },
            )
            .fold(
              (outcome) => outcome,
              (error) => fail('unexpected push failure: ${error.describe()}'),
            );

        expect(h.api.callLog, contains('DELETE taskfolders/rf-copy-1'));
        expect(
          h.api.callLog.where((c) => c.startsWith('DELETE tasks/')),
          isEmpty,
        );
        expect(h.repository.outbox.ops, isEmpty);
      },
    );

    test('mid-batch push failure commits partial remoteIds and does not duplicate tasks on retry', () async {
      final h = await createSyncTestHarness(
        accountId: 'acct_partial_push_retry',
        defaultTasksFolderRemoteId: 'rf-default',
        lists: const [
          TodoList(id: 'list_src', title: 'Source', remoteId: 'rf-src'),
        ],
        tasks: [
          TaskItem(
            id: 't_src_1',
            listId: 'list_src',
            title: 'Alpha',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-src-1',
            remoteParentFolderId: 'rf-src',
          ),
          TaskItem(
            id: 't_src_2',
            listId: 'list_src',
            title: 'Beta',
            createdAt: DateTime.utc(2026, 11, 22, 9),
            remoteId: 'rt-src-2',
            remoteParentFolderId: 'rf-src',
          ),
        ],
      );

      h.container.read(tasksViewPresenterProvider).duplicateList('list_src');

      var createdCount = 0;
      var failedOnce = false;
      h.api.onCreateFolder = (payload) async {
        return RemoteTodoFolder(
          id: 'rf-dup-1',
          name: payload['Name'] as String,
        );
      };
      h.api.onCreateTask = (folderRemoteId, payload) async {
        final subject = payload['Subject'] as String;
        if (subject == 'Beta' && !failedOnce) {
          failedOnce = true;
          throw const AppError.network(message: 'transient error');
        }
        createdCount += 1;
        return RemoteTodoTask(
          id: 'rt-dup-$createdCount',
          subject: subject,
          parentFolderId: folderRemoteId,
          changeKey: 'ck-$createdCount',
        );
      };

      final todoNotifier = h.container.read(todoProvider.notifier);
      final pushEngine = SubstratePushEngine(h.api);

      final firstResult = await pushEngine.pushOutbox(
        readState: () => h.container.read(todoProvider),
        outbox: h.repository.outbox,
        nowUtc: DateTime.now().toUtc(),
        onItemCommitted: todoNotifier.commitPushBatch,
      );
      expect(firstResult.isError(), isTrue);

      // Alpha and the duplicated folder should already be committed with remoteIds.
      final midState = h.container.read(todoProvider);
      final dupList = midState.lists.firstWhere((l) => l.title == 'Source (1)');
      expect(dupList.remoteId, 'rf-dup-1');
      final alpha = midState.tasks.firstWhere(
        (t) => t.listId == dupList.id && t.title == 'Alpha',
      );
      expect(alpha.remoteId, isNotNull);

      h.api.callLog.clear();
      final secondResult = await pushEngine.pushOutbox(
        readState: () => h.container.read(todoProvider),
        outbox: h.repository.outbox,
        nowUtc: DateTime.now().toUtc(),
        onItemCommitted: todoNotifier.commitPushBatch,
      );
      expect(secondResult.isSuccess(), isTrue);

      // Retry only created Beta, never duplicated the folder or Alpha.
      expect(h.api.callLog.where((c) => c == 'POST taskfolders'), isEmpty);
      expect(
        h.api.callLog.where(
          (c) => c.startsWith('POST taskfolders/rf-dup-1/tasks'),
        ),
        hasLength(1),
      );
      expect(createdCount, 2);
    });

    test('in-flight deleteList during pushOutbox skips creating tasks for deleted list', () async {
      final h = await createSyncTestHarness(
        accountId: 'acct_inflight_delete',
        defaultTasksFolderRemoteId: 'rf-default',
        lists: const [
          TodoList(id: 'list_src', title: 'Source', remoteId: 'rf-src'),
        ],
        tasks: [
          TaskItem(
            id: 't_src_1',
            listId: 'list_src',
            title: 'Alpha',
            createdAt: DateTime.utc(2026, 11, 22, 8),
            remoteId: 'rt-src-1',
            remoteParentFolderId: 'rf-src',
          ),
        ],
      );

      h.container.read(tasksViewPresenterProvider).duplicateList('list_src');
      final dupList = h.container
          .read(todoProvider)
          .lists
          .firstWhere((l) => l.title == 'Source (1)');

      h.api.onCreateFolder = (payload) async {
        // Simulate user deleting the duplicated list while createFolder is in flight.
        h.container.read(tasksViewPresenterProvider).deleteList(dupList.id);
        return RemoteTodoFolder(
          id: 'rf-dup-gone',
          name: payload['Name'] as String,
        );
      };

      final todoNotifier = h.container.read(todoProvider.notifier);

      await SubstratePushEngine(h.api)
          .pushOutbox(
            readState: () => h.container.read(todoProvider),
            outbox: h.repository.outbox,
            nowUtc: DateTime.now().toUtc(),
            onItemCommitted: todoNotifier.commitPushBatch,
          )
          .fold(
            (outcome) => outcome,
            (error) => fail('unexpected push failure: ${error.describe()}'),
          );

      // No tasks were created for the deleted folder!
      expect(
        h.api.callLog.where(
          (c) => c.startsWith('POST taskfolders/rf-dup-gone/tasks'),
        ),
        isEmpty,
      );
    });
  });
}
