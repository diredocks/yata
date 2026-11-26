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

class MetadataPullResult {
  const MetadataPullResult({
    required this.groups,
    required this.lists,
    required this.settingsPatch,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final SyncedSettingsPatch settingsPatch;
}

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
  final SyncedSettingsPatch settingsPatch;
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

class _DeltaFetchResult<T> {
  const _DeltaFetchResult({required this.page, required this.mode});

  final DeltaPageResult<T> page;
  final DeltaFetchMode mode;

  bool get didFullFetch => mode.isFullFetch;
}

/// Pulls settings, folder groups, folders, and tasks via Substrate v1 delta
/// endpoints with 410 recovery and Outbox protection.
class SubstratePullEngine {
  const SubstratePullEngine(this.todoApi);

  static const int _maxConcurrentFolderFetches = 4;

  final MicrosoftTodoApi todoApi;

  /// Runs an incremental delta pull across settings, groups, folders, and tasks.
  Future<FullPullResult> pullDelta({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<ListGroup> workingGroups,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required SyncOutboxQueue outbox,
    required String Function(String prefix) idGenerator,
  }) async {
    final meta = await _pullMetadata(
      ctx: ctx,
      settings: settings,
      workingGroups: workingGroups,
      workingLists: workingLists,
      outbox: outbox,
      forceFullSync: false,
      idGenerator: idGenerator,
    );
    final validListIds = {for (final l in meta.lists) l.id};
    final liveTasks = workingTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();
    final tasks = await _pullTasks(
      ctx: ctx,
      settings: settings,
      workingLists: meta.lists,
      workingTasks: liveTasks,
      outbox: outbox,
      forceFullSync: false,
      idGenerator: idGenerator,
    );
    return FullPullResult(
      groups: meta.groups,
      lists: meta.lists,
      tasks: tasks,
      settingsPatch: meta.settingsPatch,
    );
  }

  /// Runs a full reset pull across settings, groups, folders, and tasks,
  /// pruning stale local items absent from the server snapshot.
  Future<FullPullResult> pullFull({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<ListGroup> workingGroups,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required SyncOutboxQueue outbox,
    required String Function(String prefix) idGenerator,
    Set<String> justPushedGroupIds = const {},
    Set<String> justPushedListIds = const {},
    Set<String> justPushedTaskIds = const {},
  }) async {
    final meta = await _pullMetadata(
      ctx: ctx,
      settings: settings,
      workingGroups: workingGroups,
      workingLists: workingLists,
      outbox: outbox,
      forceFullSync: true,
      idGenerator: idGenerator,
      justPushedGroupIds: justPushedGroupIds,
      justPushedListIds: justPushedListIds,
    );
    final validListIds = {for (final l in meta.lists) l.id};
    final liveTasks = workingTasks
        .where((t) => validListIds.contains(t.listId))
        .toList();
    final tasks = await _pullTasks(
      ctx: ctx,
      settings: settings,
      workingLists: meta.lists,
      workingTasks: liveTasks,
      outbox: outbox,
      forceFullSync: true,
      idGenerator: idGenerator,
      justPushedTaskIds: justPushedTaskIds,
    );
    return FullPullResult(
      groups: meta.groups,
      lists: meta.lists,
      tasks: tasks,
      settingsPatch: meta.settingsPatch,
    );
  }

  /// Pulls only the flagged folders after a Push pass (no metadata pull).
  Future<List<TaskItem>> pullSelectiveFolders({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required SyncOutboxQueue outbox,
    required String Function(String prefix) idGenerator,
  }) {
    return _pullTasks(
      ctx: ctx,
      settings: settings,
      workingLists: workingLists,
      workingTasks: workingTasks,
      outbox: outbox,
      forceFullSync: false,
      idGenerator: idGenerator,
      onlyFolderRemoteIds: settings.loadPendingTaskFolderPulls(),
    );
  }

  Future<MetadataPullResult> _pullMetadata({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<ListGroup> workingGroups,
    required List<TodoList> workingLists,
    required SyncOutboxQueue outbox,
    required bool forceFullSync,
    required String Function(String prefix) idGenerator,
    Set<String> justPushedGroupIds = const {},
    Set<String> justPushedListIds = const {},
  }) async {
    final pendingSettings = outbox.pendingLocalIds(SyncEntityType.setting);
    final pendingGroups = outbox.pendingLocalIds(SyncEntityType.group);
    final pendingLists = outbox.pendingLocalIds(SyncEntityType.list);
    final pendingDeletedGroupRemotes = outbox.pendingDeletedRemoteIds(
      SyncEntityType.group,
    );
    final pendingDeletedListRemotes = outbox.pendingDeletedRemoteIds(
      SyncEntityType.list,
    );

    // Pull remote settings (skip keys still pending in Outbox).
    final remoteSettings = (await todoApi.getSettings(ctx)).getOrThrow();
    final settingsPatch = buildSyncedSettingsPatchFromWire(
      remoteSettings,
      skipKeys: pendingSettings,
    );

    // Pull folder groups delta.
    final groupsFetch = (await _fetchDeltaWithMode(
      savedDeltaLink: settings.loadGroupsDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => settings.saveGroupsDeltaLink(null),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    )).getOrThrow();
    final groupsDelta = groupsFetch.page;
    if (groupsDelta.deltaLink != null) {
      await settings.saveGroupsDeltaLink(groupsDelta.deltaLink);
    }
    final filteredGroupItems = groupsDelta.items
        .where((g) => !pendingDeletedGroupRemotes.contains(g.id))
        .toList();
    var nextGroups = mergeFolderGroupsDelta(
      localGroups: workingGroups,
      remoteDelta: filteredGroupItems,
      dirtyGroupIds: pendingGroups,
      idGenerator: idGenerator,
    );
    if (forceFullSync && groupsDelta.deltaLink != null) {
      final seenGroupRemoteIds = {
        for (final g in filteredGroupItems)
          if (!g.isDeleted && g.id.isNotEmpty) g.id,
      };
      nextGroups = _pruneStale(
        items: nextGroups,
        shouldKeep: (g) =>
            g.remoteId == null ||
            seenGroupRemoteIds.contains(g.remoteId) ||
            pendingGroups.contains(g.id) ||
            justPushedGroupIds.contains(g.id),
        onPruned: (g) => _log.fine(
          'Phase 8 full-sync prune stale group=${g.id} '
          'remote=${shortSyncId(g.remoteId)} title="${g.title}"',
        ),
      );
    }
    _log.info(
      'Phase 8 groups mode=${groupsFetch.mode.label} '
      'items=${groupsDelta.items.length} '
      'hasDeltaLink=${groupsDelta.deltaLink != null}',
    );

    // Pull folders delta.
    final foldersFetch = (await _fetchDeltaWithMode(
      savedDeltaLink: settings.loadFoldersDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => settings.saveFoldersDeltaLink(null),
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    )).getOrThrow();
    final foldersDelta = foldersFetch.page;
    if (foldersDelta.deltaLink != null) {
      await settings.saveFoldersDeltaLink(foldersDelta.deltaLink);
    }
    final filteredFolderItems = foldersDelta.items
        .where((f) => !pendingDeletedListRemotes.contains(f.id))
        .toList();
    final groupLocalIdByRemoteId = {
      for (final g in nextGroups)
        if (g.remoteId != null) g.remoteId!: g.id,
    };
    var nextLists = mergeFoldersDelta(
      localLists: workingLists,
      remoteDelta: filteredFolderItems,
      dirtyListIds: pendingLists,
      groupLocalIdByRemoteId: groupLocalIdByRemoteId,
      idGenerator: idGenerator,
    );
    if (forceFullSync && foldersDelta.deltaLink != null) {
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
              pendingLists.contains(l.id) ||
              justPushedListIds.contains(l.id),
          onPruned: (l) => _log.fine(
            'Phase 9 full-sync prune stale list=${l.id} '
            'remote=${shortSyncId(l.remoteId)} title="${l.title}"',
          ),
        );
      }
    }
    _log.info(
      'Phase 9 folders mode=${foldersFetch.mode.label} '
      'items=${foldersDelta.items.length} '
      'hasDeltaLink=${foldersDelta.deltaLink != null}',
    );

    return MetadataPullResult(
      groups: nextGroups,
      lists: nextLists,
      settingsPatch: settingsPatch,
    );
  }

