import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/main.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/todo_wire_codecs.dart';

import '../helpers/microsoft_sync_fakes.dart';

Future<void> _pumpYataApp(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required FakeSubstrateApi api,
  bool startupSyncEnabled = false,
  Key? key,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: key,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
        microsoftTodoApiProvider.overrideWithValue(api),
        realtimeSyncEnabledProvider.overrideWithValue(false),
        periodicSyncEnabledProvider.overrideWithValue(false),
        startupSyncEnabledProvider.overrideWithValue(startupSyncEnabled),
      ],
      child: const YataApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SyncNotifier UI integration', () {
    testWidgets(
      'Tasks default list displays Completed pill even when remote ShowCompletedTasks is false and syncs toggle',
      (tester) async {
        final session = await seedMicrosoftSyncSession(
          accountId: 'acct_tasks_done',
        );
        Map<String, dynamic>? patchedDefaultFolder;
        final fakeApi = FakeSubstrateApi();
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
        addTearDown(fakeApi.realtimeController.close);

        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpYataApp(tester, prefs: session.prefs, api: fakeApi);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        await container.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tasks'));
        await tester.pumpAndSettle();

        expect(find.text('Active default task'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Done default task'), findsNothing);

        await tester.tap(find.text('Completed'));
        await tester.pumpAndSettle();
        expect(find.text('Done default task'), findsOneWidget);

        // The debounced push-only pass sends the edit; no manual refresh.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(patchedDefaultFolder?['ShowCompletedTasks'], isTrue);
        expect(
          TodoRepository.forAccount(
            session.prefs,
            accountId: 'acct_tasks_done',
          ).outbox.pendingLocalIds(SyncEntityType.list),
          isNot(contains('tasks')),
        );
      },
    );

    testWidgets(
      'Sidebar renders remote groups, interleaved ungrouped lists, and group members in descending OrderDateTime order across restarts',
      (tester) async {
        final session = await seedMicrosoftSyncSession(
          accountId: 'acct_order_ui',
        );
        final fakeApi = FakeSubstrateApi();
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
        addTearDown(fakeApi.realtimeController.close);

        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpYataApp(tester, prefs: session.prefs, api: fakeApi);

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

        await _pumpYataApp(
          tester,
          key: UniqueKey(),
          prefs: session.prefs,
          api: fakeApi,
        );
        assertOrder();
      },
    );

    testWidgets(
      'Pulls remote task and subtask manual order (including legacy .-Z timestamps, CreatedDateTime ASC tiebreak, and My Day CommittedOrder) and preserves across restarts',
      (tester) async {
        final session = await seedMicrosoftSyncSession(
          accountId: 'acct_task_pull_order',
          lastSyncedAt: DateTime(2026, 11, 22, 8),
        );
        final today = DateTime.now();
        var defaultTaskSyncCount = 0;
        Map<String, dynamic>? uiReorderPatch;
        final fakeApi = FakeSubstrateApi();
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
        addTearDown(fakeApi.realtimeController.close);

        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpYataApp(tester, prefs: session.prefs, api: fakeApi);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        await container.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();

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

        final tieTask = container
            .read(todoProvider)
            .tasks
            .firstWhere((t) => t.remoteId == 'rt-tie-later');
        expect(tieTask.steps.map((s) => s.title).toList(), [
          'Step First',
          'Step Second',
        ]);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Work Tasks'));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.text('Due Today Uncommitted')).dy,
          lessThan(tester.getTopLeft(find.text('MyDay First')).dy),
        );
        expect(
          tester.getTopLeft(find.text('MyDay First')).dy,
          lessThan(tester.getTopLeft(find.text('MyDay Second')).dy),
        );

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

        await _pumpYataApp(
          tester,
          key: UniqueKey(),
          prefs: session.prefs,
          api: fakeApi,
        );
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

        await restartedContainer.read(syncProvider.notifier).syncNow();
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Default Third')).dy,
          lessThan(tester.getTopLeft(find.text('Tie Created Earlier')).dy),
        );

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

    testWidgets(
      'auto-syncs on shell mount for both never-synced and previously synced accounts',
      (tester) async {
        // 1) Never-synced account
        final neverSynced = await seedMicrosoftSyncSession(
          accountId: 'acct_auto_sync',
        );
        final api1 = FakeSubstrateApi();
        addTearDown(api1.realtimeController.close);

        await _pumpYataApp(
          tester,
          prefs: neverSynced.prefs,
          api: api1,
          startupSyncEnabled: true,
        );

        final container1 = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        expect(container1.read(syncProvider).status, SyncStatus.success);
        final active1 = container1.read(accountProvider).activeAccount;
        expect(active1, isA<MicrosoftAccount>());
        expect((active1! as MicrosoftAccount).lastSyncedAt, isNotNull);
        expect(
          api1.callLog.where((c) => c.startsWith('GET foldergroups')).length,
          1,
        );
        expect(container1.read(todoProvider).lists, isNotEmpty);

        // 2) Previously synced account on cold start
        final initialSyncedAt = DateTime(2026, 11, 22, 12, 0);
        final coldStart = await seedMicrosoftSyncSession(
          accountId: 'acct_cold_start',
          lastSyncedAt: initialSyncedAt,
        );
        final api2 = FakeSubstrateApi();
        addTearDown(api2.realtimeController.close);

        await _pumpYataApp(
          tester,
          key: UniqueKey(),
          prefs: coldStart.prefs,
          api: api2,
          startupSyncEnabled: true,
        );

        final container2 = ProviderScope.containerOf(
          tester.element(find.byType(YataApp)),
        );
        expect(container2.read(syncProvider).status, SyncStatus.success);
        expect(
          api2.callLog.where((c) => c.startsWith('GET foldergroups')).length,
          greaterThanOrEqualTo(1),
        );
        final active2 =
            container2.read(accountProvider).activeAccount as MicrosoftAccount;
        expect(active2.lastSyncedAt!.isAfter(initialSyncedAt), isTrue);
      },
    );

    testWidgets(
      'pull-to-refresh bypasses saved taskDeltaLinks and visually reorders tasks',
      (tester) async {
        final tOld = DateTime.utc(2026, 11, 22, 8);
        final tMid = DateTime.utc(2026, 11, 22, 10);
        final tNew = DateTime.utc(2026, 11, 22, 14);

        final session = await seedMicrosoftSyncSession(
          accountId: 'acct_ptr_reorder',
          lastSyncedAt: DateTime(2026, 11, 22, 12, 0),
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
        addTearDown(fakeApi.realtimeController.close);

        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await _pumpYataApp(tester, prefs: session.prefs, api: fakeApi);

        await tester.tap(find.text('Tasks'));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.text('Task One')).dy,
          lessThan(tester.getTopLeft(find.text('Task Two')).dy),
        );

        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, 500),
        );
        await tester.pump();
        expect(find.byType(RefreshProgressIndicator), findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();

        expect(fakeApi.callLog, contains('GET tasks(rf-default,null)'));
        expect(
          tester.getTopLeft(find.text('Task Two')).dy,
          lessThan(tester.getTopLeft(find.text('Task One')).dy),
        );
      },
    );
  });
}
