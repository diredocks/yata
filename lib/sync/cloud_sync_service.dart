import 'package:result_dart/result_dart.dart';

import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/result/app_result.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../models/account.dart';
import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_api.dart';
import 'substrate_sync_mappers.dart';
import 'sync_guard.dart';
import 'todo_wire_codecs.dart';

/// Result returned by a full 10-phase Substrate sync pass.
class SyncOutcome {
  const SyncOutcome({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.settingsPatch,
    required this.processedDeletedGroupRemoteIds,
    required this.processedDeletedListRemoteIds,
    required this.processedDeletedTaskRemoteIds,
    required this.processedDeletedSteps,
    required this.syncedGroupIds,
    required this.syncedListIds,
    required this.syncedTaskIds,
    required this.syncedSettingKeys,
    required this.syncedAt,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final SyncedSettingsPatch settingsPatch;
  final List<String> processedDeletedGroupRemoteIds;
  final List<String> processedDeletedListRemoteIds;
  final List<String> processedDeletedTaskRemoteIds;
  final List<PendingStepDeletion> processedDeletedSteps;
  final Set<String> syncedGroupIds;
  final Set<String> syncedListIds;
  final Set<String> syncedTaskIds;
  final Set<String> syncedSettingKeys;
  final DateTime syncedAt;
}

class CloudSyncService {
  CloudSyncService({
    required this.authClient,
    required this.todoApi,
    required this.tokenStorage,
  });

  final MicrosoftAuthClient authClient;
  final MicrosoftTodoApi todoApi;
  final AuthTokenStorage tokenStorage;

  /// Resolves valid MSA bearer token, CID, and discovered Substrate base URL.
  AsyncAppResult<SubstrateRequestContext> resolveContext(
    MicrosoftAccount account,
    TodoSettingsStore settings, {
    bool forceRefreshToken = false,
  }) async {
    final AppResult<MicrosoftAuthTokens> tokensResult;
    if (forceRefreshToken) {
      final stored = await tokenStorage.loadTokens(account.id);
      if (stored == null || stored.refreshToken.isEmpty) {
        return const Failure(
          AppError.auth(
            message: 'Refresh token unavailable; please sign in again.',
            code: 'no_refresh_token',
            requiresReauth: true,
          ),
        );
      }
      tokensResult = await authClient.refreshTokens(
        refreshToken: stored.refreshToken,
        fallbackUserId: stored.userId.isNotEmpty
            ? stored.userId
            : account.microsoftUserId,
      );
      if (tokensResult.isSuccess()) {
        await tokenStorage.saveTokens(account.id, tokensResult.getOrThrow());
      }
    } else {
      tokensResult = await authClient.ensureValidTokens(
        accountId: account.id,
        storage: tokenStorage,
        fallbackCid: account.microsoftUserId,
      );
    }

    if (tokensResult.isError()) {
      return Failure(tokensResult.exceptionOrNull()!);
    }
    final tokens = tokensResult.getOrThrow();
    final cid = tokens.userId.isNotEmpty
        ? tokens.userId
        : account.microsoftUserId;
    var baseUrl = settings.loadCachedEndpointUrl();
    if (baseUrl == null) {
      baseUrl = await authClient.discoverTodoEndpoint(cid);
      await settings.saveCachedEndpointUrl(baseUrl);
    }
    return Success(
      SubstrateRequestContext(
        baseUrl: baseUrl,
        accessToken: tokens.accessToken,
        cid: cid,
      ),
    );
  }

  /// Runs all 10 Substrate v1 sync phases for [account] and [currentState].
  AsyncAppResult<SyncOutcome> syncAccount({
    required MicrosoftAccount account,
    required TodoState currentState,
    required TodoRepository repository,
    required TodoSettingsStore settings,
    required String Function(String prefix) idGenerator,
  }) async {
    Future<AppResult<SyncOutcome>> runAttempt({
      required bool forceRefreshToken,
    }) => resolveContext(
      account,
      settings,
      forceRefreshToken: forceRefreshToken,
    ).flatMap(
      (ctx) => guardApiCall(
        () => _executeSyncPhases(
          ctx: ctx,
          currentState: currentState,
          repository: repository,
          settings: settings,
          idGenerator: idGenerator,
        ),
        operation: 'syncPhases',
      ),
    );

    final firstAttempt = await runAttempt(forceRefreshToken: false);
    if (firstAttempt.exceptionOrNull() is! AuthError) {
      return firstAttempt;
    }

    // 401: force a token refresh and retry once.
    final retried = await runAttempt(forceRefreshToken: true);
    return retried.mapError(
      (error) => error is AuthError
          ? AppError.auth(
              message: error.message,
              code: error.code,
              requiresReauth: true,
            )
          : error,
    );
  }

  Future<SyncOutcome> _executeSyncPhases({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required TodoRepository repository,
    required TodoSettingsStore settings,
    required String Function(String prefix) idGenerator,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    var workingGroups = [...currentState.groups];
    var workingLists = [...currentState.lists];
    var workingTasks = [...currentState.tasks];

    final dirtySettingKeys = settings.loadDirtySettingKeys().toSet();
    final dirtyGroupIds = repository.loadDirtyGroupIds().toSet();
    final dirtyListIds = repository.loadDirtyListIds().toSet();
    final dirtyTaskIds = repository.loadDirtyTaskIds().toSet();

    final syncedSettingKeys = <String>{};
    final syncedGroupIds = <String>{};
    final syncedListIds = <String>{};
    final syncedTaskIds = <String>{};

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
      deleteCall: (s) => todoApi.deleteStep(ctx, s.taskRemoteId, s.stepRemoteId),
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
        final patchResult = await todoApi
            .patchFolderGroup(ctx, group.remoteId!, {
              'Name': group.title,
              if (group.orderDateTime != null)
                'OrderDateTime': formatSubstrateUtcTimestamp(
                  group.orderDateTime!,
                ),
            })
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
        final patchResult = await todoApi
            .patchFolder(
              ctx,
              list.remoteId!,
              buildFolderPatchPayload(
                list,
                parentGroupRemoteId: parentGroupRemoteId,
              ),
            )
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
      }
    }

    // Phase 6: Delete pending folder groups (after ungrouping member folders).
    final processedDeletedGroupRemoteIds = await _pushPendingDeletions(
      items: repository.loadPendingDeletedGroupRemoteIds(),
      deleteCall: (id) => todoApi.deleteFolderGroup(ctx, id),
      keepQueuedOn: (e) => e.isFolderGroupNotEmpty,
    );

    // Phase 7: Pull remote settings (skip keys still dirty locally).
    final remainingDirtySettings = dirtySettingKeys.difference(
      syncedSettingKeys,
    );
    final remoteSettings = (await todoApi.getSettings(ctx)).getOrThrow();
    final settingsPatch = buildSyncedSettingsPatchFromWire(
      remoteSettings,
      skipKeys: remainingDirtySettings,
    );

    // Phase 8: Pull folder groups delta (with 410 full-resync recovery).
    final groupsDeltaResult = await _fetchWithDeltaRecovery(
      deltaLink: settings.loadGroupsDeltaLink(),
      clearDeltaLink: () => settings.saveGroupsDeltaLink(null),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    );
    if (groupsDeltaResult.deltaLink != null) {
      await settings.saveGroupsDeltaLink(groupsDeltaResult.deltaLink);
    }
    workingGroups = mergeFolderGroupsDelta(
      localGroups: workingGroups,
      remoteDelta: groupsDeltaResult.items,
      dirtyGroupIds: dirtyGroupIds.difference(syncedGroupIds),
      idGenerator: idGenerator,
    );

    // Phase 9: Pull folders delta (with 410 full-resync recovery).
    final foldersDeltaResult = await _fetchWithDeltaRecovery(
      deltaLink: settings.loadFoldersDeltaLink(),
      clearDeltaLink: () => settings.saveFoldersDeltaLink(null),
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    );
    if (foldersDeltaResult.deltaLink != null) {
      await settings.saveFoldersDeltaLink(foldersDeltaResult.deltaLink);
    }
    final groupLocalIdByRemoteId = {
      for (final g in workingGroups)
        if (g.remoteId != null) g.remoteId!: g.id,
    };
    workingLists = mergeFoldersDelta(
      localLists: workingLists,
      remoteDelta: foldersDeltaResult.items,
      dirtyListIds: dirtyListIds.difference(syncedListIds),
      groupLocalIdByRemoteId: groupLocalIdByRemoteId,
      idGenerator: idGenerator,
    );

    // Remove tasks orphaned by a deleted remote folder.
    final validListIds = {for (final l in workingLists) l.id};
    workingTasks = workingTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();

    // Phase 10a: Push dirty / new tasks & steps.
    final folderRemoteByLocalId = {
      for (final l in workingLists)
        if (l.remoteId != null) l.id: l.remoteId!,
    };
    for (var i = 0; i < workingTasks.length; i++) {
      final task = workingTasks[i];
      final folderRemoteId = folderRemoteByLocalId[task.listId];
      if (folderRemoteId == null) continue;

      if (task.remoteId != null &&
          processedDeletedTaskRemoteIds.contains(task.remoteId)) {
        syncedTaskIds.add(task.id);
        continue;
      }

      final isCreate = task.remoteId == null;
      if (!isCreate && !dirtyTaskIds.contains(task.id)) continue;

      final payload = buildTaskWritePayload(
        task,
        parentFolderRemoteId: folderRemoteId,
        isCreate: isCreate,
        firstDayOfWeek: currentState.startOfWeek,
      );
      final remoteTask = isCreate
          ? (await todoApi.createTask(ctx, folderRemoteId, payload)).getOrThrow()
          : await _patchTaskWithConflictRetry(
              ctx: ctx,
              task: task,
              payload: payload,
              folderRemoteId: folderRemoteId,
              firstDayOfWeek: currentState.startOfWeek,
            );
      final wasRecreated = !isCreate && remoteTask.id != task.remoteId;
      final stepsToSync = wasRecreated
          ? [for (final s in task.steps) s.copyWith(remoteId: null)]
          : task.steps;
      final pushedSteps = await _syncStepsForTask(
        ctx: ctx,
        taskRemoteId: remoteTask.id,
        localSteps: stepsToSync,
      );
      workingTasks[i] = task.copyWith(
        remoteId: remoteTask.id,
        remoteParentFolderId: remoteTask.parentFolderId ?? folderRemoteId,
        changeKey: remoteTask.changeKey ?? task.changeKey,
        orderDateTime: remoteTask.orderDateTime ?? task.orderDateTime,
        committedOrder: remoteTask.committedOrder ?? task.committedOrder,
        steps: pushedSteps,
        updatedAt: nowUtc,
      );
      syncedTaskIds.add(task.id);
    }

    // Phase 10b: Pull per-folder tasks delta (with 410 recovery + move safety).
    final mergedTasks = await _pullAndMergeTasksDelta(
      ctx: ctx,
      settings: settings,
      workingLists: workingLists,
      workingTasks: workingTasks,
      remainingDirtyTasks: dirtyTaskIds.difference(syncedTaskIds),
      idGenerator: idGenerator,
    );

    return SyncOutcome(
      groups: workingGroups,
      lists: workingLists,
      tasks: mergedTasks,
      settingsPatch: settingsPatch,
      processedDeletedGroupRemoteIds: processedDeletedGroupRemoteIds,
      processedDeletedListRemoteIds: processedDeletedListRemoteIds,
      processedDeletedTaskRemoteIds: processedDeletedTaskRemoteIds,
      processedDeletedSteps: processedDeletedSteps,
      syncedGroupIds: syncedGroupIds,
      syncedListIds: syncedListIds,
      syncedTaskIds: syncedTaskIds,
      syncedSettingKeys: syncedSettingKeys,
      syncedAt: DateTime.now(),
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
      result.fold(
        (_) => processed.add(item),
        (error) {
          if ((treatAsDeletedOn ?? (err) => err.isNotFound)(error)) {
            processed.add(item);
          } else if (keepQueuedOn != null && keepQueuedOn(error)) {
            // Leave queued for a future sync pass.
          } else {
            throw error;
          }
        },
      );
    }
    return processed;
  }

  Future<List<TaskItem>> _pullAndMergeTasksDelta({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required Set<String> remainingDirtyTasks,
    required String Function(String prefix) idGenerator,
  }) async {
    final taskDeltaLinks = Map<String, String>.from(
      settings.loadTaskDeltaLinks(),
    );
    final localListIdByFolderRemoteId = {
      for (final l in workingLists)
        if (l.remoteId != null) l.remoteId!: l.id,
    };

    final seenActiveRemoteTaskIds = <String>{};
    final deferredDeletesByFolder = <String, Set<String>>{};
    final ignoredRemoteIds = <String>{};
    final tasksById = {for (final t in workingTasks) t.id: t};
    final taskIdByRemoteId = <String, String>{
      for (final t in workingTasks)
        if (t.remoteId != null) t.remoteId!: t.id,
    };

    for (final entry in localListIdByFolderRemoteId.entries) {
      final folderRemoteId = entry.key;
      final localListId = entry.value;

      final taskDeltaResult = await _fetchWithDeltaRecovery(
        deltaLink: taskDeltaLinks[folderRemoteId],
        clearDeltaLink: () async {
          taskDeltaLinks.remove(folderRemoteId);
          await settings.saveTaskDeltaLinks(taskDeltaLinks);
        },
        fetch: (dl) => todoApi.fetchTasksDelta(
          ctx,
          folderRemoteId: folderRemoteId,
          deltaLink: dl,
        ),
      );
      if (taskDeltaResult.deltaLink != null) {
        taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
      }

      for (final remote in taskDeltaResult.items) {
        if (remote.isIgnored) {
          ignoredRemoteIds.add(remote.id);
          continue;
        }
        if (remote.isDeleted) {
          (deferredDeletesByFolder[remote.id] ??= <String>{}).add(localListId);
          continue;
        }
        seenActiveRemoteTaskIds.add(remote.id);

        final resolvedListId =
            (remote.parentFolderId != null
                ? localListIdByFolderRemoteId[remote.parentFolderId!]
                : null) ??
            localListId;

        final existingId = taskIdByRemoteId[remote.id];
        final existing = existingId != null ? tasksById[existingId] : null;
        if (existing != null) {
          tasksById[existing.id] = remainingDirtyTasks.contains(existing.id)
              ? existing.copyWith(
                  changeKey: remote.changeKey ?? existing.changeKey,
                )
              : taskFromRemote(
                  remote,
                  localId: existing.id,
                  listId: resolvedListId,
                  existingSteps: existing.steps,
                  idGenerator: idGenerator,
                );
        } else {
          final newLocalId = idGenerator('task');
          tasksById[newLocalId] = taskFromRemote(
            remote,
            localId: newLocalId,
            listId: resolvedListId,
            existingSteps: const [],
            idGenerator: idGenerator,
          );
          taskIdByRemoteId[remote.id] = newLocalId;
        }
      }
    }

    // Apply ignored removals unconditionally (for non-dirty tasks).
    for (final ignoredRemoteId in ignoredRemoteIds) {
      final localId = taskIdByRemoteId[ignoredRemoteId];
      if (localId == null || remainingDirtyTasks.contains(localId)) continue;
      tasksById.remove(localId);
    }

    // Apply deferred deletions ONLY if task was not returned active elsewhere
    // AND the local task still belongs to the folder whose delta reported deletion.
    for (final entry in deferredDeletesByFolder.entries) {
      final deletedRemoteId = entry.key;
      final deletedFromListIds = entry.value;
      if (seenActiveRemoteTaskIds.contains(deletedRemoteId)) continue;
      final localId = taskIdByRemoteId[deletedRemoteId];
      if (localId == null || remainingDirtyTasks.contains(localId)) continue;
      final localTask = tasksById[localId];
      if (localTask == null || !deletedFromListIds.contains(localTask.listId)) {
        continue;
      }
      tasksById.remove(localId);
    }

    await settings.saveTaskDeltaLinks(taskDeltaLinks);
    return tasksById.values.toList();
  }

  Future<DeltaPageResult<T>> _fetchWithDeltaRecovery<T>({
    required String? deltaLink,
    required Future<void> Function() clearDeltaLink,
    required AsyncAppResult<DeltaPageResult<T>> Function(String? deltaLink)
    fetch,
  }) async {
    final result = await fetch(deltaLink).recover((error) async {
      if (!error.isDeltaExpired || deltaLink == null) {
        return Failure<DeltaPageResult<T>, AppError>(error);
      }
      await clearDeltaLink();
      return fetch(null);
    });
    return result.getOrThrow();
  }

  Future<RemoteTodoTask> _patchTaskWithConflictRetry({
    required SubstrateRequestContext ctx,
    required TaskItem task,
    required Map<String, dynamic> payload,
    required String folderRemoteId,
    required WeekStart firstDayOfWeek,
  }) async {
    final result = await todoApi
        .patchTask(ctx, task.remoteId!, payload, changeKey: task.changeKey)
        .recover((error) async {
          if (!error.isConflict) {
            return Failure<RemoteTodoTask, AppError>(error);
          }
          return todoApi
              .getTask(ctx, task.remoteId!)
              .flatMap(
                (latest) => todoApi.patchTask(
                  ctx,
                  task.remoteId!,
                  payload,
                  changeKey: latest.changeKey,
                ),
              );
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
    return result.getOrThrow();
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

  Future<List<TaskStep>> _syncStepsForTask({
    required SubstrateRequestContext ctx,
    required String taskRemoteId,
    required List<TaskStep> localSteps,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final syncedSteps = <TaskStep>[];
    for (var i = 0; i < localSteps.length; i++) {
      final step = localSteps[i];
      final stepOrder =
          step.orderDateTime ??
          nowUtc.subtract(
            Duration(seconds: i * kOrderDateTimeStep.inSeconds),
          );
      if (step.remoteId == null) {
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