  Future<List<TaskItem>> _pullTasks({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<TodoList> workingLists,
    required List<TaskItem> workingTasks,
    required SyncOutboxQueue outbox,
    required bool forceFullSync,
    required String Function(String prefix) idGenerator,
    Set<String>? onlyFolderRemoteIds,
    Set<String> justPushedTaskIds = const {},
  }) async {
    final pendingTasks = outbox.pendingLocalIds(SyncEntityType.task);
    final pendingDeletedTaskRemotes = outbox.pendingDeletedRemoteIds(
      SyncEntityType.task,
    );

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
    final pendingFolderPulls = settings.loadPendingTaskFolderPulls();
    final livePendingFolderPulls = pendingFolderPulls
        .where(localListIdByFolderRemoteId.containsKey)
        .toSet();
    final listTitleByLocalId = {for (final l in workingLists) l.id: l.title};

    final pullFolderRemoteIds = onlyFolderRemoteIds == null
        ? localListIdByFolderRemoteId.keys.toList()
        : [
            for (final folderRemoteId in localListIdByFolderRemoteId.keys)
              if (onlyFolderRemoteIds.contains(folderRemoteId)) folderRemoteId,
          ];
    if (onlyFolderRemoteIds != null) {
      _log.info(
        'Phase 10b selective pull folders=${pullFolderRemoteIds.length} '
        'of=${localListIdByFolderRemoteId.length} '
        'pending=${livePendingFolderPulls.length}',
      );
      if (pullFolderRemoteIds.isEmpty) {
        if (livePendingFolderPulls.length != pendingFolderPulls.length) {
          await settings.savePendingTaskFolderPulls(livePendingFolderPulls);
        }
        return workingTasks;
      }
    }

    final fullSyncedListIds = <String>{};

    final fetches = await mapWithConcurrency(
      pullFolderRemoteIds,
      _maxConcurrentFolderFetches,
      (folderRemoteId) async {
        final fetchResult = await _fetchDeltaWithMode(
          savedDeltaLink: taskDeltaLinks[folderRemoteId],
          forceFullSync: forceFullSync,
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
        return fetchResult.recover((error) {
          if (onlyFolderRemoteIds == null || !error.isNotFound) {
            return Failure<_DeltaFetchResult<RemoteTodoTask>, AppError>(error);
          }
          _log.info(
            'Phase 10b selective pull skipped missing folder '
            'remote=${shortSyncId(folderRemoteId)} error=${error.describe()}',
          );
          return const Success<_DeltaFetchResult<RemoteTodoTask>, AppError>(
            _DeltaFetchResult<RemoteTodoTask>(
              page: DeltaPageResult<RemoteTodoTask>(items: []),
              mode: DeltaFetchMode.missing,
            ),
          );
        }).getOrThrow();
      },
    );

    final allChanges = <RemoteTaskChange>[];
    for (var index = 0; index < pullFolderRemoteIds.length; index++) {
      final folderRemoteId = pullFolderRemoteIds[index];
      final localListId = localListIdByFolderRemoteId[folderRemoteId]!;
      final taskFetch = fetches[index];
      final taskDeltaResult = taskFetch.page;
      final mode = taskFetch.mode;
      final didFullFetch = taskFetch.didFullFetch;

      if (taskDeltaResult.deltaLink != null) {
        taskDeltaLinks[folderRemoteId] = taskDeltaResult.deltaLink!;
      }
      if (forceFullSync && didFullFetch && taskDeltaResult.deltaLink != null) {
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
        'remote=${shortSyncId(folderRemoteId)} mode=${mode.label} '
        'items=${taskDeltaResult.items.length} '
        'hasDeltaLink=${taskDeltaResult.deltaLink != null}',
      );
    }

    final reconciled = reconcileRemoteTaskChanges(
      lists: workingLists,
      currentTasks: workingTasks,
      changes: allChanges,
      dirtyTaskIds: pendingTasks,
      pendingDeletedTaskRemoteIds: pendingDeletedTaskRemotes,
      idGenerator: idGenerator,
    );

    var nextTasks = reconciled.tasks;
    if (fullSyncedListIds.isNotEmpty) {
      nextTasks = _pruneStale(
        items: nextTasks,
        shouldKeep: (task) =>
            task.remoteId == null ||
            !fullSyncedListIds.contains(task.listId) ||
            reconciled.seenActiveRemoteIds.contains(task.remoteId) ||
            pendingTasks.contains(task.id) ||
            justPushedTaskIds.contains(task.id),
        onPruned: (removed) => _log.fine(
          'Phase 10b full-sync prune stale local=${removed.id} '
          'remote=${shortSyncId(removed.remoteId)} '
          'title="${removed.title}" list=${removed.listId}',
        ),
      );
    }

    final pulledFolderRemoteIds = pullFolderRemoteIds.toSet();
    final remainingPendingPulls = onlyFolderRemoteIds == null
        ? <String>{}
        : livePendingFolderPulls.difference(pulledFolderRemoteIds);
    if (remainingPendingPulls.length != pendingFolderPulls.length ||
        !pendingFolderPulls.containsAll(remainingPendingPulls)) {
      await settings.savePendingTaskFolderPulls(remainingPendingPulls);
    }
    await settings.saveTaskDeltaLinks(taskDeltaLinks);
    return nextTasks;
  }

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
        ? DeltaFetchMode.forcedFull
        : (recovered410
              ? DeltaFetchMode.recovered410
              : (effectiveDelta == null
                    ? DeltaFetchMode.initialFull
                    : DeltaFetchMode.delta));
    return result.map((page) => _DeltaFetchResult(page: page, mode: mode));
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
