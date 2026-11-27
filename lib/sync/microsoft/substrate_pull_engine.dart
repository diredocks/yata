import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_repository.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../sync_concurrency.dart';
import '../sync_log_format.dart';
import 'microsoft_todo_api.dart';
import 'remote_change_reconciler.dart';

final _log = appLogFor('SyncEngine');

class FullPullResult {
  const FullPullResult({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.remoteSettings,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final Map<String, String>? remoteSettings;
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

    final taskChanges = <RemoteTaskChange>[];
    final fullSyncedFolderRemoteIds = <String>{};
    for (final MapEntry(key: folderRemoteId, value: taskFetch)
        in patch.taskFetchesByFolderRemoteId.entries) {
      final taskDeltaResult = taskFetch.page;
      if (patch.forceFullSync &&
          taskFetch.didFullFetch &&
          taskDeltaResult.deltaLink != null) {
        fullSyncedFolderRemoteIds.add(folderRemoteId);
      }
      for (final remote in taskDeltaResult.items) {
        taskChanges.add((
          remote: remote,
          fallbackFolderRemoteId: folderRemoteId,
          preserveStepsWhenMissing: false,
          preserveAttachmentsWhenMissing: false,
        ));
      }
    }

    final delta = RemoteDelta(
      groups: patch.isSelective
          ? const []
          : (patch.groupsFetch?.page.items ?? const []),
      folders: patch.isSelective
          ? const []
          : (patch.foldersFetch?.page.items ?? const []),
      tasks: taskChanges,
      remoteSettings: patch.isSelective ? null : patch.remoteSettings,
      pruneGroups:
          !patch.isSelective &&
          patch.forceFullSync &&
          patch.groupsFetch?.page.deltaLink != null,
      pruneFolders:
          !patch.isSelective &&
          patch.forceFullSync &&
          patch.foldersFetch?.page.deltaLink != null,
      fullSyncedFolderRemoteIds: fullSyncedFolderRemoteIds,
    );

    final reconciled = reconcileRemoteDelta(
      delta: delta,
      liveGroups: liveGroups,
      liveLists: liveLists,
      liveTasks: liveTasks,
      protection: protection,
      idGenerator: idGenerator,
    );

    final finalGroups = reconciled.groups ?? liveGroups;
    final finalLists = reconciled.lists ?? liveLists;
    final finalTasks = reconciled.tasks ?? liveTasks;

    final localListIdByFolderRemoteId = {
      for (final l in finalLists)
        if (l.remoteId != null) l.remoteId!: l.id,
    };
    final listTitleByLocalId = {for (final l in finalLists) l.id: l.title};
    final taskDeltaLinks = Map<String, String>.from(
      repository.loadTaskDeltaLinks(),
    )..removeWhere((id, _) => !localListIdByFolderRemoteId.containsKey(id));

    for (final MapEntry(key: folderRemoteId, value: taskFetch)
        in patch.taskFetchesByFolderRemoteId.entries) {
      final localListId = localListIdByFolderRemoteId[folderRemoteId];
      if (localListId == null) continue;
      final taskDeltaResult = taskFetch.page;
      if (taskDeltaResult.deltaLink != null) {
        taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
      }
      _log.info(
        'pull folder="${listTitleByLocalId[localListId] ?? localListId}" '
        'remote=${shortSyncId(folderRemoteId)} mode=${taskFetch.mode.label} '
        'items=${taskDeltaResult.items.length} '
        'hasDeltaLink=${taskDeltaResult.deltaLink != null}',
      );
    }

    await _commitDeltaLinks(
      patch: patch,
      repository: repository,
      localListIdByFolderRemoteId: localListIdByFolderRemoteId,
      taskDeltaLinks: taskDeltaLinks,
    );

    return FullPullResult(
      groups: finalGroups,
      lists: finalLists,
      tasks: finalTasks,
      remoteSettings: reconciled.remoteSettings,
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
}
