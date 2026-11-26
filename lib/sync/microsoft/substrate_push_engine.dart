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
import 'microsoft_todo_api.dart';
import 'substrate_sync_mappers.dart';
import '../sync_concurrency.dart';
import '../sync_guard.dart';
import '../sync_log_format.dart';
import '../text_merge.dart';
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
  if (!hasOrderChange) return false;
  if (dirtyFields.contains(TaskDirtyField.body)) return false;
  return !(dirtyFields.contains(TaskDirtyField.status) && isCompleted);
}

/// Pushes ordered [SyncOutboxOp] batches to Substrate To Do v1.
class SubstratePushEngine {
  const SubstratePushEngine(this.todoApi);

  static const int _maxConcurrentTaskPushes = 4;

  final MicrosoftTodoApi todoApi;

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Drains the current Outbox batch in dependency order:
  /// settings -> step/task/folder deletions -> groups -> folders ->
  /// group deletions -> tasks/steps.
  AsyncAppResult<OutboxPushOutcome> pushOutbox({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required SyncOutboxQueue outbox,
    required DateTime nowUtc,
    TodoState Function()? readLatestState,
    Future<void> Function(OutboxPushOutcome itemOutcome)? onItemCommitted,
  }) async {
    final batch = outbox.beginBatch();
    try {
      if (batch.isEmpty) {
        return const Success(
          OutboxPushOutcome(
            ackedSeqs: [],
            pushedGroups: {},
            pushedLists: {},
            pushedTasks: {},
            clearedRemoteIdKeys: [],
            followUpPullFolderRemoteIds: {},
          ),
        );
      }

      final ackedSeqs = <int>[];
      final clearedRemoteIdKeys = <({SyncEntityType type, String localId})>[];
      final pushedGroups = <String, ListGroup>{};
      final pushedLists = <String, TodoList>{};
      final pushedTasks = <String, TaskItem>{};
      final followUpPullFolderRemoteIds = <String>{};
      final deletedGroupRemoteIds = <String>{};
      final deletedListRemoteIds = <String>{};
      final deletedTaskRemoteIds = <String>{};

      Future<void> commitOp({
        required int seq,
        ListGroup? group,
        TodoList? list,
        TaskItem? task,
        ({SyncEntityType type, String localId})? clearedRemoteIdKey,
        String? followUpFolderRemoteId,
      }) async {
        ackedSeqs.add(seq);
        if (group != null) pushedGroups[group.id] = group;
        if (list != null) pushedLists[list.id] = list;
        if (task != null) pushedTasks[task.id] = task;
        if (clearedRemoteIdKey != null) {
          clearedRemoteIdKeys.add(clearedRemoteIdKey);
        }
        if (followUpFolderRemoteId != null) {
          followUpPullFolderRemoteIds.add(followUpFolderRemoteId);
        }
        if (onItemCommitted != null) {
          await onItemCommitted(
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
      }

      ListGroup? findLiveGroup(String id) {
        final latest = readLatestState?.call();
        if (latest != null) {
          for (final g in latest.groups) {
            if (g.id == id) return pushedGroups[id] ?? g;
          }
          return null;
        }
        return pushedGroups[id] ??
            currentState.groups.where((g) => g.id == id).firstOrNull;
      }

      TodoList? findLiveList(String id) {
        final latest = readLatestState?.call();
        if (latest != null) {
          for (final l in latest.lists) {
            if (l.id == id) return pushedLists[id] ?? l;
          }
          return null;
        }
        return pushedLists[id] ??
            currentState.lists.where((l) => l.id == id).firstOrNull;
      }

      TaskItem? findLiveTask(String id) {
        final latest = readLatestState?.call();
        if (latest != null) {
          for (final t in latest.tasks) {
            if (t.id == id) return pushedTasks[id] ?? t;
          }
          return null;
        }
        return pushedTasks[id] ??
            currentState.tasks.where((t) => t.id == id).firstOrNull;
      }

      return await guardApiCall(() async {
        // 1. Settings
        for (final op in batch) {
          if (op.entityType != SyncEntityType.setting) continue;
          final latestState = readLatestState?.call() ?? currentState;
          final wireValue = extractSettingValueForKey(latestState, op.localId);
          if (wireValue != null) {
            (await todoApi.patchSetting(
              ctx,
              op.localId,
              wireValue,
            )).getOrThrow();
          }
          await commitOp(seq: op.seq);
        }

        // 2. Step, Task, and Folder deletions
        for (final op in batch) {
          if (op.kind != SyncOpKind.delete) continue;
          if (op.entityType == SyncEntityType.step) {
            final taskRemoteId =
                op.parentRemoteId ??
                (op.parentLocalId != null
                    ? outbox.resolveRemoteId(
                        SyncEntityType.task,
                        op.parentLocalId!,
                      )
                    : null);
            final stepRemoteId =
                op.remoteId ??
                outbox.resolveRemoteId(SyncEntityType.step, op.localId);
            if (taskRemoteId != null && stepRemoteId != null) {
              await _deleteOne(
                () => todoApi.deleteStep(ctx, taskRemoteId, stepRemoteId),
              );
            }
            await commitOp(
              seq: op.seq,
              clearedRemoteIdKey: (
                type: SyncEntityType.step,
                localId: op.localId,
              ),
            );
          } else if (op.entityType == SyncEntityType.task) {
            final remoteId =
                op.remoteId ??
                outbox.resolveRemoteId(SyncEntityType.task, op.localId);
            if (remoteId != null) {
              deletedTaskRemoteIds.add(remoteId);
              await _deleteOne(() => todoApi.deleteTask(ctx, remoteId));
            }
            await commitOp(
              seq: op.seq,
              clearedRemoteIdKey: (
                type: SyncEntityType.task,
                localId: op.localId,
              ),
            );
          } else if (op.entityType == SyncEntityType.list) {
            final remoteId =
                op.remoteId ??
                outbox.resolveRemoteId(SyncEntityType.list, op.localId);
            if (remoteId != null) {
              deletedListRemoteIds.add(remoteId);
              await _deleteOne(
                () => todoApi.deleteFolder(ctx, remoteId),
                treatAsDeletedOn: (e) =>
                    e.isNotFound || e.isCantDeleteDefaultFolder,
              );
            }
            await commitOp(
              seq: op.seq,
              clearedRemoteIdKey: (
                type: SyncEntityType.list,
                localId: op.localId,
              ),
            );
          }
        }

        // 3. Folder group upserts
        for (final op in batch) {
          if (op.entityType != SyncEntityType.group ||
              op.kind != SyncOpKind.upsert) {
            continue;
          }
          final rawGroup = findLiveGroup(op.localId);
          final resolvedGroupRemoteId =
              rawGroup?.remoteId ??
              outbox.resolveRemoteId(SyncEntityType.group, op.localId);
          final group =
              rawGroup != null &&
                  rawGroup.remoteId == null &&
                  resolvedGroupRemoteId != null
              ? rawGroup.copyWith(remoteId: resolvedGroupRemoteId)
              : rawGroup;
          if (group == null ||
              (group.remoteId != null &&
                  deletedGroupRemoteIds.contains(group.remoteId))) {
            await commitOp(seq: op.seq);
            continue;
          }
          if (group.remoteId == null) {
            final created = (await todoApi.createFolderGroup(
              ctx,
              name: group.title,
              orderDateTime: group.orderDateTime ?? nowUtc,
            )).getOrThrow();
            outbox.recordRemoteId(SyncEntityType.group, group.id, created.id);
            await commitOp(
              seq: op.seq,
              group: group.copyWith(
                remoteId: created.id,
                orderDateTime: created.orderDateTime ?? group.orderDateTime,
                updatedAt: nowUtc,
              ),
            );
          } else {
            final dirtyFields = _decodeEnumFields(
              op.fields,
              GroupDirtyField.values,
            );
            final patchPayload = buildGroupPatchPayload(
              group,
              dirtyFields: dirtyFields,
            );
            if (patchPayload.isEmpty) {
              await commitOp(seq: op.seq, group: group);
              continue;
            }
            _log.fine(
              'Phase 4 PATCH group=${group.id} remote=${shortSyncId(group.remoteId)} '
              'keys=${patchPayload.keys.toList()}',
            );
            final remoteGroup =
                (await todoApi
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
                        }))
                    .getOrThrow();
            outbox.recordRemoteId(
              SyncEntityType.group,
              group.id,
              remoteGroup.id,
            );
            await commitOp(
              seq: op.seq,
              group: group.copyWith(
                remoteId: remoteGroup.id,
                title: remoteGroup.name.isNotEmpty
                    ? remoteGroup.name
                    : group.title,
                orderDateTime: remoteGroup.orderDateTime ?? group.orderDateTime,
                updatedAt: nowUtc,
              ),
            );
          }
        }

        String? resolveGroupRemoteId(String? groupId) {
          if (groupId == null) return null;
          return findLiveGroup(groupId)?.remoteId ??
              outbox.resolveRemoteId(SyncEntityType.group, groupId);
        }

        // 4. Folder upserts (BEFORE deleting folder groups to prevent 9018)
        for (final op in batch) {
          if (op.entityType != SyncEntityType.list ||
              op.kind != SyncOpKind.upsert) {
            continue;
          }
          final rawList = findLiveList(op.localId);
          final resolvedListRemoteId =
              rawList?.remoteId ??
              outbox.resolveRemoteId(SyncEntityType.list, op.localId);
          final list =
              rawList != null &&
                  rawList.remoteId == null &&
                  resolvedListRemoteId != null
              ? rawList.copyWith(remoteId: resolvedListRemoteId)
              : rawList;
          if (list == null ||
              (list.remoteId != null &&
                  deletedListRemoteIds.contains(list.remoteId)) ||
              (list.isSmartList && list.smartType != SmartListType.tasks)) {
            await commitOp(seq: op.seq);
            continue;
          }
          final parentGroupRemoteId = resolveGroupRemoteId(list.groupId);
          if (!list.isSmartList && list.remoteId == null) {
            final created = (await todoApi.createFolder(
              ctx,
              buildFolderCreatePayload(
                list,
                parentGroupRemoteId: parentGroupRemoteId,
                nowUtc: nowUtc,
              ),
            )).getOrThrow();
            outbox.recordRemoteId(SyncEntityType.list, list.id, created.id);
            await commitOp(
              seq: op.seq,
              list: list.copyWith(
                remoteId: created.id,
                orderDateTime: created.orderDateTime ?? list.orderDateTime,
                updatedAt: nowUtc,
              ),
            );
          } else if (list.remoteId != null) {
            final dirtyFields = _decodeEnumFields(
              op.fields,
              ListDirtyField.values,
            );
            final patchPayload = buildFolderPatchPayload(
              list,
              parentGroupRemoteId: parentGroupRemoteId,
              dirtyFields: dirtyFields,
            );
            if (patchPayload.isEmpty) {
              await commitOp(seq: op.seq, list: list);
              continue;
            }
            _log.fine(
              'Phase 5 PATCH folder=${list.id} remote=${shortSyncId(list.remoteId)} '
              'keys=${patchPayload.keys.toList()}',
            );
            final remoteFolder =
                (await todoApi
                        .patchFolder(ctx, list.remoteId!, patchPayload)
                        .recover((error) async {
                          if (!error.isNotFound) {
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
                        }))
                    .getOrThrow();
            outbox.recordRemoteId(
              SyncEntityType.list,
              list.id,
              remoteFolder.id,
            );
            await commitOp(
              seq: op.seq,
              list: list.copyWith(
                remoteId: remoteFolder.id,
                title: list.title,
                orderDateTime: remoteFolder.orderDateTime ?? list.orderDateTime,
                updatedAt: nowUtc,
              ),
            );
          } else {
            await commitOp(seq: op.seq);
          }
        }

        // 5. Folder group deletions
        for (final op in batch) {
          if (op.entityType != SyncEntityType.group ||
              op.kind != SyncOpKind.delete) {
            continue;
          }
          final remoteId =
              op.remoteId ??
              outbox.resolveRemoteId(SyncEntityType.group, op.localId);
          if (remoteId != null) {
            await _deleteOne(() => todoApi.deleteFolderGroup(ctx, remoteId));
          }
          await commitOp(
            seq: op.seq,
            clearedRemoteIdKey: (
              type: SyncEntityType.group,
              localId: op.localId,
            ),
          );
        }

        // 6. Task & step upserts (bounded concurrency across distinct tasks)
        String? resolveLiveListRemoteId(String listId) {
          final liveList = findLiveList(listId);
          if (liveList == null) return null;
          return liveList.remoteId ??
              outbox.resolveRemoteId(SyncEntityType.list, listId);
        }

        final taskOpsByLocalId = <String, List<SyncOutboxOp>>{};
        for (final op in batch) {
          if (op.entityType != SyncEntityType.task ||
              op.kind != SyncOpKind.upsert) {
            continue;
          }
          (taskOpsByLocalId[op.localId] ??= <SyncOutboxOp>[]).add(op);
        }

        Future<void> pushSingleTaskOp(SyncOutboxOp op) async {
          final rawTask = findLiveTask(op.localId);
          final resolvedTaskRemoteId =
              rawTask?.remoteId ??
              outbox.resolveRemoteId(SyncEntityType.task, op.localId);
          final task =
              rawTask != null &&
                  rawTask.remoteId == null &&
                  resolvedTaskRemoteId != null
              ? rawTask.copyWith(remoteId: resolvedTaskRemoteId)
              : rawTask;
          if (task == null ||
              (task.remoteId != null &&
                  deletedTaskRemoteIds.contains(task.remoteId))) {
            await commitOp(seq: op.seq);
            return;
          }
          final folderRemoteId = resolveLiveListRemoteId(task.listId);
          if (folderRemoteId == null) {
            if (findLiveList(task.listId) == null) {
              // Parent list was deleted locally while push was in flight.
              await commitOp(seq: op.seq);
            }
            return;
          }

          final isCreate = task.remoteId == null;
          final dirtyFields = isCreate
              ? null
              : _decodeEnumFields(op.fields, TaskDirtyField.values);
          final payload = buildTaskWritePayload(
            task,
            parentFolderRemoteId: folderRemoteId,
            isCreate: isCreate,
            firstDayOfWeek: currentState.startOfWeek,
            dirtyFields: dirtyFields,
          );

          if (!isCreate && payload.isEmpty) {
            _log.fine(
              'Phase 10a SKIP task PATCH (steps-only) local=${task.id} '
              'remote=${shortSyncId(task.remoteId)}',
            );
            final syncedSteps = await _syncStepsForTask(
              ctx: ctx,
              outbox: outbox,
              taskRemoteId: task.remoteId!,
              localSteps: task.steps,
              dirtyStepIds: op.stepIds,
            );
            await commitOp(
              seq: op.seq,
              task: task.copyWith(steps: syncedSteps, updatedAt: nowUtc),
            );
            return;
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
                  firstDayOfWeek: currentState.startOfWeek,
                  dirtyFields: dirtyFields,
                  baseNote: op.baseNote,
                );
          final remoteTask = patchOutcome.remoteTask;
          outbox.recordRemoteId(SyncEntityType.task, task.id, remoteTask.id);
          final wasRecreated = !isCreate && remoteTask.id != task.remoteId;
          final stepsToSync = wasRecreated
              ? [for (final s in task.steps) s.copyWith(remoteId: null)]
              : task.steps;
          final Set<String>? stepDirtyIdsForTask;
          if (wasRecreated || isCreate || dirtyFields == null) {
            stepDirtyIdsForTask = null;
          } else if (dirtyFields.contains(TaskDirtyField.steps)) {
            stepDirtyIdsForTask = op.stepIds;
          } else {
            stepDirtyIdsForTask = const <String>{};
          }
          final syncedSteps = await _syncStepsForTask(
            ctx: ctx,
            outbox: outbox,
            taskRemoteId: remoteTask.id,
            localSteps: stepsToSync,
            dirtyStepIds: stepDirtyIdsForTask,
          );
          final needsFollowUpPull =
              isCreate ||
              !isReorderOnlyTaskPatch(
                dirtyFields,
                isCompleted: task.isCompleted,
              );
          await commitOp(
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
              steps: syncedSteps,
              updatedAt: nowUtc,
            ),
            followUpFolderRemoteId: needsFollowUpPull ? folderRemoteId : null,
          );
          _log.fine(
            'Phase 10a ${isCreate ? "CREATE" : "PATCH"} local=${task.id} '
            'remote=${shortSyncId(remoteTask.id)} title="${task.title}" '
            'keys=${payload.keys.toList()}',
          );
        }

        await runWithConcurrency(
          taskOpsByLocalId.values.toList(),
          _maxConcurrentTaskPushes,
          (opsForTask) async {
            for (final op in opsForTask) {
              await pushSingleTaskOp(op);
            }
          },
        );

        return OutboxPushOutcome(
          ackedSeqs: ackedSeqs,
          pushedGroups: pushedGroups,
          pushedLists: pushedLists,
          pushedTasks: pushedTasks,
          clearedRemoteIdKeys: clearedRemoteIdKeys,
          followUpPullFolderRemoteIds: followUpPullFolderRemoteIds,
        );
      }, operation: 'pushOutbox');
    } finally {
      outbox.endBatch();
    }
  }

