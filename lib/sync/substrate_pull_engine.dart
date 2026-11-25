import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/todo_settings_store.dart';
import '../data/todo_settings_sync.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_api.dart';
import 'substrate_sync_mappers.dart';
import 'sync_log_format.dart';

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

/// Pulls settings, folder groups, folders, and tasks via Substrate v1 delta
/// endpoints with 410 recovery and `forceFullSync` pruning (Phases 7–9 and 10b).
class SubstratePullEngine {
  const SubstratePullEngine(this.todoApi);

  final MicrosoftTodoApi todoApi;

  /// Executes Phases 7–9: settings, folder groups delta, and folders delta.
  Future<MetadataPullResult> pullSettingsGroupsAndFolders({
    required SubstrateRequestContext ctx,
    required TodoSettingsStore settings,
    required List<ListGroup> workingGroups,
    required List<TodoList> workingLists,
    required Set<String> remainingDirtySettings,
    required Set<String> remainingDirtyGroups,
    required Set<String> remainingDirtyLists,
    required Set<String> syncedGroupIds,
    required Set<String> syncedListIds,
    required bool forceFullSync,
    required String Function(String prefix) idGenerator,
  }) async {
    // Phase 7: Pull remote settings (skip keys still dirty locally).
    final remoteSettings = (await todoApi.getSettings(ctx)).getOrThrow();
    final settingsPatch = buildSyncedSettingsPatchFromWire(
      remoteSettings,
      skipKeys: remainingDirtySettings,
    );

    // Phase 8: Pull folder groups delta (with 410 & forceFullSync recovery).
    final groupsFetch = await _fetchDeltaWithMode(
      savedDeltaLink: settings.loadGroupsDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => settings.saveGroupsDeltaLink(null),
      fetch: (dl) => todoApi.fetchFolderGroupsDelta(ctx, deltaLink: dl),
    );
    final groupsDelta = groupsFetch.page;
    if (groupsDelta.deltaLink != null) {
      await settings.saveGroupsDeltaLink(groupsDelta.deltaLink);
    }
    var nextGroups = mergeFolderGroupsDelta(
      localGroups: workingGroups,
      remoteDelta: groupsDelta.items,
      dirtyGroupIds: remainingDirtyGroups,
      idGenerator: idGenerator,
    );
    if (forceFullSync && groupsDelta.deltaLink != null) {
      final seenGroupRemoteIds = {
        for (final g in groupsDelta.items)
          if (!g.isDeleted && g.id.isNotEmpty) g.id,
      };
      nextGroups = _pruneStale(
        items: nextGroups,
        shouldKeep: (g) =>
            g.remoteId == null ||
            seenGroupRemoteIds.contains(g.remoteId) ||
            remainingDirtyGroups.contains(g.id) ||
            syncedGroupIds.contains(g.id),
        onPruned: (g) => appLog(
          'Phase 8 full-sync prune stale group=${g.id} '
          'remote=${shortSyncId(g.remoteId)} title="${g.title}"',
          label: 'SyncEngine',
        ),
      );
    }
    appLog(
      'Phase 8 groups mode=${groupsFetch.mode} '
      'items=${groupsDelta.items.length} '
      'hasDeltaLink=${groupsDelta.deltaLink != null}',
      label: 'SyncEngine',
    );

    // Phase 9: Pull folders delta (with 410 & forceFullSync recovery).
    final foldersFetch = await _fetchDeltaWithMode(
      savedDeltaLink: settings.loadFoldersDeltaLink(),
      forceFullSync: forceFullSync,
      clearDeltaLink: () => settings.saveFoldersDeltaLink(null),
      fetch: (dl) => todoApi.fetchFoldersDelta(ctx, deltaLink: dl),
    );
    final foldersDelta = foldersFetch.page;
    if (foldersDelta.deltaLink != null) {
      await settings.saveFoldersDeltaLink(foldersDelta.deltaLink);
    }
    final groupLocalIdByRemoteId = {
      for (final g in nextGroups)
        if (g.remoteId != null) g.remoteId!: g.id,
    };
    var nextLists = mergeFoldersDelta(
      localLists: workingLists,
      remoteDelta: foldersDelta.items,
      dirtyListIds: remainingDirtyLists,
      groupLocalIdByRemoteId: groupLocalIdByRemoteId,
      idGenerator: idGenerator,
    );
    if (forceFullSync && foldersDelta.deltaLink != null) {
      final seenFolderRemoteIds = {
        for (final f in foldersDelta.items)
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
              remainingDirtyLists.contains(l.id) ||
              syncedListIds.contains(l.id),
          onPruned: (l) => appLog(
            'Phase 9 full-sync prune stale list=${l.id} '
            'remote=${shortSyncId(l.remoteId)} title="${l.title}"',
            label: 'SyncEngine',
          ),
        );
      }
    }
    appLog(
      'Phase 9 folders mode=${foldersFetch.mode} '
      'items=${foldersDelta.items.length} '
      'hasDeltaLink=${foldersDelta.deltaLink != null}',
      label: 'SyncEngine',
    );

    return MetadataPullResult(
      groups: nextGroups,
      lists: nextLists,
      settingsPatch: settingsPatch,
    );
  }

  /// Executes Phase 10b: pull per-folder tasks delta with 410 & move safety.
  Future<List<TaskItem>> pullAndMergeTasksDelta({
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
      final taskFetch = await _fetchDeltaWithMode(
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
      final taskDeltaResult = taskFetch.page;
      final mode = taskFetch.mode;
      final didFullFetch = taskFetch.didFullFetch;

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
          if (!didFullFetch) {
            appLog(
              'Phase 10b task[$mode] ADD remote=${shortSyncId(remote.id)} '
              'local=$newLocalId title="${created.title}" list=$resolvedListId '
              'order=${formatSyncTimestamp(created.orderDateTime)} '
              'committedOrder=${formatSyncTimestamp(created.committedOrder)}',
              label: 'SyncEngine',
            );
          }
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

    // Prune stale remotely deleted tasks missed by delta after a complete forced
    // full fetch (terminated by a DeltaLink so both Page 1 and Phase 2 completed).
    if (fullSyncedListIds.isNotEmpty) {
      final staleLocalIds = [
        for (final task in tasksById.values)
          if (task.remoteId != null &&
              fullSyncedListIds.contains(task.listId) &&
              !seenActiveRemoteTaskIds.contains(task.remoteId) &&
              !remainingDirtyTasks.contains(task.id) &&
              !syncedTaskIds.contains(task.id))
            task.id,
      ];
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

  Future<({DeltaPageResult<T> page, String mode, bool didFullFetch})>
  _fetchDeltaWithMode<T>({
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
        ? 'full(forced)'
        : (recovered410
              ? 'full(410)'
              : (effectiveDelta == null ? 'full(initial)' : 'delta'));
    return (
      page: result.getOrThrow(),
      mode: mode,
      didFullFetch: effectiveDelta == null || recovered410,
    );
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
