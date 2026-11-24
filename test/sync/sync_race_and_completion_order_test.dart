import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/cloud_sync_service.dart';
import 'package:yata/sync/microsoft_todo_models.dart';
import 'package:yata/tasksview/tasks_view_grouping.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  test('applySyncResult preserves local task edit made while persisting settings patch', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final initialTask = TaskItem(
      id: 't1',
      listId: 'tasks',
      title: 'Original',
      createdAt: DateTime.utc(2026, 11, 23, 8),
      remoteId: 'rt1',
    );
    final repo = TodoRepository.forAccount(prefs);
    await repo.saveTasks([initialTask]);

    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(todoProvider.notifier);
    final snapshot = container.read(todoProvider);

    // Start applySyncResult (which updates state synchronously before awaiting
    // persistence) and immediately mutate the task locally while its
    // persistence futures are still in flight.
    final applyFuture = notifier.applySyncResult(
      lists: snapshot.lists,
      tasks: [initialTask],
      snapshotLists: snapshot.lists,
      snapshotTasks: snapshot.tasks,
      snapshotState: snapshot,
      settingsPatch: const SyncedSettingsPatch(playCompletionSound: false),
    );

    final current = container.read(todoProvider);
    notifier.commit(
      current.copyWith(
        tasks: [initialTask.copyWith(title: 'Edited During Apply')],
      ),
    );

    await applyFuture;

    final finalState = container.read(todoProvider);
    expect(finalState.tasks.single.title, 'Edited During Apply');
    expect(repo.loadDirtyTaskIds(), contains('t1'));
  });

  test('TodoRepository updates in-memory cache synchronously before awaiting DB write', () async {
    final repo = TodoRepository(
      sharedFallbackTodoDatabase,
      accountKey: 'acct_cache_test',
      scopeKey: 'acct_cache_test',
    );
    final task = TaskItem(
      id: 't1',
      listId: 'tasks',
      title: 'Sync Cache',
      createdAt: DateTime.utc(2026, 11, 23, 8),
    );

    final saveTaskFuture = repo.saveTasks([task]);
    final saveDirtyFuture = repo.saveDirtyTaskIds({'t1'});

    // Readers must immediately see the new cache without awaiting the DB future.
    expect(repo.readCachedTasks().single.title, 'Sync Cache');
    expect(repo.loadDirtyTaskIds(), ['t1']);

    await Future.wait([saveTaskFuture, saveDirtyFuture]);
  });

  test('CloudSyncService preserves local completedAt precision when remote returns same-day midnight CompletedDateTime', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = TodoSettingsStore(prefs, accountId: 'acct');
    final repo = TodoRepository.forAccount(prefs, accountId: 'acct');

    final t1 = TaskItem(
      id: 't1',
      listId: 'tasks',
      title: 'First completed',
      createdAt: DateTime.utc(2026, 11, 23, 8, 0),
      isCompleted: true,
      completedAt: DateTime.utc(2026, 11, 23, 10, 0, 1),
      remoteId: 'rt1',
      orderDateTime: DateTime.utc(2026, 11, 23, 8, 3),
    );
    final t2 = TaskItem(
      id: 't2',
      listId: 'tasks',
      title: 'Second completed',
      createdAt: DateTime.utc(2026, 11, 23, 8, 1),
      isCompleted: true,
      completedAt: DateTime.utc(2026, 11, 23, 10, 0, 2),
      remoteId: 'rt2',
      orderDateTime: DateTime.utc(2026, 11, 23, 8, 2),
    );
    final t3 = TaskItem(
      id: 't3',
      listId: 'tasks',
      title: 'Third completed',
      createdAt: DateTime.utc(2026, 11, 23, 8, 2),
      isCompleted: true,
      completedAt: DateTime.utc(2026, 11, 23, 10, 0, 3),
      remoteId: 'rt3',
      orderDateTime: DateTime.utc(2026, 11, 23, 8, 1),
    );

    final fakeApi = FakeSubstrateApi();
    fakeApi.onFetchFoldersDelta = (_) => const DeltaPageResult(
      items: [
        RemoteTodoFolder(
          id: 'rf-default',
          name: 'Tasks',
          isDefaultFolder: true,
        ),
      ],
      deltaLink: 'dl-folders',
    );
    fakeApi.onFetchTasksDelta = (folderId, dl) => DeltaPageResult(
      items: [
        RemoteTodoTask(
          id: 'rt1',
          parentFolderId: 'rf-default',
          subject: 'First completed',
          status: 'Completed',
          completedDateTime: DateTime.utc(2026, 11, 23, 0, 0, 0),
          orderDateTime: DateTime.utc(2026, 11, 23, 8, 3),
        ),
        RemoteTodoTask(
          id: 'rt2',
          parentFolderId: 'rf-default',
          subject: 'Second completed',
          status: 'Completed',
          completedDateTime: DateTime.utc(2026, 11, 23, 0, 0, 0),
          orderDateTime: DateTime.utc(2026, 11, 23, 8, 2),
        ),
        RemoteTodoTask(
          id: 'rt3',
          parentFolderId: 'rf-default',
          subject: 'Third completed',
          status: 'Completed',
          completedDateTime: DateTime.utc(2026, 11, 23, 0, 0, 0),
          orderDateTime: DateTime.utc(2026, 11, 23, 8, 1),
        ),
      ],
      deltaLink: 'dl-tasks',
    );

    final tokenStorage = AuthTokenStorage(prefs);
    await tokenStorage.saveTokens(
      'acct',
      MicrosoftAuthTokens(
        accessToken: 'tok-1',
        refreshToken: 'rt-1',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        userId: 'cid1',
      ),
    );
    final service = CloudSyncService(
      authClient: FakeAuthClient(),
      todoApi: fakeApi,
      tokenStorage: tokenStorage,
    );
    final account = MicrosoftAccount(
      id: 'acct',
      displayName: 'Alice',
      email: 'alice@outlook.com',
      createdAt: DateTime.utc(2026, 11, 23),
      microsoftUserId: 'cid1',
    );
    const tasksList = TodoList(
      id: 'tasks',
      title: 'Tasks',
      smartType: SmartListType.tasks,
      remoteId: 'rf-default',
    );
    final state = TodoState(
      lists: const [tasksList],
      groups: const [],
      tasks: [t1, t2, t3],
      selectedListId: 'tasks',
    );
    await repo.saveLists(state.lists);
    await repo.saveTasks(state.tasks);
    await repo.saveDirtyTaskIds({'t1', 't2', 't3'});

    final result = await service.syncAccount(
      account: account,
      currentState: state,
      repository: repo,
      settings: settings,
      idGenerator: (p) => '${p}_gen',
    );

    final outcome = result.getOrThrow();
    final split = splitTasksForDisplay(outcome.tasks, tasksList);
    expect(split.completed.map((t) => t.id), ['t3', 't2', 't1']);
  });
}