  Set<T>? _decodeEnumFields<T extends Enum>(
    Set<String> rawFields,
    List<T> values,
  ) {
    if (rawFields.isEmpty) return null;
    final byName = {for (final v in values) v.name: v};
    final result = <T>{};
    for (final name in rawFields) {
      final match = byName[name];
      if (match != null) result.add(match);
    }
    return result.isEmpty ? null : result;
  }

  Future<void> _deleteOne(
    AsyncAppResult<Unit> Function() deleteCall, {
    bool Function(AppError e)? treatAsDeletedOn,
  }) async {
    final result = await deleteCall();
    result.fold((_) {}, (error) {
      if ((treatAsDeletedOn ?? (err) => err.isNotFound)(error)) {
        return;
      }
      throw error;
    });
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
    final isReorderOnlyPatch = isReorderOnlyTaskPatch(
      dirtyFields,
      isCompleted: task.isCompleted,
    );
    final effectiveChangeKey = isReorderOnlyPatch ? null : task.changeKey;

    final result = await todoApi
        .patchTask(ctx, task.remoteId!, payload, changeKey: effectiveChangeKey)
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
    required SyncOutboxQueue outbox,
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
    outbox.recordRemoteId(SyncEntityType.step, step.id, created.id);
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

  Future<List<TaskStep>> _syncStepsForTask({
    required SubstrateRequestContext ctx,
    required SyncOutboxQueue outbox,
    required String taskRemoteId,
    required List<TaskStep> localSteps,
    Set<String>? dirtyStepIds,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final syncedSteps = <TaskStep>[];

    for (var i = 0; i < localSteps.length; i++) {
      final rawStep = localSteps[i];
      final resolvedStepRemoteId =
          rawStep.remoteId ??
          outbox.resolveRemoteId(SyncEntityType.step, rawStep.id);
      final step = rawStep.remoteId == null && resolvedStepRemoteId != null
          ? rawStep.copyWith(remoteId: resolvedStepRemoteId)
          : rawStep;
      final stepOrder =
          step.orderDateTime ??
          nowUtc.subtract(Duration(seconds: i * kOrderDateTimeStep.inSeconds));
      if (step.remoteId == null) {
        syncedSteps.add(
          await _createAndSyncStep(
            ctx: ctx,
            outbox: outbox,
            taskRemoteId: taskRemoteId,
            step: step,
            stepOrder: stepOrder,
          ),
        );
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
        syncedSteps.add(
          await _createAndSyncStep(
            ctx: ctx,
            outbox: outbox,
            taskRemoteId: taskRemoteId,
            step: step,
            stepOrder: stepOrder,
          ),
        );
        continue;
      }
      final patched = patchResult.getOrThrow();
      syncedSteps.add(
        step.copyWith(
          orderDateTime: patched.orderDateTime ?? step.orderDateTime,
        ),
      );
    }

    return syncedSteps;
  }
}
