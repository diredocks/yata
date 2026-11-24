import '../data/sync_dirty_fields.dart';
import '../data/todo_settings_sync.dart';
import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_models.dart';
import 'sync_log_format.dart';
import 'todo_wire_codecs.dart';

Map<String, dynamic> buildGroupPatchPayload(
  ListGroup group, {
  Set<GroupDirtyField>? dirtyFields,
}) {
  if (dirtyFields == null) {
    return <String, dynamic>{
      'Name': group.title,
      if (group.orderDateTime != null)
        'OrderDateTime': formatSubstrateUtcTimestamp(group.orderDateTime!),
    };
  }
  return <String, dynamic>{
    if (dirtyFields.contains(GroupDirtyField.name)) 'Name': group.title,
    if (dirtyFields.contains(GroupDirtyField.orderDateTime) &&
        group.orderDateTime != null)
      'OrderDateTime': formatSubstrateUtcTimestamp(group.orderDateTime!),
  };
}

Map<String, dynamic> buildFolderCreatePayload(
  TodoList list, {
  required String? parentGroupRemoteId,
  required DateTime nowUtc,
}) {
  return <String, dynamic>{
    'Name': encodeFolderName(list.title, list.emoji),
    'OrderDateTime': formatSubstrateUtcTimestamp(list.orderDateTime ?? nowUtc),
    'ThemeColor': encodeThemeColor(list.themeColor, list.themePhoto),
    'ThemeBackground': 'mountain',
    'ShowCompletedTasks': list.showCompleted,
    'SortType': encodeSortType(list.sortOption),
    'SortAscending': list.sortAscending,
    'ParentFolderGroupId': ?parentGroupRemoteId,
  };
}

Map<String, dynamic> buildFolderPatchPayload(
  TodoList list, {
  required String? parentGroupRemoteId,
  Set<ListDirtyField>? dirtyFields,
}) {
  if (dirtyFields == null) {
    return <String, dynamic>{
      if (!list.isSmartList) 'Name': encodeFolderName(list.title, list.emoji),
      if (!list.isSmartList) 'ParentFolderGroupId': parentGroupRemoteId,
      'ThemeColor': encodeThemeColor(list.themeColor, list.themePhoto),
      'ThemeBackground': 'mountain',
      'ShowCompletedTasks': list.showCompleted,
      'SortType': encodeSortType(list.sortOption),
      'SortAscending': list.sortAscending,
      if (list.orderDateTime != null)
        'OrderDateTime': formatSubstrateUtcTimestamp(list.orderDateTime!),
    };
  }
  return <String, dynamic>{
    if (!list.isSmartList && dirtyFields.contains(ListDirtyField.name))
      'Name': encodeFolderName(list.title, list.emoji),
    if (!list.isSmartList && dirtyFields.contains(ListDirtyField.group))
      'ParentFolderGroupId': parentGroupRemoteId,
    if (dirtyFields.contains(ListDirtyField.theme)) ...{
      'ThemeColor': encodeThemeColor(list.themeColor, list.themePhoto),
      'ThemeBackground': 'mountain',
    },
    if (dirtyFields.contains(ListDirtyField.showCompleted))
      'ShowCompletedTasks': list.showCompleted,
    if (dirtyFields.contains(ListDirtyField.sort)) ...{
      'SortType': encodeSortType(list.sortOption),
      'SortAscending': list.sortAscending,
    },
    if (dirtyFields.contains(ListDirtyField.orderDateTime) &&
        list.orderDateTime != null)
      'OrderDateTime': formatSubstrateUtcTimestamp(list.orderDateTime!),
  };
}

List<ListGroup> mergeFolderGroupsDelta({
  required List<ListGroup> localGroups,
  required List<RemoteFolderGroup> remoteDelta,
  required Set<String> dirtyGroupIds,
  required String Function(String prefix) idGenerator,
}) {
  final result = [...localGroups];
  for (final remote in remoteDelta) {
    final idx = result.indexWhere((g) => g.remoteId == remote.id);
    if (remote.isDeleted) {
      if (idx >= 0 && !dirtyGroupIds.contains(result[idx].id)) {
        result.removeAt(idx);
      }
      continue;
    }
    if (idx >= 0) {
      final existing = result[idx];
      if (!dirtyGroupIds.contains(existing.id)) {
        result[idx] = existing.copyWith(
          title: remote.name,
          orderDateTime: remote.orderDateTime ?? existing.orderDateTime,
        );
      }
    } else {
      result.add(
        ListGroup(
          id: idGenerator('group'),
          title: remote.name,
          isExpanded: true,
          remoteId: remote.id,
          orderDateTime: remote.orderDateTime,
        ),
      );
    }
  }
  return sortGroupsByOrder(result);
}

