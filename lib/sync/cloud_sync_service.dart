import '../data/todo_local_storage.dart';
import '../models/account.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../auth/microsoft_auth_service.dart';
import 'microsoft_todo_api.dart';

class SyncOutcome {
  const SyncOutcome({
    required this.lists,
    required this.tasks,
    required this.syncedAt,
  });

  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final DateTime syncedAt;
}

class CloudSyncService {
  CloudSyncService({
    required this.authClient,
    required this.tokenStorage,
    required this.todoApi,
  });

  final MicrosoftAuthClient authClient;
  final AuthTokenStorage tokenStorage;
  final MicrosoftTodoApi todoApi;

  Future<String> _getValidAccessToken(String accountId) async {
    final tokens = tokenStorage.load(accountId);
    if (tokens == null) {
      throw const MicrosoftAuthException(
        'Session expired. Please sign in again.',
        requiresRelogin: true,
      );
    }
    if (!tokens.isExpired) {
      return tokens.accessToken;
    }
    final refreshed = await authClient.refreshTokens(tokens);
    await tokenStorage.save(accountId, refreshed);
    return refreshed.accessToken;
  }

  Future<SyncOutcome> sync({
    required MicrosoftAccount account,
    required List<TodoList> localLists,
    required List<TaskItem> localTasks,
    required List<String> pendingDeletedListRemoteIds,
    required List<PendingTaskDeletion> pendingDeletedTasks,
    bool addNewTasksOnTop = true,
  }) async {
    final accessToken = await _getValidAccessToken(account.id);

    // 1. Push pending task deletions, then list deletions.
    final deletedListSet = pendingDeletedListRemoteIds.toSet();
    for (final deletion in pendingDeletedTasks) {
      if (deletedListSet.contains(deletion.listRemoteId)) continue;
      await todoApi.deleteTask(
        accessToken,
        deletion.listRemoteId,
        deletion.taskRemoteId,
      );
    }
    for (final listRemoteId in deletedListSet) {
      await todoApi.deleteList(accessToken, listRemoteId);
    }

    // 2. Fetch remote lists and reconcile.
    final remoteLists = await todoApi.fetchLists(accessToken);
    final remoteById = {for (final r in remoteLists) r.id: r};
    final remoteDefaultList = remoteLists.where((r) => r.isDefaultList).firstOrNull;

    final mergedLists = <TodoList>[];
    final matchedRemoteListIds = <String>{};
    // Maps local listId -> remote listId for task syncing.
    final localToRemoteListId = <String, String>{};
    final removedLocalListIds = <String>{};

    for (final local in localLists) {
      if (local.smartType == SmartListType.tasks) {
        final remoteId = remoteDefaultList?.id ?? local.remoteId;
        final updated = local.copyWith(remoteId: remoteId);
        mergedLists.add(updated);
        if (remoteId != null) {
          matchedRemoteListIds.add(remoteId);
          localToRemoteListId[local.id] = remoteId;
        }
        continue;
      }

      if (local.isSmartList) {
        mergedLists.add(local);
        continue;
      }

      // Custom list
      if (local.remoteId == null) {
        final created = await todoApi.createList(accessToken, local.title);
        final updated = local.copyWith(
          remoteId: created.id,
          updatedAt: DateTime.now().toUtc(),
        );
        mergedLists.add(updated);
        matchedRemoteListIds.add(created.id);
        localToRemoteListId[local.id] = created.id;
      } else {
        final remote = remoteById[local.remoteId!];
        if (remote == null) {
          // Deleted remotely
          removedLocalListIds.add(local.id);
          continue;
        }
        matchedRemoteListIds.add(remote.id);
        var reconciled = local;
        if (remote.displayName != local.title) {
          if (local.updatedAt != null) {
            await todoApi.renameList(accessToken, remote.id, local.title);
          } else {
            reconciled = local.copyWith(title: remote.displayName);
          }
        }
        mergedLists.add(reconciled);
        localToRemoteListId[local.id] = remote.id;
      }
    }

    // Add remote-only custom lists.
    for (final remote in remoteLists) {
      if (remote.isDefaultList) continue;
      if (remote.wellknownListName == 'flaggedEmails') continue;
      if (matchedRemoteListIds.contains(remote.id)) continue;
      if (deletedListSet.contains(remote.id)) continue;

      final localId = 'ms_list_${remote.id}';
      mergedLists.add(
        TodoList(
          id: localId,
          title: remote.displayName,
          remoteId: remote.id,
        ),
      );
      localToRemoteListId[localId] = remote.id;
    }

    // 3. Reconcile tasks while preserving existing local task order across lists.
    final deletedTaskRemoteIds =
        pendingDeletedTasks.map((d) => d.taskRemoteId).toSet();

    final remoteTasksByLocalList = <String, List<RemoteTodoTask>>{};
    final remoteTasksByIdPerList = <String, Map<String, RemoteTodoTask>>{};
    final matchedRemoteTaskIdsPerList = <String, Set<String>>{};

    for (final entry in localToRemoteListId.entries) {
      final localListId = entry.key;
      final remoteListId = entry.value;
      final remoteTasks = await todoApi.fetchTasks(accessToken, remoteListId);
      remoteTasksByLocalList[localListId] = remoteTasks;
      remoteTasksByIdPerList[localListId] = {
        for (final r in remoteTasks) r.id: r,
      };
      matchedRemoteTaskIdsPerList[localListId] = <String>{};
    }

    final existingMergedTasks = <TaskItem>[];
    for (final localTask in localTasks) {
      if (removedLocalListIds.contains(localTask.listId)) continue;
      final remoteListId = localToRemoteListId[localTask.listId];
      if (remoteListId == null) {
        existingMergedTasks.add(localTask);
        continue;
      }

      final remoteTasksById = remoteTasksByIdPerList[localTask.listId]!;
      final matchedRemoteTaskIds = matchedRemoteTaskIdsPerList[localTask.listId]!;

      if (localTask.remoteId == null) {
        final created = await todoApi.createTask(
          accessToken,
          remoteListId,
          localTask,
        );
        final syncedSteps = await _syncStepsForNewTask(
          accessToken: accessToken,
          remoteListId: remoteListId,
          remoteTaskId: created.id,
          localSteps: localTask.steps,
        );
        existingMergedTasks.add(
          localTask.copyWith(
            remoteId: created.id,
            updatedAt: created.lastModifiedDateTime.toUtc(),
            steps: syncedSteps,
          ),
        );
        matchedRemoteTaskIds.add(created.id);
      } else {
        final remoteTask = remoteTasksById[localTask.remoteId!];
        if (remoteTask == null) {
          // Deleted remotely
          continue;
        }
        matchedRemoteTaskIds.add(remoteTask.id);

        final localUpdated = localTask.updatedAt;
        final localIsNewer = localUpdated != null &&
            localUpdated.toUtc().isAfter(
                  remoteTask.lastModifiedDateTime.toUtc().add(
                        const Duration(seconds: 2),
                      ),
                );

        if (localIsNewer) {
          final updatedRemote = await todoApi.updateTask(
            accessToken,
            remoteListId,
            remoteTask.id,
            localTask,
          );
          final syncedSteps = await _reconcileStepsToRemote(
            accessToken: accessToken,
            remoteListId: remoteListId,
            remoteTaskId: remoteTask.id,
            localSteps: localTask.steps,
            remoteSteps: remoteTask.checklistItems,
          );
          existingMergedTasks.add(
            localTask.copyWith(
              updatedAt: updatedRemote.lastModifiedDateTime.toUtc(),
              steps: syncedSteps,
            ),
          );
        } else {
          existingMergedTasks.add(
            _mergeRemoteIntoLocal(
              local: localTask,
              remote: remoteTask,
              localListId: localTask.listId,
            ),
          );
        }
      }
    }

    // Collect newly added remote-only tasks and order by createdDateTime.
    final newRemoteTasks = <TaskItem>[];
    for (final entry in localToRemoteListId.entries) {
      final localListId = entry.key;
      final remoteTasks = remoteTasksByLocalList[localListId] ?? const [];
      final matchedRemoteTaskIds =
          matchedRemoteTaskIdsPerList[localListId] ?? const <String>{};
      for (final remoteTask in remoteTasks) {
        if (matchedRemoteTaskIds.contains(remoteTask.id)) continue;
        if (deletedTaskRemoteIds.contains(remoteTask.id)) continue;
        newRemoteTasks.add(
          _fromRemoteTask(
            remote: remoteTask,
            localListId: localListId,
          ),
        );
      }
    }

    newRemoteTasks.sort(
      (a, b) => addNewTasksOnTop
          ? b.createdAt.compareTo(a.createdAt)
          : a.createdAt.compareTo(b.createdAt),
    );

    final mergedTasks = addNewTasksOnTop
        ? [...newRemoteTasks, ...existingMergedTasks]
        : [...existingMergedTasks, ...newRemoteTasks];

    return SyncOutcome(
      lists: mergedLists,
      tasks: mergedTasks,
      syncedAt: DateTime.now().toUtc(),
    );
  }

