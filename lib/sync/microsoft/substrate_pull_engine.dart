import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_settings_store.dart';
import '../../data/todo_settings_sync.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'microsoft_todo_api.dart';
import 'remote_change_reconciler.dart';
import 'substrate_sync_mappers.dart';
import '../sync_concurrency.dart';
import '../sync_log_format.dart';

final _log = appLogFor('SyncEngine');

class FullPullResult {
  const FullPullResult({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.settingsPatch,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final SyncedSettingsPatch? settingsPatch;
}

enum DeltaFetchMode {
  forcedFull('full(forced)', isFullFetch: true),
  recovered410('full(410)', isFullFetch: true),
  initialFull('full(initial)', isFullFetch: true),
  delta('delta', isFullFetch: false),
  missing('missing', isFullFetch: false);

  const DeltaFetchMode(this.label, {required this.isFullFetch});

  final String label;
  final bool isFullFetch;
}

class DeltaFetchResult<T> {
  const DeltaFetchResult({required this.page, required this.mode});

  final DeltaPageResult<T> page;
  final DeltaFetchMode mode;

  bool get didFullFetch => mode.isFullFetch;
}

/// Outcome of [SubstratePullEngine.fetchPatch]: either a fetched remote patch
/// or an explicit cooperative cancellation (without throwing exceptions).
sealed class PullPatchFetch {
  const PullPatchFetch();
}

final class PullPatchCancelled extends PullPatchFetch {
  const PullPatchCancelled();
}

/// Pure remote payload returned by [SubstratePullEngine.fetchPatch].
///
/// Contains no local entity snapshots; it is applied atomically against the
/// latest live local state in [SubstratePullEngine.applyPatch].
final class RemotePullPatch extends PullPatchFetch {
  const RemotePullPatch({
    required this.forceFullSync,
    required this.isSelective,
    this.remoteSettings,
    this.groupsFetch,
    this.foldersFetch,
    this.taskFetchesByFolderRemoteId = const {},
    this.pulledFolderRemoteIds = const {},
  });

  final bool forceFullSync;
  final bool isSelective;
  final Map<String, String>? remoteSettings;
  final DeltaFetchResult<RemoteFolderGroup>? groupsFetch;
  final DeltaFetchResult<RemoteTodoFolder>? foldersFetch;
  final Map<String, DeltaFetchResult<RemoteTodoTask>>
  taskFetchesByFolderRemoteId;
  final Set<String> pulledFolderRemoteIds;
}

/// Stateless remote fetcher & patch reconciler for Substrate v1 delta endpoints.
///
/// Network fetches ([fetchPatch]) never hold local entity snapshots and never
/// advance saved `deltaLink`s until [applyPatch] commits against live state.
class SubstratePullEngine {
  const SubstratePullEngine(this.todoApi);

  static const int _maxConcurrentFolderFetches = 4;

  final MicrosoftTodoApi todoApi;

  /// Fetches remote settings, groups, folders, and/or tasks without touching
  /// local entity snapshots or advancing saved `deltaLink`s.
  AsyncAppResult<PullPatchFetch> fetchPatch({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required Set<String> knownFolderRemoteIds,
    required bool forceFullSync,
    required bool isSelective,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() == true;
    if (cancelled()) return const Success(PullPatchCancelled());

    if (isSelective) {
      return _fetchSelectivePatch(
        ctx: ctx,
        settings: settings,
        knownFolderRemoteIds: knownFolderRemoteIds,
        isCancelled: cancelled,
      );
    }

    return _fetchFullOrDeltaPatch(
      ctx: ctx,
      settings: settings,
      knownFolderRemoteIds: knownFolderRemoteIds,
      forceFullSync: forceFullSync,
      isCancelled: cancelled,
    );
  }

  AsyncAppResult<PullPatchFetch> _fetchSelectivePatch({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required Set<String> knownFolderRemoteIds,
    required bool Function() isCancelled,
  }) async {
    final pendingPulls = settings.loadPendingTaskFolderPulls();
    final targetFolderRemoteIds = knownFolderRemoteIds
        .where(pendingPulls.contains)
        .toSet();
    _log.info(
      'Phase 10b selective pull folders=${targetFolderRemoteIds.length} '
      'of=${knownFolderRemoteIds.length} '
      'pending=${targetFolderRemoteIds.length}',
    );
    if (targetFolderRemoteIds.isEmpty) {
      return const Success(
        RemotePullPatch(
          forceFullSync: false,
          isSelective: true,
          pulledFolderRemoteIds: {},
        ),
      );
    }

    return _fetchTaskDeltas(
      ctx: ctx,
      settings: settings,
      targetFolderRemoteIds: targetFolderRemoteIds,
      forceFullSync: false,
      isSelective: true,
      isCancelled: isCancelled,
    );
  }

  AsyncAppResult<PullPatchFetch> _fetchFullOrDeltaPatch({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required Set<String> knownFolderRemoteIds,
    required bool forceFullSync,
    required bool Function() isCancelled,
  }) async {
    final settingsResult = await todoApi.getSettings(ctx);
    if (settingsResult.isError()) {
      return Failure(settingsResult.exceptionOrNull()!);
    }
    if (isCancelled()) return const Success(PullPatchCancelled());

    final groupsResult = await _fetchDeltaWithMode(
      savedDeltaLink: settings.loadGroupsDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => settings.saveGroupsDeltaLink(null),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    );
    if (groupsResult.isError()) {
      return Failure(groupsResult.exceptionOrNull()!);
    }
    if (isCancelled()) return const Success(PullPatchCancelled());

    final groupsFetch = groupsResult.getOrNull()!;
    _log.info(
      'Phase 8 groups mode=${groupsFetch.mode.label} '
      'items=${groupsFetch.page.items.length} '
      'hasDeltaLink=${groupsFetch.page.deltaLink != null}',
    );

    final foldersResult = await _fetchDeltaWithMode(
      savedDeltaLink: settings.loadFoldersDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => settings.saveFoldersDeltaLink(null),
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    );
    if (foldersResult.isError()) {
      return Failure(foldersResult.exceptionOrNull()!);
    }
    if (isCancelled()) return const Success(PullPatchCancelled());

    final foldersFetch = foldersResult.getOrNull()!;
    final foldersPage = foldersFetch.page;
    _log.info(
      'Phase 9 folders mode=${foldersFetch.mode.label} '
      'items=${foldersPage.items.length} '
      'hasDeltaLink=${foldersPage.deltaLink != null}',
    );

    final targetFolderRemoteIds = _resolveTargetFolderRemoteIds(
      foldersPage: foldersPage,
      knownFolderRemoteIds: knownFolderRemoteIds,
      forceFullSync: forceFullSync,
    );

    return _fetchTaskDeltas(
      ctx: ctx,
      settings: settings,
      targetFolderRemoteIds: targetFolderRemoteIds,
      forceFullSync: forceFullSync,
      isSelective: false,
      isCancelled: isCancelled,
      remoteSettings: settingsResult.getOrNull(),
      groupsFetch: groupsFetch,
      foldersFetch: foldersFetch,
    );
  }

  Set<String> _resolveTargetFolderRemoteIds({
    required DeltaPageResult<RemoteTodoFolder> foldersPage,
    required Set<String> knownFolderRemoteIds,
    required bool forceFullSync,
  }) {
    final activeRemoteIds = <String>{
      for (final f in foldersPage.items)
        if (!f.isDeleted && !f.isIgnoredSpecialFolder && f.id.isNotEmpty) f.id,
    };
    final deletedRemoteIds = <String>{
      for (final f in foldersPage.items)
        if (f.isDeleted && f.id.isNotEmpty) f.id,
    };
    if (forceFullSync &&
        foldersPage.deltaLink != null &&
        activeRemoteIds.isNotEmpty) {
      return activeRemoteIds;
    }
    return {
      ...knownFolderRemoteIds.where((id) => !deletedRemoteIds.contains(id)),
      ...activeRemoteIds,
    };
  }

  AsyncAppResult<PullPatchFetch> _fetchTaskDeltas({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required Set<String> targetFolderRemoteIds,
    required bool forceFullSync,
    required bool isSelective,
    required bool Function() isCancelled,
    Map<String, String>? remoteSettings,
    DeltaFetchResult<RemoteFolderGroup>? groupsFetch,
    DeltaFetchResult<RemoteTodoFolder>? foldersFetch,
  }) async {
    final savedTaskDeltaLinks = settings.loadTaskDeltaLinks();
    final folderList = targetFolderRemoteIds.toList(growable: false);

    final fetchesResult = await mapResultsWithConcurrency(
      folderList,
      _maxConcurrentFolderFetches,
      (folderRemoteId) => _fetchSingleFolderTasks(
        ctx: ctx,
        settings: settings,
        folderRemoteId: folderRemoteId,
        savedDeltaLink: savedTaskDeltaLinks[folderRemoteId],
        forceFullSync: forceFullSync,
        isSelective: isSelective,
      ),
      shouldStop: isCancelled,
    );

    if (isCancelled()) return const Success(PullPatchCancelled());

    return fetchesResult.map((fetches) {
      final taskFetches = <String, DeltaFetchResult<RemoteTodoTask>>{
        for (var i = 0; i < folderList.length; i++) folderList[i]: fetches[i],
      };
      return RemotePullPatch(
        forceFullSync: forceFullSync,
        isSelective: isSelective,
        remoteSettings: remoteSettings,
        groupsFetch: groupsFetch,
        foldersFetch: foldersFetch,
        taskFetchesByFolderRemoteId: taskFetches,
        pulledFolderRemoteIds: targetFolderRemoteIds,
      );
    });
  }

  AsyncAppResult<DeltaFetchResult<RemoteTodoTask>> _fetchSingleFolderTasks({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required String folderRemoteId,
    required String? savedDeltaLink,
    required bool forceFullSync,
    required bool isSelective,
  }) async {
    final fetchResult = await _fetchDeltaWithMode(
      savedDeltaLink: savedDeltaLink,
      forceFullSync: forceFullSync,
      clearDeltaLink: () async {
        final next = Map<String, String>.from(settings.loadTaskDeltaLinks())
          ..remove(folderRemoteId);
        await settings.saveTaskDeltaLinks(next);
      },
      fetch: (dl) => todoApi.fetchTasksDelta(
        ctx,
        folderRemoteId: folderRemoteId,
        deltaLink: dl,
      ),
    );
    return fetchResult.recover((error) {
      if (!isSelective || !error.isNotFound) {
        return Failure<DeltaFetchResult<RemoteTodoTask>, AppError>(error);
      }
      _log.info(
        'Phase 10b selective pull skipped missing folder '
        'remote=${shortSyncId(folderRemoteId)} error=${error.describe()}',
      );
      return const Success<DeltaFetchResult<RemoteTodoTask>, AppError>(
        DeltaFetchResult<RemoteTodoTask>(
          page: DeltaPageResult<RemoteTodoTask>(items: []),
          mode: DeltaFetchMode.missing,
        ),
      );
    });
  }

  /// Applies [patch] atomically against the latest live local state and
  /// commits the resulting `deltaLink`s to [settings].
  ///
  /// Any entity modified or acknowledged in [outbox] strictly after
  /// [pullStartSeq] is protected from being overwritten by stale remote data;
  /// any entity modified after [pruneProtectSinceSeq] is protected from
  /// full-sync stale pruning.
  Future<FullPullResult> applyPatch({
    required RemotePullPatch patch,
    required TodoSettingsStore settings,
    required List<ListGroup> liveGroups,
    required List<TodoList> liveLists,
    required List<TaskItem> liveTasks,
    required SyncOutboxQueue outbox,
    required String Function(String prefix) idGenerator,
    required int pullStartSeq,
    required int pruneProtectSinceSeq,
  }) async {
    final dirtySettings = outbox.modifiedLocalIdsSince(
      SyncEntityType.setting,
      pullStartSeq,
    );
    final dirtyGroups = outbox.modifiedLocalIdsSince(
      SyncEntityType.group,
      pullStartSeq,
    );
    final dirtyLists = outbox.modifiedLocalIdsSince(
      SyncEntityType.list,
      pullStartSeq,
    );
    final dirtyTasks = outbox.modifiedLocalIdsSince(
      SyncEntityType.task,
      pullStartSeq,
    );

    final pruneKeepGroups = outbox.modifiedLocalIdsSince(
      SyncEntityType.group,
      pruneProtectSinceSeq,
    );
    final pruneKeepLists = outbox.modifiedLocalIdsSince(
      SyncEntityType.list,
      pruneProtectSinceSeq,
    );
    final pruneKeepTasks = outbox.modifiedLocalIdsSince(
      SyncEntityType.task,
      pruneProtectSinceSeq,
    );

    final deletedGroupRemotes = outbox.deletedRemoteIdsSince(
      SyncEntityType.group,
      pullStartSeq,
    );
    final deletedListRemotes = outbox.deletedRemoteIdsSince(
      SyncEntityType.list,
      pullStartSeq,
    );
    final deletedTaskRemotes = outbox.deletedRemoteIdsSince(
      SyncEntityType.task,
      pullStartSeq,
    );

    SyncedSettingsPatch? settingsPatch;
    var nextGroups = liveGroups;
    var nextLists = liveLists;

    if (!patch.isSelective) {
      if (patch.remoteSettings != null) {
        settingsPatch = buildSyncedSettingsPatchFromWire(
          patch.remoteSettings!,
          skipKeys: dirtySettings,
        );
      }

      final groupsDelta = patch.groupsFetch?.page;
      if (groupsDelta != null) {
        final filteredGroupItems = groupsDelta.items
            .where((g) => !deletedGroupRemotes.contains(g.id))
            .toList();
        nextGroups = mergeFolderGroupsDelta(
          localGroups: liveGroups,
          remoteDelta: filteredGroupItems,
          dirtyGroupIds: dirtyGroups,
          idGenerator: idGenerator,
        );
        if (patch.forceFullSync && groupsDelta.deltaLink != null) {
          final seenGroupRemoteIds = {
            for (final g in filteredGroupItems)
              if (!g.isDeleted && g.id.isNotEmpty) g.id,
          };
          nextGroups = _pruneStale(
            items: nextGroups,
            shouldKeep: (g) =>
                g.remoteId == null ||
                seenGroupRemoteIds.contains(g.remoteId) ||
                pruneKeepGroups.contains(g.id),
            onPruned: (g) => _log.fine(
              'Phase 8 full-sync prune stale group=${g.id} '
              'remote=${shortSyncId(g.remoteId)} title="${g.title}"',
            ),
          );
        }
      }

      final foldersDelta = patch.foldersFetch?.page;
      if (foldersDelta != null) {
        final filteredFolderItems = foldersDelta.items
            .where((f) => !deletedListRemotes.contains(f.id))
            .toList();
        final groupLocalIdByRemoteId = {
          for (final g in nextGroups)
            if (g.remoteId != null) g.remoteId!: g.id,
        };
        nextLists = mergeFoldersDelta(
          localLists: liveLists,
          remoteDelta: filteredFolderItems,
          dirtyListIds: dirtyLists,
          groupLocalIdByRemoteId: groupLocalIdByRemoteId,
          idGenerator: idGenerator,
        );
        if (patch.forceFullSync && foldersDelta.deltaLink != null) {
          final seenFolderRemoteIds = {
            for (final f in filteredFolderItems)
              if (!f.isDeleted && !f.isIgnoredSpecialFolder && f.id.isNotEmpty)
                f.id,
          };
          if (seenFolderRemoteIds.isNotEmpty) {
            nextLists = _pruneStale(
              items: nextLists,
              shouldKeep: (l) =>
                  l.isSmartList ||
                  l.remoteId == null ||
                  seenFolderRemoteIds.contains(l.remoteId) ||
                  pruneKeepLists.contains(l.id),
              onPruned: (l) => _log.fine(
                'Phase 9 full-sync prune stale list=${l.id} '
                'remote=${shortSyncId(l.remoteId)} title="${l.title}"',
              ),
            );
          }
        }
      }
    }

    final validListIds = {for (final l in nextLists) l.id};
    final liveTasksInValidLists = liveTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();

    final localListIdByFolderRemoteId = {
      for (final l in nextLists)
        if (l.remoteId != null) l.remoteId!: l.id,
    };
    final listTitleByLocalId = {for (final l in nextLists) l.id: l.title};
    final taskDeltaLinks = Map<String, String>.from(
      settings.loadTaskDeltaLinks(),
    )..removeWhere((id, _) => !localListIdByFolderRemoteId.containsKey(id));

    final pendingFolderPulls = settings.loadPendingTaskFolderPulls();
    final livePendingFolderPulls = pendingFolderPulls
        .where(localListIdByFolderRemoteId.containsKey)
        .toSet();

    var nextTasks = liveTasksInValidLists;
    if (patch.taskFetchesByFolderRemoteId.isNotEmpty) {
      final fullSyncedListIds = <String>{};
      final allChanges = <RemoteTaskChange>[];

      for (final entry in patch.taskFetchesByFolderRemoteId.entries) {
        final folderRemoteId = entry.key;
        final localListId = localListIdByFolderRemoteId[folderRemoteId];
        if (localListId == null) continue;
        final taskFetch = entry.value;
        final taskDeltaResult = taskFetch.page;
        if (taskDeltaResult.deltaLink != null) {
          taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
        }
        if (patch.forceFullSync &&
            taskFetch.didFullFetch &&
            taskDeltaResult.deltaLink != null) {
          fullSyncedListIds.add(localListId);
        }
        for (final remote in taskDeltaResult.items) {
          allChanges.add((
            remote: remote,
            fallbackLocalListId: localListId,
            preserveStepsWhenMissing: false,
            preserveAttachmentsWhenMissing: false,
          ));
        }
        _log.info(
          'Phase 10b folder="${listTitleByLocalId[localListId] ?? localListId}" '
          'remote=${shortSyncId(folderRemoteId)} mode=${taskFetch.mode.label} '
          'items=${taskDeltaResult.items.length} '
          'hasDeltaLink=${taskDeltaResult.deltaLink != null}',
        );
      }

      final reconciled = reconcileRemoteTaskChanges(
        lists: nextLists,
        currentTasks: liveTasksInValidLists,
        changes: allChanges,
        dirtyTaskIds: dirtyTasks,
        pendingDeletedTaskRemoteIds: deletedTaskRemotes,
        idGenerator: idGenerator,
      );

      nextTasks = reconciled.tasks;
      if (fullSyncedListIds.isNotEmpty) {
        nextTasks = _pruneStale(
          items: nextTasks,
          shouldKeep: (task) =>
              task.remoteId == null ||
              !fullSyncedListIds.contains(task.listId) ||
              reconciled.seenActiveRemoteIds.contains(task.remoteId) ||
              pruneKeepTasks.contains(task.id),
          onPruned: (removed) => _log.fine(
            'Phase 10b full-sync prune stale local=${removed.id} '
            'remote=${shortSyncId(removed.remoteId)} '
            'title="${removed.title}" list=${removed.listId}',
          ),
        );
      }
    }

    // Commit all delta links atomically at the end of reconciliation.
    final groupsDeltaLink = patch.groupsFetch?.page.deltaLink;
    if (groupsDeltaLink != null) {
      await settings.saveGroupsDeltaLink(groupsDeltaLink);
    }
    final foldersDeltaLink = patch.foldersFetch?.page.deltaLink;
    if (foldersDeltaLink != null) {
      await settings.saveFoldersDeltaLink(foldersDeltaLink);
    }
    final remainingPendingPulls = patch.isSelective
        ? livePendingFolderPulls.difference(patch.pulledFolderRemoteIds)
        : <String>{};
    if (remainingPendingPulls.length != pendingFolderPulls.length ||
        !pendingFolderPulls.containsAll(remainingPendingPulls)) {
      await settings.savePendingTaskFolderPulls(remainingPendingPulls);
    }
    if (patch.taskFetchesByFolderRemoteId.isNotEmpty || !patch.isSelective) {
      await settings.saveTaskDeltaLinks(taskDeltaLinks);
    }

    return FullPullResult(
      groups: nextGroups,
      lists: nextLists,
      tasks: nextTasks,
      settingsPatch: settingsPatch,
    );
  }

  AsyncAppResult<DeltaFetchResult<T>> _fetchDeltaWithMode<T>({
    required String? savedDeltaLink,
    required bool forceFullSync,
    required Future<void> Function() clearDeltaLink,
    required AsyncAppResult<DeltaPageResult<T>> Function(String? deltaLink)
    fetch,
  }) async {
    final effectiveDelta = forceFullSync ? null : savedDeltaLink;
    var recovered410 = false;
    final result = await fetch(effectiveDelta).recover((error) async {
      if (!error.isDeltaExpired || effectiveDelta == null) {
        return Failure<DeltaPageResult<T>, AppError>(error);
      }
      recovered410 = true;
      await clearDeltaLink();
      return fetch(null);
    });
    final mode = forceFullSync
        ? DeltaFetchMode.forcedFull
        : (recovered410
              ? DeltaFetchMode.recovered410
              : (effectiveDelta == null
                    ? DeltaFetchMode.initialFull
                    : DeltaFetchMode.delta));
    return result.map((page) => DeltaFetchResult(page: page, mode: mode));
  }

  List<T> _pruneStale<T>({
    required List<T> items,
    required bool Function(T item) shouldKeep,
    required void Function(T item) onPruned,
  }) {
    final kept = <T>[];
    for (final item in items) {
      if (shouldKeep(item)) {
        kept.add(item);
      } else {
        onPruned(item);
      }
    }
    return kept;
  }
}