List<TodoList> mergeFoldersDelta({
  required List<TodoList> localLists,
  required List<RemoteTodoFolder> remoteDelta,
  required Set<String> dirtyListIds,
  required Map<String, String> groupLocalIdByRemoteId,
  required String Function(String prefix) idGenerator,
}) {
  TodoList applyRemoteFolderProps(
    TodoList existing,
    RemoteTodoFolder remote, {
    String? title,
    String? emoji,
    bool updateGroup = false,
    String? groupId,
  }) {
    if (dirtyListIds.contains(existing.id)) {
      return existing.copyWith(remoteId: remote.id);
    }
    final theme = decodeThemeColor(
      remote.themeColor,
      fallbackColor: existing.themeColor,
    );
    return existing.copyWith(
      title: title ?? existing.title,
      emoji: title != null ? emoji : existing.emoji,
      groupId: updateGroup ? groupId : existing.groupId,
      themeColor: theme.themeColor,
      themePhoto: theme.themePhoto,
      showCompleted: remote.showCompletedTasks,
      sortOption: remote.sortOption,
      sortAscending: remote.sortAscending,
      remoteId: remote.id,
      orderDateTime: remote.orderDateTime ?? existing.orderDateTime,
    );
  }

  final result = [...localLists];
  for (final remote in remoteDelta) {
    if (remote.isIgnoredSpecialFolder) continue;

    if (remote.isDeleted) {
      final idx = result.indexWhere(
        (l) => !l.isSmartList && l.remoteId == remote.id,
      );
      if (idx >= 0 && !dirtyListIds.contains(result[idx].id)) {
        result.removeAt(idx);
      }
      continue;
    }

    if (remote.isDefaultFolder) {
      final idx = result.indexWhere((l) => l.smartType == SmartListType.tasks);
      if (idx >= 0) {
        result[idx] = applyRemoteFolderProps(result[idx], remote);
      }
      continue;
    }

    final decodedName = decodeFolderName(remote.name);
    final mappedGroupId = remote.parentFolderGroupId != null
        ? groupLocalIdByRemoteId[remote.parentFolderGroupId!]
        : null;

    var idx = result.indexWhere(
      (l) => !l.isSmartList && l.remoteId == remote.id,
    );
    if (idx < 0) {
      idx = result.indexWhere(
        (l) =>
            !l.isSmartList &&
            l.remoteId == null &&
            (encodeFolderName(l.title, l.emoji) == remote.name ||
                l.title == remote.name),
      );
    }

    if (idx >= 0) {
      result[idx] = applyRemoteFolderProps(
        result[idx],
        remote,
        title: decodedName.title,
        emoji: decodedName.emoji,
        updateGroup: true,
        groupId: mappedGroupId,
      );
    } else {
      final theme = decodeThemeColor(remote.themeColor);
      result.add(
        TodoList(
          id: idGenerator('list'),
          title: decodedName.title,
          groupId: mappedGroupId,
          emoji: decodedName.emoji,
          themeColor: theme.themeColor,
          themePhoto: theme.themePhoto,
          showCompleted: remote.showCompletedTasks,
          sortOption: remote.sortOption,
          sortAscending: remote.sortAscending,
          remoteId: remote.id,
          orderDateTime: remote.orderDateTime,
        ),
      );
    }
  }
  return sortListsPreservingSmartLists(result);
}

String _firstDayOfWeekWireName(WeekStart firstDayOfWeek) =>
    switch (firstDayOfWeek) {
      WeekStart.system || WeekStart.monday => 'Monday',
      WeekStart.tuesday => 'Tuesday',
      WeekStart.wednesday => 'Wednesday',
      WeekStart.thursday => 'Thursday',
      WeekStart.friday => 'Friday',
      WeekStart.saturday => 'Saturday',
      WeekStart.sunday => 'Sunday',
    };

Map<String, dynamic>? encodeTaskRecurrenceMap(
  TaskItem task, {
  required WeekStart firstDayOfWeek,
}) {
  final raw = normalizeRawRecurrence(task.rawRecurrence);
  if (raw != null) {
    raw.putIfAbsent(
      'FirstDayOfWeek',
      () => _firstDayOfWeekWireName(firstDayOfWeek),
    );
    return raw;
  }
  return encodeSubstrateRecurrence(
    task.recurrence,
    dueDate: task.dueDate,
    firstDayOfWeek: firstDayOfWeek,
  );
}

