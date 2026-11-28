import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync/sync_outbox.dart';
import '../../data/state/todo_state.dart';
import '../../core/network/http_guard.dart';
import 'microsoft_todo_api.dart';
import 'push_entity_handlers.dart';
import 'push_task_handler.dart';
import 'substrate_push_context.dart';

export 'substrate_push_context.dart' show OutboxPushOutcome, PushLaneFilter;

final _log = appLogFor('SyncEngine');

enum _PushStage {
  setting,
  nonGroupDelete,
  groupUpsert,
  listUpsert,
  groupDelete,
  taskUpsert,
  attachmentUpsert,
}

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
      final ctx = PushContext(
        todoApi: todoApi,
        readState: readState,
        startOfWeek: startState.startOfWeek,
        outbox: outbox,
        nowUtc: nowUtc,
        onItemCommitted: onItemCommitted,
      );
      return await _PushStageRunner(ctx).execute(batch);
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

class _PushStageRunner {
  _PushStageRunner(this.ctx)
    : _entities = EntityPushHandlers(ctx),
      _tasks = TaskPushHandler(ctx);

  final PushContext ctx;
  final EntityPushHandlers _entities;
  final TaskPushHandler _tasks;
  AppError? _firstItemError;

  static bool _isSessionFatalError(AppError error) =>
      error is AuthError || error is DatabaseError || error.isRetryable;

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
        _entities.pushSetting,
      ),
      () => _runSequentially(
        buckets[_PushStage.nonGroupDelete] ?? const [],
        _entities.pushDelete,
      ),
      () => _runSequentially(
        buckets[_PushStage.groupUpsert] ?? const [],
        _entities.pushGroupUpsert,
      ),
      () => _runSequentially(
        buckets[_PushStage.listUpsert] ?? const [],
        _entities.pushFolderUpsert,
      ),
      () => _runSequentially(
        buckets[_PushStage.groupDelete] ?? const [],
        _entities.pushDelete,
      ),
      () => _pushTaskUpserts(buckets[_PushStage.taskUpsert] ?? const []),
      () => _runSequentially(
        buckets[_PushStage.attachmentUpsert] ?? const [],
        _entities.pushAttachmentUpsert,
      ),
    ];

    for (final runStage in stages) {
      final result = await runStage();
      if (result.isError()) return Failure(result.exceptionOrNull()!);
    }

    if (_firstItemError != null) return Failure(_firstItemError!);
    return Success(ctx.buildOutcome());
  }

  AsyncAppResult<Unit> _pushTaskUpserts(List<SyncOutboxOp> ops) {
    final opsByLocalId = ops.groupListsBy((op) => op.localId);
    return runResultsWithConcurrency(
      opsByLocalId.values.toList(),
      SubstratePushEngine._maxConcurrentTaskPushes,
      (opsForTask) => _runSequentially(
        opsForTask,
        _tasks.pushTaskOp,
        stopOnItemError: true,
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

  Future<bool> _handleNotFound(SyncOutboxOp op) async {
    if (op.kind == SyncOpKind.delete) {
      await ctx.commitOp(seq: op.seq);
      return true;
    }
    final target = _resolveNotFoundDeletionTarget(op);
    if (target == null) return false;
    await ctx.commitRemoteDeletion(
      op,
      target.entity,
      remoteId: target.remoteId,
    );
    return true;
  }

  ({SyncEntityKey entity, String? remoteId})? _resolveNotFoundDeletionTarget(
    SyncOutboxOp op,
  ) {
    switch (op.entityType) {
      case SyncEntityType.group:
        final group = ctx.resolveGroup(op.localId);
        if (group?.remoteId == null) return null;
        return (
          entity: (type: SyncEntityType.group, localId: group!.id),
          remoteId: group.remoteId,
        );
      case SyncEntityType.list:
        final list = ctx.resolveList(op.localId);
        if (list == null || list.isSmartList || list.remoteId == null) {
          return null;
        }
        return (
          entity: (type: SyncEntityType.list, localId: list.id),
          remoteId: list.remoteId,
        );
      case SyncEntityType.task:
        final task = ctx.resolveTask(op.localId);
        if (task == null) return null;
        if (task.remoteId != null) {
          return (
            entity: (type: SyncEntityType.task, localId: task.id),
            remoteId: task.remoteId,
          );
        }
        final parentList = ctx.resolveList(task.listId);
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
            ? ctx.resolveTask(op.parentLocalId!)
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
}
