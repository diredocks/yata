import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'sync_dirty_fields.dart';
import 'sync_outbox.dart';
import '../lists/todo_settings_sync.dart';

bool isGroupSyncDirty(ListGroup prev, ListGroup next) =>
    diffGroupDirtyFields(prev, next).isNotEmpty;

bool isListSyncDirty(TodoList prev, TodoList next) =>
    diffListDirtyFields(prev, next).isNotEmpty;

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
