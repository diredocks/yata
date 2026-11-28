import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/sync/sync_outbox.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/data/storage/todo_repository.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_models.dart';
import 'package:yata/sync/microsoft/substrate_pull_engine.dart';
import 'package:yata/sync/microsoft/substrate_push_engine.dart';
import 'package:yata/sync/microsoft/todo_wire_codecs.dart';
import 'package:yata/sync/sync_dispatcher.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/ui/task_grouping.dart';

import '../helpers/microsoft_sync_fakes.dart';

import 'package:yata/data/storage/preferences.dart';
import 'package:yata/data/storage/todo_database.dart';

void main() {
  test('applyPulledState preserves local task edit made while persisting settings patch', () async {
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

    // Start applyPulledState (which updates state synchronously before awaiting
    // persistence) and immediately mutate the task locally while its
    // persistence futures are still in flight.
    final applyFuture = notifier.applyRemoteState(
      lists: snapshot.lists,
      tasks: [initialTask],
      remoteSettings: const {TodoSettingKeys.soundOnCompletion: 'false'},
    );

    notifier.mutateTask('t1', (t) => t.copyWith(title: 'Edited During Apply'));

    await applyFuture;

    final finalState = container.read(todoProvider);
    expect(finalState.tasks.single.title, 'Edited During Apply');
    expect(repo.outbox.pendingLocalIds(SyncEntityType.task), contains('t1'));
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
    repo.outbox.enqueueUpsert(entityType: SyncEntityType.task, localId: 't1');
    final saveOutboxFuture = repo.saveOutbox();

    // Readers must immediately see the new cache without awaiting the DB future.
    expect(repo.readCachedTasks().single.title, 'Sync Cache');
    expect(repo.outbox.pendingLocalIds(SyncEntityType.task), {'t1'});

    await Future.wait([saveTaskFuture, saveOutboxFuture]);
  });

  test('SubstratePullEngine preserves local completedAt precision when remote returns same-day midnight CompletedDateTime', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
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
    for (final id in ['t1', 't2', 't3']) {
      repo.outbox.enqueueUpsert(entityType: SyncEntityType.task, localId: id);
    }
    await repo.saveOutbox();

    final pushOutcome = (await SubstratePushEngine(fakeApi).pushOutbox(
      readState: () => state,
      outbox: repo.outbox,
      nowUtc: DateTime.now().toUtc(),
      onItemCommitted: (o) async {
        repo.outbox.ackBatch(o.ackedSeqs);
        await repo.saveOutbox();
      },
    )).getOrThrow();
    final postPushState = state.copyWith(
      tasks: [for (final t in state.tasks) pushOutcome.pushedTasks[t.id] ?? t],
    );
    final outcome = (await SubstratePullEngine(fakeApi).pull(
      repository: repo,
      readState: () => postPushState,
      idGenerator: (p) => '${p}_gen',
    )).getOrThrow();
    final split = splitTasksForDisplay(outcome.tasks, tasksList);
    expect(split.completed.map((t) => t.id), ['t3', 't2', 't1']);
  });

  test(
    'TodoRepository.flushPendingWrites waits for queued SQLite writes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TodoRepository.forAccount(
        prefs,
        accountId: 'acct_flush',
        database: db,
      );
      final task = TaskItem(
        id: 't_flush',
        listId: 'tasks',
        title: 'Persist me',
        createdAt: DateTime.utc(2026, 11, 24),
      );

      unawaited(repo.saveTasks([task]));
      await repo.flushPendingWrites();

      final rows = await db.selectTaskItemRecords('acct_flush');
      expect(rows, hasLength(1));
      expect(rows.single.id, 't_flush');
    },
  );

  test('SyncNotifier drains Delete op with newly created remoteId when task is deleted mid-sync', () async {
    final createStarted = Completer<void>();
    final releaseCreate = Completer<void>();
    final fakeApi = FakeSubstrateApi();
    fakeApi.onCreateTask = (folderRemoteId, payload) async {
      createStarted.complete();
      await releaseCreate.future;
      return RemoteTodoTask(
        id: 'rt_5',
        parentFolderId: folderRemoteId,
        subject: payload['Subject'] as String? ?? '5',
        status: 'NotStarted',
        changeKey: 'ck-5',
      );
    };
    fakeApi.onFetchTasksDelta = (folderId, dl) =>
        const DeltaPageResult(items: [], deltaLink: 'dl-tasks-new');

    final h = await createSyncTestHarness(
      accountId: 'acct_mid_delete',
      api: fakeApi,
      defaultTasksFolderRemoteId: 'rf-default',
      taskDeltaLinks: const {'rf-default': 'dl-tasks'},
    );

    final todoNotifier = h.container.read(todoProvider.notifier);
    final task5 = TaskItem(
      id: 't_5',
      listId: 'tasks',
      title: '5',
      createdAt: DateTime.utc(2026, 11, 25, 8),
    );
    todoNotifier.addTask(task5);

    final syncFuture = h.container
        .read(syncProvider.notifier)
        .syncNow(reason: SyncReason.localMutation);
    await createStarted.future;

    // User deletes task 5 locally while its createTask request is in flight!
    todoNotifier.deleteTasks(const {'t_5'});
    releaseCreate.complete();
    await syncFuture;

    expect(h.container.read(todoProvider).tasks, isEmpty);
    expect(h.repository.outbox.isEmpty, isTrue);
    expect(h.api.callLog, contains('POST taskfolders/rf-default/tasks 5'));
    expect(h.api.callLog, contains('DELETE tasks/rt_5'));
  });

  test('SyncNotifier drains Delete step op with newly created remoteId when step is deleted mid-sync', () async {
    final stepStarted = Completer<void>();
    final releaseStep = Completer<void>();
    final fakeApi = FakeSubstrateApi();
    fakeApi.onCreateStep = (taskRemoteId, subject, orderDateTime) async {
      stepStarted.complete();
      await releaseStep.future;
      return RemoteTaskStep(id: 'rs_1', subject: subject);
    };
    fakeApi.onFetchTasksDelta = (folderId, dl) =>
        const DeltaPageResult(items: [], deltaLink: 'dl-tasks-new');

    const step = TaskStep(id: 's_new', title: 'Step 1');
    final task = TaskItem(
      id: 't_parent',
      listId: 'tasks',
      title: 'Parent',
      createdAt: DateTime.utc(2026, 11, 25, 8),
      remoteId: 'rt_parent',
      steps: const [step],
    );

    final h = await createSyncTestHarness(
      accountId: 'acct_mid_step_delete',
      api: fakeApi,
      defaultTasksFolderRemoteId: 'rf-default',
      taskDeltaLinks: const {'rf-default': 'dl-tasks'},
      tasks: [task],
      dirtyTaskIds: {'t_parent'},
    );

    final syncFuture = h.container
        .read(syncProvider.notifier)
        .syncNow(reason: SyncReason.localMutation);
    await stepStarted.future;

    // User deletes the step locally while its createStep request is in flight!
    final todoNotifier = h.container.read(todoProvider.notifier);
    todoNotifier.mutateTask('t_parent', (t) => t.copyWith(steps: const []));
    releaseStep.complete();
    await syncFuture;

    expect(h.container.read(todoProvider).tasks.single.steps, isEmpty);
    expect(h.repository.outbox.isEmpty, isTrue);
    expect(h.api.callLog, contains('POST tasks/rt_parent/subtasks Step 1'));
    expect(h.api.callLog, contains('DELETE tasks/rt_parent/subtasks/rs_1'));
  });
}
