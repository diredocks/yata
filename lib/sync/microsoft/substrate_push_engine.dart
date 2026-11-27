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
import '../sync_guard.dart';
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
    this.deletedEntities = const {},
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
  final List<SyncEntityKey> clearedRemoteIdKeys;

  /// Folders needing one targeted task pull (recurring task completion or
  /// attachment upload where the server creates extra entities/links).
  final Set<String> followUpPullFolderRemoteIds;
  final Set<SyncEntityKey> deletedEntities;

  bool get didWork =>
      ackedSeqs.isNotEmpty ||
      pushedGroups.isNotEmpty ||
      pushedLists.isNotEmpty ||
      pushedTasks.isNotEmpty ||
      deletedEntities.isNotEmpty;
}

bool _isReorderOnlyTaskPatch(
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
    required TodoState Function() readState,
    required SyncOutboxQueue outbox,
    required DateTime nowUtc,
    Future<void> Function(OutboxPushOutcome itemOutcome)? onItemCommitted,
    PushLaneFilter laneFilter = PushLaneFilter.all,
    String reason = 'push',
  }) async {
    final batch = _filterBatch(outbox.beginBatch(), laneFilter);
    try {
      if (batch.isEmpty) {
        return const Success(OutboxPushOutcome.empty);
      }
      final startState = readState();
      _log.info(
        'push start reason=$reason '
        'localLists=${startState.lists.length} '
        'localTasks=${startState.tasks.length} '
        'outboxOps=${batch.length}',
      );
      final session = _PushSession(
        todoApi: todoApi,
        readState: readState,
        startOfWeek: startState.startOfWeek,
        outbox: outbox,
        nowUtc: nowUtc,
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
    required this.readState,
    required this.startOfWeek,
    required this.outbox,
    required this.nowUtc,
    this.onItemCommitted,
  });

  final MicrosoftTodoApi todoApi;
  final TodoState Function() readState;
  final WeekStart startOfWeek;
  final SyncOutboxQueue outbox;
  final DateTime nowUtc;
  final Future<void> Function(OutboxPushOutcome itemOutcome)? onItemCommitted;

  final List<int> _ackedSeqs = [];
  final List<SyncEntityKey> _clearedRemoteIdKeys = [];
  final Map<String, ListGroup> _pushedGroups = {};
  final Map<String, TodoList> _pushedLists = {};
  final Map<String, TaskItem> _pushedTasks = {};
  final Set<String> _followUpPullFolderRemoteIds = {};
  final Set<String> _deletedRemoteKeys = {};
  final Set<SyncEntityKey> _deletedEntities = {};
  AppError? _firstItemError;

  static bool _isSessionFatalError(AppError error) =>
      error is AuthError || error is DatabaseError || error.isRetryable;

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
      () => _runSequentially(
        buckets[_PushStage.setting] ?? const [],
        _pushSingleSetting,
      ),
      () => _runSequentially(
        buckets[_PushStage.nonGroupDelete] ?? const [],
        _pushSingleDeleteOp,
      ),
      () => _runSequentially(
        buckets[_PushStage.groupUpsert] ?? const [],
        _pushSingleGroupUpsert,
      ),
      () => _runSequentially(
        buckets[_PushStage.listUpsert] ?? const [],
        _pushSingleFolderUpsert,
      ),
      () => _runSequentially(
        buckets[_PushStage.groupDelete] ?? const [],
        _pushSingleDeleteOp,
      ),
      () => _pushTaskUpserts(buckets[_PushStage.taskUpsert] ?? const []),
      () => _runSequentially(
        buckets[_PushStage.attachmentUpsert] ?? const [],
        _pushSingleAttachmentUpsert,
      ),
    ];

    for (final runStage in stages) {
      final result = await runStage();
      if (result.isError()) return Failure(result.exceptionOrNull()!);
    }

    if (_firstItemError != null) return Failure(_firstItemError!);

    return Success(
      OutboxPushOutcome(
        ackedSeqs: _ackedSeqs,
        pushedGroups: _pushedGroups,
        pushedLists: _pushedLists,
        pushedTasks: _pushedTasks,
        clearedRemoteIdKeys: _clearedRemoteIdKeys,
        followUpPullFolderRemoteIds: _followUpPullFolderRemoteIds,
        deletedEntities: _deletedEntities,
      ),
    );
  }

  AsyncAppResult<Unit> _runSequentially(
    List<SyncOutboxOp> ops,
    AsyncAppResult<Unit> Function(SyncOutboxOp op) run, {
    bool stopOnItemError = false,
  }) async {
    for (final op in ops) {
      final result = await run(op);
      final err = result.exceptionOrNull();
      if (err == null) continue;
      if (err.isNotFound && await _handleNotFound(op)) continue;
      if (_isSessionFatalError(err)) return Failure(err);
      _firstItemError ??= err;
      _log.warning(
        'push op failed entity=${op.entityType.name} local=${op.localId} '
        'error=${err.describe()}',
      );
      if (stopOnItemError) break;
    }
    return const Success(unit);
  }

  Future<void> _commitOp({
    required int seq,
    ListGroup? group,
    TodoList? list,
    TaskItem? task,
    SyncEntityKey? deletedEntity,
    SyncEntityKey? clearedRemoteIdKey,
    String? followUpFolderRemoteId,
  }) async {
    _ackedSeqs.add(seq);
    if (group != null) _pushedGroups[group.id] = group;
    if (list != null) _pushedLists[list.id] = list;
    if (task != null) _pushedTasks[task.id] = task;
    if (deletedEntity != null) _deletedEntities.add(deletedEntity);
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
        deletedEntities: deletedEntity != null ? {deletedEntity} : const {},
      ),
    );
  }

  T? _findLive<T>({
    required String id,
    required Map<String, T> pushed,
    required List<T> Function(TodoState state) selector,
    required String Function(T item) idOf,
  }) {
    final match = selector(readState()).firstWhereOrNull((e) => idOf(e) == id);
    return match == null ? null : (pushed[id] ?? match);
  }

  T? _resolveEntity<T>({
    required SyncEntityType entityType,
    required String localId,
    required Map<String, T> pushed,
    required List<T> Function(TodoState state) selector,
    required String Function(T item) idOf,
    required String? Function(T item) remoteIdOf,
    required T Function(T item, String remoteId) withRemoteId,
  }) {
    if (_deletedEntities.contains((type: entityType, localId: localId))) {
      return null;
    }
    final raw = _findLive(
      id: localId,
      pushed: pushed,
      selector: selector,
      idOf: idOf,
    );
    if (raw == null) return null;
    final rawRemoteId = remoteIdOf(raw);
    final resolvedRemoteId =
        rawRemoteId ?? outbox.resolveRemoteId(entityType, localId);
    final resolved = rawRemoteId == null && resolvedRemoteId != null
        ? withRemoteId(raw, resolvedRemoteId)
        : raw;
    final effectiveRemoteId = remoteIdOf(resolved);
    if (effectiveRemoteId != null &&
        _deletedRemoteKeys.contains(
          SyncOutboxQueue.remoteKey(entityType, effectiveRemoteId),
        )) {
      return null;
    }
    return resolved;
  }

  ListGroup? _resolveGroup(String localId) => _resolveEntity(
    entityType: SyncEntityType.group,
    localId: localId,
    pushed: _pushedGroups,
    selector: (s) => s.groups,
    idOf: (g) => g.id,
    remoteIdOf: (g) => g.remoteId,
    withRemoteId: (g, remoteId) => g.copyWith(remoteId: remoteId),
  );

  TodoList? _resolveList(String localId) => _resolveEntity(
    entityType: SyncEntityType.list,
    localId: localId,
    pushed: _pushedLists,
    selector: (s) => s.lists,
    idOf: (l) => l.id,
    remoteIdOf: (l) => l.remoteId,
    withRemoteId: (l, remoteId) => l.copyWith(remoteId: remoteId),
  );

  TaskItem? _resolveTask(String localId) {
    final resolved = _resolveEntity(
      entityType: SyncEntityType.task,
      localId: localId,
      pushed: _pushedTasks,
      selector: (s) => s.tasks,
      idOf: (t) => t.id,
      remoteIdOf: (t) => t.remoteId,
      withRemoteId: (t, remoteId) => t.copyWith(remoteId: remoteId),
    );
    if (resolved != null &&
        _deletedEntities.contains((
          type: SyncEntityType.list,
          localId: resolved.listId,
        ))) {
      return null;
    }
    return resolved;
  }

  String? _resolveGroupRemoteId(String? groupId) {
    if (groupId == null) return null;
    final liveGroup = _resolveGroup(groupId);
    if (liveGroup == null) return null;
    return liveGroup.remoteId ??
        outbox.resolveRemoteId(SyncEntityType.group, groupId);
  }

  Future<bool> _handleNotFound(SyncOutboxOp op) async {
    if (op.kind == SyncOpKind.delete) {
      await _commitOp(
        seq: op.seq,
        clearedRemoteIdKey: (type: op.entityType, localId: op.localId),
      );
      return true;
    }
    final target = _resolveNotFoundDeletionTarget(op);
    if (target == null) return false;
    await _commitRemoteDeletion(op, target.entity, remoteId: target.remoteId);
    return true;
  }

  ({SyncEntityKey entity, String? remoteId})? _resolveNotFoundDeletionTarget(
    SyncOutboxOp op,
  ) {
    switch (op.entityType) {
      case SyncEntityType.group:
        final group = _resolveGroup(op.localId);
        if (group?.remoteId == null) return null;
        return (
          entity: (type: SyncEntityType.group, localId: group!.id),
          remoteId: group.remoteId,
        );
      case SyncEntityType.list:
        final list = _resolveList(op.localId);
        if (list == null || list.isSmartList || list.remoteId == null) {
          return null;
        }
        return (
          entity: (type: SyncEntityType.list, localId: list.id),
          remoteId: list.remoteId,
        );
      case SyncEntityType.task:
        final task = _resolveTask(op.localId);
        if (task == null) return null;
        if (task.remoteId != null) {
          return (
            entity: (type: SyncEntityType.task, localId: task.id),
            remoteId: task.remoteId,
          );
        }
        final parentList = _resolveList(task.listId);
        if (parentList == null ||
            parentList.isSmartList ||
            parentList.remoteId == null) {
          return null;
        }
        return (
          entity: (type: SyncEntityType.list, localId: parentList.id),
          remoteId: parentList.remoteId,
        );
      case SyncEntityType.attachment:
        final parentTask = op.parentLocalId != null
            ? _resolveTask(op.parentLocalId!)
            : null;
        if (parentTask?.remoteId == null) return null;
        return (
          entity: (type: SyncEntityType.task, localId: parentTask!.id),
          remoteId: parentTask.remoteId,
        );
      case SyncEntityType.step:
      case SyncEntityType.setting:
        return null;
    }
  }

  Future<void> _commitRemoteDeletion(
    SyncOutboxOp op,
    SyncEntityKey entity, {
    String? remoteId,
  }) async {
    final effectiveRemoteId =
        remoteId ?? outbox.resolveRemoteId(entity.type, entity.localId);
    if (effectiveRemoteId != null) {
      _deletedRemoteKeys.add(
        SyncOutboxQueue.remoteKey(entity.type, effectiveRemoteId),
      );
    }
    switch (entity.type) {
      case SyncEntityType.group:
        _pushedGroups.remove(entity.localId);
      case SyncEntityType.list:
        _pushedLists.remove(entity.localId);
      case SyncEntityType.task:
        _pushedTasks.remove(entity.localId);
      case SyncEntityType.step:
      case SyncEntityType.attachment:
      case SyncEntityType.setting:
        break;
    }
    _log.info(
      'push DELETE-WINS ${entity.type.name} local=${entity.localId} '
      'remote=${shortSyncId(effectiveRemoteId)}',
    );
    await _commitOp(
      seq: op.seq,
      deletedEntity: entity,
      clearedRemoteIdKey: entity,
    );
  }

  String? _resolveLiveListRemoteId(String listId) {
    final liveList = _resolveList(listId);
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

  AsyncAppResult<Unit> _pushSingleSetting(SyncOutboxOp op) async {
    final wireValue = extractSettingValueForKey(readState(), op.localId);
    if (wireValue != null) {
      final result = await todoApi.patchSetting(op.localId, wireValue);
      if (result.isError()) return Failure(result.exceptionOrNull()!);
    }
    await _commitOp(seq: op.seq);
    return const Success(unit);
  }

  AsyncAppResult<Unit> _pushSingleDeleteOp(SyncOutboxOp op) async {
    final result = await _performDelete(op);
    if (result.isError()) return result;
    await _commitOp(
      seq: op.seq,
      clearedRemoteIdKey: (type: op.entityType, localId: op.localId),
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> _performDelete(SyncOutboxOp op) {
    final remoteId =
        op.remoteId ?? outbox.resolveRemoteId(op.entityType, op.localId);
    if (remoteId == null) return Future.value(const Success(unit));

    switch (op.entityType) {
      case SyncEntityType.step:
        final taskRemoteId = _resolveParentTaskRemoteId(op);
        if (taskRemoteId == null) return Future.value(const Success(unit));
        return todoApi.deleteStep(taskRemoteId, remoteId);
      case SyncEntityType.attachment:
        final taskRemoteId = _resolveParentTaskRemoteId(op);
        if (taskRemoteId == null) return Future.value(const Success(unit));
        return todoApi.deleteLinkedEntity(taskRemoteId, remoteId);
      case SyncEntityType.task:
        _deletedRemoteKeys.add(
          SyncOutboxQueue.remoteKey(op.entityType, remoteId),
        );
        return todoApi.deleteTask(remoteId);
      case SyncEntityType.list:
        _deletedRemoteKeys.add(
          SyncOutboxQueue.remoteKey(op.entityType, remoteId),
        );
        return todoApi
            .deleteFolder(remoteId)
            .recover(
              (e) =>
                  e.isCantDeleteDefaultFolder ? const Success(unit) : Failure(e),
            );
      case SyncEntityType.group:
        _deletedRemoteKeys.add(
          SyncOutboxQueue.remoteKey(op.entityType, remoteId),
        );
        return todoApi.deleteFolderGroup(remoteId);
      case SyncEntityType.setting:
        return Future.value(const Success(unit));
    }
  }

  AsyncAppResult<Unit> _pushSingleGroupUpsert(SyncOutboxOp op) async {
    final group = _resolveGroup(op.localId);
    if (group == null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    final AppResult<RemoteFolderGroup> remoteResult;
    if (group.remoteId == null) {
      remoteResult = await todoApi.createFolderGroup(
        name: group.title,
        orderDateTime: group.orderDateTime ?? nowUtc,
      );
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
      remoteResult = await todoApi.patchFolderGroup(
        group.remoteId!,
        patchPayload,
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

  AsyncAppResult<Unit> _pushSingleFolderUpsert(SyncOutboxOp op) async {
    final list = _resolveList(op.localId);
    if (list == null ||
        (list.isSmartList && list.smartType != SmartListType.tasks)) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    final parentGroupRemoteId = _resolveGroupRemoteId(list.groupId);
    final AppResult<RemoteTodoFolder> remoteResult;
    if (!list.isSmartList && list.remoteId == null) {
      remoteResult = await todoApi.createFolder(
        buildFolderCreatePayload(
          list,
          parentGroupRemoteId: parentGroupRemoteId,
          nowUtc: nowUtc,
        ),
      );
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
      remoteResult = await todoApi.patchFolder(list.remoteId!, patchPayload);
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
      (opsForTask) => _runSequentially(
        opsForTask,
        _pushSingleTaskOp,
        stopOnItemError: true,
      ),
    );
  }

  AsyncAppResult<Unit> _pushSingleTaskOp(SyncOutboxOp op) async {
    final task = _resolveTask(op.localId);
    if (task == null) {
      await _commitOp(seq: op.seq);
      return const Success(unit);
    }

    final folderRemoteId = _resolveLiveListRemoteId(task.listId);
    if (folderRemoteId == null) {
      if (_resolveList(task.listId) == null) {
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
      firstDayOfWeek: startOfWeek,
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
            dirtyFields: dirtyFields,
            baseNote: op.baseNote,
          );
    if (writeResult.isError()) return Failure(writeResult.exceptionOrNull()!);

    final patchOutcome = writeResult.getOrNull()!;
    final remoteTask = patchOutcome.remoteTask;
    outbox.recordRemoteId(SyncEntityType.task, task.id, remoteTask.id);

    final Set<String>? stepDirtyIdsForTask = (isCreate || dirtyFields == null)
        ? null
        : (dirtyFields.contains(TaskDirtyField.steps)
              ? op.stepIds
              : const <String>{});

    final stepsResult = await _syncStepsForTask(
      taskRemoteId: remoteTask.id,
      localSteps: task.steps,
      dirtyStepIds: stepDirtyIdsForTask,
    );
    if (stepsResult.isError()) return Failure(stepsResult.exceptionOrNull()!);

    final isRecurring =
        task.recurrence != RecurrenceType.none ||
        (task.rawRecurrence != null && task.rawRecurrence!.isNotEmpty);
    final statusDirty =
        dirtyFields == null || dirtyFields.contains(TaskDirtyField.status);
    final needsFollowUpPull =
        !isCreate && task.isCompleted && isRecurring && statusDirty;
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

  AsyncAppResult<Unit> _pushSingleAttachmentUpsert(SyncOutboxOp op) async {
    final task = op.parentLocalId != null
        ? _resolveTask(op.parentLocalId!)
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
    final folderRemoteId = _resolveList(task.listId)?.remoteId;
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
    final first = await todoApi.createTask(folderRemoteId, payload);
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
    return todoApi.createTask(folderRemoteId, retryPayload);
  }

  AsyncAppResult<_TaskPatchOutcome> _patchTaskWithConflictRetry({
    required TaskItem task,
    required Map<String, dynamic> payload,
    required Set<TaskDirtyField>? dirtyFields,
    required String? baseNote,
  }) async {
    const maxConflictRetries = 3;
    String? mergedNote;
    var preservedRemoteStatus = false;
    final isReorderOnlyPatch = _isReorderOnlyTaskPatch(
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
      task.remoteId!,
      currentPayload,
      changeKey: currentChangeKey,
    );

    for (var attempt = 0; attempt < maxConflictRetries; attempt++) {
      final err = result.exceptionOrNull();
      if (err == null || !err.isConflict) break;

      final latestResult = await todoApi.getTask(task.remoteId!);
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
        task.remoteId!,
        currentPayload,
        changeKey: currentChangeKey,
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

      final stepResult = await todoApi.patchStep(taskRemoteId, step.remoteId!, {
        'Subject': step.title,
        'IsCompleted': step.isCompleted,
        if (step.orderDateTime != null)
          'OrderDateTime': formatSubstrateUtcTimestamp(step.orderDateTime!),
      });
      final stepErr = stepResult.exceptionOrNull();
      if (stepErr != null) {
        if (stepErr.isNotFound) {
          final probe = await todoApi.getTask(taskRemoteId);
          if (probe.isError()) return Failure(probe.exceptionOrNull()!);
          continue;
        }
        return Failure(stepErr);
      }
      final patched = stepResult.getOrNull()!;
      syncedSteps.add(
        step.copyWith(
          orderDateTime: patched.orderDateTime ?? step.orderDateTime,
        ),
      );
    }

    return Success(syncedSteps);
  }
}
