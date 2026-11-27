import 'dart:io';

import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync_dirty_fields.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_settings_sync.dart';
import '../../data/todo_state.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../sync_concurrency.dart';
import '../sync_guard.dart';
import '../sync_log_format.dart';
import '../text_merge.dart';
import 'microsoft_todo_api.dart';
import 'substrate_sync_mappers.dart';
import 'todo_wire_codecs.dart';

final _log = appLogFor('SyncEngine');

class OutboxPushOutcome {
  const OutboxPushOutcome({
    required this.ackedSeqs,
    required this.pushedGroups,
    required this.pushedLists,
    required this.pushedTasks,
    required this.clearedRemoteIdKeys,
    required this.followUpPullFolderRemoteIds,
  });

  static const empty = OutboxPushOutcome(
    ackedSeqs: [],
    pushedGroups: {},
    pushedLists: {},
    pushedTasks: {},
    clearedRemoteIdKeys: [],
    followUpPullFolderRemoteIds: {},
  );

  final List<int> ackedSeqs;
  final Map<String, ListGroup> pushedGroups;
  final Map<String, TodoList> pushedLists;
  final Map<String, TaskItem> pushedTasks;
  final List<({SyncEntityType type, String localId})> clearedRemoteIdKeys;

  /// Folders needing one targeted task pull: the server may have changed more
  /// than the push response tells us (recurring spawn, move, conflict merge).
  final Set<String> followUpPullFolderRemoteIds;

  bool get didWork =>
      ackedSeqs.isNotEmpty ||
      pushedGroups.isNotEmpty ||
      pushedLists.isNotEmpty ||
      pushedTasks.isNotEmpty;
}

/// Whether [dirtyFields] describes nothing but an intra-list position change.
bool isReorderOnlyTaskPatch(
  Set<TaskDirtyField>? dirtyFields, {
  required bool isCompleted,
}) {
  if (dirtyFields == null || dirtyFields.isEmpty) return false;
  final hasOrderChange =
      dirtyFields.contains(TaskDirtyField.orderDateTime) ||
      dirtyFields.contains(TaskDirtyField.committedOrder);
  if (!hasOrderChange || dirtyFields.contains(TaskDirtyField.body)) {
    return false;
  }
  return !(dirtyFields.contains(TaskDirtyField.status) && isCompleted);
}

/// Filters which Outbox operations a push pass drains so slow attachment
/// uploads can run on a dedicated transfer lane without blocking metadata sync.
enum PushLaneFilter { all, metadataOnly, attachmentsOnly }

enum _PushStage {
  setting,
  nonGroupDelete,
  groupUpsert,
  listUpsert,
  groupDelete,
  taskUpsert,
  attachmentUpsert,
}

typedef _TaskPatchOutcome = ({
  RemoteTodoTask remoteTask,
  String? mergedNote,
  bool preservedRemoteStatus,
});

/// Pushes ordered [SyncOutboxOp] batches to Substrate To Do v1.
class SubstratePushEngine {
  const SubstratePushEngine(this.todoApi);

  static const int _maxConcurrentTaskPushes = 4;

  final MicrosoftTodoApi todoApi;

  /// Drains the current Outbox batch in dependency order:
  /// settings -> step/task/folder deletions -> groups -> folders ->
  /// group deletions -> tasks/steps -> attachments.
  AsyncAppResult<OutboxPushOutcome> pushOutbox({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required SyncOutboxQueue outbox,
    required DateTime nowUtc,
    TodoState Function()? readLatestState,
    Future<void> Function(OutboxPushOutcome itemOutcome)? onItemCommitted,
    PushLaneFilter laneFilter = PushLaneFilter.all,
  }) async {
    final batch = _filterBatch(outbox.beginBatch(), laneFilter);
    try {
      if (batch.isEmpty) {
        return const Success(OutboxPushOutcome.empty);
      }
      final session = _PushSession(
        todoApi: todoApi,
        ctx: ctx,
        initialState: currentState,
        outbox: outbox,
        nowUtc: nowUtc,
        readLatestState: readLatestState,
        onItemCommitted: onItemCommitted,
      );
      return await session.execute(batch);
    } finally {
      outbox.endBatch();
    }
  }

  static List<SyncOutboxOp> _filterBatch(
    List<SyncOutboxOp> batch,
    PushLaneFilter filter,
  ) {
    if (filter == PushLaneFilter.all) return batch;
    final wantAttachments = filter == PushLaneFilter.attachmentsOnly;
    return batch
        .where((op) => op.isAttachmentUpload == wantAttachments)
        .toList(growable: false);
  }
}

