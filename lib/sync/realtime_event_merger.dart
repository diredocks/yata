import 'package:collection/collection.dart';

import '../data/todo_settings_sync.dart';
import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_models.dart';
import 'substrate_sync_mappers.dart';
import 'sync_log_format.dart';

/// Outcome of merging a single [RealtimeEvent] directly into local state.
class RealtimeMergeResult<T> {
  const RealtimeMergeResult({
    required this.handled,
    required this.changed,
    required this.summary,
    this.value,
  });

  const RealtimeMergeResult.unhandled(this.summary)
    : handled = false,
      changed = false,
      value = null;

  const RealtimeMergeResult.noOp(this.summary)
    : handled = true,
      changed = false,
      value = null;

  const RealtimeMergeResult.updated(this.value, this.summary)
    : handled = true,
      changed = true;

  /// Whether the event was fully processed (or intentionally ignored under
  /// dirty / pending-delete protection) without needing a fallback sync pass.
  final bool handled;

  /// Whether [value] contains a state update that should be committed.
  final bool changed;
  final T? value;
  final String summary;
}

typedef RealtimeFolderUpdate = ({List<TodoList> lists, List<TaskItem>? tasks});

enum _RealtimeOp { created, updated, deleted, unsupported }

_RealtimeOp _parseRealtimeOp(String? raw) =>
    switch (raw?.trim().toLowerCase()) {
      'created' => _RealtimeOp.created,
      'updated' => _RealtimeOp.updated,
      'deleted' => _RealtimeOp.deleted,
      _ => _RealtimeOp.unsupported,
    };

String _resolveDeleteRemoteId(RealtimeEvent event) {
  final eventId = event.id?.trim();
  if (eventId != null && eventId.isNotEmpty) return eventId;
  return (event.payload?['Id'] as String?)?.trim() ?? '';
}

Map<String, dynamic> _normalizeEntityPayload(RealtimeEvent event) {
  final payloadMap = Map<String, dynamic>.from(event.payload!);
  final payloadId = (payloadMap['Id'] as String?)?.trim();
  final eventId = event.id?.trim();
  if ((payloadId == null || payloadId.isEmpty) &&
      eventId != null &&
      eventId.isNotEmpty) {
    payloadMap['Id'] = eventId;
  }
  return payloadMap;
}

