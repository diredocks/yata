import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync/sync_dirty_fields.dart';
import '../../data/sync/sync_outbox.dart';
import '../../models/task_item.dart';
import '../../core/network/http_guard.dart';
import '../text_merge.dart';
import 'microsoft_todo_api.dart';
import 'substrate_push_context.dart';
import 'substrate_sync_mappers.dart';
import 'todo_wire_codecs.dart';

final _log = appLogFor('SyncEngine');

typedef _TaskPatchOutcome = ({
  RemoteTodoTask remoteTask,
  String? mergedNote,
  String? mergedNoteHtml,
  String? mergedNoteContentType,
  bool preservedRemoteStatus,
});

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

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Handles task upserts, subtask synchronization, 409 conflict retries, and
/// three-way note merging against Substrate.
class TaskPushHandler {
  const TaskPushHandler(this.ctx);

  final PushContext ctx;

  AsyncAppResult<Unit> pushTaskOp(SyncOutboxOp op) async {
    final task = ctx.resolveTask(op.localId);
    if (task == null) {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }

    final folderRemoteId = ctx.resolveLiveListRemoteId(task.listId);
    if (folderRemoteId == null) {
      if (ctx.resolveList(task.listId) == null) {
        // Parent list was deleted locally while push was in flight.
        await ctx.commitOp(seq: op.seq);
      }
      return const Success(unit);
    }

    final isCreate = task.remoteId == null;
    final dirtyFields = isCreate
        ? null
        : ctx.decodeEnumFields(op.fields, TaskDirtyField.values);
    final payload = buildTaskWritePayload(
      task,
      parentFolderRemoteId: folderRemoteId,
      isCreate: isCreate,
      firstDayOfWeek: ctx.startOfWeek,
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
      await ctx.commitOp(
        seq: op.seq,
        task: task.copyWith(
          steps: stepsResult.getOrNull()!,
          updatedAt: ctx.nowUtc,
        ),
      );
      return const Success(unit);
    }

    final writeResult = isCreate
        ? await _createTaskWithConflictRetry(folderRemoteId, payload).map(
            (remoteTask) => (
              remoteTask: remoteTask,
              mergedNote: null as String?,
              mergedNoteHtml: null as String?,
              mergedNoteContentType: null as String?,
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
    ctx.recordCreatedRemoteId(SyncEntityType.task, task.id, remoteTask.id);

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
    await ctx.commitOp(
      seq: op.seq,
      task: task.copyWith(
        remoteId: remoteTask.id,
        remoteParentFolderId: remoteTask.parentFolderId ?? folderRemoteId,
        changeKey: remoteTask.changeKey ?? task.changeKey,
        orderDateTime: remoteTask.orderDateTime ?? task.orderDateTime,
        committedOrder: remoteTask.committedOrder ?? task.committedOrder,
        note: patchOutcome.mergedNote ?? task.note,
        noteHtml: patchOutcome.mergedNoteHtml ?? task.noteHtml,
        noteContentType:
            patchOutcome.mergedNoteContentType ?? task.noteContentType,
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
        updatedAt: ctx.nowUtc,
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

  /// Aligns with MS To Do's `CreatedTasksPusher`: if `POST` with
  /// `CreatedWithLocalId` fails with 409 / `ErrorIrresolvableConflict` (and the
  /// API did not already recover an existing task from the 409 body), retry
  /// once without `CreatedWithLocalId`.
  AsyncAppResult<RemoteTodoTask> _createTaskWithConflictRetry(
    String folderRemoteId,
    Map<String, dynamic> payload,
  ) async {
    final first = await ctx.todoApi.createTask(folderRemoteId, payload);
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
    return ctx.todoApi.createTask(folderRemoteId, retryPayload);
  }

  AsyncAppResult<_TaskPatchOutcome> _patchTaskWithConflictRetry({
    required TaskItem task,
    required Map<String, dynamic> payload,
    required Set<TaskDirtyField>? dirtyFields,
    required String? baseNote,
  }) async {
    const maxConflictRetries = 3;
    String? mergedNote;
    String? mergedNoteHtml;
    String? mergedNoteContentType;
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

    var result = await ctx.todoApi.patchTask(
      task.remoteId!,
      currentPayload,
      changeKey: currentChangeKey,
    );

    for (var attempt = 0; attempt < maxConflictRetries; attempt++) {
      final err = result.exceptionOrNull();
      if (err == null || !err.isConflict) break;

      final latestResult = await ctx.todoApi.getTask(task.remoteId!);
      if (latestResult.isError()) {
        return Failure(latestResult.exceptionOrNull()!);
      }
      final latest = latestResult.getOrNull()!;
      final retryPayload = Map<String, dynamic>.of(payload);

      if (bodyDirty) {
        final remoteIsHtml =
            latest.bodyContentType?.trim().toLowerCase() == 'html';
        if (task.isHtmlNote || remoteIsHtml) {
          final remoteTime = latest.bodyLastModifiedTime;
          final localTime = task.noteUpdatedAt;
          final remoteNewer =
              remoteTime != null &&
              (localTime == null || localTime.isBefore(remoteTime));
          if (remoteNewer) {
            mergedNote = latest.plainTextNote;
            mergedNoteHtml =
                remoteIsHtml && !isHtmlBodyEmpty(latest.bodyContent)
                ? latest.bodyContent
                : '';
            mergedNoteContentType = latest.bodyContentType;
            retryPayload['Body'] = {
              'Content': remoteIsHtml
                  ? normalizeHtmlBodyDocument(latest.bodyContent)
                  : truncatePlainTextBody(latest.plainTextNote),
              'ContentType': latest.bodyContentType ?? 'Text',
            };
          } else {
            mergedNote = task.note;
            mergedNoteHtml = task.noteHtml;
            mergedNoteContentType = task.noteContentType;
            retryPayload['Body'] = task.isHtmlNote
                ? {
                    'Content': normalizeHtmlBodyDocument(task.noteHtml),
                    'ContentType': 'HTML',
                  }
                : {
                    'Content': truncatePlainTextBody(task.note),
                    'ContentType': 'Text',
                  };
          }
        } else {
          final resolvedNote = mergeThreeWayNoteText(
            base: baseNote,
            local: task.note,
            remote: latest.plainTextNote,
          );
          mergedNote = resolvedNote;
          mergedNoteHtml = '';
          mergedNoteContentType = 'Text';
          retryPayload['Body'] = {
            'Content': truncatePlainTextBody(resolvedNote),
            'ContentType': 'Text',
          };
        }
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
      result = await ctx.todoApi.patchTask(
        task.remoteId!,
        currentPayload,
        changeKey: currentChangeKey,
      );
    }

    return result.map(
      (remoteTask) => (
        remoteTask: remoteTask,
        mergedNote: mergedNote,
        mergedNoteHtml: mergedNoteHtml,
        mergedNoteContentType: mergedNoteContentType,
        preservedRemoteStatus: preservedRemoteStatus,
      ),
    );
  }

  AsyncAppResult<TaskStep> _createAndSyncStep({
    required String taskRemoteId,
    required TaskStep step,
    required DateTime stepOrder,
  }) async {
    final createdResult = await ctx.todoApi.createStep(
      taskRemoteId,
      subject: step.title,
      orderDateTime: stepOrder,
    );
    if (createdResult.isError()) {
      return Failure(createdResult.exceptionOrNull()!);
    }
    final created = createdResult.getOrNull()!;
    ctx.recordCreatedRemoteId(SyncEntityType.step, step.id, created.id);
    if (step.isCompleted) {
      final completeResult = await ctx.todoApi.patchStep(
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
          ctx.resolveSessionRemoteId(SyncEntityType.step, rawStep.id);
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

      final stepResult = await ctx.todoApi.patchStep(
        taskRemoteId,
        step.remoteId!,
        {
          'Subject': step.title,
          'IsCompleted': step.isCompleted,
          if (step.orderDateTime != null)
            'OrderDateTime': formatSubstrateUtcTimestamp(step.orderDateTime!),
        },
      );
      final stepErr = stepResult.exceptionOrNull();
      if (stepErr != null) {
        if (stepErr.isNotFound) {
          final probe = await ctx.todoApi.getTask(taskRemoteId);
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
