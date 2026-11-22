import '../auth/microsoft_auth_service.dart';
import '../data/todo_local_storage.dart';
import '../data/todo_provider.dart';
import '../homeview/home_view_ordering.dart';
import '../models/account.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_api.dart';
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
  Future<SubstrateRequestContext> resolveContext(
    MicrosoftAccount account,
    TodoLocalStorage storage, {
    bool forceRefreshToken = false,
  }) async {
    MicrosoftAuthTokens tokens;
    if (forceRefreshToken) {
      final stored = await tokenStorage.loadTokens(account.id);
      if (stored == null || stored.refreshToken.isEmpty) {
        throw const MicrosoftAuthException(
          'Refresh token unavailable; please sign in again.',
          code: 'no_refresh_token',
          requiresReauth: true,
        );
      }
      tokens = await authClient.refreshTokens(
        refreshToken: stored.refreshToken,
        fallbackUserId: stored.userId.isNotEmpty
            ? stored.userId
            : account.microsoftUserId,
      );
      await tokenStorage.saveTokens(account.id, tokens);
    } else {
      tokens = await authClient.ensureValidTokens(
        accountId: account.id,
        storage: tokenStorage,
        fallbackCid: account.microsoftUserId,
      );
    }

    final cid = tokens.userId.isNotEmpty
        ? tokens.userId
        : account.microsoftUserId;
    var baseUrl = storage.loadCachedEndpointUrl();
    if (baseUrl == null) {
      baseUrl = await authClient.discoverTodoEndpoint(cid);
      await storage.saveCachedEndpointUrl(baseUrl);
    }
    return SubstrateRequestContext(
      baseUrl: baseUrl,
      accessToken: tokens.accessToken,
      cid: cid,
    );
  }

  /// Runs all 10 Substrate v1 sync phases for [account] and [currentState].
  Future<SyncOutcome> syncAccount({
    required MicrosoftAccount account,
    required TodoState currentState,
    required TodoLocalStorage storage,
    required String Function(String prefix) idGenerator,
  }) async {
    Future<T> withAuthRetry<T>(
      Future<T> Function(SubstrateRequestContext ctx) run,
    ) async {
      final ctx = await resolveContext(account, storage);
      try {
        return await run(ctx);
      } on SyncApiException catch (e) {
        if (!e.isAuthError) rethrow;
        final refreshedCtx = await resolveContext(
          account,
          storage,
          forceRefreshToken: true,
        );
        try {
          return await run(refreshedCtx);
        } on SyncApiException catch (retryErr) {
          if (retryErr.isAuthError) {
            throw MicrosoftAuthException(
              retryErr.message,
              code: retryErr.errorCode,
              requiresReauth: true,
            );
          }
          rethrow;
        }
      }
    }

    return withAuthRetry(
      (ctx) => _executeSyncPhases(
        ctx: ctx,
        currentState: currentState,
        storage: storage,
        idGenerator: idGenerator,
      ),
    );
  }

  Future<SyncOutcome> _executeSyncPhases({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required TodoLocalStorage storage,
    required String Function(String prefix) idGenerator,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    var workingGroups = [...currentState.groups];
    var workingLists = [...currentState.lists];
    var workingTasks = [...currentState.tasks];

    final dirtySettingKeys = storage.loadDirtySettingKeys().toSet();
    final dirtyGroupIds = storage.loadDirtyGroupIds().toSet();
    final dirtyListIds = storage.loadDirtyListIds().toSet();
    final dirtyTaskIds = storage.loadDirtyTaskIds().toSet();

    final syncedSettingKeys = <String>{};
    final syncedGroupIds = <String>{};
    final syncedListIds = <String>{};
    final syncedTaskIds = <String>{};

    final processedDeletedSteps = <PendingStepDeletion>[];
    final processedDeletedTaskRemoteIds = <String>[];
    final processedDeletedListRemoteIds = <String>[];
    final processedDeletedGroupRemoteIds = <String>[];

    // Phase 2: Push dirty settings.
    for (final key in dirtySettingKeys) {
      final wireValue = extractSettingValueForKey(currentState, key);
      if (wireValue != null) {
        await todoApi.patchSetting(ctx, key, wireValue);
      }
      syncedSettingKeys.add(key);
    }

    // Phase 3: Push step, task, and folder deletions.
    for (final stepDel in storage.loadPendingDeletedSteps()) {
      try {
        await todoApi.deleteStep(
          ctx,
          stepDel.taskRemoteId,
          stepDel.stepRemoteId,
        );
        processedDeletedSteps.add(stepDel);
      } on SyncApiException catch (e) {
        if (e.isNotFound) {
          processedDeletedSteps.add(stepDel);
        } else {
          rethrow;
        }
      }
    }

    for (final taskRemoteId in storage.loadPendingDeletedTaskRemoteIds()) {
      try {
        await todoApi.deleteTask(ctx, taskRemoteId);
        processedDeletedTaskRemoteIds.add(taskRemoteId);
      } on SyncApiException catch (e) {
        if (e.isNotFound) {
          processedDeletedTaskRemoteIds.add(taskRemoteId);
        } else {
          rethrow;
        }
      }
    }

    for (final listRemoteId in storage.loadPendingDeletedListRemoteIds()) {
      try {
        await todoApi.deleteFolder(ctx, listRemoteId);
        processedDeletedListRemoteIds.add(listRemoteId);
      } on SyncApiException catch (e) {
        if (e.isNotFound || e.isCantDeleteDefaultFolder) {
          processedDeletedListRemoteIds.add(listRemoteId);
        } else {
          rethrow;
        }
      }
    }

    // Phase 4: Push dirty / new folder groups.
    for (var i = 0; i < workingGroups.length; i++) {
      final group = workingGroups[i];
      if (group.remoteId == null) {
        final created = await todoApi.createFolderGroup(
          ctx,
          name: group.title,
          orderDateTime: group.orderDateTime ?? nowUtc,
        );
        workingGroups[i] = group.copyWith(
          remoteId: created.id,
          orderDateTime: created.orderDateTime ?? group.orderDateTime,
          updatedAt: nowUtc,
        );
        syncedGroupIds.add(group.id);
      } else if (dirtyGroupIds.contains(group.id)) {
        try {
          final patched = await todoApi.patchFolderGroup(ctx, group.remoteId!, {
            'Name': group.title,
            if (group.orderDateTime != null)
              'OrderDateTime': formatSubstrateUtcTimestamp(
                group.orderDateTime!,
              ),
          });
          workingGroups[i] = group.copyWith(
            title: patched.name.isNotEmpty ? patched.name : group.title,
            orderDateTime: patched.orderDateTime ?? group.orderDateTime,
            updatedAt: nowUtc,
          );
          syncedGroupIds.add(group.id);
        } on SyncApiException catch (e) {
          if (!e.isNotFound) rethrow;
          final recreated = await todoApi.createFolderGroup(
            ctx,
            name: group.title,
            orderDateTime: group.orderDateTime ?? nowUtc,
          );
          workingGroups[i] = group.copyWith(
            remoteId: recreated.id,
            orderDateTime: recreated.orderDateTime ?? group.orderDateTime,
            updatedAt: nowUtc,
          );
          syncedGroupIds.add(group.id);
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
        final payload = <String, dynamic>{
          'Name': encodeFolderName(list.title, list.emoji),
          'OrderDateTime': formatSubstrateUtcTimestamp(
            list.orderDateTime ?? nowUtc,
          ),
          'ThemeColor': encodeFolderThemeColor(list.themeColor),
          'ThemeBackground': ?encodeFolderThemeBackground(list.themePhoto),
          'ShowCompletedTasks': list.showCompleted,
          'SortType': encodeSortType(list.sortOption),
          'SortAscending': list.sortAscending,
          'ParentFolderGroupId': ?parentGroupRemoteId,
        };
        final created = await todoApi.createFolder(ctx, payload);
        workingLists[i] = list.copyWith(
          remoteId: created.id,
          orderDateTime: created.orderDateTime ?? list.orderDateTime,
          updatedAt: nowUtc,
        );
        syncedListIds.add(list.id);
      } else if (list.remoteId != null && dirtyListIds.contains(list.id)) {
        final patch = <String, dynamic>{
          if (!list.isSmartList)
            'Name': encodeFolderName(list.title, list.emoji),
          if (!list.isSmartList) 'ParentFolderGroupId': parentGroupRemoteId,
          'ThemeColor': encodeFolderThemeColor(list.themeColor),
          'ThemeBackground': encodeFolderThemeBackground(list.themePhoto),
          'ShowCompletedTasks': list.showCompleted,
          'SortType': encodeSortType(list.sortOption),
          'SortAscending': list.sortAscending,
          if (list.orderDateTime != null)
            'OrderDateTime': formatSubstrateUtcTimestamp(list.orderDateTime!),
        };
        try {
          final patched = await todoApi.patchFolder(ctx, list.remoteId!, patch);
          workingLists[i] = list.copyWith(
            orderDateTime: patched.orderDateTime ?? list.orderDateTime,
            updatedAt: nowUtc,
          );
          syncedListIds.add(list.id);
        } on SyncApiException catch (e) {
          if (!e.isNotFound || list.isSmartList) rethrow;
          final recreated = await todoApi.createFolder(ctx, {
            'Name': encodeFolderName(list.title, list.emoji),
            'OrderDateTime': formatSubstrateUtcTimestamp(
              list.orderDateTime ?? nowUtc,
            ),
            'ThemeColor': encodeFolderThemeColor(list.themeColor),
            'ThemeBackground': ?encodeFolderThemeBackground(list.themePhoto),
            'ShowCompletedTasks': list.showCompleted,
            'SortType': encodeSortType(list.sortOption),
            'SortAscending': list.sortAscending,
            'ParentFolderGroupId': ?parentGroupRemoteId,
          });
          workingLists[i] = list.copyWith(
            remoteId: recreated.id,
            updatedAt: nowUtc,
          );
          syncedListIds.add(list.id);
        }
      }
    }

    // Phase 6: Delete pending folder groups (after ungrouping member folders).
    for (final groupRemoteId in storage.loadPendingDeletedGroupRemoteIds()) {
      try {
        await todoApi.deleteFolderGroup(ctx, groupRemoteId);
        processedDeletedGroupRemoteIds.add(groupRemoteId);
      } on SyncApiException catch (e) {
        if (e.isNotFound) {
          processedDeletedGroupRemoteIds.add(groupRemoteId);
        } else if (e.isFolderGroupNotEmpty) {
          // Leave queued until member folders are ungrouped remotely.
        } else {
          rethrow;
        }
      }
    }

    // Phase 7: Pull remote settings (skip keys still dirty locally).
    final remainingDirtySettings = dirtySettingKeys.difference(
      syncedSettingKeys,
    );
    final remoteSettings = await todoApi.getSettings(ctx);
    final settingsPatch = buildSyncedSettingsPatchFromWire(
      remoteSettings,
      skipKeys: remainingDirtySettings,
    );

    // Phase 8: Pull folder groups delta (with 410 full-resync recovery).
    final groupsDeltaResult = await _fetchWithDeltaRecovery(
      deltaLink: storage.loadGroupsDeltaLink(),
      clearDeltaLink: () => storage.saveGroupsDeltaLink(null),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    );
    if (groupsDeltaResult.deltaLink != null) {
      await storage.saveGroupsDeltaLink(groupsDeltaResult.deltaLink);
    }
    final remainingDirtyGroups = dirtyGroupIds.difference(syncedGroupIds);
    workingGroups = _mergeFolderGroupsDelta(
      localGroups: workingGroups,
      remoteDelta: groupsDeltaResult.items,
      dirtyGroupIds: remainingDirtyGroups,
      idGenerator: idGenerator,
    );

    // Phase 9: Pull folders delta (with 410 full-resync recovery).
    final foldersDeltaResult = await _fetchWithDeltaRecovery(
      deltaLink: storage.loadFoldersDeltaLink(),
      clearDeltaLink: () => storage.saveFoldersDeltaLink(null),
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    );
    if (foldersDeltaResult.deltaLink != null) {
      await storage.saveFoldersDeltaLink(foldersDeltaResult.deltaLink);
    }
    final remainingDirtyLists = dirtyListIds.difference(syncedListIds);
    final groupLocalIdByRemoteId = {
      for (final g in workingGroups)
        if (g.remoteId != null) g.remoteId!: g.id,
    };
    workingLists = _mergeFoldersDelta(
      localLists: workingLists,
      remoteDelta: foldersDeltaResult.items,
      dirtyListIds: remainingDirtyLists,
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

      if (task.remoteId == null) {
        final payload = _buildTaskWritePayload(
          task,
          parentFolderRemoteId: folderRemoteId,
          isCreate: true,
          firstDayOfWeek: currentState.startOfWeek,
        );
        final created = await todoApi.createTask(ctx, folderRemoteId, payload);
        final pushedSteps = await _syncStepsForTask(
          ctx: ctx,
          taskRemoteId: created.id,
          localSteps: task.steps,
        );
        workingTasks[i] = task.copyWith(
          remoteId: created.id,
          remoteParentFolderId: created.parentFolderId ?? folderRemoteId,
          changeKey: created.changeKey ?? task.changeKey,
          orderDateTime: created.orderDateTime ?? task.orderDateTime,
          committedOrder: created.committedOrder ?? task.committedOrder,
          steps: pushedSteps,
          updatedAt: nowUtc,
        );
        syncedTaskIds.add(task.id);
      } else if (dirtyTaskIds.contains(task.id)) {
        final payload = _buildTaskWritePayload(
          task,
          parentFolderRemoteId: folderRemoteId,
          isCreate: false,
          firstDayOfWeek: currentState.startOfWeek,
        );
        final patched = await _patchTaskWithConflictRetry(
          ctx: ctx,
          task: task,
          payload: payload,
        );
        final pushedSteps = await _syncStepsForTask(
          ctx: ctx,
          taskRemoteId: patched.id,
          localSteps: task.steps,
        );
        workingTasks[i] = task.copyWith(
          changeKey: patched.changeKey ?? task.changeKey,
          orderDateTime: patched.orderDateTime ?? task.orderDateTime,
          committedOrder: patched.committedOrder ?? task.committedOrder,
          remoteParentFolderId: patched.parentFolderId ?? folderRemoteId,
          steps: pushedSteps,
          updatedAt: nowUtc,
        );
        syncedTaskIds.add(task.id);
      }
    }

    // Phase 10b: Pull per-folder tasks delta (with 410 recovery + move safety).
    final taskDeltaLinks = Map<String, String>.from(
      storage.loadTaskDeltaLinks(),
    );
    final remainingDirtyTasks = dirtyTaskIds.difference(syncedTaskIds);
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
          await storage.saveTaskDeltaLinks(taskDeltaLinks);
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
          if (remainingDirtyTasks.contains(existing.id)) {
            tasksById[existing.id] = existing.copyWith(
              changeKey: remote.changeKey ?? existing.changeKey,
            );
          } else {
            tasksById[existing.id] = _taskFromRemote(
              remote,
              localId: existing.id,
              listId: resolvedListId,
              existingSteps: existing.steps,
              idGenerator: idGenerator,
            );
          }
        } else {
          final newLocalId = idGenerator('task');
          final createdLocal = _taskFromRemote(
            remote,
            localId: newLocalId,
            listId: resolvedListId,
            existingSteps: const [],
            idGenerator: idGenerator,
          );
          tasksById[newLocalId] = createdLocal;
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
      if (localTask == null) continue;
      if (!deletedFromListIds.contains(localTask.listId)) continue;
      tasksById.remove(localId);
    }

    await storage.saveTaskDeltaLinks(taskDeltaLinks);

    final mergedTasks = tasksById.values.toList();
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

  Future<DeltaPageResult<T>> _fetchWithDeltaRecovery<T>({
    required String? deltaLink,
    required Future<void> Function() clearDeltaLink,
    required Future<DeltaPageResult<T>> Function(String? deltaLink) fetch,
  }) async {
    try {
      return await fetch(deltaLink);
    } on SyncApiException catch (e) {
      if (!e.isDeltaExpired || deltaLink == null) rethrow;
      await clearDeltaLink();
      return fetch(null);
    }
  }

  List<ListGroup> _mergeFolderGroupsDelta({
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

  List<TodoList> _mergeFoldersDelta({
    required List<TodoList> localLists,
    required List<RemoteTodoFolder> remoteDelta,
    required Set<String> dirtyListIds,
    required Map<String, String> groupLocalIdByRemoteId,
    required String Function(String prefix) idGenerator,
  }) {
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
        final idx = result.indexWhere(
          (l) => l.smartType == SmartListType.tasks,
        );
        if (idx >= 0) {
          final existing = result[idx];
          if (dirtyListIds.contains(existing.id)) {
            result[idx] = existing.copyWith(remoteId: remote.id);
          } else {
            final theme = decodeFolderTheme(
              themeColor: remote.themeColor,
              themeBackground: remote.themeBackground,
              fallbackColor: existing.themeColor,
            );
            result[idx] = existing.copyWith(
              remoteId: remote.id,
              themeColor: theme.themeColor,
              themePhoto: theme.themePhoto,
              showCompleted: remote.showCompletedTasks,
              sortOption: remote.sortOption,
              sortAscending: remote.sortAscending,
              orderDateTime: remote.orderDateTime ?? existing.orderDateTime,
            );
          }
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
        final existing = result[idx];
        if (dirtyListIds.contains(existing.id)) {
          result[idx] = existing.copyWith(remoteId: remote.id);
        } else {
          final theme = decodeFolderTheme(
            themeColor: remote.themeColor,
            themeBackground: remote.themeBackground,
            fallbackColor: existing.themeColor,
          );
          result[idx] = existing.copyWith(
            title: decodedName.title,
            emoji: decodedName.emoji,
            groupId: mappedGroupId,
            themeColor: theme.themeColor,
            themePhoto: theme.themePhoto,
            showCompleted: remote.showCompletedTasks,
            sortOption: remote.sortOption,
            sortAscending: remote.sortAscending,
            remoteId: remote.id,
            orderDateTime: remote.orderDateTime ?? existing.orderDateTime,
          );
        }
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

  Map<String, dynamic> _buildTaskWritePayload(
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
        'BodyLastModifiedTime': formatSubstrateUtcTimestamp(
          task.noteUpdatedAt!,
        ),
      'Status': task.isCompleted ? 'Completed' : 'NotStarted',
      'Importance': task.isImportant ? 'High' : 'Normal',
      'IsReminderOn': task.reminderAt != null,
    };

    if (task.dueDate != null) {
      payload['DueDateTime'] = formatDueDateTimeZone(task.dueDate!);
    } else if (!isCreate) {
      payload['DueDateTime'] = null;
    }

    if (task.reminderAt != null) {
      payload['ReminderDateTime'] = formatDateTimeTimeZoneUtc(task.reminderAt!);
    } else if (!isCreate) {
      payload['ReminderDateTime'] = null;
    }

    if (task.isCompleted) {
      payload['CompletedDateTime'] = formatDateTimeTimeZoneUtc(
        task.completedAt ?? nowUtc,
      );
    } else if (!isCreate) {
      payload['CompletedDateTime'] = null;
    }

    if (task.myDayDate != null) {
      payload['CommittedDay'] = formatDayString(task.myDayDate!);
    } else if (!isCreate) {
      payload['CommittedDay'] = null;
    }

    if (task.committedOrder != null) {
      payload['CommittedOrder'] = formatSubstrateUtcTimestamp(
        task.committedOrder!,
      );
    } else if (!isCreate && !task.isInMyDay) {
      payload['CommittedOrder'] = null;
    }

    if (task.postponedDay != null) {
      payload['PostponedDay'] = formatDayString(task.postponedDay!);
    } else if (!isCreate) {
      payload['PostponedDay'] = null;
    }

    if (recurrenceMap != null) {
      payload['Recurrence'] = recurrenceMap;
    } else if (!isCreate) {
      payload['Recurrence'] = null;
    }

    return payload;
  }

  Future<RemoteTodoTask> _patchTaskWithConflictRetry({
    required SubstrateRequestContext ctx,
    required TaskItem task,
    required Map<String, dynamic> payload,
  }) async {
    try {
      return await todoApi.patchTask(
        ctx,
        task.remoteId!,
        payload,
        changeKey: task.changeKey,
      );
    } on SyncApiException catch (e) {
      if (!e.isConflict) rethrow;
      final latest = await todoApi.getTask(ctx, task.remoteId!);
      return todoApi.patchTask(
        ctx,
        task.remoteId!,
        payload,
        changeKey: latest.changeKey,
      );
    }
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
      if (step.remoteId == null) {
        final stepOrder =
            step.orderDateTime ??
            nowUtc.subtract(
              Duration(seconds: i * kOrderDateTimeStep.inSeconds),
            );
        final created = await todoApi.createStep(
          ctx,
          taskRemoteId,
          subject: step.title,
          orderDateTime: stepOrder,
        );
        if (step.isCompleted) {
          await todoApi.patchStep(ctx, taskRemoteId, created.id, const {
            'IsCompleted': true,
          });
        }
        syncedSteps.add(
          step.copyWith(
            remoteId: created.id,
            orderDateTime: created.orderDateTime ?? stepOrder,
          ),
        );
      } else {
        final patched = await todoApi.patchStep(
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
        syncedSteps.add(
          step.copyWith(
            orderDateTime: patched.orderDateTime ?? step.orderDateTime,
          ),
        );
      }
    }
    return syncedSteps;
  }

  TaskItem _taskFromRemote(
    RemoteTodoTask remote, {
    required String localId,
    required String listId,
    required List<TaskStep> existingSteps,
    required String Function(String prefix) idGenerator,
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
    final mappedSteps = [for (final item in indexedSteps) item.step];

    return TaskItem(
      id: localId,
      listId: listId,
      title: remote.subject,
      createdAt: remote.createdDateTime ?? DateTime.now(),
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
      completedAt: remote.isCompleted ? remote.completedDateTime : null,
      steps: mappedSteps,
      remoteId: remote.id,
      remoteParentFolderId: remote.parentFolderId,
      orderDateTime: remote.orderDateTime,
      committedOrder: remote.committedOrder,
      changeKey: remote.changeKey,
      updatedAt: remote.lastModifiedDateTime ?? remote.createdDateTime,
    );
  }
}
