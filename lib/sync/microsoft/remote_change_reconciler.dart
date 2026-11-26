import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'microsoft_todo_models.dart';
import 'substrate_sync_mappers.dart';

/// A remote task change paired with optional fallback folder context (from
/// folder-scoped delta pulls) and whether missing `Subtasks` should preserve
/// existing local steps (for partial realtime payloads).
typedef RemoteTaskChange = ({
  RemoteTodoTask remote,
  String? fallbackLocalListId,
  bool preserveStepsWhenMissing,
});

class TaskReconcileResult {
  const TaskReconcileResult({
    required this.tasks,
    required this.seenActiveRemoteIds,
    required this.addedCount,
    required this.updatedCount,
    required this.orderChangedCount,
    required this.deletedCount,
    required this.ignoredCount,
    required this.unknownParentFolderIds,
  });

  final List<TaskItem> tasks;
  final Set<String> seenActiveRemoteIds;
  final int addedCount;
  final int updatedCount;
  final int orderChangedCount;
  final int deletedCount;
  final int ignoredCount;
  final Set<String> unknownParentFolderIds;
}

/// Unified task reconciliation used by both Delta Pull and Realtime event
/// merging so dirty protection, pending-delete protection, `changeKey`
/// preservation, and `Subtasks` handling share a single implementation.
TaskReconcileResult reconcileRemoteTaskChanges({
  required List<TodoList> lists,
  required List<TaskItem> currentTasks,
  required Iterable<RemoteTaskChange> changes,
  required Set<String> dirtyTaskIds,
  required Set<String> pendingDeletedTaskRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  final localListIdByFolderRemoteId = {
    for (final l in lists)
      if (l.remoteId != null) l.remoteId!: l.id,
  };
  final tasksById = {for (final t in currentTasks) t.id: t};
  final taskIdByRemoteId = <String, String>{
    for (final t in currentTasks)
      if (t.remoteId != null) t.remoteId!: t.id,
  };

  final seenActiveRemoteIds = <String>{};
  final deferredDeletesByFolder = <String, Set<String>?>{};
  final ignoredRemoteIds = <String>{};
  final unknownParentFolderIds = <String>{};

  var addedCount = 0;
  var updatedCount = 0;
  var orderChangedCount = 0;
  var deletedCount = 0;
  var ignoredCount = 0;

  for (final change in changes) {
    final remote = change.remote;
    if (remote.id.isEmpty) continue;

    if (remote.isIgnored) {
      ignoredCount += 1;
      ignoredRemoteIds.add(remote.id);
      continue;
    }
    if (remote.isDeleted) {
      deletedCount += 1;
      final existingSet = deferredDeletesByFolder[remote.id];
      if (change.fallbackLocalListId != null) {
        if (existingSet != null) {
          existingSet.add(change.fallbackLocalListId!);
        } else if (!deferredDeletesByFolder.containsKey(remote.id)) {
          deferredDeletesByFolder[remote.id] = {change.fallbackLocalListId!};
        }
      } else {
        // Unscoped delete (e.g. Realtime Task/Deleted without folder context).
        deferredDeletesByFolder[remote.id] = null;
      }
      continue;
    }
    if (pendingDeletedTaskRemoteIds.contains(remote.id)) {
      continue;
    }

    seenActiveRemoteIds.add(remote.id);

    final existingId = taskIdByRemoteId[remote.id];
    final existing = existingId != null ? tasksById[existingId] : null;

    final String? resolvedListId;
    if (remote.parentFolderId != null && remote.parentFolderId!.isNotEmpty) {
      resolvedListId =
          localListIdByFolderRemoteId[remote.parentFolderId!] ??
          change.fallbackLocalListId;
      if (resolvedListId == null) {
        unknownParentFolderIds.add(remote.parentFolderId!);
        continue;
      }
    } else {
      resolvedListId = change.fallbackLocalListId ?? existing?.listId;
      if (resolvedListId == null) {
        continue;
      }
    }

    if (existing != null) {
      updatedCount += 1;
      final isPending = dirtyTaskIds.contains(existing.id);
      if (isPending) {
        if (remote.changeKey != null &&
            remote.changeKey != existing.changeKey) {
          tasksById[existing.id] = existing.copyWith(
            changeKey: remote.changeKey,
          );
        }
        continue;
      }

      final orderChanged =
          existing.orderDateTime != remote.orderDateTime ||
          existing.committedOrder != remote.committedOrder ||
          existing.listId != resolvedListId;
      if (orderChanged) {
        orderChangedCount += 1;
      }

      var mapped = taskFromRemote(
        remote,
        localId: existing.id,
        listId: resolvedListId,
        existingSteps: existing.steps,
        idGenerator: idGenerator,
        existingCompletedAt: existing.completedAt,
      );
      if (change.preserveStepsWhenMissing) {
        mapped = mapped.copyWith(steps: existing.steps);
      }
      if (mapped.remoteParentFolderId == null &&
          existing.remoteParentFolderId != null) {
        mapped = mapped.copyWith(
          remoteParentFolderId: existing.remoteParentFolderId,
        );
      }
      tasksById[existing.id] = mapped;
    } else {
      addedCount += 1;
      final newLocalId = idGenerator('task');
      final created = taskFromRemote(
        remote,
        localId: newLocalId,
        listId: resolvedListId,
        existingSteps: const [],
        idGenerator: idGenerator,
      );
      tasksById[newLocalId] = created;
      taskIdByRemoteId[remote.id] = newLocalId;
    }
  }

  for (final ignoredRemoteId in ignoredRemoteIds) {
    final localId = taskIdByRemoteId[ignoredRemoteId];
    if (localId == null || dirtyTaskIds.contains(localId)) continue;
    tasksById.remove(localId);
  }

  for (final entry in deferredDeletesByFolder.entries) {
    final deletedRemoteId = entry.key;
    final deletedFromListIds = entry.value;
    if (seenActiveRemoteIds.contains(deletedRemoteId)) continue;
    final localId = taskIdByRemoteId[deletedRemoteId];
    if (localId == null || dirtyTaskIds.contains(localId)) continue;
    final localTask = tasksById[localId];
    if (localTask == null) continue;
    if (deletedFromListIds != null &&
        !deletedFromListIds.contains(localTask.listId)) {
      continue;
    }
    tasksById.remove(localId);
  }

  return TaskReconcileResult(
    tasks: tasksById.values.toList(),
    seenActiveRemoteIds: seenActiveRemoteIds,
    addedCount: addedCount,
    updatedCount: updatedCount,
    orderChangedCount: orderChangedCount,
    deletedCount: deletedCount,
    ignoredCount: ignoredCount,
    unknownParentFolderIds: unknownParentFolderIds,
  );
}