class _PushSession {
  _PushSession({
    required this.todoApi,
    required this.ctx,
    required this.initialState,
    required this.outbox,
    required this.nowUtc,
    this.readLatestState,
    this.onItemCommitted,
  });

  final MicrosoftTodoApi todoApi;
  final SubstrateRequestContext ctx;
  final TodoState initialState;
  final SyncOutboxQueue outbox;
  final DateTime nowUtc;
  final TodoState Function()? readLatestState;
  final Future<void> Function(OutboxPushOutcome itemOutcome)? onItemCommitted;

  final List<int> _ackedSeqs = [];
  final List<({SyncEntityType type, String localId})> _clearedRemoteIdKeys = [];
  final Map<String, ListGroup> _pushedGroups = {};
  final Map<String, TodoList> _pushedLists = {};
  final Map<String, TaskItem> _pushedTasks = {};
  final Set<String> _followUpPullFolderRemoteIds = {};
  final Set<String> _deletedGroupRemoteIds = {};
  final Set<String> _deletedListRemoteIds = {};
  final Set<String> _deletedTaskRemoteIds = {};

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static _PushStage? _stageForOp(SyncOutboxOp op) =>
      switch ((op.entityType, op.kind)) {
        (SyncEntityType.setting, _) => _PushStage.setting,
        (SyncEntityType.group, SyncOpKind.upsert) => _PushStage.groupUpsert,
        (SyncEntityType.group, SyncOpKind.delete) => _PushStage.groupDelete,
        (SyncEntityType.list, SyncOpKind.upsert) => _PushStage.listUpsert,
        (SyncEntityType.task, SyncOpKind.upsert) => _PushStage.taskUpsert,
        (SyncEntityType.attachment, SyncOpKind.upsert) =>
          _PushStage.attachmentUpsert,
        (_, SyncOpKind.delete) => _PushStage.nonGroupDelete,
        (SyncEntityType.step, SyncOpKind.upsert) => null,
      };

  AsyncAppResult<OutboxPushOutcome> execute(List<SyncOutboxOp> batch) async {
    final buckets = batch.groupListsBy(_stageForOp);
    final stages = <AsyncAppResult<Unit> Function()>[
      () => _pushSettings(buckets[_PushStage.setting] ?? const []),
      () => _pushDeletes(buckets[_PushStage.nonGroupDelete] ?? const []),
      () => _pushGroupUpserts(buckets[_PushStage.groupUpsert] ?? const []),
      () => _pushFolderUpserts(buckets[_PushStage.listUpsert] ?? const []),
      () => _pushDeletes(buckets[_PushStage.groupDelete] ?? const []),
      () => _pushTaskUpserts(buckets[_PushStage.taskUpsert] ?? const []),
      () => _pushAttachmentUpserts(
        buckets[_PushStage.attachmentUpsert] ?? const [],
      ),
    ];

    for (final runStage in stages) {
      final result = await runStage();
      if (result.isError()) return Failure(result.exceptionOrNull()!);
    }

    return Success(
      OutboxPushOutcome(
        ackedSeqs: _ackedSeqs,
        pushedGroups: _pushedGroups,
        pushedLists: _pushedLists,
        pushedTasks: _pushedTasks,
        clearedRemoteIdKeys: _clearedRemoteIdKeys,
        followUpPullFolderRemoteIds: _followUpPullFolderRemoteIds,
      ),
    );
  }

  Future<void> _commitOp({
    required int seq,
    ListGroup? group,
    TodoList? list,
    TaskItem? task,
    ({SyncEntityType type, String localId})? clearedRemoteIdKey,
    String? followUpFolderRemoteId,
  }) async {
    _ackedSeqs.add(seq);
    if (group != null) _pushedGroups[group.id] = group;
    if (list != null) _pushedLists[list.id] = list;
    if (task != null) _pushedTasks[task.id] = task;
    if (clearedRemoteIdKey != null) {
      _clearedRemoteIdKeys.add(clearedRemoteIdKey);
    }
    if (followUpFolderRemoteId != null) {
      _followUpPullFolderRemoteIds.add(followUpFolderRemoteId);
    }
    if (onItemCommitted == null) return;
    await onItemCommitted!(
      OutboxPushOutcome(
        ackedSeqs: [seq],
        pushedGroups: group != null ? {group.id: group} : const {},
        pushedLists: list != null ? {list.id: list} : const {},
        pushedTasks: task != null ? {task.id: task} : const {},
        clearedRemoteIdKeys: clearedRemoteIdKey != null
            ? [clearedRemoteIdKey]
            : const [],
        followUpPullFolderRemoteIds: followUpFolderRemoteId != null
            ? {followUpFolderRemoteId}
            : const {},
      ),
    );
  }