/// Merges a `Task` [RealtimeEvent] (including position-only updates that
/// Substrate omits from incremental delta) directly into [currentTasks].
RealtimeMergeResult<List<TaskItem>> mergeRealtimeTaskEvent({
  required RealtimeEvent event,
  required List<TodoList> lists,
  required List<TaskItem> currentTasks,
  required Set<String> dirtyTaskIds,
  required Set<String> pendingDeletedTaskRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  if (event.type.trim().toLowerCase() != 'task') {
    return RealtimeMergeResult.unhandled(
      'non-task event type=${event.type} op=${event.operation}',
    );
  }

  RealtimeMergeResult<List<TaskItem>> applyDelete(
    String remoteId,
    String eventLabel,
  ) {
    if (remoteId.isEmpty) {
      return RealtimeMergeResult.unhandled('$eventLabel missing Id');
    }
    final existingIndex = currentTasks.indexWhere((t) => t.remoteId == remoteId);
    if (existingIndex < 0) {
      return RealtimeMergeResult.noOp(
        '$eventLabel id=${shortSyncId(remoteId)} already absent',
      );
    }
    final existing = currentTasks[existingIndex];
    if (dirtyTaskIds.contains(existing.id)) {
      return RealtimeMergeResult.noOp(
        '$eventLabel id=${shortSyncId(remoteId)} skipped (local dirty local=${existing.id})',
      );
    }
    final nextTasks = [...currentTasks]..removeAt(existingIndex);
    return RealtimeMergeResult.updated(
      nextTasks,
      '$eventLabel id=${shortSyncId(remoteId)} removed local=${existing.id} title="${existing.title}"',
    );
  }

  final op = _parseRealtimeOp(event.operation);
  if (op == _RealtimeOp.deleted) {
    return applyDelete(_resolveDeleteRemoteId(event), 'Task/Deleted');
  }
  if (op == _RealtimeOp.unsupported) {
    return RealtimeMergeResult.unhandled(
      'Task/${event.operation} unsupported op',
    );
  }
  if (event.payload == null) {
    return RealtimeMergeResult.unhandled(
      'Task/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }

  final payloadMap = _normalizeEntityPayload(event);
  final remote = RemoteTodoTask.fromJson(payloadMap);
  if (remote.id.isEmpty) {
    return RealtimeMergeResult.unhandled('Task/${event.operation} missing Id');
  }
  if (remote.isDeleted || remote.isIgnored) {
    return applyDelete(
      remote.id,
      'Task/${event.operation}(${remote.isDeleted ? "deleted" : "ignored"})',
    );
  }
  if (pendingDeletedTaskRemoteIds.contains(remote.id)) {
    return RealtimeMergeResult.noOp(
      'Task/${event.operation} id=${shortSyncId(remote.id)} skipped (pending local delete)',
    );
  }

  final existingIndex = currentTasks.indexWhere((t) => t.remoteId == remote.id);
  final existing = existingIndex >= 0 ? currentTasks[existingIndex] : null;
  final localListIdByFolderRemoteId = {
    for (final l in lists)
      if (l.remoteId != null) l.remoteId!: l.id,
  };

  final String? resolvedListId;
  if (remote.parentFolderId != null && remote.parentFolderId!.isNotEmpty) {
    resolvedListId = localListIdByFolderRemoteId[remote.parentFolderId!];
    if (resolvedListId == null) {
      return RealtimeMergeResult.unhandled(
        'Task/${event.operation} id=${shortSyncId(remote.id)} unknown parentFolder=${shortSyncId(remote.parentFolderId)}',
      );
    }
  } else {
    resolvedListId = existing?.listId;
    if (resolvedListId == null) {
      return RealtimeMergeResult.unhandled(
        'Task/${event.operation} id=${shortSyncId(remote.id)} missing parentFolderId for new task',
      );
    }
  }

  if (existing != null) {
    if (dirtyTaskIds.contains(existing.id)) {
      if (remote.changeKey != null && remote.changeKey != existing.changeKey) {
        final nextTasks = [...currentTasks];
        nextTasks[existingIndex] = existing.copyWith(
          changeKey: remote.changeKey,
        );
        return RealtimeMergeResult.updated(
          nextTasks,
          'Task/${event.operation} id=${shortSyncId(remote.id)} local=${existing.id} dirty: updated changeKey only',
        );
      }
      return RealtimeMergeResult.noOp(
        'Task/${event.operation} id=${shortSyncId(remote.id)} local=${existing.id} skipped (local dirty)',
      );
    }

    var mapped = taskFromRemote(
      remote,
      localId: existing.id,
      listId: resolvedListId,
      existingSteps: existing.steps,
      idGenerator: idGenerator,
      existingCompletedAt: existing.completedAt,
    );
    if (!payloadMap.containsKey('Subtasks')) {
      mapped = mapped.copyWith(steps: existing.steps);
    }
    if (mapped.remoteParentFolderId == null &&
        existing.remoteParentFolderId != null) {
      mapped = mapped.copyWith(
        remoteParentFolderId: existing.remoteParentFolderId,
      );
    }
    final nextTasks = [...currentTasks];
    nextTasks[existingIndex] = mapped;
    return RealtimeMergeResult.updated(
      nextTasks,
      'Task/${event.operation} updated id=${shortSyncId(remote.id)} local=${existing.id} '
      'title="${mapped.title}" list=${existing.listId}->${mapped.listId} '
      'order=${formatSyncTimestamp(existing.orderDateTime)}->${formatSyncTimestamp(mapped.orderDateTime)} '
      'committedOrder=${formatSyncTimestamp(existing.committedOrder)}->${formatSyncTimestamp(mapped.committedOrder)} '
      'ck=${shortSyncId(mapped.changeKey)}',
    );
  }

  final newLocalId = idGenerator('task');
  final mapped = taskFromRemote(
    remote,
    localId: newLocalId,
    listId: resolvedListId,
    existingSteps: const [],
    idGenerator: idGenerator,
  );
  return RealtimeMergeResult.updated(
    [...currentTasks, mapped],
    'Task/${event.operation} created id=${shortSyncId(remote.id)} local=$newLocalId '
    'title="${mapped.title}" list=${mapped.listId} '
    'order=${formatSyncTimestamp(mapped.orderDateTime)} '
    'committedOrder=${formatSyncTimestamp(mapped.committedOrder)}',
  );
}

/// Merges a `FolderGroup` [RealtimeEvent] directly into [currentGroups].
RealtimeMergeResult<List<ListGroup>> mergeRealtimeFolderGroupEvent({
  required RealtimeEvent event,
  required List<ListGroup> currentGroups,
  required Set<String> dirtyGroupIds,
  required Set<String> pendingDeletedGroupRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  if (event.type.trim().toLowerCase() != 'foldergroup') {
    return RealtimeMergeResult.unhandled(
      'non-group event type=${event.type} op=${event.operation}',
    );
  }

  RealtimeMergeResult<List<ListGroup>> applyDelete(
    String remoteId,
    String label,
  ) {
    if (remoteId.isEmpty) {
      return RealtimeMergeResult.unhandled('$label missing Id');
    }
    final existingIdx = currentGroups.indexWhere((g) => g.remoteId == remoteId);
    if (existingIdx < 0) {
      return RealtimeMergeResult.noOp(
        '$label id=${shortSyncId(remoteId)} already absent',
      );
    }
    final existing = currentGroups[existingIdx];
    if (dirtyGroupIds.contains(existing.id)) {
      return RealtimeMergeResult.noOp(
        '$label id=${shortSyncId(remoteId)} skipped (local dirty local=${existing.id})',
      );
    }
    final nextGroups = [...currentGroups]..removeAt(existingIdx);
    return RealtimeMergeResult.updated(
      sortGroupsByOrder(nextGroups),
      '$label id=${shortSyncId(remoteId)} removed local=${existing.id} title="${existing.title}"',
    );
  }

  final op = _parseRealtimeOp(event.operation);
  if (op == _RealtimeOp.deleted) {
    return applyDelete(_resolveDeleteRemoteId(event), 'FolderGroup/Deleted');
  }
  if (op == _RealtimeOp.unsupported) {
    return RealtimeMergeResult.unhandled(
      'FolderGroup/${event.operation} unsupported op',
    );
  }
  if (event.payload == null) {
    return RealtimeMergeResult.unhandled(
      'FolderGroup/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }

  final remote = RemoteFolderGroup.fromJson(_normalizeEntityPayload(event));
  if (remote.id.isEmpty) {
    return RealtimeMergeResult.unhandled(
      'FolderGroup/${event.operation} missing Id',
    );
  }
  if (remote.isDeleted) {
    return applyDelete(remote.id, 'FolderGroup/${event.operation}(deleted)');
  }
  if (pendingDeletedGroupRemoteIds.contains(remote.id)) {
    return RealtimeMergeResult.noOp(
      'FolderGroup/${event.operation} id=${shortSyncId(remote.id)} skipped (pending local delete)',
    );
  }

  final existing = currentGroups.firstWhereOrNull(
    (g) => g.remoteId == remote.id,
  );
  if (existing != null && dirtyGroupIds.contains(existing.id)) {
    return RealtimeMergeResult.noOp(
      'FolderGroup/${event.operation} id=${shortSyncId(remote.id)} local=${existing.id} skipped (local dirty)',
    );
  }

  final merged = mergeFolderGroupsDelta(
    localGroups: currentGroups,
    remoteDelta: [remote],
    dirtyGroupIds: dirtyGroupIds,
    idGenerator: idGenerator,
  );
  return RealtimeMergeResult.updated(
    merged,
    'FolderGroup/${event.operation} id=${shortSyncId(remote.id)} '
    'name="${remote.name}" order=${formatSyncTimestamp(existing?.orderDateTime)}->${formatSyncTimestamp(remote.orderDateTime)}',
  );
}

/// Merges a `TaskFolder` [RealtimeEvent] directly into [currentLists].
RealtimeMergeResult<RealtimeFolderUpdate> mergeRealtimeFolderEvent({
  required RealtimeEvent event,
  required List<ListGroup> groups,
  required List<TodoList> currentLists,
  required List<TaskItem> currentTasks,
  required Set<String> dirtyListIds,
  required Set<String> pendingDeletedListRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  if (event.type.trim().toLowerCase() != 'taskfolder') {
    return RealtimeMergeResult.unhandled(
      'non-folder event type=${event.type} op=${event.operation}',
    );
  }

  RealtimeMergeResult<RealtimeFolderUpdate> applyDelete(
    String remoteId,
    String label,
  ) {
    if (remoteId.isEmpty) {
      return RealtimeMergeResult.unhandled('$label missing Id');
    }
    final existingIdx = currentLists.indexWhere(
      (l) => !l.isSmartList && l.remoteId == remoteId,
    );
    if (existingIdx < 0) {
      return RealtimeMergeResult.noOp(
        '$label id=${shortSyncId(remoteId)} already absent',
      );
    }
    final existing = currentLists[existingIdx];
    if (dirtyListIds.contains(existing.id)) {
      return RealtimeMergeResult.noOp(
        '$label id=${shortSyncId(remoteId)} skipped (local dirty local=${existing.id})',
      );
    }
    final nextLists = [...currentLists]..removeAt(existingIdx);
    final validListIds = {for (final l in nextLists) l.id};
    final filteredTasks = currentTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();
    return RealtimeMergeResult.updated(
      (
        lists: sortListsPreservingSmartLists(nextLists),
        tasks: filteredTasks.length == currentTasks.length
            ? null
            : filteredTasks,
      ),
      '$label id=${shortSyncId(remoteId)} removed local=${existing.id} title="${existing.title}"',
    );
  }

  final op = _parseRealtimeOp(event.operation);
  if (op == _RealtimeOp.deleted) {
    return applyDelete(_resolveDeleteRemoteId(event), 'TaskFolder/Deleted');
  }
  if (op == _RealtimeOp.unsupported) {
    return RealtimeMergeResult.unhandled(
      'TaskFolder/${event.operation} unsupported op',
    );
  }
  if (event.payload == null) {
    return RealtimeMergeResult.unhandled(
      'TaskFolder/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }

  final remote = RemoteTodoFolder.fromJson(_normalizeEntityPayload(event));
  if (remote.id.isEmpty) {
    return RealtimeMergeResult.unhandled(
      'TaskFolder/${event.operation} missing Id',
    );
  }
  if (remote.isIgnoredSpecialFolder) {
    return RealtimeMergeResult.noOp(
      'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} ignored special folder',
    );
  }
  if (remote.isDeleted) {
    return applyDelete(remote.id, 'TaskFolder/${event.operation}(deleted)');
  }
  if (pendingDeletedListRemoteIds.contains(remote.id)) {
    return RealtimeMergeResult.noOp(
      'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} skipped (pending local delete)',
    );
  }

  final groupLocalIdByRemoteId = {
    for (final g in groups)
      if (g.remoteId != null) g.remoteId!: g.id,
  };
  if (remote.parentFolderGroupId != null &&
      remote.parentFolderGroupId!.isNotEmpty &&
      !groupLocalIdByRemoteId.containsKey(remote.parentFolderGroupId!)) {
    return RealtimeMergeResult.unhandled(
      'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} unknown parentGroup=${shortSyncId(remote.parentFolderGroupId)}',
    );
  }

  final existing = currentLists.firstWhereOrNull(
    (l) =>
        (remote.isDefaultFolder && l.smartType == SmartListType.tasks) ||
        (!l.isSmartList && l.remoteId == remote.id),
  );
  if (existing != null && dirtyListIds.contains(existing.id)) {
    return RealtimeMergeResult.noOp(
      'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} local=${existing.id} skipped (local dirty)',
    );
  }

  final merged = mergeFoldersDelta(
    localLists: currentLists,
    remoteDelta: [remote],
    dirtyListIds: dirtyListIds,
    groupLocalIdByRemoteId: groupLocalIdByRemoteId,
    idGenerator: idGenerator,
  );
  return RealtimeMergeResult.updated(
    (lists: merged, tasks: null),
    'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} '
    'name="${remote.name}" order=${formatSyncTimestamp(existing?.orderDateTime)}->${formatSyncTimestamp(remote.orderDateTime)}',
  );
}

/// Merges a `Setting` [RealtimeEvent] (`{Key, Value}`) into a
/// [SyncedSettingsPatch].
RealtimeMergeResult<SyncedSettingsPatch> mergeRealtimeSettingEvent({
  required RealtimeEvent event,
  required Set<String> dirtySettingKeys,
}) {
  if (event.type.trim().toLowerCase() != 'setting') {
    return RealtimeMergeResult.unhandled(
      'non-setting event type=${event.type} op=${event.operation}',
    );
  }
  final op = _parseRealtimeOp(event.operation);
  if ((op != _RealtimeOp.updated && op != _RealtimeOp.created) ||
      event.payload == null) {
    return RealtimeMergeResult.unhandled(
      'Setting/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }
  final payload = event.payload!;
  final rawKey = (payload['Key'] ?? payload['key']) as String?;
  final key = (rawKey?.trim().isNotEmpty == true)
      ? rawKey!.trim()
      : (event.id?.trim() ?? '');
  final rawVal = payload['Value'] ?? payload['value'];
  if (key.isEmpty || rawVal == null) {
    return RealtimeMergeResult.unhandled(
      'Setting/${event.operation} missing Key/Value',
    );
  }
  if (dirtySettingKeys.contains(key)) {
    return RealtimeMergeResult.noOp('Setting/$key skipped (local dirty)');
  }
  final value = rawVal.toString();
  final patch = buildSyncedSettingsPatchFromWire(
    {key: value},
    skipKeys: dirtySettingKeys,
  );
  return RealtimeMergeResult.updated(
    patch,
    'Setting/${event.operation} key=$key value=$value',
  );
}