  Future<List<TaskStep>> _syncStepsForNewTask({
    required String accessToken,
    required String remoteListId,
    required String remoteTaskId,
    required List<TaskStep> localSteps,
  }) async {
    final result = <TaskStep>[];
    for (final step in localSteps) {
      final created = await todoApi.createChecklistItem(
        accessToken,
        remoteListId,
        remoteTaskId,
        step,
      );
      result.add(step.copyWith(remoteId: created.id));
    }
    return result;
  }

  Future<List<TaskStep>> _reconcileStepsToRemote({
    required String accessToken,
    required String remoteListId,
    required String remoteTaskId,
    required List<TaskStep> localSteps,
    required List<RemoteChecklistItem> remoteSteps,
  }) async {
    final remoteById = {for (final s in remoteSteps) s.id: s};
    final keptRemoteIds = <String>{};
    final result = <TaskStep>[];

    for (final step in localSteps) {
      if (step.remoteId == null || !remoteById.containsKey(step.remoteId)) {
        final created = await todoApi.createChecklistItem(
          accessToken,
          remoteListId,
          remoteTaskId,
          step,
        );
        keptRemoteIds.add(created.id);
        result.add(step.copyWith(remoteId: created.id));
      } else {
        keptRemoteIds.add(step.remoteId!);
        final remote = remoteById[step.remoteId!]!;
        if (remote.displayName != step.title ||
            remote.isChecked != step.isCompleted) {
          await todoApi.updateChecklistItem(
            accessToken,
            remoteListId,
            remoteTaskId,
            step,
          );
        }
        result.add(step);
      }
    }

    for (final remote in remoteSteps) {
      if (!keptRemoteIds.contains(remote.id)) {
        await todoApi.deleteChecklistItem(
          accessToken,
          remoteListId,
          remoteTaskId,
          remote.id,
        );
      }
    }

    return result;
  }

