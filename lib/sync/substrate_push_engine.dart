import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/sync_dirty_fields.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_sync.dart';
import '../data/todo_state.dart';
import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_api.dart';
import 'substrate_sync_mappers.dart';
import 'sync_log_format.dart';
import 'text_merge.dart';
import 'todo_wire_codecs.dart';

class MetadataPushResult {
  const MetadataPushResult({
    required this.groups,
    required this.lists,
    required this.processedDeletedGroupRemoteIds,
    required this.processedDeletedListRemoteIds,
    required this.processedDeletedTaskRemoteIds,
    required this.processedDeletedSteps,
    required this.syncedSettingKeys,
    required this.syncedGroupIds,
    required this.syncedListIds,
    required this.syncedGroupFields,
    required this.syncedListFields,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<String> processedDeletedGroupRemoteIds;
  final List<String> processedDeletedListRemoteIds;
  final List<String> processedDeletedTaskRemoteIds;
  final List<PendingStepDeletion> processedDeletedSteps;
  final Set<String> syncedSettingKeys;
  final Set<String> syncedGroupIds;
  final Set<String> syncedListIds;
  final Map<String, Set<GroupDirtyField>> syncedGroupFields;
  final Map<String, Set<ListDirtyField>> syncedListFields;
}

class TaskPushResult {
  const TaskPushResult({
    required this.tasks,
    required this.syncedTaskIds,
    required this.syncedTaskFields,
    required this.syncedStepIds,
  });

  final List<TaskItem> tasks;
  final Set<String> syncedTaskIds;
  final Map<String, Set<TaskDirtyField>> syncedTaskFields;
  final Map<String, Set<String>> syncedStepIds;
}

/// Pushes local deletions, settings, folder groups, folders, tasks, and steps
/// to Substrate To Do v1 (Phases 2–6 and 10a).
class SubstratePushEngine {
  const SubstratePushEngine(this.todoApi);

  final MicrosoftTodoApi todoApi;

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Executes Phases 2–6: settings, deletions, groups, folders, and group deletions.
  Future<MetadataPushResult> pushMetadataAndDeletions({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required TodoRepository repository,
    required Set<String> dirtySettingKeys,
    required Set<String> dirtyGroupIds,
    required Map<String, Set<GroupDirtyField>> dirtyGroupFields,
    required Set<String> dirtyListIds,
    required Map<String, Set<ListDirtyField>> dirtyListFields,
    required DateTime nowUtc,
  }) async {
    final workingGroups = [...currentState.groups];
    final workingLists = [...currentState.lists];
    final syncedSettingKeys = <String>{};
    final syncedGroupIds = <String>{};
    final syncedListIds = <String>{};
    final syncedGroupFields = <String, Set<GroupDirtyField>>{};
    final syncedListFields = <String, Set<ListDirtyField>>{};

    // Phase 2: Push dirty settings.
    for (final key in dirtySettingKeys) {
      final wireValue = extractSettingValueForKey(currentState, key);
      if (wireValue != null) {
        (await todoApi.patchSetting(ctx, key, wireValue)).getOrThrow();
      }
      syncedSettingKeys.add(key);
    }

    // Phase 3: Push step, task, and folder deletions.
    final processedDeletedSteps = await _pushPendingDeletions(
      items: repository.loadPendingDeletedSteps(),
      deleteCall: (s) =>
          todoApi.deleteStep(ctx, s.taskRemoteId, s.stepRemoteId),
    );
    final processedDeletedTaskRemoteIds = await _pushPendingDeletions(
      items: repository.loadPendingDeletedTaskRemoteIds(),
      deleteCall: (id) => todoApi.deleteTask(ctx, id),
    );
    final processedDeletedListRemoteIds = await _pushPendingDeletions(
      items: repository.loadPendingDeletedListRemoteIds(),
      deleteCall: (id) => todoApi.deleteFolder(ctx, id),
      treatAsDeletedOn: (e) => e.isNotFound || e.isCantDeleteDefaultFolder,
    );

    // Phase 4: Push dirty / new folder groups.
    for (var i = 0; i < workingGroups.length; i++) {
      final group = workingGroups[i];
      if (group.remoteId == null) {
        final created = (await todoApi.createFolderGroup(
          ctx,
          name: group.title,
          orderDateTime: group.orderDateTime ?? nowUtc,
        )).getOrThrow();
        workingGroups[i] = group.copyWith(
          remoteId: created.id,
          orderDateTime: created.orderDateTime ?? group.orderDateTime,
          updatedAt: nowUtc,
        );
        syncedGroupIds.add(group.id);
      } else if (dirtyGroupIds.contains(group.id)) {
        final rawFields = dirtyGroupFields[group.id];
        final effectiveFields = (rawFields == null || rawFields.isEmpty)
            ? null
            : rawFields;
        final patchPayload = buildGroupPatchPayload(
          group,
          dirtyFields: effectiveFields,
        );
        if (patchPayload.isEmpty) {
          syncedGroupIds.add(group.id);
          if (effectiveFields != null) {
            syncedGroupFields[group.id] = Set<GroupDirtyField>.from(
              effectiveFields,
            );
          }
          continue;
        }
        appLog(
          'Phase 4 PATCH group=${group.id} remote=${shortSyncId(group.remoteId)} '
          'keys=${patchPayload.keys.toList()}',
          label: 'SyncEngine',
        );
        final patchResult = await todoApi
            .patchFolderGroup(ctx, group.remoteId!, patchPayload)
            .recover((error) async {
              if (!error.isNotFound) {
                return Failure<RemoteFolderGroup, AppError>(error);
              }
              return todoApi.createFolderGroup(
                ctx,
                name: group.title,
                orderDateTime: group.orderDateTime ?? nowUtc,
              );
            });
        final remoteGroup = patchResult.getOrThrow();
        workingGroups[i] = group.copyWith(
          remoteId: remoteGroup.id,
          title: remoteGroup.name.isNotEmpty ? remoteGroup.name : group.title,
          orderDateTime: remoteGroup.orderDateTime ?? group.orderDateTime,
          updatedAt: nowUtc,
        );
        syncedGroupIds.add(group.id);
        if (effectiveFields != null) {
          syncedGroupFields[group.id] = Set<GroupDirtyField>.from(
            effectiveFields,
          );
        }
      }
    }

    final groupRemoteByLocalId = {
      for (final g in workingGroups)
        if (g.remoteId != null) g.id: g.remoteId!,
    };

    // Phase 5: Push dirty / new folders BEFORE deleting folder groups.
    for (var i = 0; i < workingLists.length; i++) {
      final list = workingLists[i];
      final isSyncableFolder =
          !list.isSmartList || list.smartType == SmartListType.tasks;
      if (!isSyncableFolder) continue;

      final parentGroupRemoteId = list.groupId != null
          ? groupRemoteByLocalId[list.groupId!]
          : null;

      if (!list.isSmartList && list.remoteId == null) {
        final created = (await todoApi.createFolder(
          ctx,
          buildFolderCreatePayload(
            list,
            parentGroupRemoteId: parentGroupRemoteId,
            nowUtc: nowUtc,
          ),
        )).getOrThrow();
        workingLists[i] = list.copyWith(
          remoteId: created.id,
          orderDateTime: created.orderDateTime ?? list.orderDateTime,
          updatedAt: nowUtc,
        );
        syncedListIds.add(list.id);
      } else if (list.remoteId != null && dirtyListIds.contains(list.id)) {
        final rawFields = dirtyListFields[list.id];
        final effectiveFields = (rawFields == null || rawFields.isEmpty)
            ? null
            : rawFields;
        final patchPayload = buildFolderPatchPayload(
          list,
          parentGroupRemoteId: parentGroupRemoteId,
          dirtyFields: effectiveFields,
        );
        if (patchPayload.isEmpty) {
          syncedListIds.add(list.id);
          if (effectiveFields != null) {
            syncedListFields[list.id] = Set<ListDirtyField>.from(
              effectiveFields,
            );
          }
          continue;
        }
        appLog(
          'Phase 5 PATCH list=${list.id} remote=${shortSyncId(list.remoteId)} '
          'keys=${patchPayload.keys.toList()}',
          label: 'SyncEngine',
        );
        final patchResult = await todoApi
            .patchFolder(ctx, list.remoteId!, patchPayload)
            .recover((error) async {
              if (!error.isNotFound || list.isSmartList) {
                return Failure<RemoteTodoFolder, AppError>(error);
              }
              return todoApi.createFolder(
                ctx,
                buildFolderCreatePayload(
                  list,
                  parentGroupRemoteId: parentGroupRemoteId,
                  nowUtc: nowUtc,
                ),
              );
            });
        final remoteFolder = patchResult.getOrThrow();
        workingLists[i] = list.copyWith(
          remoteId: remoteFolder.id,
          orderDateTime: remoteFolder.orderDateTime ?? list.orderDateTime,
          updatedAt: nowUtc,
        );
        syncedListIds.add(list.id);
        if (effectiveFields != null) {
          syncedListFields[list.id] = Set<ListDirtyField>.from(effectiveFields);
        }
      }
    }

    // Phase 6: Delete pending folder groups (after ungrouping member folders).
    final processedDeletedGroupRemoteIds = await _pushPendingDeletions(
      items: repository.loadPendingDeletedGroupRemoteIds(),
      deleteCall: (id) => todoApi.deleteFolderGroup(ctx, id),
      keepQueuedOn: (e) => e.isFolderGroupNotEmpty,
    );

    return MetadataPushResult(
      groups: workingGroups,
      lists: workingLists,
      processedDeletedGroupRemoteIds: processedDeletedGroupRemoteIds,
      processedDeletedListRemoteIds: processedDeletedListRemoteIds,
      processedDeletedTaskRemoteIds: processedDeletedTaskRemoteIds,
      processedDeletedSteps: processedDeletedSteps,
      syncedSettingKeys: syncedSettingKeys,
      syncedGroupIds: syncedGroupIds,
      syncedListIds: syncedListIds,
      syncedGroupFields: syncedGroupFields,
      syncedListFields: syncedListFields,
    );
  }

  /// Executes Phase 10a: push dirty / new tasks and subtasks.
  Future<TaskPushResult> pushTasksAndSteps({
    required SubstrateRequestContext ctx,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required List<String> processedDeletedTaskRemoteIds,
    required Set<String> dirtyTaskIds,
    required Map<String, Set<TaskDirtyField>> dirtyTaskFields,
    required Map<String, Set<String>> dirtyStepIdsByTask,
    required Map<String, String> taskBaseNotes,
    required WeekStart firstDayOfWeek,
    required DateTime nowUtc,
  }) async {
    final resultTasks = [...workingTasks];
    final syncedTaskIds = <String>{};
    final syncedTaskFields = <String, Set<TaskDirtyField>>{};
    final syncedStepIds = <String, Set<String>>{};

    final folderRemoteByLocalId = {
      for (final l in workingLists)
        if (l.remoteId != null) l.id: l.remoteId!,
    };
    for (var i = 0; i < resultTasks.length; i++) {
      final task = resultTasks[i];
      final folderRemoteId = folderRemoteByLocalId[task.listId];
      if (folderRemoteId == null) continue;

      if (task.remoteId != null &&
          processedDeletedTaskRemoteIds.contains(task.remoteId)) {
        syncedTaskIds.add(task.id);
        continue;
      }

      final isCreate = task.remoteId == null;
      if (!isCreate && !dirtyTaskIds.contains(task.id)) continue;

      final rawFields = dirtyTaskFields[task.id];
      final effectiveDirtyFields =
          (isCreate || rawFields == null || rawFields.isEmpty)
          ? null
          : rawFields;
      final payload = buildTaskWritePayload(
        task,
        parentFolderRemoteId: folderRemoteId,
        isCreate: isCreate,
        firstDayOfWeek: firstDayOfWeek,
        dirtyFields: effectiveDirtyFields,
      );

      if (!isCreate && payload.isEmpty) {
        appLog(
          'Phase 10a SKIP task PATCH (steps-only) local=${task.id} '
          'remote=${shortSyncId(task.remoteId)}',
          label: 'SyncEngine',
        );
        final stepOutcome = await _syncStepsForTask(
          ctx: ctx,
          taskRemoteId: task.remoteId!,
          localSteps: task.steps,
          dirtyStepIds: dirtyStepIdsByTask[task.id] ?? const <String>{},
        );
        resultTasks[i] = task.copyWith(
          steps: stepOutcome.steps,
          updatedAt: nowUtc,
        );
        syncedTaskIds.add(task.id);
        if (effectiveDirtyFields != null) {
          syncedTaskFields[task.id] = Set<TaskDirtyField>.from(
            effectiveDirtyFields,
          );
        }
        if (stepOutcome.syncedIds.isNotEmpty) {
          syncedStepIds[task.id] = stepOutcome.syncedIds;
        }
        continue;
      }

      final patchOutcome = isCreate
          ? (
              remoteTask: (await todoApi.createTask(
                ctx,
                folderRemoteId,
                payload,
              )).getOrThrow(),
              mergedNote: null,
              preservedRemoteStatus: false,
            )
          : await _patchTaskWithConflictRetry(
              ctx: ctx,
              task: task,
              payload: payload,
              folderRemoteId: folderRemoteId,
              firstDayOfWeek: firstDayOfWeek,
              dirtyFields: effectiveDirtyFields,
              baseNote: taskBaseNotes[task.id],
            );
      final remoteTask = patchOutcome.remoteTask;
      final wasRecreated = !isCreate && remoteTask.id != task.remoteId;
      final stepsToSync = wasRecreated
          ? [for (final s in task.steps) s.copyWith(remoteId: null)]
          : task.steps;
      final Set<String>? stepDirtyIdsForTask;
      if (wasRecreated || isCreate || effectiveDirtyFields == null) {
        stepDirtyIdsForTask = null;
      } else if (effectiveDirtyFields.contains(TaskDirtyField.steps)) {
        stepDirtyIdsForTask = dirtyStepIdsByTask[task.id] ?? const <String>{};
      } else {
        stepDirtyIdsForTask = const <String>{};
      }
      final stepOutcome = await _syncStepsForTask(
        ctx: ctx,
        taskRemoteId: remoteTask.id,
        localSteps: stepsToSync,
        dirtyStepIds: stepDirtyIdsForTask,
      );
      resultTasks[i] = task.copyWith(
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
        steps: stepOutcome.steps,
        updatedAt: nowUtc,
      );
      syncedTaskIds.add(task.id);
      if (effectiveDirtyFields != null) {
        syncedTaskFields[task.id] = Set<TaskDirtyField>.from(
          effectiveDirtyFields,
        );
      }
      if (stepOutcome.syncedIds.isNotEmpty) {
        syncedStepIds[task.id] = stepOutcome.syncedIds;
      }
      appLog(
        'Phase 10a ${isCreate ? "CREATE" : "PATCH"} local=${task.id} '
        'remote=${shortSyncId(remoteTask.id)} title="${task.title}" '
        'keys=${payload.keys.toList()} '
        'order=${formatSyncTimestamp(task.orderDateTime)} '
        'committedOrder=${formatSyncTimestamp(task.committedOrder)}',
        label: 'SyncEngine',
      );
      if (!isCreate &&
          task.hasRecurrence &&
          payload['Status'] == 'Completed' &&
          !patchOutcome.preservedRemoteStatus) {
        appLog(
          'Phase 10a recurring task completed local=${task.id} '
          'remote=${shortSyncId(remoteTask.id)}; server will spawn next occurrence',
          label: 'SyncEngine',
        );
      }
    }

    return TaskPushResult(
      tasks: resultTasks,
      syncedTaskIds: syncedTaskIds,
      syncedTaskFields: syncedTaskFields,
      syncedStepIds: syncedStepIds,
    );
  }

  Future<List<T>> _pushPendingDeletions<T>({
    required List<T> items,
    required AsyncAppResult<Unit> Function(T item) deleteCall,
    bool Function(AppError e)? treatAsDeletedOn,
    bool Function(AppError e)? keepQueuedOn,
  }) async {
    final processed = <T>[];
    for (final item in items) {
      final result = await deleteCall(item);
      result.fold((_) => processed.add(item), (error) {
        if ((treatAsDeletedOn ?? (err) => err.isNotFound)(error)) {
          processed.add(item);
        } else if (keepQueuedOn != null && keepQueuedOn(error)) {
          // Leave queued for a future sync pass.
        } else {
          throw error;
        }
      });
    }
    return processed;
  }

  Future<
    ({
      RemoteTodoTask remoteTask,
      String? mergedNote,
      bool preservedRemoteStatus,
    })
  >
  _patchTaskWithConflictRetry({
    required SubstrateRequestContext ctx,
    required TaskItem task,
    required Map<String, dynamic> payload,
    required String folderRemoteId,
    required WeekStart firstDayOfWeek,
    required Set<TaskDirtyField>? dirtyFields,
    required String? baseNote,
  }) async {
    String? mergedNote;
    var preservedRemoteStatus = false;

    final result = await todoApi
        .patchTask(ctx, task.remoteId!, payload, changeKey: task.changeKey)
        .recover((error) async {
          if (!error.isConflict) {
            return Failure<RemoteTodoTask, AppError>(error);
          }
          return todoApi.getTask(ctx, task.remoteId!).flatMap((latest) {
            final retryPayload = Map<String, dynamic>.from(payload);

            if (dirtyFields == null ||
                dirtyFields.contains(TaskDirtyField.body)) {
              final resolvedNote = mergeThreeWayNoteText(
                base: baseNote,
                local: task.note,
                remote: latest.plainTextNote,
              );
              mergedNote = resolvedNote;
              retryPayload['Body'] = {
                'Content': resolvedNote,
                'ContentType': 'Text',
              };
              appLog(
                'Phase 10a conflict 3-way note merge local=${task.id} '
                'baseLen=${baseNote?.length} localLen=${task.note.length} '
                'remoteLen=${latest.plainTextNote.length} '
                'mergedLen=${resolvedNote.length}',
                label: 'SyncEngine',
              );
            }

            final statusDirty =
                dirtyFields == null ||
                dirtyFields.contains(TaskDirtyField.status);
            if (statusDirty &&
                task.isCompleted &&
                latest.hasRecurrence &&
                latest.dueDate != null &&
                task.dueDate != null &&
                !_sameCalendarDay(latest.dueDate!, task.dueDate!)) {
              preservedRemoteStatus = true;
              retryPayload['Status'] = latest.status;
              retryPayload['DueDateTime'] = formatDueDateTimeZone(
                latest.dueDate!,
              );
              retryPayload['CompletedDateTime'] =
                  latest.completedDateTime != null
                  ? formatDateTimeTimeZoneUtc(latest.completedDateTime!)
                  : null;
              appLog(
                'Phase 10a conflict recurring task already advanced remotely; '
                'preserving remote status/dueDate local=${task.id}',
                label: 'SyncEngine',
              );
            }

            return todoApi.patchTask(
              ctx,
              task.remoteId!,
              retryPayload,
              changeKey: latest.changeKey,
            );
          });
        })
        .recover((error) async {
          if (!error.isNotFound) {
            return Failure<RemoteTodoTask, AppError>(error);
          }
          final createPayload = buildTaskWritePayload(
            task,
            parentFolderRemoteId: folderRemoteId,
            isCreate: true,
            firstDayOfWeek: firstDayOfWeek,
          );
          return todoApi.createTask(ctx, folderRemoteId, createPayload);
        });
    return (
      remoteTask: result.getOrThrow(),
      mergedNote: mergedNote,
      preservedRemoteStatus: preservedRemoteStatus,
    );
  }

  Future<TaskStep> _createAndSyncStep({
    required SubstrateRequestContext ctx,
    required String taskRemoteId,
    required TaskStep step,
    required DateTime stepOrder,
  }) async {
    final created = (await todoApi.createStep(
      ctx,
      taskRemoteId,
      subject: step.title,
      orderDateTime: stepOrder,
    )).getOrThrow();
    if (step.isCompleted) {
      (await todoApi.patchStep(ctx, taskRemoteId, created.id, const {
        'IsCompleted': true,
      })).getOrThrow();
    }
    return step.copyWith(
      remoteId: created.id,
      orderDateTime: created.orderDateTime ?? stepOrder,
    );
  }

  Future<({List<TaskStep> steps, Set<String> syncedIds})> _syncStepsForTask({
    required SubstrateRequestContext ctx,
    required String taskRemoteId,
    required List<TaskStep> localSteps,
    Set<String>? dirtyStepIds,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final syncedSteps = <TaskStep>[];
    final syncedStepIds = <String>{};
    var createdCount = 0;
    var patchedCount = 0;
    var skippedCount = 0;

    for (var i = 0; i < localSteps.length; i++) {
      final step = localSteps[i];
      final stepOrder =
          step.orderDateTime ??
          nowUtc.subtract(Duration(seconds: i * kOrderDateTimeStep.inSeconds));
      if (step.remoteId == null) {
        createdCount += 1;
        syncedStepIds.add(step.id);
        syncedSteps.add(
          await _createAndSyncStep(
            ctx: ctx,
            taskRemoteId: taskRemoteId,
            step: step,
            stepOrder: stepOrder,
          ),
        );
        continue;
      }
      if (dirtyStepIds != null && !dirtyStepIds.contains(step.id)) {
        skippedCount += 1;
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
        createdCount += 1;
        syncedStepIds.add(step.id);
        syncedSteps.add(
          await _createAndSyncStep(
            ctx: ctx,
            taskRemoteId: taskRemoteId,
            step: step,
            stepOrder: stepOrder,
          ),
        );
        continue;
      }
      final patched = patchResult.getOrThrow();
      patchedCount += 1;
      syncedStepIds.add(step.id);
      syncedSteps.add(
        step.copyWith(
          orderDateTime: patched.orderDateTime ?? step.orderDateTime,
        ),
      );
    }

    if (localSteps.isNotEmpty) {
      appLog(
        'Phase 10a steps remoteTask=${shortSyncId(taskRemoteId)} '
        'created=$createdCount patched=$patchedCount skipped=$skippedCount',
        label: 'SyncEngine',
      );
    }
    return (steps: syncedSteps, syncedIds: syncedStepIds);
  }
}
