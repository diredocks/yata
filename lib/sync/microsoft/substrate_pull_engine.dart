import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_repository.dart';
import '../../data/todo_settings_sync.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../sync_concurrency.dart';
import '../sync_log_format.dart';
import 'microsoft_todo_api.dart';
import 'remote_change_reconciler.dart';
import 'substrate_sync_mappers.dart';

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
    required TodoRepository repository,
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
        repository: repository,
        knownFolderRemoteIds: knownFolderRemoteIds,
        isCancelled: cancelled,
      );
    }

    return _fetchFullOrDeltaPatch(
      ctx: ctx,
      repository: repository,
      knownFolderRemoteIds: knownFolderRemoteIds,
      forceFullSync: forceFullSync,
      isCancelled: cancelled,
    );
  }

  AsyncAppResult<PullPatchFetch> _fetchSelectivePatch({
    required SubstrateRequestContext ctx,
    required TodoRepository repository,
    required Set<String> knownFolderRemoteIds,
    required bool Function() isCancelled,
  }) async {
    final pendingPulls = repository.loadPendingTaskFolderPulls();
    final targetFolderRemoteIds = knownFolderRemoteIds
        .where(pendingPulls.contains)
        .toSet();
    _log.info(
      'pull selective folders=${targetFolderRemoteIds.length} '
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
      repository: repository,
      targetFolderRemoteIds: targetFolderRemoteIds,
      forceFullSync: false,
      isSelective: true,
      isCancelled: isCancelled,
    );
  }

  AsyncAppResult<PullPatchFetch> _fetchFullOrDeltaPatch({
    required SubstrateRequestContext ctx,
    required TodoRepository repository,
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
      savedDeltaLink: repository.loadGroupsDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => repository.saveGroupsDeltaLink(null),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    );
    if (groupsResult.isError()) return Failure(groupsResult.exceptionOrNull()!);
    if (isCancelled()) return const Success(PullPatchCancelled());

    final groupsFetch = groupsResult.getOrNull()!;
    _log.info(
      'pull groups mode=${groupsFetch.mode.label} '
      'items=${groupsFetch.page.items.length} '
      'hasDeltaLink=${groupsFetch.page.deltaLink != null}',
    );

    final foldersResult = await _fetchDeltaWithMode(
      savedDeltaLink: repository.loadFoldersDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => repository.saveFoldersDeltaLink(null),
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    );
    if (foldersResult.isError()) {
      return Failure(foldersResult.exceptionOrNull()!);
    }
    if (isCancelled()) return const Success(PullPatchCancelled());

    final foldersFetch = foldersResult.getOrNull()!;
    final foldersPage = foldersFetch.page;
    _log.info(
      'pull folders mode=${foldersFetch.mode.label} '
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
      repository: repository,
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
    final activeRemoteIds = {
      for (final f in foldersPage.items)
        if (!f.isDeleted && !f.isIgnoredSpecialFolder && f.id.isNotEmpty) f.id,
    };
    final deletedRemoteIds = {
      for (final f in foldersPage.items)
        if (f.isDeleted && f.id.isNotEmpty) f.id,
    };
    if (forceFullSync &&
        foldersPage.deltaLink != null &&
        activeRemoteIds.isNotEmpty) {
      return activeRemoteIds;
    }
    return {
      ...knownFolderRemoteIds.difference(deletedRemoteIds),
      ...activeRemoteIds,
    };
  }

  AsyncAppResult<PullPatchFetch> _fetchTaskDeltas({
    required SubstrateRequestContext ctx,
    required TodoRepository repository,
    required Set<String> targetFolderRemoteIds,
    required bool forceFullSync,
    required bool isSelective,
    required bool Function() isCancelled,
    Map<String, String>? remoteSettings,
    DeltaFetchResult<RemoteFolderGroup>? groupsFetch,
    DeltaFetchResult<RemoteTodoFolder>? foldersFetch,
  }) async {
    final savedTaskDeltaLinks = repository.loadTaskDeltaLinks();
    final folderList = targetFolderRemoteIds.toList(growable: false);

    final fetchesResult = await mapResultsWithConcurrency(
      folderList,
      _maxConcurrentFolderFetches,
      (folderRemoteId) => _fetchSingleFolderTasks(
        ctx: ctx,
        repository: repository,
        folderRemoteId: folderRemoteId,
        savedDeltaLink: savedTaskDeltaLinks[folderRemoteId],
        forceFullSync: forceFullSync,
        isSelective: isSelective,
      ),
      shouldStop: isCancelled,
    );

    if (isCancelled()) return const Success(PullPatchCancelled());

    return fetchesResult.map((fetches) {
      final taskFetches =
          Map<String, DeltaFetchResult<RemoteTodoTask>>.fromIterables(
            folderList,
            fetches,
          );
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
    required TodoRepository repository,
    required String folderRemoteId,
    required String? savedDeltaLink,
    required bool forceFullSync,
    required bool isSelective,
  }) async {
    final fetchResult = await _fetchDeltaWithMode(
      savedDeltaLink: savedDeltaLink,
      forceFullSync: forceFullSync,
      clearDeltaLink: () async {
        final next = Map<String, String>.from(repository.loadTaskDeltaLinks())
          ..remove(folderRemoteId);
        await repository.saveTaskDeltaLinks(next);
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
        'pull selective skipped missing folder '
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
  /// commits the resulting `deltaLink`s to [repository].
  Future<FullPullResult> applyPatch({
    required RemotePullPatch patch,
    required TodoRepository repository,
    required List<ListGroup> liveGroups,
    required List<TodoList> liveLists,
    required List<TaskItem> liveTasks,
    required SyncOutboxQueue outbox,
    required String Function(String prefix) idGenerator,
    required int pullStartSeq,
    required int pruneProtectSinceSeq,
  }) async {
    final protection = outbox.capturePullProtection(
      pullStartSeq: pullStartSeq,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    );

    final settingsPatch = !patch.isSelective && patch.remoteSettings != null
        ? buildSyncedSettingsPatchFromWire(
            patch.remoteSettings!,
            skipKeys: protection.dirtySettings,
          )
        : null;

    final nextGroups = patch.isSelective
        ? liveGroups
        : _applyGroupsDelta(
            patch: patch,
            liveGroups: liveGroups,
            protection: protection,
            idGenerator: idGenerator,
          );

    final nextLists = patch.isSelective
        ? liveLists
        : _applyFoldersDelta(
            patch: patch,
            liveLists: liveLists,
            nextGroups: nextGroups,
            protection: protection,
            idGenerator: idGenerator,
          );

    final localListIdByFolderRemoteId = {
      for (final l in nextLists)
        if (l.remoteId != null) l.remoteId!: l.id,
    };
    final taskDeltaLinks = Map<String, String>.from(
      repository.loadTaskDeltaLinks(),
    )..removeWhere((id, _) => !localListIdByFolderRemoteId.containsKey(id));

    final validListIds = {for (final l in nextLists) l.id};
    final liveTasksInValidLists = liveTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();

    final nextTasks = _applyTaskDeltas(
      patch: patch,
      nextLists: nextLists,
      liveTasksInValidLists: liveTasksInValidLists,
      localListIdByFolderRemoteId: localListIdByFolderRemoteId,
      taskDeltaLinks: taskDeltaLinks,
      protection: protection,
      idGenerator: idGenerator,
    );

    await _commitDeltaLinks(
      patch: patch,
      repository: repository,
      localListIdByFolderRemoteId: localListIdByFolderRemoteId,
      taskDeltaLinks: taskDeltaLinks,
    );

    return FullPullResult(
      groups: nextGroups,
      lists: nextLists,
      tasks: nextTasks,
      settingsPatch: settingsPatch,
    );
  }

  List<ListGroup> _applyGroupsDelta({
    required RemotePullPatch patch,
    required List<ListGroup> liveGroups,
    required OutboxPullProtection protection,
    required String Function(String prefix) idGenerator,
  }) {
    final groupsDelta = patch.groupsFetch?.page;
    if (groupsDelta == null) return liveGroups;

    final filteredItems = groupsDelta.items
        .whereNot((g) => protection.deletedGroupRemotes.contains(g.id))
        .toList();
    final merged = mergeFolderGroupsDelta(
      localGroups: liveGroups,
      remoteDelta: filteredItems,
      dirtyGroupIds: protection.dirtyGroups,
      idGenerator: idGenerator,
    );
    if (!patch.forceFullSync || groupsDelta.deltaLink == null) return merged;

    final seenRemoteIds = {
      for (final g in filteredItems)
        if (!g.isDeleted && g.id.isNotEmpty) g.id,
    };
    return _pruneStale(
      items: merged,
      shouldKeep: (g) =>
          g.remoteId == null ||
          seenRemoteIds.contains(g.remoteId) ||
          protection.pruneKeepGroups.contains(g.id),
      onPruned: (g) => _log.fine(
        'pull full-sync prune stale group=${g.id} '
        'remote=${shortSyncId(g.remoteId)} title="${g.title}"',
      ),
    );
  }

  List<TodoList> _applyFoldersDelta({
    required RemotePullPatch patch,
    required List<TodoList> liveLists,
    required List<ListGroup> nextGroups,
    required OutboxPullProtection protection,
    required String Function(String prefix) idGenerator,
  }) {
    final foldersDelta = patch.foldersFetch?.page;
    if (foldersDelta == null) return liveLists;

    final filteredItems = foldersDelta.items
        .whereNot((f) => protection.deletedListRemotes.contains(f.id))
        .toList();
    final groupLocalIdByRemoteId = {
      for (final g in nextGroups)
        if (g.remoteId != null) g.remoteId!: g.id,
    };
    final merged = mergeFoldersDelta(
      localLists: liveLists,
      remoteDelta: filteredItems,
      dirtyListIds: protection.dirtyLists,
      groupLocalIdByRemoteId: groupLocalIdByRemoteId,
      idGenerator: idGenerator,
    );
    if (!patch.forceFullSync || foldersDelta.deltaLink == null) return merged;

    final seenRemoteIds = {
      for (final f in filteredItems)
        if (!f.isDeleted && !f.isIgnoredSpecialFolder && f.id.isNotEmpty) f.id,
    };
    if (seenRemoteIds.isEmpty) return merged;

    return _pruneStale(
      items: merged,
      shouldKeep: (l) =>
          l.isSmartList ||
          l.remoteId == null ||
          seenRemoteIds.contains(l.remoteId) ||
          protection.pruneKeepLists.contains(l.id),
      onPruned: (l) => _log.fine(
        'pull full-sync prune stale list=${l.id} '
        'remote=${shortSyncId(l.remoteId)} title="${l.title}"',
      ),
    );
  }

  List<TaskItem> _applyTaskDeltas({
    required RemotePullPatch patch,
    required List<TodoList> nextLists,
    required List<TaskItem> liveTasksInValidLists,
    required Map<String, String> localListIdByFolderRemoteId,
    required Map<String, String> taskDeltaLinks,
    required OutboxPullProtection protection,
    required String Function(String prefix) idGenerator,
  }) {
    if (patch.taskFetchesByFolderRemoteId.isEmpty) return liveTasksInValidLists;

    final listTitleByLocalId = {for (final l in nextLists) l.id: l.title};
    final fullSyncedListIds = <String>{};
    final allChanges = <RemoteTaskChange>[];

    for (final MapEntry(key: folderRemoteId, value: taskFetch)
        in patch.taskFetchesByFolderRemoteId.entries) {
      final localListId = localListIdByFolderRemoteId[folderRemoteId];
      if (localListId == null) continue;
      final taskDeltaResult = taskFetch.page;
      if (taskDeltaResult.deltaLink != null) {
        taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
      }
      if (patch.forceFullSync &&
          taskFetch.didFullFetch &&
          taskDeltaResult.deltaLink != null) {
        fullSyncedListIds.add(localListId);
      }
      allChanges.addAll(
        taskDeltaResult.items.map(
          (remote) => (
            remote: remote,
            fallbackLocalListId: localListId,
            preserveStepsWhenMissing: false,
            preserveAttachmentsWhenMissing: false,
          ),
        ),
      );
      _log.info(
        'pull folder="${listTitleByLocalId[localListId] ?? localListId}" '
        'remote=${shortSyncId(folderRemoteId)} mode=${taskFetch.mode.label} '
        'items=${taskDeltaResult.items.length} '
        'hasDeltaLink=${taskDeltaResult.deltaLink != null}',
      );
    }

    final reconciled = reconcileRemoteTaskChanges(
      lists: nextLists,
      currentTasks: liveTasksInValidLists,
      changes: allChanges,
      dirtyTaskIds: protection.dirtyTasks,
      pendingDeletedTaskRemoteIds: protection.deletedTaskRemotes,
      idGenerator: idGenerator,
    );

    if (fullSyncedListIds.isEmpty) return reconciled.tasks;
    return _pruneStale(
      items: reconciled.tasks,
      shouldKeep: (task) =>
          task.remoteId == null ||
          !fullSyncedListIds.contains(task.listId) ||
          reconciled.seenActiveRemoteIds.contains(task.remoteId) ||
          protection.pruneKeepTasks.contains(task.id),
      onPruned: (removed) => _log.fine(
        'pull full-sync prune stale local=${removed.id} '
        'remote=${shortSyncId(removed.remoteId)} '
        'title="${removed.title}" list=${removed.listId}',
      ),
    );
  }

  Future<void> _commitDeltaLinks({
    required RemotePullPatch patch,
    required TodoRepository repository,
    required Map<String, String> localListIdByFolderRemoteId,
    required Map<String, String> taskDeltaLinks,
  }) async {
    final groupsDeltaLink = patch.groupsFetch?.page.deltaLink;
    final foldersDeltaLink = patch.foldersFetch?.page.deltaLink;
    final pendingFolderPulls = repository.loadPendingTaskFolderPulls();
    final livePendingFolderPulls = pendingFolderPulls
        .where(localListIdByFolderRemoteId.containsKey)
        .toSet();
    final remainingPendingPulls = patch.isSelective
        ? livePendingFolderPulls.difference(patch.pulledFolderRemoteIds)
        : <String>{};
    final pendingPullsChanged = !const SetEquality<String>().equals(
      pendingFolderPulls,
      remainingPendingPulls,
    );
    final updateTaskDeltaLinks =
        patch.taskFetchesByFolderRemoteId.isNotEmpty || !patch.isSelective;

    await repository.saveSyncMetaBatch(
      groupsDeltaLink: groupsDeltaLink,
      updateGroupsDeltaLink: groupsDeltaLink != null,
      foldersDeltaLink: foldersDeltaLink,
      updateFoldersDeltaLink: foldersDeltaLink != null,
      taskDeltaLinks: updateTaskDeltaLinks ? taskDeltaLinks : null,
      pendingTaskFolderPulls: pendingPullsChanged
          ? remainingPendingPulls
          : null,
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
