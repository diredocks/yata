import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'sync_dirty_fields.dart';
import 'sync_outbox.dart';
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
  Set<String> updatedShowCompletedSmartListIds = const {},
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
    } else if (updatedShowCompletedSmartListIds.contains(list.id) &&
        nextExpanded[list.id] != list.showCompleted) {
      nextExpanded[list.id] = list.showCompleted;
      changed = true;
    }
  }
  return (expanded: nextExpanded, changed: changed);
}

/// Enqueues sync mutations for a single created or modified [ListGroup].
({ListGroup group, bool syncNeeded}) enqueueGroupUpsertToOutbox({
  required ListGroup? prev,
  required ListGroup next,
  required DateTime nowUtc,
  required SyncOutboxQueue outbox,
}) {
  if (prev != null && !isGroupSyncDirty(prev, next)) {
    return (group: next, syncNeeded: false);
  }
  final changed = diffGroupDirtyFields(prev, next);
  outbox.enqueueUpsert(
    entityType: SyncEntityType.group,
    localId: next.id,
    fields: {for (final f in changed) f.name},
  );
  return (group: next.copyWith(updatedAt: nowUtc), syncNeeded: true);
}

/// Enqueues sync mutations for a single created or modified [TodoList] (or
/// smart-list setting keys when [next] is a smart list).
({TodoList list, bool syncNeeded}) enqueueListUpsertToOutbox({
  required TodoList? prev,
  required TodoList next,
  required DateTime nowUtc,
  required SyncOutboxQueue outbox,
}) {
  if (isSyncableFolderList(next)) {
    if (prev != null && !isListSyncDirty(prev, next)) {
      return (list: next, syncNeeded: false);
    }
    final changed = diffListDirtyFields(prev, next);
    outbox.enqueueUpsert(
      entityType: SyncEntityType.list,
      localId: next.id,
      fields: {for (final f in changed) f.name},
    );
    return (list: next.copyWith(updatedAt: nowUtc), syncNeeded: true);
  }
  if (prev != null) {
    final changedSmartKeys = smartListChangedSettingKeys(prev, next);
    if (changedSmartKeys.isNotEmpty) {
      for (final key in changedSmartKeys) {
        outbox.enqueueSetting(key);
      }
      return (list: next, syncNeeded: true);
    }
  }
  return (list: next, syncNeeded: false);
}

/// Enqueues sync mutations (task upsert, step/attachment deletes, attachment
/// uploads) for a single created or modified [TaskItem] in O(1) relative to
/// the total task count.
({TaskItem task, bool syncNeeded}) enqueueTaskUpsertToOutbox({
  required TaskItem? prev,
  required TaskItem next,
  required DateTime nowUtc,
  required SyncOutboxQueue outbox,
  Map<String, String> prevListRemoteById = const {},
}) {
  var syncNeeded = false;
  if (prev != null) {
    final nextStepIds = {for (final s in next.steps) s.id};
    for (final prevStep in prev.steps) {
      if (!nextStepIds.contains(prevStep.id)) {
        syncNeeded = true;
        outbox.enqueueDelete(
          entityType: SyncEntityType.step,
          localId: prevStep.id,
          remoteId: prevStep.remoteId,
          parentLocalId: prev.id,
          parentRemoteId: prev.remoteId,
        );
      }
    }
    final nextAttachmentIds = {for (final a in next.attachments) a.id};
    for (final prevAtt in prev.attachments) {
      if (!nextAttachmentIds.contains(prevAtt.id)) {
        syncNeeded = true;
        outbox.enqueueDelete(
          entityType: SyncEntityType.attachment,
          localId: prevAtt.id,
          remoteId: prevAtt.remoteId,
          parentLocalId: prev.id,
          parentRemoteId: prev.remoteId,
        );
      }
    }
  }
  final prevAttachmentIds = {
    for (final a in prev?.attachments ?? const <TaskAttachment>[]) a.id,
  };
  for (final att in next.attachments) {
    if (att.remoteId == null &&
        att.localPath != null &&
        !prevAttachmentIds.contains(att.id)) {
      syncNeeded = true;
      outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: att.id,
        parentLocalId: next.id,
        parentRemoteId: next.remoteId,
      );
    }
  }
  if (!doesTaskNeedSyncStamp(prev, next)) {
    return (task: next, syncNeeded: syncNeeded);
  }
  syncNeeded = true;
  final changedFields = diffTaskDirtyFields(prev, next);
  final changedSteps = diffDirtyStepIds(prev, next);
  outbox.enqueueUpsert(
    entityType: SyncEntityType.task,
    localId: next.id,
    fields: {for (final f in changedFields) f.name},
    stepIds: changedSteps,
    baseNote: (changedFields.contains(TaskDirtyField.body) && prev != null)
        ? prev.note
        : null,
  );
  final resolvedRemoteParent =
      (prev != null &&
          prev.listId != next.listId &&
          next.remoteId != null &&
          next.remoteParentFolderId == null)
      ? prevListRemoteById[prev.listId]
      : next.remoteParentFolderId;
  return (
    task: next.copyWith(
      remoteParentFolderId: resolvedRemoteParent,
      updatedAt: nowUtc,
    ),
    syncNeeded: syncNeeded,
  );
}