Map<String, dynamic> buildTaskWritePayload(
  TaskItem task, {
  required String parentFolderRemoteId,
  required bool isCreate,
  required WeekStart firstDayOfWeek,
  Set<TaskDirtyField>? dirtyFields,
  String? dueDateTimeZoneId,
}) {
  final nowUtc = DateTime.now().toUtc();
  final recurrenceMap = encodeTaskRecurrenceMap(
    task,
    firstDayOfWeek: firstDayOfWeek,
  );
  final movedFolder =
      !isCreate &&
      task.remoteParentFolderId != null &&
      task.remoteParentFolderId != parentFolderRemoteId;

  if (isCreate || dirtyFields == null) {
    final payload = <String, dynamic>{
      'Subject': task.title,
      if (isCreate || movedFolder) 'ParentFolderId': parentFolderRemoteId,
      'OrderDateTime': formatSubstrateUtcTimestamp(
        task.orderDateTime ?? task.createdAt,
      ),
      if (isCreate) 'CreatedWithLocalId': task.id,
      'Body': {'Content': task.note, 'ContentType': 'Text'},
      if (task.noteUpdatedAt != null)
        'BodyLastModifiedTime': formatSubstrateUtcTimestamp(
          task.noteUpdatedAt!,
        ),
      'Status': task.isCompleted ? 'Completed' : 'NotStarted',
      'Importance': task.isImportant ? 'High' : 'Normal',
      'IsReminderOn': task.reminderAt != null,
    };

    void putNullable(String key, Object? value, {bool clearOnPatch = true}) {
      if (value != null) {
        payload[key] = value;
      } else if (!isCreate && clearOnPatch) {
        payload[key] = null;
      }
    }

    putNullable(
      'DueDateTime',
      task.dueDate != null
          ? formatDueDateTimeZone(task.dueDate!, timeZoneId: dueDateTimeZoneId)
          : null,
    );
    putNullable(
      'ReminderDateTime',
      task.reminderAt != null
          ? formatDateTimeTimeZoneUtc(task.reminderAt!)
          : null,
    );
    putNullable(
      'CompletedDateTime',
      task.isCompleted
          ? formatDateTimeTimeZoneUtc(task.completedAt ?? nowUtc)
          : null,
    );
    putNullable(
      'CommittedDay',
      task.myDayDate != null ? formatDayString(task.myDayDate!) : null,
    );
    putNullable(
      'CommittedOrder',
      task.committedOrder != null
          ? formatSubstrateUtcTimestamp(task.committedOrder!)
          : null,
      clearOnPatch: !task.isInMyDay,
    );
    putNullable(
      'PostponedDay',
      task.postponedDay != null ? formatDayString(task.postponedDay!) : null,
    );
    putNullable('Recurrence', recurrenceMap);
    return payload;
  }

  // Incremental PATCH: send only dirty fields (aligns with ChangedTasksPusher).
  final payload = <String, dynamic>{};
  if (dirtyFields.contains(TaskDirtyField.subject)) {
    payload['Subject'] = task.title;
  }
  if (movedFolder || dirtyFields.contains(TaskDirtyField.parentFolder)) {
    payload['ParentFolderId'] = parentFolderRemoteId;
  }
  if (dirtyFields.contains(TaskDirtyField.orderDateTime)) {
    payload['OrderDateTime'] = formatSubstrateUtcTimestamp(
      task.orderDateTime ?? task.createdAt,
    );
  }
  if (dirtyFields.contains(TaskDirtyField.body)) {
    payload['Body'] = {'Content': task.note, 'ContentType': 'Text'};
    if (task.noteUpdatedAt != null) {
      payload['BodyLastModifiedTime'] = formatSubstrateUtcTimestamp(
        task.noteUpdatedAt!,
      );
    }
  }
  if (dirtyFields.contains(TaskDirtyField.status)) {
    payload['Status'] = task.isCompleted ? 'Completed' : 'NotStarted';
    payload['CompletedDateTime'] = task.isCompleted
        ? formatDateTimeTimeZoneUtc(task.completedAt ?? nowUtc)
        : null;
  }
  if (dirtyFields.contains(TaskDirtyField.importance)) {
    payload['Importance'] = task.isImportant ? 'High' : 'Normal';
  }
  if (dirtyFields.contains(TaskDirtyField.reminder)) {
    payload['IsReminderOn'] = task.reminderAt != null;
    payload['ReminderDateTime'] = task.reminderAt != null
        ? formatDateTimeTimeZoneUtc(task.reminderAt!)
        : null;
  }
  if (dirtyFields.contains(TaskDirtyField.dueDate) ||
      dirtyFields.contains(TaskDirtyField.recurrence)) {
    payload['DueDateTime'] = task.dueDate != null
        ? formatDueDateTimeZone(task.dueDate!, timeZoneId: dueDateTimeZoneId)
        : null;
    payload['Recurrence'] = recurrenceMap;
  }
  if (dirtyFields.contains(TaskDirtyField.myDay)) {
    payload['CommittedDay'] = task.myDayDate != null
        ? formatDayString(task.myDayDate!)
        : null;
    if (task.committedOrder != null) {
      payload['CommittedOrder'] = formatSubstrateUtcTimestamp(
        task.committedOrder!,
      );
    } else if (!task.isInMyDay) {
      payload['CommittedOrder'] = null;
    }
  } else if (dirtyFields.contains(TaskDirtyField.committedOrder)) {
    if (task.committedOrder != null) {
      payload['CommittedOrder'] = formatSubstrateUtcTimestamp(
        task.committedOrder!,
      );
    } else if (!task.isInMyDay) {
      payload['CommittedOrder'] = null;
    }
  }
  if (dirtyFields.contains(TaskDirtyField.postponedDay)) {
    payload['PostponedDay'] = task.postponedDay != null
        ? formatDayString(task.postponedDay!)
        : null;
  }
  return payload;
}

