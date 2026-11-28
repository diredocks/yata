import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/storage/todo_repository.dart';
import '../../data/state/todo_state.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../../core/network/http_guard.dart';
import 'microsoft_todo_api.dart';
import 'remote_change_reconciler.dart';

final _log = appLogFor('SyncEngine');

/// Result returned by a completed [SubstratePullEngine.pull] pass.
class PullOutcome {
  const PullOutcome({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.syncedAt,
    this.remoteSettings,
    this.isSelective = false,
    this.cancelled = false,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;

  /// Null when the pass was selective or cancelled without settings.
  final Map<String, String>? remoteSettings;
  final DateTime syncedAt;
  final bool isSelective;
  final bool cancelled;
}

enum _DeltaFetchMode {
  forcedFull('full(forced)', isFullFetch: true),
  recovered410('full(410)', isFullFetch: true),
  initialFull('full(initial)', isFullFetch: true),
  delta('delta', isFullFetch: false),
  missing('missing', isFullFetch: false);

  const _DeltaFetchMode(this.label, {required this.isFullFetch});

  final String label;
  final bool isFullFetch;
}

class _DeltaFetchResult<T> {
  const _DeltaFetchResult({required this.page, required this.mode});

  final DeltaPageResult<T> page;
  final _DeltaFetchMode mode;

  bool get didFullFetch => mode.isFullFetch;
}

sealed class _PullFetch {
  const _PullFetch();
}

final class _PullCancelled extends _PullFetch {
  const _PullCancelled();
}

final class _RemotePullPatch extends _PullFetch {
  const _RemotePullPatch({
    required this.forceFullSync,
    required this.isSelective,
    this.remoteSettings,
    this.groupsFetch,
    this.foldersFetch,
    this.taskFetchesByFolderRemoteId = const {},
  });

  final bool forceFullSync;
  final bool isSelective;
  final Map<String, String>? remoteSettings;
  final _DeltaFetchResult<RemoteFolderGroup>? groupsFetch;
  final _DeltaFetchResult<RemoteTodoFolder>? foldersFetch;
  final Map<String, _DeltaFetchResult<RemoteTodoTask>>
  taskFetchesByFolderRemoteId;
}

/// Stateless remote fetcher & patch reconciler for Substrate v1 delta endpoints.
///
/// Network fetches never hold local entity snapshots and never advance saved
/// `deltaLink`s until reconciliation commits synchronously against live state.
class SubstratePullEngine {
  const SubstratePullEngine(this.todoApi);

  static const int _maxConcurrentFolderFetches = 4;

  final MicrosoftTodoApi todoApi;

  /// Fetches remote settings, groups, folders, and/or tasks (or just
  /// [onlyFolderRemoteIds] when performing a selective follow-up pull), then
  /// reconciles them against the latest live state.
  AsyncAppResult<PullOutcome> pull({
    required TodoRepository repository,
    required TodoState Function() readState,
    required String Function(String prefix) idGenerator,
    Future<void> Function(PullOutcome outcome)? onReconciled,
    bool forceFullSync = false,
    Set<String>? onlyFolderRemoteIds,
    bool Function()? isCancelled,
    int? pruneProtectSinceSeq,
    String reason = 'pull',
  }) async {
    final outbox = repository.outbox;
    final pullStartSeq = outbox.lastSeq;
    final effectivePruneSeq = pruneProtectSinceSeq ?? pullStartSeq;
    final startState = readState();
    final isSelective = onlyFolderRemoteIds != null;

    bool cancelled() => isCancelled?.call() == true;

    PullOutcome cancelledOutcome() {
      final live = readState();
      _log.info('pull cancelled reason=$reason');
      return PullOutcome(
        groups: live.groups,
        lists: live.lists,
        tasks: live.tasks,
        syncedAt: DateTime.now().toUtc(),
        isSelective: isSelective,
        cancelled: true,
      );
    }

    if (cancelled()) return Success(cancelledOutcome());

    _log.info(
      'pull start reason=$reason '
      'mode=${isSelective ? 'selective' : (forceFullSync ? 'full' : 'delta')} '
      'localLists=${startState.lists.length} '
      'localTasks=${startState.tasks.length}',
    );

    final knownFolderRemoteIds = <String>{
      for (final l in startState.lists)
        if (l.remoteId != null) l.remoteId!,
    };

    final AppResult<_PullFetch> fetchResult;
    if (isSelective) {
      fetchResult = await _fetchSelectivePatch(
        repository: repository,
        knownFolderRemoteIds: knownFolderRemoteIds,
        onlyFolderRemoteIds: onlyFolderRemoteIds,
        isCancelled: cancelled,
      );
    } else {
      fetchResult = await _fetchFullOrDeltaPatch(
        repository: repository,
        knownFolderRemoteIds: knownFolderRemoteIds,
        forceFullSync: forceFullSync,
        isCancelled: cancelled,
      );
    }

    if (fetchResult.isError()) {
      return Failure(fetchResult.exceptionOrNull()!);
    }
    final fetched = fetchResult.getOrNull()!;
    if (fetched is! _RemotePullPatch || cancelled()) {
      return Success(cancelledOutcome());
    }
    final patch = fetched;

    if (patch.isSelective && patch.taskFetchesByFolderRemoteId.isEmpty) {
      final liveState = readState();
      return Success(
        PullOutcome(
          groups: liveState.groups,
          lists: liveState.lists,
          tasks: liveState.tasks,
          syncedAt: DateTime.now().toUtc(),
          isSelective: true,
        ),
      );
    }

    return _applyPatch(
      patch: patch,
      repository: repository,
      readState: readState,
      idGenerator: idGenerator,
      pullStartSeq: pullStartSeq,
      pruneProtectSinceSeq: effectivePruneSeq,
      onReconciled: onReconciled,
    );
  }

  AsyncAppResult<_PullFetch> _fetchSelectivePatch({
    required TodoRepository repository,
    required Set<String> knownFolderRemoteIds,
    required Set<String> onlyFolderRemoteIds,
    required bool Function() isCancelled,
  }) async {
    final targetFolderRemoteIds = knownFolderRemoteIds.intersection(
      onlyFolderRemoteIds,
    );
    _log.info(
      'pull selective folders=${targetFolderRemoteIds.length} '
      'of=${knownFolderRemoteIds.length}',
    );
    if (targetFolderRemoteIds.isEmpty) {
      return const Success(
        _RemotePullPatch(forceFullSync: false, isSelective: true),
      );
    }
    return _fetchTaskDeltas(
      repository: repository,
      targetFolderRemoteIds: targetFolderRemoteIds,
      forceFullSync: false,
      isSelective: true,
      isCancelled: isCancelled,
    );
  }

  AsyncAppResult<_PullFetch> _fetchFullOrDeltaPatch({
    required TodoRepository repository,
    required Set<String> knownFolderRemoteIds,
    required bool forceFullSync,
    required bool Function() isCancelled,
  }) async {
    final settingsResult = await todoApi.getSettings();
    if (settingsResult.isError()) {
      return Failure(settingsResult.exceptionOrNull()!);
    }
    if (isCancelled()) return const Success(_PullCancelled());

    final groupsResult = await _fetchDeltaWithMode(
      savedDeltaLink: repository.loadGroupsDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => repository.saveSyncMetaBatch(
        groupsDeltaLink: null,
        updateGroupsDeltaLink: true,
      ),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(deltaLink: dl),
    );
    if (groupsResult.isError()) return Failure(groupsResult.exceptionOrNull()!);
    if (isCancelled()) return const Success(_PullCancelled());

    final groupsFetch = groupsResult.getOrNull()!;
    _log.info(
      'pull groups mode=${groupsFetch.mode.label} '
      'items=${groupsFetch.page.items.length} '
      'hasDeltaLink=${groupsFetch.page.deltaLink != null}',
    );

    final foldersResult = await _fetchDeltaWithMode(
      savedDeltaLink: repository.loadFoldersDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => repository.saveSyncMetaBatch(
        foldersDeltaLink: null,
        updateFoldersDeltaLink: true,
      ),
      fetch: (dl) => todoApi.fetchFoldersDelta(deltaLink: dl),
    );
    if (foldersResult.isError()) {
      return Failure(foldersResult.exceptionOrNull()!);
    }
    if (isCancelled()) return const Success(_PullCancelled());

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

  AsyncAppResult<_PullFetch> _fetchTaskDeltas({
    required TodoRepository repository,
    required Set<String> targetFolderRemoteIds,
    required bool forceFullSync,
    required bool isSelective,
    required bool Function() isCancelled,
    Map<String, String>? remoteSettings,
    _DeltaFetchResult<RemoteFolderGroup>? groupsFetch,
    _DeltaFetchResult<RemoteTodoFolder>? foldersFetch,
  }) async {
    final savedTaskDeltaLinks = repository.loadTaskDeltaLinks();
    final folderList = targetFolderRemoteIds.toList(growable: false);

    final fetchesResult = await mapResultsWithConcurrency(
      folderList,
      _maxConcurrentFolderFetches,
      (folderRemoteId) => _fetchSingleFolderTasks(
        repository: repository,
        folderRemoteId: folderRemoteId,
        savedDeltaLink: savedTaskDeltaLinks[folderRemoteId],
        forceFullSync: forceFullSync,
        isSelective: isSelective,
      ),
      shouldStop: isCancelled,
    );

    if (isCancelled()) return const Success(_PullCancelled());

    return fetchesResult.map((fetches) {
      final taskFetches =
          Map<String, _DeltaFetchResult<RemoteTodoTask>>.fromIterables(
            folderList,
            fetches,
          );
      return _RemotePullPatch(
        forceFullSync: forceFullSync,
        isSelective: isSelective,
        remoteSettings: remoteSettings,
        groupsFetch: groupsFetch,
        foldersFetch: foldersFetch,
        taskFetchesByFolderRemoteId: taskFetches,
      );
    });
  }

  AsyncAppResult<_DeltaFetchResult<RemoteTodoTask>> _fetchSingleFolderTasks({
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
        await repository.saveSyncMetaBatch(taskDeltaLinks: next);
      },
      fetch: (dl) => todoApi.fetchTasksDelta(
        folderRemoteId: folderRemoteId,
        deltaLink: dl,
      ),
    );
    return fetchResult.recover((error) {
      if (!isSelective || !error.isNotFound) {
        return Failure<_DeltaFetchResult<RemoteTodoTask>, AppError>(error);
      }
      _log.info(
        'pull selective skipped missing folder '
        'remote=${shortSyncId(folderRemoteId)} error=${error.describe()}',
      );
      return const Success<_DeltaFetchResult<RemoteTodoTask>, AppError>(
        _DeltaFetchResult<RemoteTodoTask>(
          page: DeltaPageResult<RemoteTodoTask>(items: []),
          mode: _DeltaFetchMode.missing,
        ),
      );
    });
  }

  AsyncAppResult<PullOutcome> _applyPatch({
    required _RemotePullPatch patch,
    required TodoRepository repository,
    required TodoState Function() readState,
    required String Function(String prefix) idGenerator,
    required int pullStartSeq,
    required int pruneProtectSinceSeq,
    Future<void> Function(PullOutcome outcome)? onReconciled,
  }) => guardApiCall(() async {
    final liveState = readState();
    final outbox = repository.outbox;
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
      liveGroups: liveState.groups,
      liveLists: liveState.lists,
      liveTasks: liveState.tasks,
      protection: protection,
      idGenerator: idGenerator,
      deferDirtyDeletes: patch.isSelective,
    );

    final finalGroups = reconciled.groups ?? liveState.groups;
    final finalLists = reconciled.lists ?? liveState.lists;
    final finalTasks = reconciled.tasks ?? liveState.tasks;

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
      final hasDeferredDirtyDelete = reconciled.deferredDeleteFolderRemoteIds
          .contains(folderRemoteId);
      if (taskDeltaResult.deltaLink != null && !hasDeferredDirtyDelete) {
        taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
      } else if (hasDeferredDirtyDelete) {
        _log.info(
          'pull folder="${listTitleByLocalId[localListId] ?? localListId}" '
          'remote=${shortSyncId(folderRemoteId)} withheld deltaLink due to '
          'deferred dirty delete',
        );
      }
      _log.info(
        'pull folder="${listTitleByLocalId[localListId] ?? localListId}" '
        'remote=${shortSyncId(folderRemoteId)} mode=${taskFetch.mode.label} '
        'items=${taskDeltaResult.items.length} '
        'hasDeltaLink=${taskDeltaResult.deltaLink != null}',
      );
    }

    final outcome = PullOutcome(
      groups: finalGroups,
      lists: finalLists,
      tasks: finalTasks,
      remoteSettings: reconciled.remoteSettings,
      syncedAt: DateTime.now().toUtc(),
      isSelective: patch.isSelective,
    );

    final applyFuture = onReconciled?.call(outcome);
    final groupsDeltaLink = patch.groupsFetch?.page.deltaLink;
    final foldersDeltaLink = patch.foldersFetch?.page.deltaLink;
    final metaFuture = repository.saveSyncMetaBatch(
      groupsDeltaLink: groupsDeltaLink,
      updateGroupsDeltaLink: groupsDeltaLink != null,
      foldersDeltaLink: foldersDeltaLink,
      updateFoldersDeltaLink: foldersDeltaLink != null,
      taskDeltaLinks:
          patch.taskFetchesByFolderRemoteId.isNotEmpty || !patch.isSelective
          ? taskDeltaLinks
          : null,
    );
    if (applyFuture != null) await applyFuture;
    await metaFuture;

    return outcome;
  }, operation: 'applyPullPatch');

  AsyncAppResult<_DeltaFetchResult<T>> _fetchDeltaWithMode<T>({
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
        ? _DeltaFetchMode.forcedFull
        : (recovered410
              ? _DeltaFetchMode.recovered410
              : (effectiveDelta == null
                    ? _DeltaFetchMode.initialFull
                    : _DeltaFetchMode.delta));
    return result.map((page) => _DeltaFetchResult(page: page, mode: mode));
  }
}
