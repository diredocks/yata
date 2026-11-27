import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_local_storage.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/background_sync_bridge.dart';
import 'package:yata/sync/background_sync_entrypoint.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/microsoft/substrate_pull_engine.dart';
import 'package:yata/sync/microsoft/substrate_push_engine.dart';
import 'package:yata/sync/sync_provider.dart';

import '../helpers/microsoft_sync_fakes.dart';

Future<SyncTestHarness> _createSqliteSyncHarness({
  required String accountId,
  required TodoDatabase database,
  FakeSubstrateApi? api,
  String defaultTasksFolderRemoteId = 'rf-default',
  List<TodoList> extraLists = const [],
  List<ListGroup> groups = const [],
  List<TaskItem> tasks = const [],
  String? groupsDeltaLink,
  String? foldersDeltaLink,
  Map<String, String>? taskDeltaLinks,
  Set<String>? dirtyGroupIds,
  Set<String>? dirtyListIds,
  Set<String>? dirtyTaskIds,
  bool realtimeSyncEnabled = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final account = MicrosoftAccount(
    id: accountId,
    displayName: 'Alice',
    email: 'alice@outlook.com',
    microsoftUserId: 'cid1',
  );
  await AccountLocalStorage(prefs).saveAccounts([account]);
  await AccountLocalStorage(prefs).saveActiveAccountId(accountId);
  await AuthTokenStorage(prefs).saveTokens(
    accountId,
    MicrosoftAuthTokens(
      accessToken: 'tok-1',
      refreshToken: 'rt-1',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      userId: 'cid1',
    ),
  );

  final settings = TodoSettingsStore(prefs, accountId: accountId);
  final repository = TodoRepository.forSession(database, settings);
  if (groups.isNotEmpty) {
    await repository.saveGroups(groups);
  }
  await repository.saveLists([
    ...defaultSmartLists().map(
      (l) => l.smartType == SmartListType.tasks
          ? l.copyWith(remoteId: defaultTasksFolderRemoteId)
          : l,
    ),
    ...extraLists,
  ]);
  if (tasks.isNotEmpty) {
    await repository.saveTasks(tasks);
  }
  await repository.saveSyncMetaBatch(
    groupsDeltaLink: groupsDeltaLink,
    updateGroupsDeltaLink: groupsDeltaLink != null,
    foldersDeltaLink: foldersDeltaLink,
    updateFoldersDeltaLink: foldersDeltaLink != null,
    taskDeltaLinks: taskDeltaLinks,
  );
  for (final id in dirtyGroupIds ?? const <String>{}) {
    repository.outbox.enqueueUpsert(
      entityType: SyncEntityType.group,
      localId: id,
    );
  }
  for (final id in dirtyListIds ?? const <String>{}) {
    repository.outbox.enqueueUpsert(
      entityType: SyncEntityType.list,
      localId: id,
    );
  }
  for (final id in dirtyTaskIds ?? const <String>{}) {
    repository.outbox.enqueueUpsert(
      entityType: SyncEntityType.task,
      localId: id,
    );
  }
  await repository.saveOutbox();
  await repository.flushPendingWrites();

  final effectiveApi = api ?? FakeSubstrateApi();
  final authClient = FakeAuthClient();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoDatabaseProvider.overrideWithValue(database),
      microsoftAuthClientProvider.overrideWithValue(authClient),
      microsoftTodoApiProvider.overrideWithValue(effectiveApi),
      realtimeSyncEnabledProvider.overrideWithValue(realtimeSyncEnabled),
      periodicSyncEnabledProvider.overrideWithValue(false),
      startupSyncEnabledProvider.overrideWithValue(false),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await effectiveApi.realtimeController.close();
  });

  return SyncTestHarness(
    prefs: prefs,
    account: account,
    repository: repository,
    settings: settings,
    api: effectiveApi,
    authClient: authClient,
    container: container,
  );
}

