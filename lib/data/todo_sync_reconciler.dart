import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

bool isSyncableFolderList(TodoList list) =>
    !list.isSmartList || list.smartType == SmartListType.tasks;

bool isGroupSyncDirty(ListGroup prev, ListGroup next) =>
    prev.title != next.title || prev.orderDateTime != next.orderDateTime;

bool isListSyncDirty(TodoList prev, TodoList next) =>
    prev.title != next.title ||
    prev.emoji != next.emoji ||
    prev.groupId != next.groupId ||
    prev.themeColor != next.themeColor ||
    prev.themePhoto != next.themePhoto ||
    prev.sortOption != next.sortOption ||
    prev.sortAscending != next.sortAscending ||
    prev.showCompleted != next.showCompleted ||
    prev.orderDateTime != next.orderDateTime;

bool doesTaskNeedSyncStamp(TaskItem? prev, TaskItem next) {
  if (prev == null) return true;
  if (prev.steps.length != next.steps.length) return true;
  final normalizedPrev = prev.copyWith(
    remoteId: next.remoteId,
    remoteParentFolderId: next.remoteParentFolderId,
    changeKey: next.changeKey,
    updatedAt: next.updatedAt,
    noteUpdatedAt: next.noteUpdatedAt,
    steps: [
      for (var i = 0; i < prev.steps.length; i++)
        prev.steps[i].copyWith(
          id: next.steps[i].id,
          remoteId: next.steps[i].remoteId,
        ),
    ],
  );
  return normalizedPrev != next;
}

/// Collects remote IDs of items present in [prevItems] that were removed from
/// [nextIds], clearing their local IDs from [dirtyIds].
({List<String> deletedRemoteIds, bool changed}) collectPendingRemoteDeletions<T>({
  required List<T> prevItems,
  required Set<String> nextIds,
  required String Function(T item) idOf,
  required String? Function(T item) remoteIdOf,
  required Set<String> dirtyIds,
  required Iterable<String> existingDeletedRemoteIds,
  bool Function(T item)? canDeleteRemotely,
}) {
  final deleted = [...existingDeletedRemoteIds];
  var changed = false;
  for (final prev in prevItems) {
    final id = idOf(prev);
    if (!nextIds.contains(id)) {
      dirtyIds.remove(id);
      if (canDeleteRemotely != null && !canDeleteRemotely(prev)) continue;
      final remoteId = remoteIdOf(prev);
      if (remoteId != null) {
        changed = true;
        if (!deleted.contains(remoteId)) {
          deleted.add(remoteId);
        }
      }
    }
  }
  return (deletedRemoteIds: deleted, changed: changed);
}

/// Collects remote step deletions for tasks whose subtasks were removed locally.
({List<PendingStepDeletion> deletedSteps, bool changed})
collectPendingStepDeletions({
  required Map<String, TaskItem> prevTaskById,
  required List<TaskItem> nextTasks,
  required Iterable<PendingStepDeletion> existingDeletedSteps,
}) {
  final deletedSteps = [...existingDeletedSteps];
  var changed = false;
  for (final task in nextTasks) {
    final prev = prevTaskById[task.id];
    final taskRemoteId = prev?.remoteId;
    if (prev == null || taskRemoteId == null) continue;
    final nextStepIds = {for (final s in task.steps) s.id};
    for (final prevStep in prev.steps) {
      final stepRemoteId = prevStep.remoteId;
      if (!nextStepIds.contains(prevStep.id) && stepRemoteId != null) {
        final candidate = PendingStepDeletion(
          taskRemoteId: taskRemoteId,
          stepRemoteId: stepRemoteId,
        );
        if (!deletedSteps.contains(candidate)) {
          changed = true;
          deletedSteps.add(candidate);
        }
      }
    }
  }
  return (deletedSteps: deletedSteps, changed: changed);
}

List<ListGroup> reconcileSyncedGroups({
  required List<ListGroup> currentGroups,
  required List<ListGroup> outcomeGroups,
  required List<ListGroup> snapshotGroups,
  required Set<String> preserveDirtyGroupIds,
}) {
  return _reconcileEntities<ListGroup>(
    currentItems: currentGroups,
    outcomeItems: outcomeGroups,
    snapshotItems: snapshotGroups,
    idOf: (g) => g.id,
    isDirtyBetween: isGroupSyncDirty,
    mergeEditedWithOutcome: (current, outcome) {
      preserveDirtyGroupIds.add(current.id);
      return current.copyWith(remoteId: outcome.remoteId ?? current.remoteId);
    },
    mergeOutcomeWithLocalState: (current, outcome) =>
        outcome.copyWith(isExpanded: current.isExpanded),
  );
}

