import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_local_storage.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/data/todo_local_storage.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/homeview/home_view_ordering.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/main.dart';
import 'package:yata/models/account.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/todo_wire_codecs.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncNotifier & UI sync integration', () {
    testWidgets(
      'Tasks default list displays Completed pill even when remote ShowCompletedTasks is false and syncs toggle',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final tokenStorage = AuthTokenStorage(prefs);
        await tokenStorage.saveTokens(
          'acct_tasks_done',
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: 'cid1',
          ),
        );
        final account = MicrosoftAccount(
          id: 'acct_tasks_done',
          displayName: 'Alice',
          email: 'alice@outlook.com',
          createdAt: DateTime(2026, 11, 22),
          microsoftUserId: 'cid1',
        );
        await AccountLocalStorage(prefs).saveAccounts([account]);
        await AccountLocalStorage(prefs).saveActiveAccountId('acct_tasks_done');

        final fakeApi = FakeSubstrateApi();
        Map<String, dynamic>? patchedDefaultFolder;
        fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
          items: [
            RemoteTodoFolder(
              id: 'rf-default',
              name: 'Tasks',
              isDefaultFolder: true,
              showCompletedTasks: false,
            ),
          ],
          deltaLink: 'dl-folders-1',
        );
        fakeApi.onFetchTasksDelta = (folderId, dl) {
          if (folderId == 'rf-default' && dl == null) {
            return DeltaPageResult(
              items: [
                RemoteTodoTask.fromJson({
                  'Id': 'rt-active',
                  'ChangeKey': 'ck-a',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Active default task',
                  'Status': 'NotStarted',
                }),
                RemoteTodoTask.fromJson({
                  'Id': 'rt-done',
                  'ChangeKey': 'ck-d',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Done default task',
                  'Status': 'Completed',
                }),
              ],
              deltaLink: 'dl-tasks-default-1',
            );
          }
          return DeltaPageResult(
            items: const [],
            deltaLink: 'dl-tasks-$folderId',
          );
        };
        fakeApi.onPatchFolder = (remoteId, patch) async {
          if (remoteId == 'rf-default') {
            patchedDefaultFolder = Map<String, dynamic>.from(patch);
          }
          return RemoteTodoFolder(
            id: remoteId,
            name: 'Tasks',
            isDefaultFolder: true,
            showCompletedTasks: patch['ShowCompletedTasks'] as bool? ?? true,
          );
        };

        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
              microsoftTodoApiProvider.overrideWithValue(fakeApi),
              realtimeSyncEnabledProvider.overrideWithValue(false),
            ],
            child: const YataApp(),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        await container.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tasks'));
        await tester.pumpAndSettle();

        // Active task is visible and Completed pill appears even though ShowCompletedTasks was false
        expect(find.text('Active default task'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Done default task'), findsNothing);

        // Tapping Completed expands the section and marks default Tasks folder dirty
        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();
        expect(find.text('Done default task'), findsOneWidget);
        expect(
          TodoLocalStorage(
            prefs,
            accountId: 'acct_tasks_done',
          ).loadDirtyListIds(),
          contains('tasks'),
        );

        await container.read(syncProvider.notifier).syncNow();
        expect(patchedDefaultFolder?['ShowCompletedTasks'], isTrue);
      },
    );

    testWidgets(
      'Sidebar renders remote groups, interleaved ungrouped lists, and group members in descending OrderDateTime order across restarts',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final tokenStorage = AuthTokenStorage(prefs);
        await tokenStorage.saveTokens(
          'acct_order_ui',
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: 'cid1',
          ),
        );
        final account = MicrosoftAccount(
          id: 'acct_order_ui',
          displayName: 'Alice',
          email: 'alice@outlook.com',
          createdAt: DateTime(2026, 11, 22),
          microsoftUserId: 'cid1',
        );
        await AccountLocalStorage(prefs).saveAccounts([account]);
        await AccountLocalStorage(prefs).saveActiveAccountId('acct_order_ui');

        final fakeApi = FakeSubstrateApi();
        // Return groups and folders in deliberately scrambled array order.
        fakeApi.onFetchGroupsDelta = (dl) => DeltaPageResult(
          items: [
            RemoteFolderGroup(
              id: 'rg-work',
              name: 'Work Group',
              orderDateTime: DateTime.utc(2026, 11, 22, 9),
            ),
            RemoteFolderGroup(
              id: 'rg-personal',
              name: 'Personal Group',
              orderDateTime: DateTime.utc(2026, 11, 22, 11),
            ),
          ],
          deltaLink: 'dl-groups-1',
        );
        fakeApi.onFetchFoldersDelta = (dl) => DeltaPageResult(
          items: [
            const RemoteTodoFolder(
              id: 'rf-default',
              name: 'Tasks',
              isDefaultFolder: true,
            ),
            RemoteTodoFolder(
              id: 'rf-bot',
              name: 'Bottom Unfiled',
              orderDateTime: DateTime.utc(2026, 11, 22, 8),
            ),
            RemoteTodoFolder(
              id: 'rf-w2',
              name: 'Work Second',
              parentFolderGroupId: 'rg-work',
              orderDateTime: DateTime.utc(2026, 11, 22, 7),
            ),
            RemoteTodoFolder(
              id: 'rf-top',
              name: 'Top Unfiled',
              orderDateTime: DateTime.utc(2026, 11, 22, 12),
            ),
            RemoteTodoFolder(
              id: 'rf-mid',
              name: 'Middle Unfiled',
              orderDateTime: DateTime.utc(2026, 11, 22, 10),
            ),
            RemoteTodoFolder(
              id: 'rf-w1',
              name: 'Work First',
              parentFolderGroupId: 'rg-work',
              orderDateTime: DateTime.utc(2026, 11, 22, 7, 30),
            ),
          ],
          deltaLink: 'dl-folders-1',
        );

        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
              microsoftTodoApiProvider.overrideWithValue(fakeApi),
              realtimeSyncEnabledProvider.overrideWithValue(false),
            ],
            child: const YataApp(),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        await container.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();

        void assertOrder() {
          final yTop = tester.getTopLeft(find.text('Top Unfiled')).dy;
          final yPersonal = tester.getTopLeft(find.text('Personal Group')).dy;
          final yMid = tester.getTopLeft(find.text('Middle Unfiled')).dy;
          final yWork = tester.getTopLeft(find.text('Work Group')).dy;
          final yW1 = tester.getTopLeft(find.text('Work First')).dy;
          final yW2 = tester.getTopLeft(find.text('Work Second')).dy;
          final yBot = tester.getTopLeft(find.text('Bottom Unfiled')).dy;

          expect(yTop, lessThan(yPersonal));
          expect(yPersonal, lessThan(yMid));
          expect(yMid, lessThan(yWork));
          expect(yWork, lessThan(yW1));
          expect(yW1, lessThan(yW2));
          expect(yW2, lessThan(yBot));
        }

        assertOrder();

        // Verify exact same interleaved order persists across app restart without syncing
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
              microsoftTodoApiProvider.overrideWithValue(fakeApi),
              realtimeSyncEnabledProvider.overrideWithValue(false),
            ],
            child: const YataApp(),
          ),
        );
        await tester.pumpAndSettle();
        assertOrder();
      },
    );

    test('HomeViewPresenter manual reorder updates descending OrderDateTime, marks moved items dirty, and PATCHes remote', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_reorder_sync',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_reorder_sync',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_reorder_sync');

      final fakeApi = FakeSubstrateApi();
      final patchedGroups = <String, Map<String, dynamic>>{};
      final patchedFolders = <String, Map<String, dynamic>>{};
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

      final homePresenter = container.read(homeViewPresenterProvider);
      var state = container.read(todoProvider);
      var entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      expect(entries.map((e) => e.stableKey).toList(), [
        'list_${state.lists.firstWhere((l) => l.remoteId == 'rf-alpha').id}',
        'group_${state.groups.first.id}',
        'list_${state.lists.firstWhere((l) => l.remoteId == 'rf-beta').id}',
      ]);

      // Move Alpha (index 0) to bottom (index 2, below Beta)
      homePresenter.reorderTopLevelEntries(entries, 0, 2);
      // Move rg-work (now index 0) below Beta -> wait let's inspect first then move group to top/bottom
      state = container.read(todoProvider);
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

      // Move Beta (index 1) to top (index 0, above rg-work) & swap group members
      homePresenter.reorderTopLevelEntries(entries, 1, 0);
      // Also move rg-work between Beta and Alpha? Swap Beta back via moving rg-work so group PATCH is exercised too
      state = container.read(todoProvider);
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
      // Now move rg-work from index 1 to index 0 (back to top) so group OrderDateTime updates too
      state = container.read(todoProvider);
      entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      homePresenter.reorderTopLevelEntries(entries, 1, 0);

      await container.read(syncProvider.notifier).syncNow();

      expect(patchedGroups['rg-work']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-alpha']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-beta']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-m2']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-m1']?['OrderDateTime'], isNull);

      state = container.read(todoProvider);
      final syncedM1 = state.lists.firstWhere((l) => l.remoteId == 'rf-m1');
      final syncedM2 = state.lists.firstWhere((l) => l.remoteId == 'rf-m2');
      expect(syncedM2.orderDateTime!.isAfter(syncedM1.orderDateTime!), isTrue);
    });

    testWidgets(
      'Pulls remote task and subtask manual order (including legacy .-Z timestamps, CreatedDateTime ASC tiebreak, and My Day CommittedOrder) and preserves across restarts',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final tokenStorage = AuthTokenStorage(prefs);
        await tokenStorage.saveTokens(
          'acct_task_pull_order',
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: 'cid1',
          ),
        );
        final account = MicrosoftAccount(
          id: 'acct_task_pull_order',
          displayName: 'Alice',
          email: 'alice@outlook.com',
          createdAt: DateTime(2026, 11, 22),
          microsoftUserId: 'cid1',
          lastSyncedAt: DateTime(2026, 11, 22, 8),
        );
        await AccountLocalStorage(prefs).saveAccounts([account]);
        await AccountLocalStorage(prefs)
            .saveActiveAccountId('acct_task_pull_order');

        final fakeApi = FakeSubstrateApi();
        final today = DateTime.now();
        var defaultTaskSyncCount = 0;
        Map<String, dynamic>? uiReorderPatch;
        fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
          items: [
            RemoteTodoFolder(
              id: 'rf-default',
              name: 'Tasks',
              isDefaultFolder: true,
            ),
            RemoteTodoFolder(id: 'rf-custom', name: 'Work Tasks'),
          ],
          deltaLink: 'dl-folders-1',
        );
        fakeApi.onFetchTasksDelta = (folderId, dl) {
          if (folderId == 'rf-default') {
            defaultTaskSyncCount += 1;
            if (dl == null) {
              return DeltaPageResult(
                items: [
                  // Scrambled order; includes equal OrderDateTime tiebreak & legacy .-1234Z
                  RemoteTodoTask.fromJson({
                    'Id': 'rt-tie-later',
                    'ChangeKey': 'ck-1',
                    'ParentFolderId': 'rf-default',
                    'Subject': 'Tie Created Later',
                    'OrderDateTime': '2026-11-22T10:00:00.000-1234Z',
                    'CreatedDateTime': '2026-11-22T09:00:00.0000000Z',
                    'Subtasks': [
                      {
                        'Id': 'st-low',
                        'Subject': 'Step Second',
                        'OrderDateTime': '2026-11-22T08:00:00.0000000Z',
                      },
                      {
                        'Id': 'st-high',
                        'Subject': 'Step First',
                        'OrderDateTime': '2026-11-22T12:00:00.0000000Z',
                      },
                    ],
                  }),
                  RemoteTodoTask.fromJson({
                    'Id': 'rt-bottom',
                    'ChangeKey': 'ck-2',
                    'ParentFolderId': 'rf-default',
                    'Subject': 'Default Third',
                    'OrderDateTime': '2026-11-22T08:00:00.0000000Z',
                    'CreatedDateTime': '2026-11-22T07:00:00.0000000Z',
                  }),
                  RemoteTodoTask.fromJson({
                    'Id': 'rt-tie-earlier',
                    'ChangeKey': 'ck-3',
                    'ParentFolderId': 'rf-default',
                    'Subject': 'Tie Created Earlier',
                    'OrderDateTime': '2026-11-22T10:00:00.000-1234Z',
                    'CreatedDateTime': '2026-11-22T06:00:00.0000000Z',
                  }),
                ],
                deltaLink: 'dl-default-1',
              );
            }
            if (defaultTaskSyncCount == 2) {
              return DeltaPageResult(
                items: [
                  RemoteTodoTask.fromJson({
                    'Id': 'rt-bottom',
                    'ChangeKey': 'ck-2b',
                    'ParentFolderId': 'rf-default',
                    'Subject': 'Default Third',
                    'OrderDateTime': '2026-11-22T14:00:00.0000000Z',
                    'CreatedDateTime': '2026-11-22T07:00:00.0000000Z',
                  }),
                ],
                deltaLink: 'dl-default-2',
              );
            }
            return DeltaPageResult(
              items: const [],
              deltaLink: 'dl-$folderId-latest',
            );
          }
          if (dl != null) {
            return DeltaPageResult(
              items: const [],
              deltaLink: 'dl-$folderId-2',
            );
          }
          if (folderId == 'rf-custom') {
            return DeltaPageResult(
              items: [
                RemoteTodoTask.fromJson({
                  'Id': 'rt-due-today-uncommitted',
                  'ChangeKey': 'ck-c1',
                  'ParentFolderId': 'rf-custom',
                  'Subject': 'Due Today Uncommitted',
                  // High OrderDateTime should NOT beat an explicit CommittedOrder in My Day!
                  'OrderDateTime': '2026-11-22T15:00:00.0000000Z',
                  'DueDate': formatDayString(today),
                  'CreatedDateTime': '2026-11-22T05:00:00.0000000Z',
                }),
                RemoteTodoTask.fromJson({
                  'Id': 'rt-myday-low',
                  'ChangeKey': 'ck-c2',
                  'ParentFolderId': 'rf-custom',
                  'Subject': 'MyDay Second',
                  'OrderDateTime': '2026-11-22T07:00:00.0000000Z',
                  'CommittedDay': formatDayString(today),
                  'CommittedOrder': '2026-11-22T09:00:00.0000000Z',
                  'CreatedDateTime': '2026-11-22T06:00:00.0000000Z',
                }),
                RemoteTodoTask.fromJson({
                  'Id': 'rt-myday-top',
                  'ChangeKey': 'ck-c3',
                  'ParentFolderId': 'rf-custom',
                  'Subject': 'MyDay First',
                  'OrderDateTime': '2026-11-22T12:00:00.0000000Z',
                  'CommittedDay': formatDayString(today),
                  'CommittedOrder': '2026-11-22T11:00:00.0000000Z',
                  'CreatedDateTime': '2026-11-22T07:00:00.0000000Z',
                }),
              ],
              deltaLink: 'dl-custom-1',
            );
          }
          return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
        };
        fakeApi.onPatchTask = (taskRemoteId, patch, ck) async {
          if (taskRemoteId == 'rt-bottom') {
            uiReorderPatch = Map<String, dynamic>.from(patch);
          }
          return RemoteTodoTask(
            id: taskRemoteId,
            changeKey: 'ck-patched-$taskRemoteId',
            parentFolderId: 'rf-default',
            subject: patch['Subject'] as String? ?? 'Task',
            orderDateTime: parseSubstrateTimestamp(
              patch['OrderDateTime'] as String?,
            ),
          );
        };

        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
              microsoftTodoApiProvider.overrideWithValue(fakeApi),
              realtimeSyncEnabledProvider.overrideWithValue(false),
            ],
            child: const YataApp(),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        await container.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();

        // Verify Tasks default list manual order (including legacy .-1234Z & CreatedDateTime ASC tiebreak)
        await tester.tap(find.text('Tasks'));
        await tester.pumpAndSettle();

        void assertTasksOrder() {
          final yTieEarlier = tester
              .getTopLeft(find.text('Tie Created Earlier'))
              .dy;
          final yTieLater = tester
              .getTopLeft(find.text('Tie Created Later'))
              .dy;
          final yDefaultThird = tester
              .getTopLeft(find.text('Default Third'))
              .dy;
          expect(yTieEarlier, lessThan(yTieLater));
          expect(yTieLater, lessThan(yDefaultThird));
        }

        assertTasksOrder();

        // Verify subtasks sorted descending by OrderDateTime
        final tieTask = container
            .read(todoProvider)
            .tasks
            .firstWhere((t) => t.remoteId == 'rt-tie-later');
        expect(tieTask.steps.map((s) => s.title).toList(), [
          'Step First',
          'Step Second',
        ]);

        // Navigate back and verify custom list & My Day manual order
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Work Tasks'));
        await tester.pumpAndSettle();

        void assertCustomListOrder() {
          final yDueToday = tester
              .getTopLeft(find.text('Due Today Uncommitted'))
              .dy;
          final yMyDayTop = tester.getTopLeft(find.text('MyDay First')).dy;
          final yMyDayLow = tester.getTopLeft(find.text('MyDay Second')).dy;
          expect(yDueToday, lessThan(yMyDayTop));
          expect(yMyDayTop, lessThan(yMyDayLow));
        }

        assertCustomListOrder();

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        await tester.tap(find.text('My Day'));
        await tester.pumpAndSettle();

        void assertMyDayOrder() {
          final yMyDayTop = tester.getTopLeft(find.text('MyDay First')).dy;
          final yMyDayLow = tester.getTopLeft(find.text('MyDay Second')).dy;
          final yDueToday = tester
              .getTopLeft(find.text('Due Today Uncommitted'))
              .dy;
          expect(yMyDayTop, lessThan(yMyDayLow));
          expect(yMyDayLow, lessThan(yDueToday));
        }

        assertMyDayOrder();

        // Restart app (without syncing) and verify My Day & Tasks order persist
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
              microsoftTodoApiProvider.overrideWithValue(fakeApi),
              realtimeSyncEnabledProvider.overrideWithValue(false),
            ],
            child: const YataApp(),
          ),
        );
        await tester.pumpAndSettle();
        // Last entered list was My Day (or Home if not persisted) -> open My Day if needed
        if (find.text('MyDay First').evaluate().isEmpty) {
          await tester.tap(find.text('My Day'));
          await tester.pumpAndSettle();
        }
        assertMyDayOrder();

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tasks'));
        await tester.pumpAndSettle();
        assertTasksOrder();

        final restartedContainer = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );

        // In-place remote delta reorder while viewing Tasks updates AnimatedTaskSliverList visually
        await restartedContainer.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Default Third')).dy,
          lessThan(tester.getTopLeft(find.text('Tie Created Earlier')).dy),
        );

        // Reorder via UI menu + keyboard_arrow_down + check, then sync PATCH
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.reorder));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.text('Tie Created Earlier')).dy,
          lessThan(tester.getTopLeft(find.text('Default Third')).dy),
        );
        await restartedContainer.read(syncProvider.notifier).syncNow();
        expect(uiReorderPatch?['OrderDateTime'], isNotNull);
      },
    );

    test('Task manual reorder pushes OrderDateTime / CommittedOrder cleanly without Reminder or stale ParentFolderId, retries 412 conflicts, and sends ParentFolderId on cross-list move', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_task_push_order',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_task_push_order',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs)
          .saveActiveAccountId('acct_task_push_order');

      final fakeApi = FakeSubstrateApi();
      final today = DateTime.now();
      final patchedPayloads = <String, List<Map<String, dynamic>>>{};
      var return412Once = true;

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

      final tWide1 = DateTime.utc(2026, 11, 22, 12);
      final tWide2 = DateTime.utc(2026, 11, 22, 10);
      final tTightBase = DateTime.utc(2026, 11, 22, 9, 0, 10);
      final tTightSecond = DateTime.utc(2026, 11, 22, 9, 0, 0);

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
        if (taskRemoteId == 'rt-w1' && return412Once) {
          return412Once = false;
          throw const SyncApiException(
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
          committedOrder: parseSubstrateTimestamp(
            patch['CommittedOrder'] as String?,
          ),
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

      await container.read(syncProvider.notifier).syncNow();

      final presenter = container.read(tasksViewPresenterProvider);
      final detailPresenter = container.read(detailViewPresenterProvider);

      // 1) Wide-gap single move in Tasks (rt-w1 from index 0 to index 1)
      container.read(todoProvider.notifier).selectList('tasks');
      final tasksVisible = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(tasksVisible.map((t) => t.remoteId), ['rt-w1', 'rt-w2']);
      presenter.reorderActiveTasks(tasksVisible, 0, 1);

      await container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads.keys, contains('rt-w1'));
      expect(patchedPayloads.containsKey('rt-w2'), isFalse);
      final w1Patch = patchedPayloads['rt-w1']!.single;
      expect(w1Patch.containsKey('Reminder'), isFalse);
      expect(w1Patch.containsKey('ParentFolderId'), isFalse);
      expect(w1Patch['OrderDateTime'], isNotNull);
      final w1Updated = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-w1');
      expect(w1Updated.changeKey, 'ck-patched-rt-w1');
      expect(w1Updated.orderDateTime!.isBefore(tWide2), isTrue);

      // 2) Tight <= 16s / equal timestamps in Work custom list trigger full re-space
      patchedPayloads.clear();
      final workList = container
          .read(todoProvider)
          .lists
          .firstWhere((l) => l.remoteId == 'rf-work');
      container.read(todoProvider.notifier).selectList(workList.id);
      final workVisible = container.read(todoProvider).tasksForList(workList);
      expect(workVisible.map((t) => t.remoteId), [
        'rt-tight-1',
        'rt-tight-2',
        'rt-tight-3',
      ]);
      // Move rt-tight-3 (equal timestamp to rt-tight-2, only 10s below rt-tight-1) to middle
      presenter.reorderActiveTasks(workVisible, 2, 1);

      await container.read(syncProvider.notifier).syncNow();

      // Anchor equals rt-tight-1's timestamp so rt-tight-1 doesn't need a redundant PATCH,
      // while rt-tight-3 and rt-tight-2 are re-spaced descending in 4096s steps.
      expect(patchedPayloads.containsKey('rt-tight-1'), isFalse);
      expect(patchedPayloads.containsKey('rt-tight-2'), isTrue);
      expect(patchedPayloads.containsKey('rt-tight-3'), isTrue);
      for (final pList in patchedPayloads.values) {
        expect(pList.single.containsKey('Reminder'), isFalse);
        expect(pList.single.containsKey('ParentFolderId'), isFalse);
      }
      final afterTight = container
          .read(todoProvider)
          .tasksForList(
            container
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

      // 3) Reorder due-today uncommitted task (rt-tight-1, myDayDate == null) above committed task (rt-w1) in My Day
      patchedPayloads.clear();
      container.read(todoProvider.notifier).selectList('my_day');
      final myDayVisible = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(myDayVisible.map((t) => t.remoteId), ['rt-w1', 'rt-tight-1']);
      presenter.reorderActiveTasks(myDayVisible, 1, 0);

      await container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-tight-1'], isNotNull);
      final tightMyDayPatch = patchedPayloads['rt-tight-1']!.single;
      expect(tightMyDayPatch['CommittedOrder'], isNotNull);
      expect(tightMyDayPatch.containsKey('Reminder'), isFalse);
      final syncedMyDay = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(syncedMyDay.map((t) => t.remoteId), ['rt-tight-1', 'rt-w1']);

      // 4) Cross-list move MUST include ParentFolderId; subsequent same-folder edit MUST omit it
      patchedPayloads.clear();
      final w2 = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-w2');
      detailPresenter.moveTaskToList(w2.id, workList.id);
      await container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-w2']!.single['ParentFolderId'], 'rf-work');

      patchedPayloads.clear();
      detailPresenter.updateTaskTitle(w2.id, 'Wide Bottom Renamed');
      await container.read(syncProvider.notifier).syncNow();

      expect(
        patchedPayloads['rt-w2']!.single.containsKey('ParentFolderId'),
        isFalse,
      );
      expect(
        patchedPayloads['rt-w2']!.single['Subject'],
        'Wide Bottom Renamed',
      );
    });

    test('concurrent syncNow calls share the in-flight sync future', () async {
      final prefs = await SharedPreferences.getInstance();
      await AuthTokenStorage(prefs).saveTokens(
        'acct_shared_sync',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_shared_sync',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

      final started = Completer<void>();
      final release = Completer<void>();
      final fakeApi = BlockingFoldersApi(started, release);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final first = container.read(syncProvider.notifier).syncNow();
      await started.future;
      expect(container.read(syncProvider).isSyncing, isTrue);

      var secondCompleted = false;
      unawaited(
        container.read(syncProvider.notifier).syncNow().whenComplete(() {
          secondCompleted = true;
        }),
      );
      await pumpEventQueue();

      expect(secondCompleted, isFalse);
      expect(container.read(syncProvider).isSyncing, isTrue);

      release.complete();
      await first;
      await pumpEventQueue();

      expect(secondCompleted, isTrue);
      expect(container.read(syncProvider).status, SyncStatus.success);
      expect(fakeApi.folderFetchCount, greaterThanOrEqualTo(2));
    });

    testWidgets(
      'auto-syncs once when the shell mounts for a never-synced account',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await AuthTokenStorage(prefs).saveTokens(
          'acct_auto_sync',
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: 'cid1',
          ),
        );
        final account = MicrosoftAccount(
          id: 'acct_auto_sync',
          displayName: 'Alice',
          email: 'alice@outlook.com',
          createdAt: DateTime(2026, 11, 22),
          microsoftUserId: 'cid1',
        );
        await AccountLocalStorage(prefs).saveAccounts([account]);
        await AccountLocalStorage(prefs).saveActiveAccountId(account.id);

        final fakeApi = FakeSubstrateApi();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const YataApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(container.read(syncProvider).status, SyncStatus.success);
        final active = container.read(accountProvider).activeAccount;
        expect(active, isA<MicrosoftAccount>());
        expect((active! as MicrosoftAccount).lastSyncedAt, isNotNull);
        expect(
          fakeApi.callLog.where((c) => c.startsWith('GET foldergroups')).length,
          1,
        );
        expect(container.read(todoProvider).lists, isNotEmpty);
      },
    );
  });
}
