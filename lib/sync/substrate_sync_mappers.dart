import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_models.dart';
import 'todo_wire_codecs.dart';

Map<String, dynamic> buildFolderCreatePayload(
  TodoList list, {
  required String? parentGroupRemoteId,
  required DateTime nowUtc,
}) {
  return <String, dynamic>{
    'Name': encodeFolderName(list.title, list.emoji),
    'OrderDateTime': formatSubstrateUtcTimestamp(list.orderDateTime ?? nowUtc),
    'ThemeColor': encodeFolderThemeColor(list.themeColor),
    'ThemeBackground': encodeFolderThemeBackground(list.themePhoto),
    'ShowCompletedTasks': list.showCompleted,
    'SortType': encodeSortType(list.sortOption),
    'SortAscending': list.sortAscending,
    'ParentFolderGroupId': ?parentGroupRemoteId,
  };
}

Map<String, dynamic> buildFolderPatchPayload(
  TodoList list, {
  required String? parentGroupRemoteId,
}) {
  return <String, dynamic>{
    if (!list.isSmartList) 'Name': encodeFolderName(list.title, list.emoji),
    if (!list.isSmartList) 'ParentFolderGroupId': parentGroupRemoteId,
    'ThemeColor': encodeFolderThemeColor(list.themeColor),
    'ThemeBackground': encodeFolderThemeBackground(list.themePhoto),
    'ShowCompletedTasks': list.showCompleted,
    'SortType': encodeSortType(list.sortOption),
    'SortAscending': list.sortAscending,
    if (list.orderDateTime != null)
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
    final theme = decodeFolderTheme(
      themeColor: remote.themeColor,
      themeBackground: remote.themeBackground,
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
      final theme = decodeFolderTheme(
        themeColor: remote.themeColor,
        themeBackground: remote.themeBackground,
      );
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

Map<String, dynamic> buildTaskWritePayload(
  TaskItem task, {
  required String parentFolderRemoteId,
  required bool isCreate,
  required WeekStart firstDayOfWeek,
}) {
  final nowUtc = DateTime.now().toUtc();
  final recurrenceMap = encodeSubstrateRecurrence(
    task.recurrence,
    dueDate: task.dueDate,
    firstDayOfWeek: firstDayOfWeek,
  );
  final movedFolder =
      !isCreate &&
      task.remoteParentFolderId != null &&
      task.remoteParentFolderId != parentFolderRemoteId;

  final payload = <String, dynamic>{
    'Subject': task.title,
    if (isCreate || movedFolder) 'ParentFolderId': parentFolderRemoteId,
    'OrderDateTime': formatSubstrateUtcTimestamp(
      task.orderDateTime ?? task.createdAt,
    ),
    if (isCreate) 'CreatedWithLocalId': task.id,
    'Body': {'Content': task.note, 'ContentType': 'Text'},
    if (task.noteUpdatedAt != null)
      'BodyLastModifiedTime': formatSubstrateUtcTimestamp(task.noteUpdatedAt!),
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
    task.dueDate != null ? formatDueDateTimeZone(task.dueDate!) : null,
  );
  putNullable(
    'ReminderDateTime',
    task.reminderAt != null ? formatDateTimeTimeZoneUtc(task.reminderAt!) : null,
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
