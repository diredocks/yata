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
      final prev = prevGroupById[group.id];
      if (prev == null || isGroupSyncDirty(prev, group)) {
        syncNeeded = true;
        final changed = diffGroupDirtyFields(prev, group);
        outbox.enqueueUpsert(
          entityType: SyncEntityType.group,
          localId: group.id,
          fields: {for (final f in changed) f.name},
        );
        stampedGroups.add(group.copyWith(updatedAt: nowUtc));
      } else {
        stampedGroups.add(group);
      }
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
      final prev = prevListById[list.id];
      if (isSyncableFolderList(list)) {
        if (prev == null || isListSyncDirty(prev, list)) {
          syncNeeded = true;
          final changed = diffListDirtyFields(prev, list);
          outbox.enqueueUpsert(
            entityType: SyncEntityType.list,
            localId: list.id,
            fields: {for (final f in changed) f.name},
          );
          stampedLists.add(list.copyWith(updatedAt: nowUtc));
        } else {
          stampedLists.add(list);
        }
        continue;
      }
      if (prev != null) {
        final changedSmartKeys = smartListChangedSettingKeys(prev, list);
        if (changedSmartKeys.isNotEmpty) {
          syncNeeded = true;
          for (final key in changedSmartKeys) {
            outbox.enqueueSetting(key);
          }
        }
      }
      stampedLists.add(list);
    }
  }

  var stampedTasks = nextState.tasks;
  if (!identical(prevTasks, nextState.tasks)) {
    final nextTaskIds = {for (final t in nextState.tasks) t.id};
    final prevTaskById = {for (final t in prevTasks) t.id: t};
    for (final prev in prevTasks) {
      if (!nextTaskIds.contains(prev.id)) {
        if (deletedListIds.contains(prev.listId)) {
          // Deleting the parent folder on Substrate deletes all its tasks;
          // just drop any un-pushed task upserts without N DELETE calls.
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
      final prev = prevTaskById[task.id];
      if (prev != null) {
        final nextStepIds = {for (final s in task.steps) s.id};
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
        final nextAttachmentIds = {for (final a in task.attachments) a.id};
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
      for (final att in task.attachments) {
        if (att.remoteId == null &&
            att.localPath != null &&
            !prevAttachmentIds.contains(att.id)) {
          syncNeeded = true;
          outbox.enqueueUpsert(
            entityType: SyncEntityType.attachment,
            localId: att.id,
            parentLocalId: task.id,
            parentRemoteId: task.remoteId,
          );
        }
      }
      if (!doesTaskNeedSyncStamp(prev, task)) {
        stampedTasks.add(task);
        continue;
      }
      syncNeeded = true;
      final changedFields = diffTaskDirtyFields(prev, task);
      final changedSteps = diffDirtyStepIds(prev, task);
      outbox.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: task.id,
        fields: {for (final f in changedFields) f.name},
        stepIds: changedSteps,
        baseNote: (changedFields.contains(TaskDirtyField.body) && prev != null)
            ? prev.note
            : null,
      );
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
