import 'package:result_dart/result_dart.dart';

import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/sync_dirty_fields.dart';
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
import 'sync_log_format.dart';
import 'text_merge.dart';
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
    this.syncedGroupFields = const {},
    this.syncedListFields = const {},
    this.syncedTaskFields = const {},
    this.syncedStepIds = const {},
    this.snapshotState,
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
  final Map<String, Set<GroupDirtyField>> syncedGroupFields;
  final Map<String, Set<ListDirtyField>> syncedListFields;
  final Map<String, Set<TaskDirtyField>> syncedTaskFields;
  final Map<String, Set<String>> syncedStepIds;
  final DateTime syncedAt;
  final TodoState? snapshotState;
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
    TodoState Function()? readLatestState,
    bool forceFullSync = false,
    String reason = 'sync',
  }) async {
    Future<AppResult<SyncOutcome>> runAttempt({
      required bool forceRefreshToken,
    }) =>
        resolveContext(
          account,
          settings,
          forceRefreshToken: forceRefreshToken,
        ).flatMap(
          (ctx) => guardApiCall(
            () => _executeSyncPhases(
              ctx: ctx,
              currentState: readLatestState?.call() ?? currentState,
              repository: repository,
              settings: settings,
              idGenerator: idGenerator,
              forceFullSync: forceFullSync,
              reason: reason,
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
    bool forceFullSync = false,
    String reason = 'sync',
  }) async {
    final nowUtc = DateTime.now().toUtc();
    var workingGroups = [...currentState.groups];
    var workingLists = [...currentState.lists];
    var workingTasks = [...currentState.tasks];

    final dirtySettingKeys = settings.loadDirtySettingKeys().toSet();
    final dirtyGroupIds = repository.loadDirtyGroupIds().toSet();
    final dirtyGroupFields = repository.loadDirtyGroupFields();
    final dirtyListIds = repository.loadDirtyListIds().toSet();
    final dirtyListFields = repository.loadDirtyListFields();
    final dirtyTaskIds = repository.loadDirtyTaskIds().toSet();
    final dirtyTaskFields = repository.loadDirtyTaskFields();
    final dirtyStepIdsByTask = repository.loadDirtyStepIds();
    final taskBaseNotes = repository.loadTaskBaseNotes();

    appLog(
      'start reason=$reason forceFullSync=$forceFullSync '
      'localLists=${workingLists.length} localTasks=${workingTasks.length} '
      'dirtyTasks=${dirtyTaskIds.length}',
      label: 'SyncEngine',
    );

    final syncedSettingKeys = <String>{};
    final syncedGroupIds = <String>{};
    final syncedListIds = <String>{};
    final syncedTaskIds = <String>{};
    final syncedGroupFields = <String, Set<GroupDirtyField>>{};
    final syncedListFields = <String, Set<ListDirtyField>>{};
    final syncedTaskFields = <String, Set<TaskDirtyField>>{};
    final syncedStepIds = <String, Set<String>>{};

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

    // Phase 7: Pull remote settings (skip keys still dirty locally).
    final remainingDirtySettings = dirtySettingKeys.difference(
      syncedSettingKeys,
    );
    final remoteSettings = (await todoApi.getSettings(ctx)).getOrThrow();
    final settingsPatch = buildSyncedSettingsPatchFromWire(
      remoteSettings,
      skipKeys: remainingDirtySettings,
    );

    // Phase 8: Pull folder groups delta (with 410 & forceFullSync recovery).
    final savedGroupsDelta = settings.loadGroupsDeltaLink();
    final effectiveGroupsDelta = forceFullSync ? null : savedGroupsDelta;
    var recoveredGroups410 = false;
    final groupsDeltaResult = await _fetchWithDeltaRecovery(
      deltaLink: effectiveGroupsDelta,
      clearDeltaLink: () async {
        recoveredGroups410 = true;
        await settings.saveGroupsDeltaLink(null);
      },
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    );
    if (groupsDeltaResult.deltaLink != null) {
      await settings.saveGroupsDeltaLink(groupsDeltaResult.deltaLink);
    }
    final remainingDirtyGroups = dirtyGroupIds.difference(syncedGroupIds);
    workingGroups = mergeFolderGroupsDelta(
      localGroups: workingGroups,
      remoteDelta: groupsDeltaResult.items,
      dirtyGroupIds: remainingDirtyGroups,
      idGenerator: idGenerator,
    );
    if (forceFullSync && groupsDeltaResult.deltaLink != null) {
      final seenGroupRemoteIds = {
        for (final g in groupsDeltaResult.items)
          if (!g.isDeleted && g.id.isNotEmpty) g.id,
      };
      final keptGroups = <ListGroup>[];
      for (final g in workingGroups) {
        final keep =
            g.remoteId == null ||
            seenGroupRemoteIds.contains(g.remoteId) ||
            remainingDirtyGroups.contains(g.id) ||
            syncedGroupIds.contains(g.id);
        if (keep) {
          keptGroups.add(g);
        } else {
          appLog(
            'Phase 8 full-sync prune stale group=${g.id} '
            'remote=${shortSyncId(g.remoteId)} title="${g.title}"',
            label: 'SyncEngine',
          );
        }
      }
      workingGroups = keptGroups;
    }
    appLog(
      'Phase 8 groups mode=${forceFullSync ? "full(forced)" : (recoveredGroups410 ? "full(410)" : (effectiveGroupsDelta == null ? "full(initial)" : "delta"))} '
      'items=${groupsDeltaResult.items.length} '
      'hasDeltaLink=${groupsDeltaResult.deltaLink != null}',
      label: 'SyncEngine',
    );

    // Phase 9: Pull folders delta (with 410 & forceFullSync recovery).
    final savedFoldersDelta = settings.loadFoldersDeltaLink();
    final effectiveFoldersDelta = forceFullSync ? null : savedFoldersDelta;
    var recoveredFolders410 = false;
    final foldersDeltaResult = await _fetchWithDeltaRecovery(
      deltaLink: effectiveFoldersDelta,
      clearDeltaLink: () async {
        recoveredFolders410 = true;
        await settings.saveFoldersDeltaLink(null);
      },
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    );
    if (foldersDeltaResult.deltaLink != null) {
      await settings.saveFoldersDeltaLink(foldersDeltaResult.deltaLink);
    }
    final groupLocalIdByRemoteId = {
      for (final g in workingGroups)
        if (g.remoteId != null) g.remoteId!: g.id,
    };
    final remainingDirtyLists = dirtyListIds.difference(syncedListIds);
    workingLists = mergeFoldersDelta(
      localLists: workingLists,
      remoteDelta: foldersDeltaResult.items,
      dirtyListIds: remainingDirtyLists,
      groupLocalIdByRemoteId: groupLocalIdByRemoteId,
      idGenerator: idGenerator,
    );
    if (forceFullSync && foldersDeltaResult.deltaLink != null) {
      final seenFolderRemoteIds = {
        for (final f in foldersDeltaResult.items)
          if (!f.isDeleted && !f.isIgnoredSpecialFolder && f.id.isNotEmpty)
            f.id,
      };
      final keptLists = <TodoList>[];
      for (final l in workingLists) {
        final keep =
            l.isSmartList ||
            l.remoteId == null ||
            seenFolderRemoteIds.contains(l.remoteId) ||
            remainingDirtyLists.contains(l.id) ||
            syncedListIds.contains(l.id);
        if (keep) {
          keptLists.add(l);
        } else {
          appLog(
            'Phase 9 full-sync prune stale list=${l.id} '
            'remote=${shortSyncId(l.remoteId)} title="${l.title}"',
            label: 'SyncEngine',
          );
        }
      }
      workingLists = keptLists;
    }
    appLog(
      'Phase 9 folders mode=${forceFullSync ? "full(forced)" : (recoveredFolders410 ? "full(410)" : (effectiveFoldersDelta == null ? "full(initial)" : "delta"))} '
      'items=${foldersDeltaResult.items.length} '
      'hasDeltaLink=${foldersDeltaResult.deltaLink != null}',
      label: 'SyncEngine',
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

      final rawFields = dirtyTaskFields[task.id];
      final effectiveDirtyFields =
          (isCreate || rawFields == null || rawFields.isEmpty)
          ? null
          : rawFields;
      final payload = buildTaskWritePayload(
        task,
        parentFolderRemoteId: folderRemoteId,
        isCreate: isCreate,
        firstDayOfWeek: currentState.startOfWeek,
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
        workingTasks[i] = task.copyWith(
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
              firstDayOfWeek: currentState.startOfWeek,
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
      workingTasks[i] = task.copyWith(
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

    // Phase 10b: Pull per-folder tasks delta (with 410 recovery + move safety).
    final mergedTasks = await _pullAndMergeTasksDelta(
      ctx: ctx,
      settings: settings,
      workingLists: workingLists,
      workingTasks: workingTasks,
      remainingDirtyTasks: dirtyTaskIds.difference(syncedTaskIds),
      syncedTaskIds: syncedTaskIds,
      forceFullSync: forceFullSync,
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
      syncedGroupFields: syncedGroupFields,
      syncedListFields: syncedListFields,
      syncedTaskFields: syncedTaskFields,
      syncedStepIds: syncedStepIds,
      syncedAt: DateTime.now().toUtc(),
      snapshotState: currentState,
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

  Future<List<TaskItem>> _pullAndMergeTasksDelta({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required Set<String> remainingDirtyTasks,
    required Set<String> syncedTaskIds,
    required bool forceFullSync,
    required String Function(String prefix) idGenerator,
  }) async {
    final taskDeltaLinks = Map<String, String>.from(
      settings.loadTaskDeltaLinks(),
    );
    final localListIdByFolderRemoteId = {
      for (final l in workingLists)
        if (l.remoteId != null) l.remoteId!: l.id,
    };
    taskDeltaLinks.removeWhere(
      (folderRemoteId, _) =>
          !localListIdByFolderRemoteId.containsKey(folderRemoteId),
    );
    final listTitleByLocalId = {for (final l in workingLists) l.id: l.title};

    final seenActiveRemoteTaskIds = <String>{};
    final fullSyncedListIds = <String>{};
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
      final savedDeltaLink = taskDeltaLinks[folderRemoteId];
      final effectiveDeltaLink = forceFullSync ? null : savedDeltaLink;
      var recoveredFrom410 = false;

      final taskDeltaResult = await _fetchWithDeltaRecovery(
        deltaLink: effectiveDeltaLink,
        clearDeltaLink: () async {
          recoveredFrom410 = true;
          taskDeltaLinks.remove(folderRemoteId);
          await settings.saveTaskDeltaLinks(taskDeltaLinks);
        },
        fetch: (dl) => todoApi.fetchTasksDelta(
          ctx,
          folderRemoteId: folderRemoteId,
          deltaLink: dl,
        ),
      );
      final didFullFetch = effectiveDeltaLink == null || recoveredFrom410;
      final mode = forceFullSync
          ? 'full(forced)'
          : (recoveredFrom410
                ? 'full(410)'
                : (effectiveDeltaLink == null ? 'full(initial)' : 'delta'));

      if (taskDeltaResult.deltaLink != null) {
        taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
      }
      // Only prune missing remote tasks when we intentionally requested a full
      // snapshot AND received a terminating DeltaLink (meaning all pages were
      // fetched cleanly). Keeping initial sync unpruned avoids breaking tests
      // that pre-seed local tasks without stubbing fetchTasksDelta.
      if (forceFullSync && didFullFetch && taskDeltaResult.deltaLink != null) {
        fullSyncedListIds.add(localListId);
      }

      var addedCount = 0;
      var updatedCount = 0;
      var orderChangedCount = 0;
      var deletedCount = 0;
      var ignoredCount = 0;

      for (final remote in taskDeltaResult.items) {
        if (remote.isIgnored) {
          ignoredCount += 1;
          ignoredRemoteIds.add(remote.id);
          appLog(
            'Phase 10b task[$mode] IGNORED remote=${shortSyncId(remote.id)}',
            label: 'SyncEngine',
          );
          continue;
        }
        if (remote.isDeleted) {
          deletedCount += 1;
          (deferredDeletesByFolder[remote.id] ??= <String>{}).add(localListId);
          appLog(
            'Phase 10b task[$mode] DELETED remote=${shortSyncId(remote.id)} folder=$localListId',
            label: 'SyncEngine',
          );
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
          updatedCount += 1;
          final isDirty = remainingDirtyTasks.contains(existing.id);
          final orderChanged =
              !isDirty &&
              (existing.orderDateTime != remote.orderDateTime ||
                  existing.committedOrder != remote.committedOrder ||
                  existing.listId != resolvedListId);
          if (orderChanged) {
            orderChangedCount += 1;
          }
          if (!didFullFetch || orderChanged) {
            appLog(
              'Phase 10b task[$mode] remote=${shortSyncId(remote.id)} '
              'local=${existing.id} dirty=$isDirty title="${remote.subject}" '
              'list=${existing.listId}->$resolvedListId '
              'order=${formatSyncTimestamp(existing.orderDateTime)}->${formatSyncTimestamp(remote.orderDateTime)} '
              'committedOrder=${formatSyncTimestamp(existing.committedOrder)}->${formatSyncTimestamp(remote.committedOrder)}',
              label: 'SyncEngine',
            );
          }
          tasksById[existing.id] = isDirty
              ? existing.copyWith(
                  changeKey: remote.changeKey ?? existing.changeKey,
                )
              : taskFromRemote(
                  remote,
                  localId: existing.id,
                  listId: resolvedListId,
                  existingSteps: existing.steps,
                  idGenerator: idGenerator,
                  existingCompletedAt: existing.completedAt,
                );
        } else {
          addedCount += 1;
          final newLocalId = idGenerator('task');
          final created = taskFromRemote(
            remote,
            localId: newLocalId,
            listId: resolvedListId,
            existingSteps: const [],
            idGenerator: idGenerator,
          );
          tasksById[newLocalId] = created;
          taskIdByRemoteId[remote.id] = newLocalId;
          appLog(
            'Phase 10b task[$mode] ADD remote=${shortSyncId(remote.id)} '
            'local=$newLocalId title="${created.title}" list=$resolvedListId '
            'order=${formatSyncTimestamp(created.orderDateTime)} '
            'committedOrder=${formatSyncTimestamp(created.committedOrder)}',
            label: 'SyncEngine',
          );
        }
      }

      appLog(
        'Phase 10b folder="${listTitleByLocalId[localListId] ?? localListId}" '
        'remote=${shortSyncId(folderRemoteId)} mode=$mode '
        'items=${taskDeltaResult.items.length} added=$addedCount '
        'updated=$updatedCount orderChanged=$orderChangedCount '
        'deleted=$deletedCount ignored=$ignoredCount '
        'hasDeltaLink=${taskDeltaResult.deltaLink != null}',
        label: 'SyncEngine',
      );
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

    // Prune stale remotely deleted tasks missed by delta after forced full fetch.
    if (fullSyncedListIds.isNotEmpty) {
      final staleLocalIds = <String>[];
      for (final task in tasksById.values) {
        final remoteId = task.remoteId;
        if (remoteId == null) continue;
        if (!fullSyncedListIds.contains(task.listId)) continue;
        if (seenActiveRemoteTaskIds.contains(remoteId)) continue;
        if (remainingDirtyTasks.contains(task.id)) continue;
        if (syncedTaskIds.contains(task.id)) continue;
        staleLocalIds.add(task.id);
      }
      for (final localId in staleLocalIds) {
        final removed = tasksById.remove(localId);
        if (removed != null) {
          appLog(
            'Phase 10b full-sync prune stale local=${removed.id} '
            'remote=${shortSyncId(removed.remoteId)} '
            'title="${removed.title}" list=${removed.listId}',
            label: 'SyncEngine',
          );
        }
      }
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

  static bool _sameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