  TaskItem _mergeRemoteIntoLocal({
    required TaskItem local,
    required RemoteTodoTask remote,
    required String localListId,
  }) {
    final steps = remote.checklistItems
        .map(
          (c) => TaskStep(
            id: 'step_${c.id}',
            title: c.displayName,
            isCompleted: c.isChecked,
            remoteId: c.id,
          ),
        )
        .toList();

    return local.copyWith(
      listId: localListId,
      title: remote.title,
      isCompleted: remote.isCompleted,
      isImportant: remote.isImportant,
      dueDate: remote.dueDate,
      clearDueDate: remote.dueDate == null,
      reminderAt: remote.reminderAt,
      clearReminderAt: remote.reminderAt == null,
      recurrence: remote.recurrence,
      note: remote.note,
      completedAt: remote.completedDateTime,
      clearCompletedAt: !remote.isCompleted,
      steps: steps,
      remoteId: remote.id,
      updatedAt: remote.lastModifiedDateTime.toUtc(),
    );
  }

  TaskItem _fromRemoteTask({
    required RemoteTodoTask remote,
    required String localListId,
  }) {
    final steps = remote.checklistItems
        .map(
          (c) => TaskStep(
            id: 'step_${c.id}',
            title: c.displayName,
            isCompleted: c.isChecked,
            remoteId: c.id,
          ),
        )
        .toList();

    return TaskItem(
      id: 'ms_task_${remote.id}',
      listId: localListId,
      title: remote.title,
      createdAt: remote.createdDateTime,
      isCompleted: remote.isCompleted,
      isImportant: remote.isImportant,
      dueDate: remote.dueDate,
      reminderAt: remote.reminderAt,
      recurrence: remote.recurrence,
      note: remote.note,
      completedAt: remote.completedDateTime,
      steps: steps,
      remoteId: remote.id,
      updatedAt: remote.lastModifiedDateTime.toUtc(),
    );
  }
}