AppError _notFound([String id = 'ErrorItemNotFound']) =>
    AppError.notFound(message: 'Item not found', id: id);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Remote delete zombie prevention (Delete Wins)', () {
    test('Probe A: steps-only task op hitting 404 deletes zombie task in state, SQLite, and outbox', () async {
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 11, 27, 8);
      final fakeApi = FakeSubstrateApi()
        ..onCreateStep = ((taskRemoteId, subject, order) async {
          throw _notFound();
        })
        ..onFetchFoldersDelta = ((dl) => const DeltaPageResult(
          items: [
            RemoteTodoFolder(
              id: 'rf-default',
              name: 'Tasks',
              isDefaultFolder: true,
            ),
          ],
          deltaLink: 'dl-folders-2',
        ))
        ..onFetchTasksDelta = ((folderId, dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-tasks-2'));

      final h = await _createSqliteSyncHarness(
        accountId: 'acct_probe_a',
        database: db,
        api: fakeApi,
        tasks: [
          TaskItem(
            id: 't_zombie',
            listId: 'tasks',
            title: 'Zombie Task',
            createdAt: now,
            remoteId: 'rt-zombie',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-zombie',
          ),
        ],
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      h.container
          .read(detailViewPresenterProvider)
          .addStep('t_zombie', 'New Step');
      expect(h.repository.outbox.ops, hasLength(1));

      await h.container.read(syncProvider.notifier).syncNow();
      expect(h.container.read(syncProvider).status, SyncStatus.success);
      expect(h.container.read(todoProvider).tasks, isEmpty);
      expect(h.repository.outbox.ops, isEmpty);

      await h.repository.flushPendingWrites();
      final reloaded = TodoRepository.forSession(db, h.settings);
      (await reloaded.preload()).getOrThrow();
      expect(reloaded.readCachedTasks(), isEmpty);
      expect(reloaded.outbox.ops, isEmpty);

      await h.container.read(syncProvider.notifier).refresh();
      expect(h.container.read(syncProvider).status, SyncStatus.success);
      expect(
        fakeApi.callLog
            .where((c) => c == 'POST tasks/rt-zombie/subtasks New Step')
            .length,
        1,
      );
    });

    test('steps-only patchStep 404 deletes task when getTask returns 404, or drops only the step when getTask returns 200', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      var taskExistsRemotely = false;
      final fakeApi = FakeSubstrateApi()
        ..onPatchStep = (taskRemoteId, stepRemoteId, patch) async {
          throw _notFound();
        }
        ..onGetTask = (taskRemoteId) async {
          if (!taskExistsRemotely) throw _notFound();
          return RemoteTodoTask(
            id: taskRemoteId,
            changeKey: 'ck-live',
            parentFolderId: 'rf-default',
            subject: 'Live Task',
          );
        }
        ..onFetchTasksDelta = (folderId, dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-t-2');

      // Subcase 1: parent task also deleted (getTask 404).
      final hDeletedTask = await createSyncTestHarness(
        accountId: 'acct_step_404_task_gone',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_gone',
            listId: 'tasks',
            title: 'Deleted Task',
            createdAt: now,
            remoteId: 'rt-gone',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
            steps: const [
              TaskStep(id: 's_1', title: 'Step 1', remoteId: 'rs-1'),
            ],
          ),
        ],
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );
      hDeletedTask.container
          .read(detailViewPresenterProvider)
          .toggleStepCompleted('t_gone', 's_1');
      await hDeletedTask.container.read(syncProvider.notifier).syncNow();
      expect(
        hDeletedTask.container.read(syncProvider).status,
        SyncStatus.success,
      );
      expect(hDeletedTask.container.read(todoProvider).tasks, isEmpty);
      expect(hDeletedTask.repository.outbox.ops, isEmpty);

      // Subcase 2: parent task alive (getTask 200), only step deleted remotely.
      taskExistsRemotely = true;
      fakeApi.callLog.clear();
      final hStepOnlyGone = await createSyncTestHarness(
        accountId: 'acct_step_404_task_live',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_live',
            listId: 'tasks',
            title: 'Live Task',
            createdAt: now,
            remoteId: 'rt-live',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-live',
            steps: const [
              TaskStep(
                id: 's_deleted',
                title: 'Deleted Step',
                remoteId: 'rs-del',
              ),
              TaskStep(id: 's_kept', title: 'Kept Step', remoteId: 'rs-kept'),
            ],
          ),
        ],
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );
      hStepOnlyGone.container
          .read(detailViewPresenterProvider)
          .toggleStepCompleted('t_live', 's_deleted');

      await hStepOnlyGone.container.read(syncProvider.notifier).syncNow();
      expect(
        hStepOnlyGone.container.read(syncProvider).status,
        SyncStatus.success,
      );
      final remaining = hStepOnlyGone.container.read(todoProvider).tasks;
      expect(remaining, hasLength(1));
      expect(remaining.single.steps.map((s) => s.id).toList(), ['s_kept']);
      expect(hStepOnlyGone.repository.outbox.ops, isEmpty);
      expect(
        fakeApi.callLog.any((c) => c.startsWith('POST tasks/rt-live/subtasks')),
        isFalse,
      );
    });

    test('task PATCH 409 conflict followed by getTask 404 deletes local task without resurrecting it', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      final fakeApi = FakeSubstrateApi()
        ..onPatchTask = (id, patch, changeKey) async {
          throw const AppError.network(
            statusCode: 409,
            code: 'ErrorIrresolvableConflict',
            message: 'conflict',
          );
        }
        ..onGetTask = (id) async {
          throw _notFound();
        };

      final h = await createSyncTestHarness(
        accountId: 'acct_409_404',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Edited Task',
            createdAt: now,
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
        ],
        dirtyTaskIds: const {'t_1'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      await h.container.read(syncProvider.notifier).syncNow();
      expect(h.container.read(syncProvider).status, SyncStatus.success);
      expect(h.container.read(todoProvider).tasks, isEmpty);
      expect(h.repository.outbox.ops, isEmpty);
      expect(
        fakeApi.callLog.any((c) => c.contains('POST taskfolders/')),
        isFalse,
      );
    });

    test('attachment upload 404 deletes zombie task in both foreground syncNow and headless background transfer lane', () async {
      final tempDir = Directory.systemTemp.createTempSync('yata_att_404_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final fgFilePath = p.join(tempDir.path, 'fg', 'note.txt');
      File(fgFilePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('hello');
      final bgFilePath = p.join(tempDir.path, 'bg', 'note.txt');
      File(bgFilePath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('hello');
      final now = DateTime.utc(2026, 11, 27, 8);

      // Foreground syncNow()
      final fgDb = TodoDatabase(NativeDatabase.memory());
      addTearDown(fgDb.close);
      final fgApi = FakeSubstrateApi()
        ..onUploadAttachment = (taskRemoteId, fileName, bytes, ct) async {
          throw _notFound();
        };
      final h = await _createSqliteSyncHarness(
        accountId: 'acct_att_fg',
        database: fgDb,
        api: fgApi,
        tasks: [
          TaskItem(
            id: 't_att',
            listId: 'tasks',
            title: 'Task With Att',
            createdAt: now,
            remoteId: 'rt-att',
            remoteParentFolderId: 'rf-default',
            attachments: [
              TaskAttachment(
                id: 'att_1',
                displayName: 'note.txt',
                localPath: fgFilePath,
                isTransferring: true,
              ),
            ],
          ),
        ],
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );
      h.repository.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_1',
        parentLocalId: 't_att',
        parentRemoteId: 'rt-att',
      );
      await h.repository.saveOutbox();

      await h.container.read(syncProvider.notifier).syncNow();
      await h.repository.flushPendingWrites();
      expect(h.container.read(syncProvider).status, SyncStatus.success);
      expect(h.container.read(todoProvider).tasks, isEmpty);
      expect(h.repository.outbox.ops, isEmpty);
      expect(File(fgFilePath).existsSync(), isFalse);
      expect(Directory(p.dirname(fgFilePath)).existsSync(), isFalse);

      // Headless background transfer lane
      final bgDb = TodoDatabase(NativeDatabase.memory());
      addTearDown(bgDb.close);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final bgSettings = TodoSettingsStore(prefs, accountId: 'acct_att_bg');
      final bgRepo = TodoRepository.forSession(bgDb, bgSettings);
      await bgRepo.saveTasks([
        TaskItem(
          id: 't_bg',
          listId: 'tasks',
          title: 'BG Att Task',
          createdAt: now,
          remoteId: 'rt-bg',
          remoteParentFolderId: 'rf-default',
          attachments: [
            TaskAttachment(
              id: 'att_bg',
              displayName: 'note.txt',
              localPath: bgFilePath,
              isTransferring: true,
            ),
          ],
        ),
      ]);
      bgRepo.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_bg',
        parentLocalId: 't_bg',
        parentRemoteId: 'rt-bg',
      );
      await bgRepo.saveOutbox();
      await bgRepo.flushPendingWrites();

      final emittedEvents = <BackgroundDbChangedEvent>[];
      final passOutcome = await runBackgroundOutboxPass(
        repository: bgRepo,
        settings: bgSettings,
        todoApi: fgApi,
        lane: BackgroundSyncLane.transfer,
        reason: 'bg_test',
        onDbChanged: emittedEvents.add,
      );
      expect(passOutcome.shouldRetry, isFalse);
      expect(passOutcome.didMutateDb, isTrue);
      expect(emittedEvents, hasLength(1));
      expect(File(bgFilePath).existsSync(), isFalse);
      expect(Directory(p.dirname(bgFilePath)).existsSync(), isFalse);

      final verifyRepo = TodoRepository.forSession(bgDb, bgSettings);
      (await verifyRepo.preload()).getOrThrow();
      expect(verifyRepo.readCachedTasks(), isEmpty);
      expect(verifyRepo.outbox.ops, isEmpty);
    });

    test('handles group PATCH 404, custom folder PATCH 404, and task CREATE in deleted custom folder 404 without deleting smart lists', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      final fakeApi = FakeSubstrateApi()
        ..onPatchGroup = ((remoteId, patch) async {
          throw _notFound();
        })
        ..onPatchFolder = ((remoteId, patch) async {
          if (remoteId == 'rf-custom') throw _notFound();
          return RemoteTodoFolder(
            id: remoteId,
            name: patch['Name'] as String? ?? 'List',
            parentFolderGroupId: patch['ParentFolderGroupId'] as String?,
          );
        })
        ..onCreateTask = ((folderRemoteId, payload) async {
          if (folderRemoteId == 'rf-dead-folder') throw _notFound();
          return RemoteTodoTask(
            id: 'rt-created',
            changeKey: 'ck-created',
            parentFolderId: folderRemoteId,
            subject: payload['Subject'] as String? ?? 'Task',
          );
        });

      final h = await createSyncTestHarness(
        accountId: 'acct_group_folder_404',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        groups: const [
          ListGroup(id: 'g_1', title: 'Deleted Group', remoteId: 'rg-1'),
          ListGroup(id: 'g_kept', title: 'Kept Group', remoteId: 'rg-kept'),
        ],
        extraLists: const [
          TodoList(
            id: 'list_custom',
            title: 'Deleted Custom',
            remoteId: 'rf-custom',
          ),
          TodoList(
            id: 'list_in_deleted_group',
            title: 'In Deleted Group',
            groupId: 'g_1',
            remoteId: 'rf-in-del-group',
          ),
          TodoList(
            id: 'list_dead_for_create',
            title: 'Dead For Create',
            remoteId: 'rf-dead-folder',
          ),
        ],
        tasks: [
          TaskItem(
            id: 't_in_custom',
            listId: 'list_custom',
            title: 'In Deleted Custom',
            createdAt: now,
            remoteId: 'rt-in-custom',
          ),
          TaskItem(
            id: 't_create_in_dead',
            listId: 'list_dead_for_create',
            title: 'Create In Dead Folder',
            createdAt: now,
          ),
        ],
        dirtyListIds: const {'list_custom'},
        dirtyTaskIds: const {'t_create_in_dead'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );
      h.repository.outbox.enqueueUpsert(
        entityType: SyncEntityType.group,
        localId: 'g_1',
      );

      await h.container.read(syncProvider.notifier).syncNow();
      expect(h.container.read(syncProvider).status, SyncStatus.success);
      final state = h.container.read(todoProvider);
      expect(state.groups.map((g) => g.id).toList(), ['g_kept']);
      expect(state.lists.any((l) => l.id == 'list_custom'), isFalse);
      expect(state.lists.any((l) => l.id == 'list_dead_for_create'), isFalse);
      expect(state.lists.any((l) => l.id == 'tasks'), isTrue);
      final ungrouped = state.lists.firstWhere(
        (l) => l.id == 'list_in_deleted_group',
      );
      expect(ungrouped.groupId, isNull);
      expect(state.tasks, isEmpty);
      expect(h.repository.outbox.ops, isEmpty);
      expect(
        fakeApi.callLog.any((c) => c.startsWith('POST foldergroups')),
        isFalse,
      );
      expect(
        fakeApi.callLog.any(
          (c) => c.contains('POST taskfolders Deleted Custom'),
        ),
        isFalse,
      );

      // Default smart list must never be deleted on task CREATE 404.
      final smartApi = FakeSubstrateApi()
        ..onCreateTask = (folderRemoteId, payload) async => throw _notFound();
      final hSmart = await createSyncTestHarness(
        accountId: 'acct_smart_never_deleted',
        api: smartApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_smart_new',
            listId: 'tasks',
            title: 'New Task',
            createdAt: now,
          ),
        ],
        dirtyTaskIds: const {'t_smart_new'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );
      await hSmart.container.read(syncProvider.notifier).syncNow();
      expect(hSmart.container.read(syncProvider).status, SyncStatus.error);
      expect(
        hSmart.container.read(todoProvider).lists.any((l) => l.id == 'tasks'),
        isTrue,
      );
    });

    test('Probe B: non-selective delta pull deletes dirty task, dirty list, and dirty group on tombstone, prunes outbox in SQLite, and preserves cross-folder moves', () async {
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime.utc(2026, 11, 27, 8);
      final fakeApi = FakeSubstrateApi()
        ..onFetchGroupsDelta = ((dl) => const DeltaPageResult(
          items: [RemoteFolderGroup(id: 'rg-del', name: '', isDeleted: true)],
          deltaLink: 'dl-groups-2',
        ))
        ..onFetchFoldersDelta = ((dl) => const DeltaPageResult(
          items: [RemoteTodoFolder(id: 'rf-del', name: '', isDeleted: true)],
          deltaLink: 'dl-folders-2',
        ))
        ..onFetchTasksDelta = ((folderId, dl) {
          if (folderId == 'rf-default') {
            return const DeltaPageResult(
              items: [
                RemoteTodoTask(id: 'rt-zombie', subject: '', isDeleted: true),
                RemoteTodoTask(id: 'rt-moved', subject: '', isDeleted: true),
              ],
              deltaLink: 'dl-default-2',
            );
          }
          if (folderId == 'rf-other') {
            return const DeltaPageResult(
              items: [
                RemoteTodoTask(
                  id: 'rt-moved',
                  changeKey: 'ck-moved-new',
                  parentFolderId: 'rf-other',
                  subject: 'Moved Remotely',
                ),
              ],
              deltaLink: 'dl-other-2',
            );
          }
          return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
        });

      final h = await _createSqliteSyncHarness(
        accountId: 'acct_probe_b',
        database: db,
        api: fakeApi,
        groups: const [
          ListGroup(
            id: 'g_del',
            title: 'Dirty Deleted Group',
            remoteId: 'rg-del',
          ),
        ],
        extraLists: const [
          TodoList(
            id: 'list_del',
            title: 'Dirty Deleted List',
            remoteId: 'rf-del',
          ),
          TodoList(id: 'list_other', title: 'Other List', remoteId: 'rf-other'),
        ],
        tasks: [
          TaskItem(
            id: 't_zombie',
            listId: 'tasks',
            title: 'Dirty Zombie',
            createdAt: now,
            remoteId: 'rt-zombie',
            remoteParentFolderId: 'rf-default',
          ),
          TaskItem(
            id: 't_in_del_list',
            listId: 'list_del',
            title: 'Task In Deleted List',
            createdAt: now,
            remoteId: 'rt-in-del',
            remoteParentFolderId: 'rf-del',
          ),
          TaskItem(
            id: 't_moved',
            listId: 'tasks',
            title: 'Dirty Moved Task',
            createdAt: now,
            remoteId: 'rt-moved',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-moved-1',
          ),
        ],
        dirtyGroupIds: const {'g_del'},
        dirtyListIds: const {'list_del'},
        dirtyTaskIds: const {'t_zombie', 't_in_del_list', 't_moved'},
        groupsDeltaLink: 'dl-groups-1',
        foldersDeltaLink: 'dl-folders-1',
        taskDeltaLinks: const {
          'rf-default': 'dl-default-1',
          'rf-other': 'dl-other-1',
        },
      );

      final todoNotifier = h.container.read(todoProvider.notifier);
      final pullResult = await SubstratePullEngine(fakeApi).pull(
        repository: h.repository,
        readState: () => h.container.read(todoProvider),
        idGenerator: todoNotifier.nextId,
        onReconciled: (outcome) => todoNotifier.applyRemoteState(
          groups: outcome.groups,
          lists: outcome.lists,
          tasks: outcome.tasks,
          remoteSettings: outcome.remoteSettings,
        ),
      );
      expect(pullResult.isSuccess(), isTrue);

      final state = h.container.read(todoProvider);
      expect(state.groups, isEmpty);
      expect(state.lists.any((l) => l.id == 'list_del'), isFalse);
      expect(state.tasks.map((t) => t.id).toList(), ['t_moved']);
      expect(
        h.repository.outbox.pendingLocalIds(SyncEntityType.group),
        isEmpty,
      );
      expect(h.repository.outbox.pendingLocalIds(SyncEntityType.list), isEmpty);
      expect(h.repository.outbox.pendingLocalIds(SyncEntityType.task), {
        't_moved',
      });
      expect(h.repository.loadGroupsDeltaLink(), 'dl-groups-2');
      expect(h.repository.loadFoldersDeltaLink(), 'dl-folders-2');
      expect(h.repository.loadTaskDeltaLinks()['rf-default'], 'dl-default-2');

      await h.repository.flushPendingWrites();
      final reloaded = TodoRepository.forSession(db, h.settings);
      (await reloaded.preload()).getOrThrow();
      expect(reloaded.readCachedTasks().map((t) => t.id).toList(), ['t_moved']);
      expect(reloaded.outbox.pendingLocalIds(SyncEntityType.task), {'t_moved'});
    });

    test('selective pull withholds deltaLink advancement on dirty task tombstone so next delta pull deletes it', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      final fakeApi = FakeSubstrateApi()
        ..onFetchFoldersDelta = ((dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-f-2'))
        ..onFetchTasksDelta = ((folderId, dl) {
          if (dl == 'dl-t-1') {
            return const DeltaPageResult(
              items: [
                RemoteTodoTask(id: 'rt-dirty', subject: '', isDeleted: true),
              ],
              deltaLink: 'dl-t-2',
            );
          }
          return DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-t-2');
        });

      final h = await createSyncTestHarness(
        accountId: 'acct_selective_defer',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_dirty',
            listId: 'tasks',
            title: 'Dirty Task',
            createdAt: now,
            remoteId: 'rt-dirty',
            remoteParentFolderId: 'rf-default',
          ),
        ],
        dirtyTaskIds: const {'t_dirty'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      final todoNotifier = h.container.read(todoProvider.notifier);
      final selectiveResult = await SubstratePullEngine(fakeApi).pull(
        repository: h.repository,
        readState: () => h.container.read(todoProvider),
        idGenerator: todoNotifier.nextId,
        onlyFolderRemoteIds: const {'rf-default'},
        onReconciled: (outcome) => todoNotifier.applyRemoteState(
          tasks: outcome.tasks,
          remoteSettings: outcome.remoteSettings,
        ),
      );
      expect(selectiveResult.isSuccess(), isTrue);
      expect(h.container.read(todoProvider).tasks, hasLength(1));
      expect(h.repository.loadTaskDeltaLinks()['rf-default'], 'dl-t-1');

      final deltaResult = await SubstratePullEngine(fakeApi).pull(
        repository: h.repository,
        readState: () => h.container.read(todoProvider),
        idGenerator: todoNotifier.nextId,
        onReconciled: (outcome) => todoNotifier.applyRemoteState(
          groups: outcome.groups,
          lists: outcome.lists,
          tasks: outcome.tasks,
          remoteSettings: outcome.remoteSettings,
        ),
      );
      expect(deltaResult.isSuccess(), isTrue);
      expect(h.container.read(todoProvider).tasks, isEmpty);
      expect(h.repository.outbox.ops, isEmpty);
      expect(h.repository.loadTaskDeltaLinks()['rf-default'], 'dl-t-2');
    });

    test('realtime Task/Deleted removes dirty task immediately and handles Task/Updated + Task/Deleted in same drained batch', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      final pullStarted = Completer<void>();
      final releasePull = Completer<void>();
      final fakeApi = BlockingFoldersApi(pullStarted, releasePull)
        ..onFetchTasksDelta = (folderId, dl) =>
            DeltaPageResult(items: const [], deltaLink: dl ?? 'dl-t-2');

      final h = await createSyncTestHarness(
        accountId: 'acct_rt_delete_wins',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_1',
            listId: 'tasks',
            title: 'Dirty RT 1',
            createdAt: now,
            remoteId: 'rt-1',
            remoteParentFolderId: 'rf-default',
          ),
          TaskItem(
            id: 't_2',
            listId: 'tasks',
            title: 'Dirty RT 2',
            createdAt: now,
            remoteId: 'rt-2',
            remoteParentFolderId: 'rf-default',
          ),
        ],
        dirtyTaskIds: const {'t_1', 't_2'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
        realtimeSyncEnabled: true,
      );

      h.container.read(syncProvider);
      await pumpEventQueue();

      // Immediate deletion while idle.
      h.api.realtimeController.add(
        const RealtimeEvent(type: 'Task', operation: 'Deleted', id: 'rt-1'),
      );
      await pumpEventQueue();
      expect(h.container.read(todoProvider).tasks.map((t) => t.id).toList(), [
        't_2',
      ]);
      expect(h.repository.outbox.pendingLocalIds(SyncEntityType.task), {'t_2'});

      // Drained batch while pull is in flight: Task/Updated followed by Task/Deleted.
      final pullFuture = h.container.read(syncProvider.notifier).refresh();
      await pullStarted.future;

      h.api.realtimeController.add(
        const RealtimeEvent(
          type: 'Task',
          operation: 'Updated',
          id: 'rt-2',
          payload: {
            'Id': 'rt-2',
            'Subject': 'Dirty RT 2',
            'ParentFolderId': 'rf-default',
          },
        ),
      );
      h.api.realtimeController.add(
        const RealtimeEvent(type: 'Task', operation: 'Deleted', id: 'rt-2'),
      );
      await pumpEventQueue();

      releasePull.complete();
      await pullFuture;
      await pumpEventQueue();

      expect(h.container.read(todoProvider).tasks, isEmpty);
      expect(h.repository.outbox.ops, isEmpty);
    });

    test('full-sync prune removes stale dirty zombie absent from complete snapshot while keeping uncreated and concurrently edited tasks', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      final pullStarted = Completer<void>();
      final releasePull = Completer<void>();
      final fakeApi = BlockingFoldersApi(pullStarted, releasePull)
        ..onFetchFoldersDelta = ((dl) => const DeltaPageResult(
          items: [
            RemoteTodoFolder(
              id: 'rf-default',
              name: 'Tasks',
              isDefaultFolder: true,
            ),
          ],
          deltaLink: 'dl-f-full',
        ))
        ..onFetchTasksDelta = ((folderId, dl) =>
            const DeltaPageResult(items: [], deltaLink: 'dl-t-full'));

      final h = await createSyncTestHarness(
        accountId: 'acct_full_prune_seq',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_stale_zombie',
            listId: 'tasks',
            title: 'Stale Dirty Zombie',
            createdAt: now,
            remoteId: 'rt-stale',
            remoteParentFolderId: 'rf-default',
          ),
          TaskItem(
            id: 't_local_only',
            listId: 'tasks',
            title: 'Never Pushed Yet',
            createdAt: now,
          ),
          TaskItem(
            id: 't_concurrent',
            listId: 'tasks',
            title: 'Edited Mid-Pull',
            createdAt: now,
            remoteId: 'rt-concurrent',
            remoteParentFolderId: 'rf-default',
          ),
        ],
        dirtyTaskIds: const {'t_stale_zombie', 't_local_only'},
      );

      final preSeq = h.repository.outbox.lastSeq;
      final todoNotifier = h.container.read(todoProvider.notifier);
      final pullFuture = SubstratePullEngine(fakeApi).pull(
        repository: h.repository,
        readState: () => h.container.read(todoProvider),
        idGenerator: todoNotifier.nextId,
        forceFullSync: true,
        pruneProtectSinceSeq: preSeq,
        onReconciled: (outcome) => todoNotifier.applyRemoteState(
          groups: outcome.groups,
          lists: outcome.lists,
          tasks: outcome.tasks,
          remoteSettings: outcome.remoteSettings,
        ),
      );
      await pullStarted.future;

      // Concurrent edit during full pull creates an op with seq > preSeq.
      h.container
          .read(detailViewPresenterProvider)
          .updateTaskTitle('t_concurrent', 'Edited Mid-Pull Updated');

      releasePull.complete();
      final outcome = await pullFuture;
      expect(outcome.isSuccess(), isTrue);

      final remainingIds = h.container
          .read(todoProvider)
          .tasks
          .map((t) => t.id)
          .toSet();
      expect(remainingIds, {'t_local_only', 't_concurrent'});
      expect(h.repository.outbox.pendingLocalIds(SyncEntityType.task), {
        't_local_only',
        't_concurrent',
      });
    });

    test('preserves unresolved push error across subsequent pull success and clears it once push recovers or pull prunes the op', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      var failPatch = true;
      var returnRemoteTombstone = false;
      final fakeApi = FakeSubstrateApi()
        ..onPatchTask = (id, patch, changeKey) async {
          if (failPatch) {
            throw const AppError.network(
              statusCode: 400,
              code: 'ErrorInvalidRequest',
              message: 'Bad request',
            );
          }
          return RemoteTodoTask(
            id: id,
            changeKey: 'ck-2',
            parentFolderId: 'rf-default',
            subject: patch['Subject'] as String? ?? 'Live',
          );
        }
        ..onFetchTasksDelta = (folderId, dl) => DeltaPageResult(
          items: [
            RemoteTodoTask(
              id: 'rt-live',
              changeKey: 'ck-1',
              parentFolderId: 'rf-default',
              subject: 'Live',
              isDeleted: returnRemoteTombstone,
            ),
          ],
          deltaLink: 'dl-t-2',
        );

      final h = await createSyncTestHarness(
        accountId: 'acct_push_err_preserve',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_live',
            listId: 'tasks',
            title: 'Edited Live',
            createdAt: now,
            remoteId: 'rt-live',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-1',
          ),
        ],
        dirtyTaskIds: const {'t_live'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );

      await h.container.read(syncProvider.notifier).syncNow();
      final syncStateAfterFail = h.container.read(syncProvider);
      expect(syncStateAfterFail.status, SyncStatus.error);
      expect(syncStateAfterFail.error, 'Bad request');
      expect(syncStateAfterFail.lastSyncedAt, isNotNull);
      expect(
        (h.container.read(accountProvider).activeAccount as MicrosoftAccount?)
            ?.syncError,
        'Bad request',
      );
      expect(h.repository.outbox.ops, hasLength(1));

      // When pull removes the failing entity and prunes its outbox op, error clears.
      returnRemoteTombstone = true;
      await h.container.read(syncProvider.notifier).syncNow();
      final syncStateAfterPrune = h.container.read(syncProvider);
      expect(syncStateAfterPrune.status, SyncStatus.success);
      expect(syncStateAfterPrune.error, isNull);
      expect(
        (h.container.read(accountProvider).activeAccount as MicrosoftAccount?)
            ?.syncError,
        isNull,
      );
      expect(h.repository.outbox.ops, isEmpty);

      // Also verify recovery when push succeeds directly on retry.
      returnRemoteTombstone = false;
      h.container
          .read(todoProvider.notifier)
          .commit(
            h.container
                .read(todoProvider)
                .copyWith(
                  tasks: [
                    TaskItem(
                      id: 't_live_2',
                      listId: 'tasks',
                      title: 'Live 2',
                      createdAt: now,
                      remoteId: 'rt-live-2',
                      remoteParentFolderId: 'rf-default',
                      changeKey: 'ck-2',
                    ),
                  ],
                ),
          );
      await h.container.read(syncProvider.notifier).syncNow();
      expect(h.container.read(syncProvider).status, SyncStatus.error);
      failPatch = false;
      await h.container.read(syncProvider.notifier).syncNow();
      final syncStateAfterHeal = h.container.read(syncProvider);
      expect(syncStateAfterHeal.status, SyncStatus.success);
      expect(syncStateAfterHeal.error, isNull);
      expect(
        (h.container.read(accountProvider).activeAccount as MicrosoftAccount?)
            ?.syncError,
        isNull,
      );
      expect(h.repository.outbox.ops, isEmpty);
    });

    test('non-retryable 400 error on one task does not block other tasks or attachments, while retryable 500/401 aborts immediately', () async {
      final tempDir = Directory.systemTemp.createTempSync('yata_iso_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final filePath = p.join(tempDir.path, 'att.txt');
      File(filePath).writeAsStringSync('payload');
      final now = DateTime.utc(2026, 11, 27, 8);

      // Non-retryable 400 on Task A allows Task B and Attachment C to commit.
      final api400 = FakeSubstrateApi()
        ..onPatchTask = (id, patch, changeKey) async {
          if (id == 'rt-a') {
            throw const AppError.network(
              statusCode: 400,
              code: 'ErrorInvalidRequest',
              message: 'Invalid task A',
            );
          }
          return RemoteTodoTask(
            id: id,
            changeKey: 'ck-b-2',
            parentFolderId: 'rf-default',
            subject: patch['Subject'] as String? ?? 'Task B',
          );
        };

      final h400 = await createSyncTestHarness(
        accountId: 'acct_isolate_400',
        api: api400,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_a',
            listId: 'tasks',
            title: 'Task A',
            createdAt: now,
            remoteId: 'rt-a',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-a',
          ),
          TaskItem(
            id: 't_b',
            listId: 'tasks',
            title: 'Task B',
            createdAt: now,
            remoteId: 'rt-b',
            remoteParentFolderId: 'rf-default',
            changeKey: 'ck-b',
            attachments: [
              TaskAttachment(
                id: 'att_c',
                displayName: 'att.txt',
                localPath: filePath,
                isTransferring: true,
              ),
            ],
          ),
        ],
        dirtyTaskIds: const {'t_a', 't_b'},
        groupsDeltaLink: 'dl-g-1',
        foldersDeltaLink: 'dl-f-1',
        taskDeltaLinks: const {'rf-default': 'dl-t-1'},
      );
      h400.repository.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_c',
        parentLocalId: 't_b',
        parentRemoteId: 'rt-b',
      );

      final todoNotifier = h400.container.read(todoProvider.notifier);
      final push400Result = await SubstratePushEngine(api400).pushOutbox(
        readState: () => h400.container.read(todoProvider),
        outbox: h400.repository.outbox,
        nowUtc: now,
        onItemCommitted: todoNotifier.commitPushBatch,
      );
      expect(push400Result.isError(), isTrue);
      expect(h400.repository.outbox.ops.map((op) => op.localId).toList(), [
        't_a',
      ]);
      expect(api400.callLog, contains('POST tasks/rt-b/attachments (att.txt)'));
      final pushedB = h400.container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_b');
      expect(pushedB.attachments.single.remoteId, isNotNull);

      // Retryable 500 or AuthError aborts stage immediately before attachment upload.
      for (final fatalErr in [
        const AppError.network(statusCode: 500, message: 'Server error'),
        const AppError.auth(message: 'Expired', requiresReauth: true),
      ]) {
        final apiFatal = FakeSubstrateApi()
          ..onPatchTask = (id, patch, changeKey) async {
            if (id == 'rt-a') throw fatalErr;
            return RemoteTodoTask(
              id: id,
              changeKey: 'ck-b-2',
              parentFolderId: 'rf-default',
              subject: 'Task B',
            );
          };
        final hFatal = await createSyncTestHarness(
          accountId: 'acct_fatal_${fatalErr.hashCode}',
          api: apiFatal,
          defaultTasksFolderRemoteId: 'rf-default',
          tasks: [
            TaskItem(
              id: 't_a',
              listId: 'tasks',
              title: 'Task A',
              createdAt: now,
              remoteId: 'rt-a',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-a',
            ),
            TaskItem(
              id: 't_b',
              listId: 'tasks',
              title: 'Task B',
              createdAt: now,
              remoteId: 'rt-b',
              remoteParentFolderId: 'rf-default',
              changeKey: 'ck-b',
              attachments: [
                TaskAttachment(
                  id: 'att_c',
                  displayName: 'att.txt',
                  localPath: filePath,
                  isTransferring: true,
                ),
              ],
            ),
          ],
          dirtyTaskIds: const {'t_a', 't_b'},
        );
        hFatal.repository.outbox.enqueueUpsert(
          entityType: SyncEntityType.attachment,
          localId: 'att_c',
          parentLocalId: 't_b',
          parentRemoteId: 'rt-b',
        );

        final notifierFatal = hFatal.container.read(todoProvider.notifier);
        final pushFatalResult = await SubstratePushEngine(apiFatal).pushOutbox(
          readState: () => hFatal.container.read(todoProvider),
          outbox: hFatal.repository.outbox,
          nowUtc: now,
          onItemCommitted: notifierFatal.commitPushBatch,
        );
        expect(pushFatalResult.isError(), isTrue);
        expect(
          apiFatal.callLog.any((c) => c.contains('/attachments')),
          isFalse,
        );
      }
    });

    test('applyRemoteState prunes stale task/step/attachment remoteIds while preserving pending delete keys', () async {
      final now = DateTime.utc(2026, 11, 27, 8);
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final keptTask = TaskItem(
        id: 't_kept',
        listId: 'tasks',
        title: 'Kept',
        remoteId: 'rt-kept',
        remoteParentFolderId: 'rf-default',
        steps: const [
          TaskStep(id: 's_kept', title: 'Kept step', remoteId: 'rs-kept'),
        ],
        attachments: const [
          TaskAttachment(
            id: 'att_kept',
            displayName: 'kept.txt',
            remoteId: 'ra-kept',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      final goneTask = TaskItem(
        id: 't_gone',
        listId: 'tasks',
        title: 'Gone',
        remoteId: 'rt-gone',
        remoteParentFolderId: 'rf-default',
        steps: const [
          TaskStep(id: 's_gone', title: 'Gone step', remoteId: 'rs-gone'),
        ],
        attachments: const [
          TaskAttachment(
            id: 'att_gone',
            displayName: 'gone.txt',
            remoteId: 'ra-gone',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final h = await _createSqliteSyncHarness(
        accountId: 'acct_prune_remote_ids',
        database: db,
        tasks: [keptTask, goneTask],
      );
      h.repository.outbox
        ..enqueueUpsert(entityType: SyncEntityType.task, localId: 't_gone')
        ..enqueueDelete(
          entityType: SyncEntityType.step,
          localId: 's_pending_del',
          remoteId: 'rs-pending-del',
          parentLocalId: 't_pending_del',
          parentRemoteId: 'rt-pending-del',
        );
      await h.repository.saveOutbox();
      await h.repository.flushPendingWrites();

      await h.container
          .read(todoProvider.notifier)
          .applyRemoteState(tasks: [keptTask]);
      await h.repository.flushPendingWrites();

      final taskRows = await db.selectTaskItemRecords(h.repository.accountKey);
      expect(taskRows, hasLength(1));
      expect(taskRows.single.id, 't_kept');

      final verifyRepo = TodoRepository(
        db,
        accountKey: h.repository.accountKey,
        scopeKey: 'verify_prune',
      );
      (await verifyRepo.preload()).getOrThrow();

      expect(verifyRepo.outbox.ops, hasLength(1));
      expect(verifyRepo.outbox.ops.single.localId, 's_pending_del');
      expect(verifyRepo.outbox.ops.single.remoteId, 'rs-pending-del');
    });
  });
}