DateTime? _resolveSyncedCompletedAt({
  required DateTime? existingCompletedAt,
  required RemoteTodoTask remote,
}) {
  if (!remote.isCompleted) return null;
  final remoteCompleted = remote.completedDateTime?.toUtc();
  final existingUtc = existingCompletedAt?.toUtc();
  if (remoteCompleted == null) return existingUtc;
  if (existingUtc == null) return remoteCompleted;

  final sameUtcDay =
      existingUtc.year == remoteCompleted.year &&
      existingUtc.month == remoteCompleted.month &&
      existingUtc.day == remoteCompleted.day;
  if (!sameUtcDay) return remoteCompleted;

  final remoteIsMidnight =
      remoteCompleted.hour == 0 &&
      remoteCompleted.minute == 0 &&
      remoteCompleted.second == 0 &&
      remoteCompleted.millisecond == 0 &&
      remoteCompleted.microsecond == 0;
  final sameSecond =
      existingUtc.hour == remoteCompleted.hour &&
      existingUtc.minute == remoteCompleted.minute &&
      existingUtc.second == remoteCompleted.second;
  if (remoteIsMidnight || sameSecond) {
    return existingUtc;
  }
  return remoteCompleted;
}

TaskItem taskFromRemote(
  RemoteTodoTask remote, {
  required String localId,
  required String listId,
  required List<TaskStep> existingSteps,
  required String Function(String prefix) idGenerator,
  DateTime? existingCompletedAt,
}) {
  final existingStepIdByRemoteId = {
    for (final s in existingSteps)
      if (s.remoteId != null) s.remoteId!: s.id,
  };
  final indexedSteps = [
    for (var i = 0; i < remote.subtasks.length; i++)
      (
        index: i,
        step: TaskStep(
          id:
              existingStepIdByRemoteId[remote.subtasks[i].id] ??
              idGenerator('step'),
          title: remote.subtasks[i].subject,
          isCompleted: remote.subtasks[i].isCompleted,
          remoteId: remote.subtasks[i].id,
          orderDateTime: remote.subtasks[i].orderDateTime,
        ),
      ),
  ];
  indexedSteps.sort((a, b) {
    final ao = a.step.orderDateTime;
    final bo = b.step.orderDateTime;
    if (ao != null && bo != null) {
      final cmp = bo.compareTo(ao);
      if (cmp != 0) return cmp;
    } else if (ao != null) {
      return -1;
    } else if (bo != null) {
      return 1;
    }
    return a.index.compareTo(b.index);
  });

  return TaskItem(
    id: localId,
    listId: listId,
    title: remote.subject,
    createdAt: remote.createdDateTime ?? DateTime.now().toUtc(),
    isCompleted: remote.isCompleted,
    isImportant: remote.isImportant,
    isInMyDay: false, // Recomputed by TodoNotifier.syncMyDayFlag
    myDayDate: remote.committedDay,
    postponedDay: remote.postponedDay,
    dueDate: remote.dueDate,
    reminderAt: remote.isReminderOn ? remote.reminderDateTime : null,
    recurrence: remote.recurrence,
    rawRecurrence: normalizeRawRecurrence(remote.rawRecurrence),
    note: remote.plainTextNote,
    noteUpdatedAt: remote.bodyLastModifiedTime,
    completedAt: _resolveSyncedCompletedAt(
      existingCompletedAt: existingCompletedAt,
      remote: remote,
    ),
    steps: [for (final item in indexedSteps) item.step],
    remoteId: remote.id,
    remoteParentFolderId: remote.parentFolderId,
    orderDateTime: remote.orderDateTime,
    committedOrder: remote.committedOrder,
    changeKey: remote.changeKey,
    updatedAt: remote.lastModifiedDateTime ?? remote.createdDateTime,
  );
}