List<TodoList> reconcileSyncedLists({
  required List<TodoList> currentLists,
  required List<TodoList> outcomeLists,
  required List<TodoList> snapshotLists,
  required Set<String> preserveDirtyListIds,
}) {
  return _reconcileEntities<TodoList>(
    currentItems: currentLists,
    outcomeItems: outcomeLists,
    snapshotItems: snapshotLists,
    idOf: (l) => l.id,
    isSyncable: isSyncableFolderList,
    isDirtyBetween: isListSyncDirty,
    mergeEditedWithOutcome: (current, outcome) {
      preserveDirtyListIds.add(current.id);
      return current.copyWith(remoteId: outcome.remoteId ?? current.remoteId);
    },
    mergeOutcomeWithLocalState: (current, outcome) =>
        outcome.copyWith(icon: current.icon),
  );
}

List<T> _reconcileEntities<T>({
  required List<T> currentItems,
  required List<T> outcomeItems,
  required List<T> snapshotItems,
  required String Function(T item) idOf,
  bool Function(T item)? isSyncable,
  required bool Function(T snap, T current) isDirtyBetween,
  required T Function(T current, T outcome) mergeEditedWithOutcome,
  required T Function(T current, T outcome) mergeOutcomeWithLocalState,
}) {
  final snapshotById = {for (final item in snapshotItems) idOf(item): item};
  final currentById = {for (final item in currentItems) idOf(item): item};
  final outcomeById = {for (final item in outcomeItems) idOf(item): item};

  final reconciled = <T>[];
  for (final current in currentItems) {
    final id = idOf(current);
    final outcome = outcomeById[id];
    final snap = snapshotById[id];
    if (outcome == null) {
      if (snap == null) {
        reconciled.add(current);
      }
      continue;
    }
    if (isSyncable != null && !isSyncable(current)) {
      reconciled.add(current);
      continue;
    }
    final editedDuringSync = snap != null && isDirtyBetween(snap, current);
    reconciled.add(
      editedDuringSync
          ? mergeEditedWithOutcome(current, outcome)
          : mergeOutcomeWithLocalState(current, outcome),
    );
  }

  for (final outcome in outcomeItems) {
    final id = idOf(outcome);
    if (!snapshotById.containsKey(id) && !currentById.containsKey(id)) {
      reconciled.add(outcome);
    }
  }
  return reconciled;
}

List<TaskItem> reconcileSyncedTasks({
  required List<TaskItem> currentTasks,
  required List<TaskItem> outcomeTasks,
  required List<TaskItem> snapshotTasks,
  required Set<String> validListIds,
  required Set<String> preserveDirtyTaskIds,
  required bool addNewTasksOnTop,
}) {
  final snapshotById = {for (final t in snapshotTasks) t.id: t};
  final currentById = {for (final t in currentTasks) t.id: t};
  final outcomeById = {for (final t in outcomeTasks) t.id: t};

  final newRemoteTasks = <TaskItem>[
    for (final outcome in outcomeTasks)
      if (!snapshotById.containsKey(outcome.id) &&
          !currentById.containsKey(outcome.id) &&
          validListIds.contains(outcome.listId))
        outcome,
  ];

  final existingAndLocal = <TaskItem>[];
  for (final current in currentTasks) {
    if (!validListIds.contains(current.listId)) continue;
    final outcome = outcomeById[current.id];
    final snap = snapshotById[current.id];
    if (outcome == null) {
      if (snap == null) {
        existingAndLocal.add(current);
      }
      continue;
    }
    final editedDuringSync = snap != null && doesTaskNeedSyncStamp(snap, current);
    if (!editedDuringSync) {
      existingAndLocal.add(outcome);
    } else {
      preserveDirtyTaskIds.add(current.id);
      final outcomeStepRemoteById = {
        for (final s in outcome.steps)
          if (s.remoteId != null) s.id: s.remoteId!,
      };
      final mergedSteps = [
        for (final step in current.steps)
          step.copyWith(
            remoteId: step.remoteId ?? outcomeStepRemoteById[step.id],
          ),
      ];
      existingAndLocal.add(
        current.copyWith(
          remoteId: outcome.remoteId ?? current.remoteId,
          remoteParentFolderId:
              outcome.remoteParentFolderId ?? current.remoteParentFolderId,
          changeKey: outcome.changeKey ?? current.changeKey,
          steps: mergedSteps,
        ),
      );
    }
  }

  return addNewTasksOnTop
      ? [...newRemoteTasks, ...existingAndLocal]
      : [...existingAndLocal, ...newRemoteTasks];
}