class LocalOutboxCommitResult {
  const LocalOutboxCommitResult({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.syncNeeded,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final bool syncNeeded;
}

/// Diffs [prevState] against [nextState], stamps `updatedAt`, and enqueues
/// ordered operations into [outbox].
LocalOutboxCommitResult enqueueLocalCommitToOutbox({
  required TodoState prevState,
  required TodoState nextState,
  required DateTime nowUtc,
  required SyncOutboxQueue outbox,
}) {
  final prevGroups = prevState.groups;
  final prevLists = prevState.lists;
  final prevTasks = prevState.tasks;

  var stampedGroups = nextState.groups;
  var syncNeeded = false;
  if (!identical(prevGroups, nextState.groups)) {
    final nextGroupIds = {for (final g in nextState.groups) g.id};
    final prevGroupById = {for (final g in prevGroups) g.id: g};
    for (final prev in prevGroups) {
      if (!nextGroupIds.contains(prev.id)) {
        syncNeeded = true;
        outbox.enqueueDelete(
          entityType: SyncEntityType.group,
          localId: prev.id,
          remoteId: prev.remoteId,
        );
      }
    }
    stampedGroups = <ListGroup>[];
    for (final group in nextState.groups) {
      final res = enqueueGroupUpsertToOutbox(
        prev: prevGroupById[group.id],
        next: group,
        nowUtc: nowUtc,
        outbox: outbox,
      );
      if (res.syncNeeded) syncNeeded = true;
      stampedGroups.add(res.group);
    }
  }

  final deletedListIds = <String>{};
  var stampedLists = nextState.lists;
  if (!identical(prevLists, nextState.lists)) {
    final nextListIds = {for (final l in nextState.lists) l.id};
    final prevListById = {for (final l in prevLists) l.id: l};
    for (final prev in prevLists) {
      if (!nextListIds.contains(prev.id) && !prev.isSmartList) {
        syncNeeded = true;
        deletedListIds.add(prev.id);
        outbox.enqueueDelete(
          entityType: SyncEntityType.list,
          localId: prev.id,
          remoteId: prev.remoteId,
        );
      }
    }
    stampedLists = <TodoList>[];
    for (final list in nextState.lists) {
      final res = enqueueListUpsertToOutbox(
        prev: prevListById[list.id],
        next: list,
        nowUtc: nowUtc,
        outbox: outbox,
      );
      if (res.syncNeeded) syncNeeded = true;
      stampedLists.add(res.list);
    }
  }

  var stampedTasks = nextState.tasks;
  if (!identical(prevTasks, nextState.tasks)) {
    final nextTaskIds = {for (final t in nextState.tasks) t.id};
    final prevTaskById = {for (final t in prevTasks) t.id: t};
    for (final prev in prevTasks) {
      if (!nextTaskIds.contains(prev.id)) {
        if (deletedListIds.contains(prev.listId)) {
          if (outbox.cancelPendingUpserts(SyncEntityType.task, prev.id)) {
            syncNeeded = true;
          }
          continue;
        }
        syncNeeded = true;
        outbox.enqueueDelete(
          entityType: SyncEntityType.task,
          localId: prev.id,
          remoteId: prev.remoteId,
        );
      }
    }
    final prevListRemoteById = {
      for (final l in prevLists)
        if (l.remoteId != null) l.id: l.remoteId!,
    };
    stampedTasks = <TaskItem>[];
    for (final task in nextState.tasks) {
      final res = enqueueTaskUpsertToOutbox(
        prev: prevTaskById[task.id],
        next: task,
        nowUtc: nowUtc,
        outbox: outbox,
        prevListRemoteById: prevListRemoteById,
      );
      if (res.syncNeeded) syncNeeded = true;
      stampedTasks.add(res.task);
    }
  }

  final changedGlobalSettingKeys = detectGlobalSettingChanges(
    prevState,
    nextState,
  );
  if (changedGlobalSettingKeys.isNotEmpty) {
    syncNeeded = true;
    for (final key in changedGlobalSettingKeys) {
      outbox.enqueueSetting(key);
    }
  }

  return LocalOutboxCommitResult(
    groups: stampedGroups,
    lists: stampedLists,
    tasks: stampedTasks,
    syncNeeded: syncNeeded,
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
    attachments: next.attachments,
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