/// Outcome of merging a single [RealtimeEvent] into local task state.
class RealtimeTaskMergeResult {
  const RealtimeTaskMergeResult({
    required this.handled,
    required this.changed,
    required this.summary,
    this.tasks,
  });

  /// Whether the event was fully processed (or intentionally ignored under
  /// dirty / pending-delete protection) without needing a fallback sync pass.
  final bool handled;

  /// Whether [tasks] contains a state update that should be committed.
  final bool changed;
  final List<TaskItem>? tasks;
  final String summary;
}

/// Merges a `Task` [RealtimeEvent] (including position-only updates that
/// Substrate omits from incremental delta) directly into [currentTasks].
RealtimeTaskMergeResult mergeRealtimeTaskEvent({
  required RealtimeEvent event,
  required List<TodoList> lists,
  required List<TaskItem> currentTasks,
  required Set<String> dirtyTaskIds,
  required Set<String> pendingDeletedTaskRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  if (event.type.trim().toLowerCase() != 'task') {
    return RealtimeTaskMergeResult(
      handled: false,
      changed: false,
      summary: 'non-task event type=${event.type} op=${event.operation}',
    );
  }

  RealtimeTaskMergeResult applyDelete(String remoteId, String eventLabel) {
    if (remoteId.isEmpty) {
      return RealtimeTaskMergeResult(
        handled: false,
        changed: false,
        summary: '$eventLabel missing Id',
      );
    }
    final existingIndex = currentTasks.indexWhere((t) => t.remoteId == remoteId);
    if (existingIndex < 0) {
      return RealtimeTaskMergeResult(
        handled: true,
        changed: false,
        summary: '$eventLabel id=${shortSyncId(remoteId)} already absent',
      );
    }
    final existing = currentTasks[existingIndex];
    if (dirtyTaskIds.contains(existing.id)) {
      return RealtimeTaskMergeResult(
        handled: true,
        changed: false,
        summary:
            '$eventLabel id=${shortSyncId(remoteId)} skipped (local dirty local=${existing.id})',
      );
    }
    final nextTasks = [...currentTasks]..removeAt(existingIndex);
    return RealtimeTaskMergeResult(
      handled: true,
      changed: true,
      tasks: nextTasks,
      summary:
          '$eventLabel id=${shortSyncId(remoteId)} removed local=${existing.id} title="${existing.title}"',
    );
  }

  final op = event.operation?.trim().toLowerCase();
  if (op == 'deleted') {
    final payloadId = (event.payload?['Id'] as String?)?.trim() ?? '';
    final remoteId = (event.id?.trim().isNotEmpty == true)
        ? event.id!.trim()
        : payloadId;
    return applyDelete(remoteId, 'Task/Deleted');
  }

  if (op != 'created' && op != 'updated') {
    return RealtimeTaskMergeResult(
      handled: false,
      changed: false,
      summary: 'Task/${event.operation} unsupported op',
    );
  }

  if (event.payload == null) {
    return RealtimeTaskMergeResult(
      handled: false,
      changed: false,
      summary:
          'Task/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }

  final payloadMap = Map<String, dynamic>.from(event.payload!);
  final payloadId = (payloadMap['Id'] as String?)?.trim();
  if ((payloadId == null || payloadId.isEmpty) &&
      event.id != null &&
      event.id!.trim().isNotEmpty) {
    payloadMap['Id'] = event.id!.trim();
  }

  final remote = RemoteTodoTask.fromJson(payloadMap);
  if (remote.id.isEmpty) {
    return RealtimeTaskMergeResult(
      handled: false,
      changed: false,
      summary: 'Task/${event.operation} missing Id',
    );
  }

  if (remote.isDeleted || remote.isIgnored) {
    return applyDelete(
      remote.id,
      'Task/${event.operation}(${remote.isDeleted ? "deleted" : "ignored"})',
    );
  }

  if (pendingDeletedTaskRemoteIds.contains(remote.id)) {
    return RealtimeTaskMergeResult(
      handled: true,
      changed: false,
      summary:
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
      return RealtimeTaskMergeResult(
        handled: false,
        changed: false,
        summary:
            'Task/${event.operation} id=${shortSyncId(remote.id)} unknown parentFolder=${shortSyncId(remote.parentFolderId)}',
      );
    }
  } else {
    resolvedListId = existing?.listId;
    if (resolvedListId == null) {
      return RealtimeTaskMergeResult(
        handled: false,
        changed: false,
        summary:
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
        return RealtimeTaskMergeResult(
          handled: true,
          changed: true,
          tasks: nextTasks,
          summary:
              'Task/${event.operation} id=${shortSyncId(remote.id)} local=${existing.id} dirty: updated changeKey only',
        );
      }
      return RealtimeTaskMergeResult(
        handled: true,
        changed: false,
        summary:
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
    return RealtimeTaskMergeResult(
      handled: true,
      changed: true,
      tasks: nextTasks,
      summary:
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
  final nextTasks = [...currentTasks, mapped];
  return RealtimeTaskMergeResult(
    handled: true,
    changed: true,
    tasks: nextTasks,
    summary:
        'Task/${event.operation} created id=${shortSyncId(remote.id)} local=$newLocalId '
        'title="${mapped.title}" list=${mapped.listId} '
        'order=${formatSyncTimestamp(mapped.orderDateTime)} '
        'committedOrder=${formatSyncTimestamp(mapped.committedOrder)}',
  );
}

/// Outcome of merging a `FolderGroup` [RealtimeEvent].
class RealtimeFolderGroupMergeResult {
  const RealtimeFolderGroupMergeResult({
    required this.handled,
    required this.changed,
    required this.summary,
    this.groups,
  });

  final bool handled;
  final bool changed;
  final List<ListGroup>? groups;
  final String summary;
}

/// Merges a `FolderGroup` [RealtimeEvent] directly into [currentGroups].
RealtimeFolderGroupMergeResult mergeRealtimeFolderGroupEvent({
  required RealtimeEvent event,
  required List<ListGroup> currentGroups,
  required Set<String> dirtyGroupIds,
  required Set<String> pendingDeletedGroupRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  if (event.type.trim().toLowerCase() != 'foldergroup') {
    return RealtimeFolderGroupMergeResult(
      handled: false,
      changed: false,
      summary: 'non-group event type=${event.type} op=${event.operation}',
    );
  }

  RealtimeFolderGroupMergeResult applyDelete(String remoteId, String label) {
    if (remoteId.isEmpty) {
      return RealtimeFolderGroupMergeResult(
        handled: false,
        changed: false,
        summary: '$label missing Id',
      );
    }
    final existingIdx = currentGroups.indexWhere((g) => g.remoteId == remoteId);
    if (existingIdx < 0) {
      return RealtimeFolderGroupMergeResult(
        handled: true,
        changed: false,
        summary: '$label id=${shortSyncId(remoteId)} already absent',
      );
    }
    final existing = currentGroups[existingIdx];
    if (dirtyGroupIds.contains(existing.id)) {
      return RealtimeFolderGroupMergeResult(
        handled: true,
        changed: false,
        summary:
            '$label id=${shortSyncId(remoteId)} skipped (local dirty local=${existing.id})',
      );
    }
    final nextGroups = [...currentGroups]..removeAt(existingIdx);
    return RealtimeFolderGroupMergeResult(
      handled: true,
      changed: true,
      groups: sortGroupsByOrder(nextGroups),
      summary:
          '$label id=${shortSyncId(remoteId)} removed local=${existing.id} title="${existing.title}"',
    );
  }

  final op = event.operation?.trim().toLowerCase();
  if (op == 'deleted') {
    final payloadId = (event.payload?['Id'] as String?)?.trim() ?? '';
    final remoteId = (event.id?.trim().isNotEmpty == true)
        ? event.id!.trim()
        : payloadId;
    return applyDelete(remoteId, 'FolderGroup/Deleted');
  }
  if (op != 'created' && op != 'updated') {
    return RealtimeFolderGroupMergeResult(
      handled: false,
      changed: false,
      summary: 'FolderGroup/${event.operation} unsupported op',
    );
  }
  if (event.payload == null) {
    return RealtimeFolderGroupMergeResult(
      handled: false,
      changed: false,
      summary:
          'FolderGroup/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }

  final payloadMap = Map<String, dynamic>.from(event.payload!);
  final payloadId = (payloadMap['Id'] as String?)?.trim();
  if ((payloadId == null || payloadId.isEmpty) &&
      event.id != null &&
      event.id!.trim().isNotEmpty) {
    payloadMap['Id'] = event.id!.trim();
  }
  final remote = RemoteFolderGroup.fromJson(payloadMap);
  if (remote.id.isEmpty) {
    return RealtimeFolderGroupMergeResult(
      handled: false,
      changed: false,
      summary: 'FolderGroup/${event.operation} missing Id',
    );
  }
  if (remote.isDeleted) {
    return applyDelete(remote.id, 'FolderGroup/${event.operation}(deleted)');
  }
  if (pendingDeletedGroupRemoteIds.contains(remote.id)) {
    return RealtimeFolderGroupMergeResult(
      handled: true,
      changed: false,
      summary:
          'FolderGroup/${event.operation} id=${shortSyncId(remote.id)} skipped (pending local delete)',
    );
  }

  final existing = currentGroups
      .where((g) => g.remoteId == remote.id)
      .firstOrNull;
  if (existing != null && dirtyGroupIds.contains(existing.id)) {
    return RealtimeFolderGroupMergeResult(
      handled: true,
      changed: false,
      summary:
          'FolderGroup/${event.operation} id=${shortSyncId(remote.id)} local=${existing.id} skipped (local dirty)',
    );
  }

  final merged = mergeFolderGroupsDelta(
    localGroups: currentGroups,
    remoteDelta: [remote],
    dirtyGroupIds: dirtyGroupIds,
    idGenerator: idGenerator,
  );
  return RealtimeFolderGroupMergeResult(
    handled: true,
    changed: true,
    groups: merged,
    summary:
        'FolderGroup/${event.operation} id=${shortSyncId(remote.id)} '
        'name="${remote.name}" order=${formatSyncTimestamp(existing?.orderDateTime)}->${formatSyncTimestamp(remote.orderDateTime)}',
  );
}

/// Outcome of merging a `TaskFolder` [RealtimeEvent].
class RealtimeFolderMergeResult {
  const RealtimeFolderMergeResult({
    required this.handled,
    required this.changed,
    required this.summary,
    this.lists,
    this.tasks,
  });

  final bool handled;
  final bool changed;
  final List<TodoList>? lists;
  final List<TaskItem>? tasks;
  final String summary;
}

/// Merges a `TaskFolder` [RealtimeEvent] directly into [currentLists].
RealtimeFolderMergeResult mergeRealtimeFolderEvent({
  required RealtimeEvent event,
  required List<ListGroup> groups,
  required List<TodoList> currentLists,
  required List<TaskItem> currentTasks,
  required Set<String> dirtyListIds,
  required Set<String> pendingDeletedListRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  if (event.type.trim().toLowerCase() != 'taskfolder') {
    return RealtimeFolderMergeResult(
      handled: false,
      changed: false,
      summary: 'non-folder event type=${event.type} op=${event.operation}',
    );
  }

  RealtimeFolderMergeResult applyDelete(String remoteId, String label) {
    if (remoteId.isEmpty) {
      return RealtimeFolderMergeResult(
        handled: false,
        changed: false,
        summary: '$label missing Id',
      );
    }
    final existingIdx = currentLists.indexWhere(
      (l) => !l.isSmartList && l.remoteId == remoteId,
    );
    if (existingIdx < 0) {
      return RealtimeFolderMergeResult(
        handled: true,
        changed: false,
        summary: '$label id=${shortSyncId(remoteId)} already absent',
      );
    }
    final existing = currentLists[existingIdx];
    if (dirtyListIds.contains(existing.id)) {
      return RealtimeFolderMergeResult(
        handled: true,
        changed: false,
        summary:
            '$label id=${shortSyncId(remoteId)} skipped (local dirty local=${existing.id})',
      );
    }
    final nextLists = [...currentLists]..removeAt(existingIdx);
    final validListIds = {for (final l in nextLists) l.id};
    final filteredTasks = currentTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();
    return RealtimeFolderMergeResult(
      handled: true,
      changed: true,
      lists: sortListsPreservingSmartLists(nextLists),
      tasks: filteredTasks.length == currentTasks.length ? null : filteredTasks,
      summary:
          '$label id=${shortSyncId(remoteId)} removed local=${existing.id} title="${existing.title}"',
    );
  }

  final op = event.operation?.trim().toLowerCase();
  if (op == 'deleted') {
    final payloadId = (event.payload?['Id'] as String?)?.trim() ?? '';
    final remoteId = (event.id?.trim().isNotEmpty == true)
        ? event.id!.trim()
        : payloadId;
    return applyDelete(remoteId, 'TaskFolder/Deleted');
  }
  if (op != 'created' && op != 'updated') {
    return RealtimeFolderMergeResult(
      handled: false,
      changed: false,
      summary: 'TaskFolder/${event.operation} unsupported op',
    );
  }
  if (event.payload == null) {
    return RealtimeFolderMergeResult(
      handled: false,
      changed: false,
      summary:
          'TaskFolder/${event.operation} id=${shortSyncId(event.id)} missing payload',
    );
  }

  final payloadMap = Map<String, dynamic>.from(event.payload!);
  final payloadId = (payloadMap['Id'] as String?)?.trim();
  if ((payloadId == null || payloadId.isEmpty) &&
      event.id != null &&
      event.id!.trim().isNotEmpty) {
    payloadMap['Id'] = event.id!.trim();
  }
  final remote = RemoteTodoFolder.fromJson(payloadMap);
  if (remote.id.isEmpty) {
    return RealtimeFolderMergeResult(
      handled: false,
      changed: false,
      summary: 'TaskFolder/${event.operation} missing Id',
    );
  }
  if (remote.isIgnoredSpecialFolder) {
    return RealtimeFolderMergeResult(
      handled: true,
      changed: false,
      summary:
          'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} ignored special folder',
    );
  }
  if (remote.isDeleted) {
    return applyDelete(remote.id, 'TaskFolder/${event.operation}(deleted)');
  }
  if (pendingDeletedListRemoteIds.contains(remote.id)) {
    return RealtimeFolderMergeResult(
      handled: true,
      changed: false,
      summary:
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
    return RealtimeFolderMergeResult(
      handled: false,
      changed: false,
      summary:
          'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} unknown parentGroup=${shortSyncId(remote.parentFolderGroupId)}',
    );
  }

  final existing = currentLists
      .where(
        (l) =>
            (remote.isDefaultFolder && l.smartType == SmartListType.tasks) ||
            (!l.isSmartList && l.remoteId == remote.id),
      )
      .firstOrNull;
  if (existing != null && dirtyListIds.contains(existing.id)) {
    return RealtimeFolderMergeResult(
      handled: true,
      changed: false,
      summary:
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
  return RealtimeFolderMergeResult(
    handled: true,
    changed: true,
    lists: merged,
    summary:
        'TaskFolder/${event.operation} id=${shortSyncId(remote.id)} '
        'name="${remote.name}" order=${formatSyncTimestamp(existing?.orderDateTime)}->${formatSyncTimestamp(remote.orderDateTime)}',
  );
}

/// Outcome of merging a `Setting` [RealtimeEvent].
class RealtimeSettingMergeResult {
  const RealtimeSettingMergeResult({
    required this.handled,
    required this.changed,
    required this.summary,
    this.patch,
  });

  final bool handled;
  final bool changed;
  final SyncedSettingsPatch? patch;
  final String summary;
}

/// Merges a `Setting` [RealtimeEvent] (`{Key, Value}`) into a
/// [SyncedSettingsPatch].
RealtimeSettingMergeResult mergeRealtimeSettingEvent({
  required RealtimeEvent event,
  required Set<String> dirtySettingKeys,
}) {
  if (event.type.trim().toLowerCase() != 'setting') {
    return RealtimeSettingMergeResult(
      handled: false,
      changed: false,
      summary: 'non-setting event type=${event.type} op=${event.operation}',
    );
  }
  final op = event.operation?.trim().toLowerCase();
  if ((op != 'updated' && op != 'created') || event.payload == null) {
    return RealtimeSettingMergeResult(
      handled: false,
      changed: false,
      summary:
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
    return RealtimeSettingMergeResult(
      handled: false,
      changed: false,
      summary: 'Setting/${event.operation} missing Key/Value',
    );
  }
  if (dirtySettingKeys.contains(key)) {
    return RealtimeSettingMergeResult(
      handled: true,
      changed: false,
      summary: 'Setting/$key skipped (local dirty)',
    );
  }
  final value = rawVal.toString();
  final patch = buildSyncedSettingsPatchFromWire(
    {key: value},
    skipKeys: dirtySettingKeys,
  );
  return RealtimeSettingMergeResult(
    handled: true,
    changed: true,
    patch: patch,
    summary: 'Setting/${event.operation} key=$key value=$value',
  );
}