  T? _findLive<T>({
    required String id,
    required Map<String, T> pushed,
    required List<T> Function(TodoState state) selector,
    required String Function(T item) idOf,
  }) {
    final latest = readLatestState?.call();
    if (latest != null) {
      final match = selector(latest).firstWhereOrNull((e) => idOf(e) == id);
      return match == null ? null : (pushed[id] ?? match);
    }
    return pushed[id] ??
        selector(initialState).firstWhereOrNull((e) => idOf(e) == id);
  }

  ListGroup? _findLiveGroup(String id) => _findLive(
    id: id,
    pushed: _pushedGroups,
    selector: (s) => s.groups,
    idOf: (g) => g.id,
  );

  TodoList? _findLiveList(String id) => _findLive(
    id: id,
    pushed: _pushedLists,
    selector: (s) => s.lists,
    idOf: (l) => l.id,
  );

  TaskItem? _findLiveTask(String id) => _findLive(
    id: id,
    pushed: _pushedTasks,
    selector: (s) => s.tasks,
    idOf: (t) => t.id,
  );

  String? _resolveGroupRemoteId(String? groupId) {
    if (groupId == null) return null;
    return _findLiveGroup(groupId)?.remoteId ??
        outbox.resolveRemoteId(SyncEntityType.group, groupId);
  }

  String? _resolveLiveListRemoteId(String listId) {
    final liveList = _findLiveList(listId);
    if (liveList == null) return null;
    return liveList.remoteId ??
        outbox.resolveRemoteId(SyncEntityType.list, listId);
  }

  String? _resolveParentTaskRemoteId(SyncOutboxOp op) =>
      op.parentRemoteId ??
      (op.parentLocalId != null
          ? outbox.resolveRemoteId(SyncEntityType.task, op.parentLocalId!)
          : null);

  Set<T>? _decodeEnumFields<T extends Enum>(
    Set<String> rawFields,
    List<T> values,
  ) {
    if (rawFields.isEmpty) return null;
    final byName = values.asNameMap();
    final result = rawFields.map((name) => byName[name]).nonNulls.toSet();
    return result.isEmpty ? null : result;
  }

  AsyncAppResult<Unit> _deleteIgnoring(
    AsyncAppResult<Unit> Function() deleteCall, {
    bool Function(AppError error)? treatAsDeletedOn,
  }) => deleteCall().recover((error) {
    final ignored = (treatAsDeletedOn ?? (e) => e.isNotFound)(error);
    return ignored ? const Success(unit) : Failure(error);
  });

  AsyncAppResult<T> _patchOrRecreateOnNotFound<T extends Object>({
    required AsyncAppResult<T> Function() patch,
    required AsyncAppResult<T> Function() create,
  }) => patch().recover((error) async {
    if (!error.isNotFound) return Failure<T, AppError>(error);
    return create();
  });

