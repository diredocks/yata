import 'dart:collection';

import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'sync_dirty_fields.dart';
import 'todo_settings_sync.dart';
import 'todo_state.dart';

bool isSyncableFolderList(TodoList list) =>
    !list.isSmartList || list.smartType == SmartListType.tasks;

bool isGroupSyncDirty(ListGroup prev, ListGroup next) =>
    diffGroupDirtyFields(prev, next).isNotEmpty;

bool isListSyncDirty(TodoList prev, TodoList next) =>
    diffListDirtyFields(prev, next).isNotEmpty;

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Recomputes [TaskItem.isInMyDay] from [TaskItem.myDayDate],
/// [TaskItem.dueDate], and [TaskItem.postponedDay], matching `MyDayContract.kt`.
TaskItem computeTaskMyDayFlag(
  TaskItem task, {
  required DateTime now,
  required bool showDueTodayInMyDay,
}) {
  final committedToday =
      task.myDayDate != null && isSameCalendarDay(task.myDayDate!, now);
  final postponedToday =
      task.postponedDay != null && isSameCalendarDay(task.postponedDay!, now);
  final dueToday =
      showDueTodayInMyDay &&
      task.dueDate != null &&
      isSameCalendarDay(task.dueDate!, now);
  final effectiveInMyDay = committedToday || (dueToday && !postponedToday);
  if (task.isInMyDay == effectiveInMyDay) return task;
  return task.copyWith(isInMyDay: effectiveInMyDay);
}

/// Applies [computeTaskMyDayFlag] across all [tasks] and reports whether any changed.
({List<TaskItem> tasks, bool changed}) syncTasksMyDayFlags(
  List<TaskItem> tasks, {
  required DateTime now,
  required bool showDueTodayInMyDay,
}) {
  var changed = false;
  final synced = <TaskItem>[];
  for (final task in tasks) {
    final next = computeTaskMyDayFlag(
      task,
      now: now,
      showDueTodayInMyDay: showDueTodayInMyDay,
    );
    if (!identical(next, task)) changed = true;
    synced.add(next);
  }
  return (tasks: changed ? synced : tasks, changed: changed);
}

/// Recomputes per-list completed-section expansion from synced folder and smart-list settings.
({Map<String, bool> expanded, bool changed}) recomputeCompletedExpandedByList({
  required Map<String, bool> currentExpanded,
  required List<TodoList> lists,
  Set<String> dirtyListIds = const {},
  Set<String> dirtySettingKeys = const {},
  SyncedSettingsPatch? settingsPatch,
  bool includeSyncableFolders = true,
}) {
  final nextExpanded = Map<String, bool>.from(currentExpanded);
  var changed = false;
  for (final list in lists) {
    if (list.smartType == SmartListType.all ||
        list.smartType == SmartListType.completed ||
        list.smartType == SmartListType.important) {
      continue;
    }
    if (isSyncableFolderList(list)) {
      if (includeSyncableFolders &&
          list.remoteId != null &&
          !dirtyListIds.contains(list.id) &&
          nextExpanded[list.id] != list.showCompleted) {
        nextExpanded[list.id] = list.showCompleted;
        changed = true;
      }
    } else if (settingsPatch != null) {
      final showKey = smartListSettingKeyMap[list.id]?.showCompletedKey;
      final patchedShow =
          settingsPatch.smartListPatches[list.id]?.showCompleted;
      if (patchedShow != null &&
          showKey != null &&
          !dirtySettingKeys.contains(showKey) &&
          nextExpanded[list.id] != list.showCompleted) {
        nextExpanded[list.id] = list.showCompleted;
        changed = true;
      }
    }
  }
  return (expanded: nextExpanded, changed: changed);
}

