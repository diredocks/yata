import '../data/sync_dirty_fields.dart';
import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_models.dart';
import 'todo_wire_codecs.dart';

Map<String, dynamic> buildGroupPatchPayload(
  ListGroup group, {
  Set<GroupDirtyField>? dirtyFields,
}) {
  bool include(GroupDirtyField f) =>
      dirtyFields == null || dirtyFields.contains(f);
  final includeOrder = include(GroupDirtyField.orderDateTime);
  return <String, dynamic>{
    if (include(GroupDirtyField.name) ||
        (includeOrder && group.orderDateTime != null))
      'Name': group.title,
    if (includeOrder && group.orderDateTime != null)
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
  bool include(ListDirtyField f) =>
      dirtyFields == null || dirtyFields.contains(f);
  final includeOrder = include(ListDirtyField.orderDateTime);
  return <String, dynamic>{
    if (!list.isSmartList &&
        (include(ListDirtyField.name) ||
            (includeOrder && list.orderDateTime != null)))
      'Name': encodeFolderName(list.title, list.emoji),
    if (!list.isSmartList && include(ListDirtyField.group))
      'ParentFolderGroupId': parentGroupRemoteId,
    if (include(ListDirtyField.theme)) ...{
      'ThemeColor': encodeThemeColor(list.themeColor, list.themePhoto),
      'ThemeBackground': 'mountain',
    },
    if (include(ListDirtyField.showCompleted))
      'ShowCompletedTasks': list.showCompleted,
    if (include(ListDirtyField.sort)) ...{
      'SortType': encodeSortType(list.sortOption),
      'SortAscending': list.sortAscending,
    },
    if (includeOrder && list.orderDateTime != null)
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

    final idx = result.indexWhere(
      (l) => !l.isSmartList && l.remoteId == remote.id,
    );

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

  bool include(TaskDirtyField field) =>
      isCreate || dirtyFields == null || dirtyFields.contains(field);
  final includePositionWrite =
      include(TaskDirtyField.orderDateTime) ||
      (include(TaskDirtyField.committedOrder) && task.committedOrder != null);

  final payload = <String, dynamic>{};

  void putNullable(String key, Object? value, {bool clearOnPatch = true}) {
    if (value != null) {
      payload[key] = value;
    } else if (!isCreate && clearOnPatch) {
      payload[key] = null;
    }
  }

  if (include(TaskDirtyField.subject) || (!isCreate && includePositionWrite)) {
    payload['Subject'] = task.title;
  }
  if (isCreate ||
      movedFolder ||
      (dirtyFields?.contains(TaskDirtyField.parentFolder) ?? false)) {
    payload['ParentFolderId'] = parentFolderRemoteId;
  }
  if (include(TaskDirtyField.orderDateTime)) {
    payload['OrderDateTime'] = formatSubstrateUtcTimestamp(
      task.orderDateTime ?? task.createdAt,
    );
  }
  if (isCreate) {
    payload['CreatedWithLocalId'] = task.id;
  }
  if (include(TaskDirtyField.body)) {
    payload['Body'] = {'Content': task.note, 'ContentType': 'Text'};
    if (task.noteUpdatedAt != null) {
      payload['BodyLastModifiedTime'] = formatSubstrateUtcTimestamp(
        task.noteUpdatedAt!,
      );
    }
  }
  if (include(TaskDirtyField.status)) {
    payload['Status'] = task.isCompleted ? 'Completed' : 'NotStarted';
    putNullable(
      'CompletedDateTime',
      task.isCompleted
          ? formatDateTimeTimeZoneUtc(task.completedAt ?? nowUtc)
          : null,
    );
  }
  if (include(TaskDirtyField.importance)) {
    payload['Importance'] = task.isImportant ? 'High' : 'Normal';
  }
  if (include(TaskDirtyField.reminder)) {
    payload['IsReminderOn'] = task.reminderAt != null;
    putNullable(
      'ReminderDateTime',
      task.reminderAt != null
          ? formatDateTimeTimeZoneUtc(task.reminderAt!)
          : null,
    );
  }
  if (include(TaskDirtyField.dueDate) || include(TaskDirtyField.recurrence)) {
    putNullable(
      'DueDateTime',
      task.dueDate != null
          ? formatDueDateTimeZone(task.dueDate!, timeZoneId: dueDateTimeZoneId)
          : null,
    );
    putNullable('Recurrence', recurrenceMap);
  }
  final includeCommittedDay =
      include(TaskDirtyField.myDay) ||
      (include(TaskDirtyField.committedOrder) &&
          task.committedOrder != null &&
          (task.myDayDate != null || task.isInMyDay));
  if (includeCommittedDay) {
    final committedDay =
        task.myDayDate ?? (task.isInMyDay ? DateTime.now() : null);
    putNullable(
      'CommittedDay',
      committedDay != null ? formatDayString(committedDay) : null,
    );
  }
  if (include(TaskDirtyField.myDay) || include(TaskDirtyField.committedOrder)) {
    putNullable(
      'CommittedOrder',
      task.committedOrder != null
          ? formatSubstrateUtcTimestamp(task.committedOrder!)
          : null,
      clearOnPatch: !task.isInMyDay,
    );
  }
  if (include(TaskDirtyField.postponedDay)) {
    putNullable(
      'PostponedDay',
      task.postponedDay != null ? formatDayString(task.postponedDay!) : null,
    );
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
    for (final (index, subtask) in remote.subtasks.indexed)
      (
        index: index,
        step: TaskStep(
          id: existingStepIdByRemoteId[subtask.id] ?? idGenerator('step'),
          title: subtask.subject,
          isCompleted: subtask.isCompleted,
          remoteId: subtask.id,
          orderDateTime: subtask.orderDateTime,
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