  AsyncAppResult<Unit> _pushSettings(List<SyncOutboxOp> ops) async {
    for (final op in ops) {
      final latestState = readLatestState?.call() ?? initialState;
      final wireValue = extractSettingValueForKey(latestState, op.localId);
      if (wireValue != null) {
        final result = await todoApi.patchSetting(ctx, op.localId, wireValue);
        if (result.isError()) return Failure(result.exceptionOrNull()!);
      }
      await _commitOp(seq: op.seq);
    }
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushDeletes(List<SyncOutboxOp> ops) async {
    for (final op in ops) {
      final result = await _pushSingleDelete(op);
      if (result.isError()) return result;
      await _commitOp(
        seq: op.seq,
        clearedRemoteIdKey: (type: op.entityType, localId: op.localId),
      );
    }
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushSingleDelete(SyncOutboxOp op) {
    final remoteId =
        op.remoteId ?? outbox.resolveRemoteId(op.entityType, op.localId);
    if (remoteId == null) return Future.value(const Success(unit));

    switch (op.entityType) {
      case SyncEntityType.step:
        final taskRemoteId = _resolveParentTaskRemoteId(op);
        if (taskRemoteId == null) return Future.value(const Success(unit));
        return _deleteIgnoring(
          () => todoApi.deleteStep(ctx, taskRemoteId, remoteId),
        );
      case SyncEntityType.attachment:
        final taskRemoteId = _resolveParentTaskRemoteId(op);
        if (taskRemoteId == null) return Future.value(const Success(unit));
        return _deleteIgnoring(
          () => todoApi.deleteLinkedEntity(ctx, taskRemoteId, remoteId),
        );
      case SyncEntityType.task:
        _deletedTaskRemoteIds.add(remoteId);
        return _deleteIgnoring(() => todoApi.deleteTask(ctx, remoteId));
      case SyncEntityType.list:
        _deletedListRemoteIds.add(remoteId);
        return _deleteIgnoring(
          () => todoApi.deleteFolder(ctx, remoteId),
          treatAsDeletedOn: (e) => e.isNotFound || e.isCantDeleteDefaultFolder,
        );
      case SyncEntityType.group:
        _deletedGroupRemoteIds.add(remoteId);
        return _deleteIgnoring(() => todoApi.deleteFolderGroup(ctx, remoteId));
      case SyncEntityType.setting:
        return Future.value(const Success(unit));
    }
  }

  AsyncAppResult<Unit> _pushGroupUpserts(List<SyncOutboxOp> ops) async {
    for (final op in ops) {
      final result = await _pushSingleGroupUpsert(op);
      if (result.isError()) return result;
    }
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushSingleGroupUpsert(SyncOutboxOp op) async {
    final rawGroup = _findLiveGroup(op.localId);
    if (rawGroup == null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }
    final resolvedRemoteId =
        rawGroup.remoteId ??
        outbox.resolveRemoteId(SyncEntityType.group, op.localId);
    final group = rawGroup.remoteId == null && resolvedRemoteId != null
        ? rawGroup.copyWith(remoteId: resolvedRemoteId)
        : rawGroup;
    if (group.remoteId != null &&
        _deletedGroupRemoteIds.contains(group.remoteId)) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    AsyncAppResult<RemoteFolderGroup> createGroup() =>
        todoApi.createFolderGroup(
          ctx,
          name: group.title,
          orderDateTime: group.orderDateTime ?? nowUtc,
        );

    final AppResult<RemoteFolderGroup> remoteResult;
    if (group.remoteId == null) {
      remoteResult = await createGroup();
    } else {
      final dirtyFields = _decodeEnumFields(op.fields, GroupDirtyField.values);
      final patchPayload = buildGroupPatchPayload(
        group,
        dirtyFields: dirtyFields,
      );
      if (patchPayload.isEmpty) {
        await _commitOp(seq: op.seq, group: group);
        return const Success(unit);
      }
      _log.fine(
        'push PATCH group=${group.id} remote=${shortSyncId(group.remoteId)} '
        'keys=${patchPayload.keys.toList()}',
      );
      remoteResult = await _patchOrRecreateOnNotFound(
        patch: () =>
            todoApi.patchFolderGroup(ctx, group.remoteId!, patchPayload),
        create: createGroup,
      );
    }

    if (remoteResult.isError()) return Failure(remoteResult.exceptionOrNull()!);
    final remoteGroup = remoteResult.getOrNull()!;
    outbox.recordRemoteId(SyncEntityType.group, group.id, remoteGroup.id);
    await _commitOp(
      seq: op.seq,
      group: group.copyWith(
        remoteId: remoteGroup.id,
        title: remoteGroup.name.isNotEmpty ? remoteGroup.name : group.title,
        orderDateTime: remoteGroup.orderDateTime ?? group.orderDateTime,
        updatedAt: nowUtc,
      ),
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushFolderUpserts(List<SyncOutboxOp> ops) async {
    for (final op in ops) {
      final result = await _pushSingleFolderUpsert(op);
      if (result.isError()) return result;
    }
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushSingleFolderUpsert(SyncOutboxOp op) async {
    final rawList = _findLiveList(op.localId);
    if (rawList == null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }
    final resolvedRemoteId =
        rawList.remoteId ??
        outbox.resolveRemoteId(SyncEntityType.list, op.localId);
    final list = rawList.remoteId == null && resolvedRemoteId != null
        ? rawList.copyWith(remoteId: resolvedRemoteId)
        : rawList;
    if ((list.remoteId != null &&
            _deletedListRemoteIds.contains(list.remoteId)) ||
        (list.isSmartList && list.smartType != SmartListType.tasks)) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    final parentGroupRemoteId = _resolveGroupRemoteId(list.groupId);
    AsyncAppResult<RemoteTodoFolder> createFolder() => todoApi.createFolder(
      ctx,
      buildFolderCreatePayload(
        list,
        parentGroupRemoteId: parentGroupRemoteId,
        nowUtc: nowUtc,
      ),
    );

    final AppResult<RemoteTodoFolder> remoteResult;
    if (!list.isSmartList && list.remoteId == null) {
      remoteResult = await createFolder();
    } else if (list.remoteId != null) {
      final dirtyFields = _decodeEnumFields(op.fields, ListDirtyField.values);
      final patchPayload = buildFolderPatchPayload(
        list,
        parentGroupRemoteId: parentGroupRemoteId,
        dirtyFields: dirtyFields,
      );
      if (patchPayload.isEmpty) {
        await _commitOp(seq: op.seq, list: list);
        return const Success(unit);
      }
      _log.fine(
        'push PATCH folder=${list.id} remote=${shortSyncId(list.remoteId)} '
        'keys=${patchPayload.keys.toList()}',
      );
      remoteResult = await _patchOrRecreateOnNotFound(
        patch: () => todoApi.patchFolder(ctx, list.remoteId!, patchPayload),
        create: createFolder,
      );
    } else {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    if (remoteResult.isError()) return Failure(remoteResult.exceptionOrNull()!);
    final remoteFolder = remoteResult.getOrNull()!;
    outbox.recordRemoteId(SyncEntityType.list, list.id, remoteFolder.id);
    await _commitOp(
      seq: op.seq,
      list: list.copyWith(
        remoteId: remoteFolder.id,
        title: list.title,
        orderDateTime: remoteFolder.orderDateTime ?? list.orderDateTime,
        updatedAt: nowUtc,
      ),
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushTaskUpserts(List<SyncOutboxOp> ops) {
    final opsByLocalId = ops.groupListsBy((op) => op.localId);
    return runResultsWithConcurrency(
      opsByLocalId.values.toList(),
      SubstratePushEngine._maxConcurrentTaskPushes,
      (opsForTask) async {
        for (final op in opsForTask) {
          final result = await _pushSingleTaskOp(op);
          if (result.isError()) return result;
        }
        return const Success(unit);
      },
    );
  }

  AsyncAppResult<Unit> _pushSingleTaskOp(SyncOutboxOp op) async {
    final rawTask = _findLiveTask(op.localId);
    if (rawTask == null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }
    final resolvedTaskRemoteId =
        rawTask.remoteId ??
        outbox.resolveRemoteId(SyncEntityType.task, op.localId);
    final task = rawTask.remoteId == null && resolvedTaskRemoteId != null
        ? rawTask.copyWith(remoteId: resolvedTaskRemoteId)
        : rawTask;
    if (task.remoteId != null &&
        _deletedTaskRemoteIds.contains(task.remoteId)) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    final folderRemoteId = _resolveLiveListRemoteId(task.listId);
    if (folderRemoteId == null) {
      if (_findLiveList(task.listId) == null) {
        // Parent list was deleted locally while push was in flight.
        await _commitOp(seq: op.seq);
      }
      return const Success(unit);
    }

    final isCreate = task.remoteId == null;
    final dirtyFields = isCreate
        ? null
        : _decodeEnumFields(op.fields, TaskDirtyField.values);
    final payload = buildTaskWritePayload(
      task,
      parentFolderRemoteId: folderRemoteId,
      isCreate: isCreate,
      firstDayOfWeek: initialState.startOfWeek,
      dirtyFields: dirtyFields,
    );

    if (!isCreate && payload.isEmpty) {
      _log.fine(
        'push SKIP task PATCH (steps-only) local=${task.id} '
        'remote=${shortSyncId(task.remoteId)}',
      );
      final stepsResult = await _syncStepsForTask(
        taskRemoteId: task.remoteId!,
        localSteps: task.steps,
        dirtyStepIds: op.stepIds,
      );
      if (stepsResult.isError()) return Failure(stepsResult.exceptionOrNull()!);
      await _commitOp(
        seq: op.seq,
        task: task.copyWith(steps: stepsResult.getOrNull()!, updatedAt: nowUtc),
      );
      return const Success(unit);
    }

    final writeResult = isCreate
        ? await _createTaskWithConflictRetry(folderRemoteId, payload).map(
            (remoteTask) => (
              remoteTask: remoteTask,
              mergedNote: null as String?,
              preservedRemoteStatus: false,
            ),
          )
        : await _patchTaskWithConflictRetry(
            task: task,
            payload: payload,
            folderRemoteId: folderRemoteId,
            dirtyFields: dirtyFields,
            baseNote: op.baseNote,
          );
    if (writeResult.isError()) return Failure(writeResult.exceptionOrNull()!);

    final patchOutcome = writeResult.getOrNull()!;
    final remoteTask = patchOutcome.remoteTask;
    outbox.recordRemoteId(SyncEntityType.task, task.id, remoteTask.id);

    final wasRecreated = !isCreate && remoteTask.id != task.remoteId;
    final stepsToSync = wasRecreated
        ? [for (final s in task.steps) s.copyWith(remoteId: null)]
        : task.steps;
    final Set<String>? stepDirtyIdsForTask =
        (wasRecreated || isCreate || dirtyFields == null)
        ? null
        : (dirtyFields.contains(TaskDirtyField.steps)
              ? op.stepIds
              : const <String>{});

    final stepsResult = await _syncStepsForTask(
      taskRemoteId: remoteTask.id,
      localSteps: stepsToSync,
      dirtyStepIds: stepDirtyIdsForTask,
    );
    if (stepsResult.isError()) return Failure(stepsResult.exceptionOrNull()!);

    final needsFollowUpPull =
        isCreate ||
        !isReorderOnlyTaskPatch(dirtyFields, isCompleted: task.isCompleted);
    await _commitOp(
      seq: op.seq,
      task: task.copyWith(
        remoteId: remoteTask.id,
        remoteParentFolderId: remoteTask.parentFolderId ?? folderRemoteId,
        changeKey: remoteTask.changeKey ?? task.changeKey,
        orderDateTime: remoteTask.orderDateTime ?? task.orderDateTime,
        committedOrder: remoteTask.committedOrder ?? task.committedOrder,
        note: patchOutcome.mergedNote ?? task.note,
        isCompleted: patchOutcome.preservedRemoteStatus
            ? remoteTask.isCompleted
            : task.isCompleted,
        completedAt: patchOutcome.preservedRemoteStatus
            ? remoteTask.completedDateTime
            : task.completedAt,
        dueDate: patchOutcome.preservedRemoteStatus
            ? (remoteTask.dueDate ?? task.dueDate)
            : task.dueDate,
        steps: stepsResult.getOrNull()!,
        updatedAt: nowUtc,
      ),
      followUpFolderRemoteId: needsFollowUpPull ? folderRemoteId : null,
    );
    _log.fine(
      'push ${isCreate ? "CREATE" : "PATCH"} local=${task.id} '
      'remote=${shortSyncId(remoteTask.id)} title="${task.title}" '
      'keys=${payload.keys.toList()}',
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushAttachmentUpserts(List<SyncOutboxOp> ops) async {
    for (final op in ops) {
      final result = await _pushSingleAttachmentUpsert(op);
      if (result.isError()) return result;
    }
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushSingleAttachmentUpsert(SyncOutboxOp op) async {
    final task = op.parentLocalId != null
        ? _findLiveTask(op.parentLocalId!)
        : null;
    if (task == null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }
    final att = task.attachments.firstWhereOrNull((a) => a.id == op.localId);
    if (att == null || att.remoteId != null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }
    final taskRemoteId =
        task.remoteId ??
        op.parentRemoteId ??
        outbox.resolveRemoteId(SyncEntityType.task, task.id);
    if (taskRemoteId == null) {
      return const Success(unit);
    }
    final localPath = att.localPath;
    if (localPath == null || localPath.isEmpty) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }
    final file = File(localPath);
    if (!await file.exists()) {
      _log.warning('Attachment file missing on disk for ${att.id}: $localPath');
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    final bytesResult = await guardApiCall(
      () => file.readAsBytes(),
      operation: 'readAttachment',
    );
    if (bytesResult.isError()) return Failure(bytesResult.exceptionOrNull()!);

    final uploadResult = await todoApi.uploadAttachment(
      ctx,
      taskRemoteId,
      fileName: att.displayName,
      bytes: bytesResult.getOrNull()!,
      contentType: att.contentType,
    );
    if (uploadResult.isError()) return Failure(uploadResult.exceptionOrNull()!);
    final uploaded = uploadResult.getOrNull()!;

    outbox.recordRemoteId(SyncEntityType.attachment, att.id, uploaded.id);
    final updatedAttachments = [
      for (final item in task.attachments)
        if (item.id == att.id)
          item.copyWith(
            remoteId: uploaded.id,
            size: uploaded.size > 0 ? uploaded.size : item.size,
            contentType: uploaded.contentType ?? item.contentType,
            lastModifiedDateTime:
                uploaded.lastModifiedDateTime ?? item.lastModifiedDateTime,
            isTransferring: false,
          )
        else
          item,
    ];
    final folderRemoteId = _findLiveList(task.listId)?.remoteId;
    await _commitOp(
      seq: op.seq,
      task: task.copyWith(attachments: updatedAttachments, updatedAt: nowUtc),
      followUpFolderRemoteId: folderRemoteId,
    );
    _log.fine(
      'push UPLOAD attachment=${att.id} remote=${shortSyncId(uploaded.id)} '
      'task=${shortSyncId(taskRemoteId)} name="${att.displayName}"',
    );
    return const Success(unit);
  }

  /// Aligns with MS To Do's `CreatedTasksPusher`: if `POST` with
  /// `CreatedWithLocalId` fails with 409 / `ErrorIrresolvableConflict` (and the
  /// API did not already recover an existing task from the 409 body), retry
  /// once without `CreatedWithLocalId`.
  AsyncAppResult<RemoteTodoTask> _createTaskWithConflictRetry(
    String folderRemoteId,
    Map<String, dynamic> payload,
  ) async {
    final first = await todoApi.createTask(ctx, folderRemoteId, payload);
    final firstErr = first.exceptionOrNull();
    if (firstErr == null ||
        !firstErr.isConflict ||
        !payload.containsKey('CreatedWithLocalId')) {
      return first;
    }
    _log.warning(
      'Conflict on task create with CreatedWithLocalId; '
      'retrying without CreatedWithLocalId',
    );
    final retryPayload = Map<String, dynamic>.of(payload)
      ..remove('CreatedWithLocalId');
    return todoApi.createTask(ctx, folderRemoteId, retryPayload);
  }

  AsyncAppResult<_TaskPatchOutcome> _patchTaskWithConflictRetry({
    required TaskItem task,
    required Map<String, dynamic> payload,
    required String folderRemoteId,
    required Set<TaskDirtyField>? dirtyFields,
    required String? baseNote,
  }) async {
    const maxConflictRetries = 3;
    String? mergedNote;
    var preservedRemoteStatus = false;
    final isReorderOnlyPatch = isReorderOnlyTaskPatch(
      dirtyFields,
      isCompleted: task.isCompleted,
    );
    var currentChangeKey = isReorderOnlyPatch ? null : task.changeKey;
    var currentPayload = payload;
    final bodyDirty =
        dirtyFields == null || dirtyFields.contains(TaskDirtyField.body);
    final statusDirty =
        dirtyFields == null || dirtyFields.contains(TaskDirtyField.status);

    var result = await todoApi.patchTask(
      ctx,
      task.remoteId!,
      currentPayload,
      changeKey: currentChangeKey,
    );

    for (var attempt = 0; attempt < maxConflictRetries; attempt++) {
      final err = result.exceptionOrNull();
      if (err == null || !err.isConflict) break;

      final latestResult = await todoApi.getTask(ctx, task.remoteId!);
      if (latestResult.isError()) {
        return Failure(latestResult.exceptionOrNull()!);
      }
      final latest = latestResult.getOrNull()!;
      final retryPayload = Map<String, dynamic>.of(payload);

      if (bodyDirty) {
        final resolvedNote = mergeThreeWayNoteText(
          base: baseNote,
          local: task.note,
          remote: latest.plainTextNote,
        );
        mergedNote = resolvedNote;
        retryPayload['Body'] = {'Content': resolvedNote, 'ContentType': 'Text'};
      }

      if (statusDirty &&
          task.isCompleted &&
          latest.hasRecurrence &&
          latest.dueDate != null &&
          task.dueDate != null &&
          !_sameCalendarDay(latest.dueDate!, task.dueDate!)) {
        preservedRemoteStatus = true;
        retryPayload['Status'] = latest.status;
        retryPayload['DueDateTime'] = formatDueDateTimeZone(latest.dueDate!);
        retryPayload['CompletedDateTime'] = latest.completedDateTime != null
            ? formatDateTimeTimeZoneUtc(latest.completedDateTime!)
            : null;
      }

      currentPayload = retryPayload;
      currentChangeKey = latest.changeKey;
      result = await todoApi.patchTask(
        ctx,
        task.remoteId!,
        currentPayload,
        changeKey: currentChangeKey,
      );
    }

    final finalErr = result.exceptionOrNull();
    if (finalErr != null && finalErr.isNotFound) {
      final createPayload = buildTaskWritePayload(
        task,
        parentFolderRemoteId: folderRemoteId,
        isCreate: true,
        firstDayOfWeek: initialState.startOfWeek,
      );
      result = await _createTaskWithConflictRetry(
        folderRemoteId,
        createPayload,
      );
    }

    return result.map(
      (remoteTask) => (
        remoteTask: remoteTask,
        mergedNote: mergedNote,
        preservedRemoteStatus: preservedRemoteStatus,
      ),
    );
  }

  AsyncAppResult<TaskStep> _createAndSyncStep({
    required String taskRemoteId,
    required TaskStep step,
    required DateTime stepOrder,
  }) async {
    final createdResult = await todoApi.createStep(
      ctx,
      taskRemoteId,
      subject: step.title,
      orderDateTime: stepOrder,
    );
    if (createdResult.isError()) {
      return Failure(createdResult.exceptionOrNull()!);
    }
    final created = createdResult.getOrNull()!;
    outbox.recordRemoteId(SyncEntityType.step, step.id, created.id);
    if (step.isCompleted) {
      final completeResult = await todoApi.patchStep(
        ctx,
        taskRemoteId,
        created.id,
        const {'IsCompleted': true},
      );
      if (completeResult.isError()) {
        return Failure(completeResult.exceptionOrNull()!);
      }
    }
    return Success(
      step.copyWith(
        remoteId: created.id,
        orderDateTime: created.orderDateTime ?? stepOrder,
      ),
    );
  }

  AsyncAppResult<List<TaskStep>> _syncStepsForTask({
    required String taskRemoteId,
    required List<TaskStep> localSteps,
    Set<String>? dirtyStepIds,
  }) async {
    final stepNowUtc = DateTime.now().toUtc();
    final syncedSteps = <TaskStep>[];

    for (final (i, rawStep) in localSteps.indexed) {
      final resolvedRemoteId =
          rawStep.remoteId ??
          outbox.resolveRemoteId(SyncEntityType.step, rawStep.id);
      final step = rawStep.remoteId == null && resolvedRemoteId != null
          ? rawStep.copyWith(remoteId: resolvedRemoteId)
          : rawStep;
      final stepOrder =
          step.orderDateTime ??
          stepNowUtc.subtract(
            Duration(seconds: i * kOrderDateTimeStep.inSeconds),
          );

      if (step.remoteId == null) {
        final created = await _createAndSyncStep(
          taskRemoteId: taskRemoteId,
          step: step,
          stepOrder: stepOrder,
        );
        if (created.isError()) return Failure(created.exceptionOrNull()!);
        syncedSteps.add(created.getOrNull()!);
        continue;
      }

      if (dirtyStepIds != null && !dirtyStepIds.contains(step.id)) {
        syncedSteps.add(step);
        continue;
      }

      final patchResult = await todoApi.patchStep(
        ctx,
        taskRemoteId,
        step.remoteId!,
        {
          'Subject': step.title,
          'IsCompleted': step.isCompleted,
          if (step.orderDateTime != null)
            'OrderDateTime': formatSubstrateUtcTimestamp(step.orderDateTime!),
        },
      );
      final patchError = patchResult.exceptionOrNull();
      if (patchError != null && patchError.isNotFound) {
        final recreated = await _createAndSyncStep(
          taskRemoteId: taskRemoteId,
          step: step,
          stepOrder: stepOrder,
        );
        if (recreated.isError()) return Failure(recreated.exceptionOrNull()!);
        syncedSteps.add(recreated.getOrNull()!);
        continue;
      }
      if (patchResult.isError()) return Failure(patchResult.exceptionOrNull()!);
      final patched = patchResult.getOrNull()!;
      syncedSteps.add(
        step.copyWith(
          orderDateTime: patched.orderDateTime ?? step.orderDateTime,
        ),
      );
    }

    return Success(syncedSteps);
  }
}