class LocalCommitTrackResult {
  const LocalCommitTrackResult({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.dirtyGroupIds,
    required this.dirtyGroupFields,
    required this.dirtyListIds,
    required this.dirtyListFields,
    required this.dirtyTaskIds,
    required this.dirtyTaskFields,
    required this.dirtyStepIds,
    required this.taskBaseNotes,
    required this.dirtySettingKeys,
    required this.syncNeeded,
    this.pendingDeletedGroupRemoteIds,
    this.pendingDeletedListRemoteIds,
    this.pendingDeletedTaskRemoteIds,
    this.pendingDeletedSteps,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final Set<String> dirtyGroupIds;
  final Map<String, Set<GroupDirtyField>> dirtyGroupFields;
  final Set<String> dirtyListIds;
  final Map<String, Set<ListDirtyField>> dirtyListFields;
  final Set<String> dirtyTaskIds;
  final Map<String, Set<TaskDirtyField>> dirtyTaskFields;
  final Map<String, Set<String>> dirtyStepIds;
  final Map<String, String> taskBaseNotes;
  final Set<String> dirtySettingKeys;
  final List<String>? pendingDeletedGroupRemoteIds;
  final List<String>? pendingDeletedListRemoteIds;
  final List<String>? pendingDeletedTaskRemoteIds;
  final List<PendingStepDeletion>? pendingDeletedSteps;
  final bool syncNeeded;
}

/// Diffs [prevState] against [nextState], stamping `updatedAt` and updating
/// per-entity/per-field dirty sets and pending remote deletion queues.
LocalCommitTrackResult trackLocalCommit({
  required TodoState prevState,
  required TodoState nextState,
  required DateTime nowUtc,
  required Set<String> dirtyGroupIds,
  required Map<String, Set<GroupDirtyField>> dirtyGroupFields,
  required Set<String> dirtyListIds,
  required Map<String, Set<ListDirtyField>> dirtyListFields,
  required Set<String> dirtyTaskIds,
  required Map<String, Set<TaskDirtyField>> dirtyTaskFields,
  required Map<String, Set<String>> dirtyStepIds,
  required Map<String, String> taskBaseNotes,
  required Set<String> dirtySettingKeys,
  required List<String> Function() loadDeletedGroupRemoteIds,
  required List<String> Function() loadDeletedListRemoteIds,
  required List<String> Function() loadDeletedTaskRemoteIds,
  required List<PendingStepDeletion> Function() loadDeletedSteps,
}) {
  final prevGroups = prevState.groups;
  final prevLists = prevState.lists;
  final prevTasks = prevState.tasks;

  var stampedGroups = nextState.groups;
  var groupSyncNeeded = false;
  List<String>? nextDeletedGroups;
  if (!identical(prevGroups, nextState.groups)) {
    final nextGroupIds = {for (final g in nextState.groups) g.id};
    dirtyGroupFields.removeWhere((id, _) => !nextGroupIds.contains(id));

    final prevGroupById = {for (final g in prevGroups) g.id: g};
    final groupDeletions = collectPendingRemoteDeletions<ListGroup>(
      prevItems: prevGroups,
      nextIds: nextGroupIds,
      idOf: (g) => g.id,
      remoteIdOf: (g) => g.remoteId,
      dirtyIds: dirtyGroupIds,
      existingDeletedRemoteIds: loadDeletedGroupRemoteIds(),
    );
    groupSyncNeeded = groupDeletions.changed;
    nextDeletedGroups = groupDeletions.deletedRemoteIds;

    stampedGroups = <ListGroup>[];
    for (final group in nextState.groups) {
      final prev = prevGroupById[group.id];
      if (prev == null || isGroupSyncDirty(prev, group)) {
        groupSyncNeeded = true;
        dirtyGroupIds.add(group.id);
        final changed = diffGroupDirtyFields(prev, group);
        if (changed.isNotEmpty) {
          (dirtyGroupFields[group.id] ??= <GroupDirtyField>{}).addAll(changed);
        }
        stampedGroups.add(group.copyWith(updatedAt: nowUtc));
      } else {
        stampedGroups.add(group);
      }
    }
  }

  var stampedLists = nextState.lists;
  var listSyncNeeded = false;
  List<String>? nextDeletedLists;
  if (!identical(prevLists, nextState.lists)) {
    final nextListIds = {for (final l in nextState.lists) l.id};
    dirtyListFields.removeWhere((id, _) => !nextListIds.contains(id));

    final prevListById = {for (final l in prevLists) l.id: l};
    final listDeletions = collectPendingRemoteDeletions<TodoList>(
      prevItems: prevLists,
      nextIds: nextListIds,
      idOf: (l) => l.id,
      remoteIdOf: (l) => l.remoteId,
      dirtyIds: dirtyListIds,
      existingDeletedRemoteIds: loadDeletedListRemoteIds(),
      canDeleteRemotely: (l) => !l.isSmartList,
    );
    listSyncNeeded = listDeletions.changed;
    nextDeletedLists = listDeletions.deletedRemoteIds;

    stampedLists = <TodoList>[];
    for (final list in nextState.lists) {
      final prev = prevListById[list.id];
      if (isSyncableFolderList(list)) {
        if (prev == null || isListSyncDirty(prev, list)) {
          listSyncNeeded = true;
          dirtyListIds.add(list.id);
          final changed = diffListDirtyFields(prev, list);
          if (changed.isNotEmpty) {
            (dirtyListFields[list.id] ??= <ListDirtyField>{}).addAll(changed);
          }
          stampedLists.add(list.copyWith(updatedAt: nowUtc));
        } else {
          stampedLists.add(list);
        }
        continue;
      }
      if (prev != null) {
        final changedSmartKeys = smartListChangedSettingKeys(prev, list);
        if (changedSmartKeys.isNotEmpty) {
          listSyncNeeded = true;
          dirtySettingKeys.addAll(changedSmartKeys);
        }
      }
      stampedLists.add(list);
    }
  }

  var stampedTasks = nextState.tasks;
  var taskSyncNeeded = false;
  List<String>? nextDeletedTasks;
  List<PendingStepDeletion>? nextDeletedSteps;
  if (!identical(prevTasks, nextState.tasks)) {
    final nextTaskIds = {for (final t in nextState.tasks) t.id};
    dirtyTaskFields.removeWhere((id, _) => !nextTaskIds.contains(id));
    dirtyStepIds.removeWhere((id, _) => !nextTaskIds.contains(id));
    taskBaseNotes.removeWhere((id, _) => !nextTaskIds.contains(id));

    final prevTaskById = {for (final t in prevTasks) t.id: t};
    final taskDeletions = collectPendingRemoteDeletions<TaskItem>(
      prevItems: prevTasks,
      nextIds: nextTaskIds,
      idOf: (t) => t.id,
      remoteIdOf: (t) => t.remoteId,
      dirtyIds: dirtyTaskIds,
      existingDeletedRemoteIds: loadDeletedTaskRemoteIds(),
    );
    taskSyncNeeded = taskDeletions.changed;
    nextDeletedTasks = taskDeletions.deletedRemoteIds;

    final stepDeletions = collectPendingStepDeletions(
      prevTaskById: prevTaskById,
      nextTasks: nextState.tasks,
      existingDeletedSteps: loadDeletedSteps(),
    );
    if (stepDeletions.changed) taskSyncNeeded = true;
    nextDeletedSteps = stepDeletions.deletedSteps;

    final prevListRemoteById = {
      for (final l in prevLists)
        if (l.remoteId != null) l.id: l.remoteId!,
    };
    stampedTasks = <TaskItem>[];
    for (final task in nextState.tasks) {
      final prev = prevTaskById[task.id];
      if (!doesTaskNeedSyncStamp(prev, task)) {
        stampedTasks.add(task);
        continue;
      }
      taskSyncNeeded = true;
      dirtyTaskIds.add(task.id);
      final changedFields = diffTaskDirtyFields(prev, task);
      if (changedFields.isNotEmpty) {
        (dirtyTaskFields[task.id] ??= <TaskDirtyField>{}).addAll(changedFields);
      }
      final changedSteps = diffDirtyStepIds(prev, task);
      if (changedSteps.isNotEmpty) {
        (dirtyStepIds[task.id] ??= <String>{}).addAll(changedSteps);
      }
      if (changedFields.contains(TaskDirtyField.body) &&
          prev != null &&
          !taskBaseNotes.containsKey(task.id)) {
        taskBaseNotes[task.id] = prev.note;
      }
      final resolvedRemoteParent =
          (prev != null &&
              prev.listId != task.listId &&
              task.remoteId != null &&
              task.remoteParentFolderId == null)
          ? prevListRemoteById[prev.listId]
          : task.remoteParentFolderId;
      stampedTasks.add(
        task.copyWith(
          remoteParentFolderId: resolvedRemoteParent,
          updatedAt: nowUtc,
        ),
      );
    }
  }

  final changedGlobalSettingKeys = detectGlobalSettingChanges(
    prevState,
    nextState,
  );
  var settingSyncNeeded = false;
  if (changedGlobalSettingKeys.isNotEmpty) {
    settingSyncNeeded = true;
    dirtySettingKeys.addAll(changedGlobalSettingKeys);
  }

  return LocalCommitTrackResult(
    groups: stampedGroups,
    lists: stampedLists,
    tasks: stampedTasks,
    dirtyGroupIds: dirtyGroupIds,
    dirtyGroupFields: dirtyGroupFields,
    dirtyListIds: dirtyListIds,
    dirtyListFields: dirtyListFields,
    dirtyTaskIds: dirtyTaskIds,
    dirtyTaskFields: dirtyTaskFields,
    dirtyStepIds: dirtyStepIds,
    taskBaseNotes: taskBaseNotes,
    dirtySettingKeys: dirtySettingKeys,
    pendingDeletedGroupRemoteIds: nextDeletedGroups,
    pendingDeletedListRemoteIds: nextDeletedLists,
    pendingDeletedTaskRemoteIds: nextDeletedTasks,
    pendingDeletedSteps: nextDeletedSteps,
    syncNeeded:
        groupSyncNeeded ||
        listSyncNeeded ||
        taskSyncNeeded ||
        settingSyncNeeded,
  );
}

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
      for (final (index, step) in prev.steps.indexed)
        step.copyWith(
          id: next.steps[index].id,
          remoteId: next.steps[index].remoteId,
        ),
    ],
  );
  return normalizedPrev != next;
}

/// Collects remote IDs of items present in [prevItems] that were removed from
/// [nextIds], clearing their local IDs from [dirtyIds].
({List<String> deletedRemoteIds, bool changed})
collectPendingRemoteDeletions<T>({
  required List<T> prevItems,
  required Set<String> nextIds,
  required String Function(T item) idOf,
  required String? Function(T item) remoteIdOf,
  required Set<String> dirtyIds,
  required Iterable<String> existingDeletedRemoteIds,
  bool Function(T item)? canDeleteRemotely,
}) {
  final deleted = LinkedHashSet<String>.of(existingDeletedRemoteIds);
  var changed = false;
  for (final prev in prevItems) {
    final id = idOf(prev);
    if (nextIds.contains(id)) continue;
    dirtyIds.remove(id);
    if (canDeleteRemotely != null && !canDeleteRemotely(prev)) continue;
    final remoteId = remoteIdOf(prev);
    if (remoteId == null) continue;
    changed = true;
    deleted.add(remoteId);
  }
  return (deletedRemoteIds: deleted.toList(), changed: changed);
}

/// Collects remote step deletions for tasks whose subtasks were removed locally.
({List<PendingStepDeletion> deletedSteps, bool changed})
collectPendingStepDeletions({
  required Map<String, TaskItem> prevTaskById,
  required List<TaskItem> nextTasks,
  required Iterable<PendingStepDeletion> existingDeletedSteps,
}) {
  final deletedSteps = LinkedHashSet<PendingStepDeletion>.of(
    existingDeletedSteps,
  );
  var changed = false;
  for (final task in nextTasks) {
    final prev = prevTaskById[task.id];
    final taskRemoteId = prev?.remoteId;
    if (prev == null || taskRemoteId == null) continue;
    final nextStepIds = {for (final s in task.steps) s.id};
    for (final prevStep in prev.steps) {
      final stepRemoteId = prevStep.remoteId;
      if (nextStepIds.contains(prevStep.id) || stepRemoteId == null) continue;
      final candidate = PendingStepDeletion(
        taskRemoteId: taskRemoteId,
        stepRemoteId: stepRemoteId,
      );
      if (deletedSteps.add(candidate)) changed = true;
    }
  }
  return (deletedSteps: deletedSteps.toList(), changed: changed);
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
    final editedDuringSync =
        snap != null && doesTaskNeedSyncStamp(snap, current);
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
