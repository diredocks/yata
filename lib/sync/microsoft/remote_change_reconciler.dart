import 'package:collection/collection.dart';

import '../../data/sync_outbox.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'microsoft_todo_models.dart';
import 'substrate_sync_mappers.dart';

/// A remote task change paired with optional fallback folder context (from
/// folder-scoped delta pulls) and whether missing `Subtasks`/`LinkedEntities`
/// should preserve existing local items (for partial realtime payloads).
typedef RemoteTaskChange = ({
  RemoteTodoTask remote,
  String? fallbackFolderRemoteId,
  bool preserveStepsWhenMissing,
  bool preserveAttachmentsWhenMissing,
});

({
  List<TaskItem> tasks,
  Set<String> seenActiveRemoteIds,
  bool hasUnresolvedParent,
})
_reconcileRemoteTaskChanges({
  required List<TodoList> lists,
  required List<TaskItem> currentTasks,
  required Iterable<RemoteTaskChange> changes,
  required Set<String> dirtyTaskIds,
  required Set<String> pendingDeletedTaskRemoteIds,
  required String Function(String prefix) idGenerator,
}) {
  final localListIdByFolderRemoteId = {
    for (final l in lists)
      if (l.remoteId != null) l.remoteId!: l.id,
  };
  final tasksById = {for (final t in currentTasks) t.id: t};
  final taskIdByRemoteId = <String, String>{
    for (final t in currentTasks)
      if (t.remoteId != null) t.remoteId!: t.id,
  };

  final seenActiveRemoteIds = <String>{};
  final deferredDeletesByFolder = <String, Set<String>?>{};
  final ignoredRemoteIds = <String>{};
  var hasUnresolvedParent = false;

  for (final change in changes) {
    final remote = change.remote;
    if (remote.id.isEmpty) continue;

    final String? fallbackLocalListId;
    if (change.fallbackFolderRemoteId != null) {
      fallbackLocalListId =
          localListIdByFolderRemoteId[change.fallbackFolderRemoteId!];
      if (fallbackLocalListId == null) continue;
    } else {
      fallbackLocalListId = null;
    }

    if (remote.isIgnored) {
      ignoredRemoteIds.add(remote.id);
      continue;
    }
    if (remote.isDeleted) {
      final existingSet = deferredDeletesByFolder[remote.id];
      if (fallbackLocalListId != null) {
        if (existingSet != null) {
          existingSet.add(fallbackLocalListId);
        } else if (!deferredDeletesByFolder.containsKey(remote.id)) {
          deferredDeletesByFolder[remote.id] = {fallbackLocalListId};
        }
      } else {
        // Unscoped delete (e.g. Realtime Task/Deleted without folder context).
        deferredDeletesByFolder[remote.id] = null;
      }
      continue;
    }
    if (pendingDeletedTaskRemoteIds.contains(remote.id)) {
      continue;
    }

    seenActiveRemoteIds.add(remote.id);

    final existingId = taskIdByRemoteId[remote.id];
    final existing = existingId != null ? tasksById[existingId] : null;

    final String? resolvedListId;
    if (remote.parentFolderId != null && remote.parentFolderId!.isNotEmpty) {
      resolvedListId =
          localListIdByFolderRemoteId[remote.parentFolderId!] ??
          fallbackLocalListId;
      if (resolvedListId == null) {
        hasUnresolvedParent = true;
        continue;
      }
    } else {
      resolvedListId = fallbackLocalListId ?? existing?.listId;
      if (resolvedListId == null) {
        hasUnresolvedParent = true;
        continue;
      }
    }

    if (existing != null) {
      final isPending = dirtyTaskIds.contains(existing.id);
      if (isPending) {
        if (remote.changeKey != null &&
            remote.changeKey != existing.changeKey) {
          tasksById[existing.id] = existing.copyWith(
            changeKey: remote.changeKey,
          );
        }
        continue;
      }

      var mapped = taskFromRemote(
        remote,
        localId: existing.id,
        listId: resolvedListId,
        existingSteps: existing.steps,
        existingAttachments: existing.attachments,
        idGenerator: idGenerator,
        existingCompletedAt: existing.completedAt,
      );
      if (change.preserveStepsWhenMissing) {
        mapped = mapped.copyWith(steps: existing.steps);
      }
      if (change.preserveAttachmentsWhenMissing) {
        mapped = mapped.copyWith(attachments: existing.attachments);
      }
      if (mapped.remoteParentFolderId == null &&
          existing.remoteParentFolderId != null) {
        mapped = mapped.copyWith(
          remoteParentFolderId: existing.remoteParentFolderId,
        );
      }
      tasksById[existing.id] = mapped;
    } else {
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
    }
  }

  for (final ignoredRemoteId in ignoredRemoteIds) {
    final localId = taskIdByRemoteId[ignoredRemoteId];
    if (localId == null || dirtyTaskIds.contains(localId)) continue;
    tasksById.remove(localId);
  }

  for (final entry in deferredDeletesByFolder.entries) {
    final deletedRemoteId = entry.key;
    final deletedFromListIds = entry.value;
    if (seenActiveRemoteIds.contains(deletedRemoteId)) continue;
    final localId = taskIdByRemoteId[deletedRemoteId];
    if (localId == null || dirtyTaskIds.contains(localId)) continue;
    final localTask = tasksById[localId];
    if (localTask == null) continue;
    if (deletedFromListIds != null &&
        !deletedFromListIds.contains(localTask.listId)) {
      continue;
    }
    tasksById.remove(localId);
  }

  return (
    tasks: tasksById.values.toList(),
    seenActiveRemoteIds: seenActiveRemoteIds,
    hasUnresolvedParent: hasUnresolvedParent,
  );
}

/// Unified remote delta payload shared by Full/Delta Pulls and Realtime events.
class RemoteDelta {
  const RemoteDelta({
    this.groups = const [],
    this.folders = const [],
    this.tasks = const [],
    this.remoteSettings,
    this.pruneGroups = false,
    this.pruneFolders = false,
    this.fullSyncedFolderRemoteIds = const {},
  });

  final List<RemoteFolderGroup> groups;
  final List<RemoteTodoFolder> folders;
  final List<RemoteTaskChange> tasks;
  final Map<String, String>? remoteSettings;
  final bool pruneGroups;
  final bool pruneFolders;
  final Set<String> fullSyncedFolderRemoteIds;
}

class ReconciledRemoteDelta {
  const ReconciledRemoteDelta({
    this.groups,
    this.lists,
    this.tasks,
    this.remoteSettings,
    this.hasUnhandledEntity = false,
  });

  final List<ListGroup>? groups;
  final List<TodoList>? lists;
  final List<TaskItem>? tasks;
  final Map<String, String>? remoteSettings;
  final bool hasUnhandledEntity;

  bool get hasChanges =>
      groups != null ||
      lists != null ||
      tasks != null ||
      (remoteSettings != null && remoteSettings!.isNotEmpty);
}

/// Reconciles a [RemoteDelta] (produced by either Pull or a batch of Realtime
/// events) against live local state using [protection].
ReconciledRemoteDelta reconcileRemoteDelta({
  required RemoteDelta delta,
  required List<ListGroup> liveGroups,
  required List<TodoList> liveLists,
  required List<TaskItem> liveTasks,
  required OutboxPullProtection protection,
  required String Function(String prefix) idGenerator,
  bool strictParentResolution = false,
  bool returnOnlyChanged = false,
}) {
  var hasUnhandledEntity = false;

  Map<String, String>? outSettings;
  if (delta.remoteSettings != null) {
    final filteredSettings = {
      for (final entry in delta.remoteSettings!.entries)
        if (!protection.dirtySettings.contains(entry.key))
          entry.key: entry.value,
    };
    if (!returnOnlyChanged || filteredSettings.isNotEmpty) {
      outSettings = filteredSettings;
    }
  }

  var effectiveGroups = liveGroups;
  List<ListGroup>? outGroups;
  if (delta.groups.isNotEmpty || delta.pruneGroups) {
    final filteredGroups = delta.groups
        .whereNot((g) => protection.deletedGroupRemotes.contains(g.id))
        .toList();
    if (filteredGroups.isNotEmpty || delta.pruneGroups) {
      var mergedGroups = mergeFolderGroupsDelta(
        localGroups: liveGroups,
        remoteDelta: filteredGroups,
        dirtyGroupIds: protection.dirtyGroups,
        idGenerator: idGenerator,
      );
      if (delta.pruneGroups) {
        final seenGroupRemoteIds = {
          for (final g in filteredGroups)
            if (!g.isDeleted && g.id.isNotEmpty) g.id,
        };
        mergedGroups = [
          for (final g in mergedGroups)
            if (g.remoteId == null ||
                seenGroupRemoteIds.contains(g.remoteId) ||
                protection.pruneKeepGroups.contains(g.id))
              g,
        ];
      }
      effectiveGroups = mergedGroups;
      if (!returnOnlyChanged ||
          !const ListEquality<ListGroup>().equals(
            liveGroups,
            effectiveGroups,
          )) {
        outGroups = effectiveGroups;
      }
    }
  }

  final groupLocalIdByRemoteId = {
    for (final g in effectiveGroups)
      if (g.remoteId != null) g.remoteId!: g.id,
  };

  var effectiveLists = liveLists;
  List<TodoList>? outLists;
  if (delta.folders.isNotEmpty || delta.pruneFolders) {
    final filteredFolders = delta.folders
        .whereNot(
          (f) =>
              f.isIgnoredSpecialFolder ||
              protection.deletedListRemotes.contains(f.id),
        )
        .toList();
    final applicableFolders = <RemoteTodoFolder>[];
    for (final f in filteredFolders) {
      if (strictParentResolution &&
          !f.isDeleted &&
          f.parentFolderGroupId != null &&
          f.parentFolderGroupId!.isNotEmpty &&
          !groupLocalIdByRemoteId.containsKey(f.parentFolderGroupId!)) {
        hasUnhandledEntity = true;
        continue;
      }
      applicableFolders.add(f);
    }
    if (applicableFolders.isNotEmpty || delta.pruneFolders) {
      var mergedLists = mergeFoldersDelta(
        localLists: liveLists,
        remoteDelta: applicableFolders,
        dirtyListIds: protection.dirtyLists,
        groupLocalIdByRemoteId: groupLocalIdByRemoteId,
        idGenerator: idGenerator,
      );
      if (delta.pruneFolders) {
        final seenFolderRemoteIds = {
          for (final f in applicableFolders)
            if (!f.isDeleted && !f.isIgnoredSpecialFolder && f.id.isNotEmpty)
              f.id,
        };
        if (seenFolderRemoteIds.isNotEmpty) {
          mergedLists = [
            for (final l in mergedLists)
              if (l.isSmartList ||
                  l.remoteId == null ||
                  seenFolderRemoteIds.contains(l.remoteId) ||
                  protection.pruneKeepLists.contains(l.id))
                l,
          ];
        }
      }
      effectiveLists = mergedLists;
      if (!returnOnlyChanged ||
          !const ListEquality<TodoList>().equals(liveLists, effectiveLists)) {
        outLists = effectiveLists;
      }
    }
  }

  final validListIds = {for (final l in effectiveLists) l.id};
  final tasksInValidLists = liveTasks
      .where((t) => validListIds.contains(t.listId))
      .toList();
  final tasksDroppedByFolderDelete =
      tasksInValidLists.length != liveTasks.length;

  final localListIdByFolderRemoteId = {
    for (final l in effectiveLists)
      if (l.remoteId != null) l.remoteId!: l.id,
  };

  List<TaskItem>? outTasks;
  if (delta.tasks.isNotEmpty || delta.fullSyncedFolderRemoteIds.isNotEmpty) {
    final reconciled = _reconcileRemoteTaskChanges(
      lists: effectiveLists,
      currentTasks: tasksInValidLists,
      changes: delta.tasks,
      dirtyTaskIds: protection.dirtyTasks,
      pendingDeletedTaskRemoteIds: protection.deletedTaskRemotes,
      idGenerator: idGenerator,
    );
    if (strictParentResolution && reconciled.hasUnresolvedParent) {
      hasUnhandledEntity = true;
    }
    final fullSyncedListIds = {
      for (final folderRemoteId in delta.fullSyncedFolderRemoteIds)
        ?localListIdByFolderRemoteId[folderRemoteId],
    };
    var finalTasks = reconciled.tasks;
    if (fullSyncedListIds.isNotEmpty) {
      finalTasks = [
        for (final task in reconciled.tasks)
          if (task.remoteId == null ||
              !fullSyncedListIds.contains(task.listId) ||
              reconciled.seenActiveRemoteIds.contains(task.remoteId) ||
              protection.pruneKeepTasks.contains(task.id))
            task,
      ];
    }
    if (!returnOnlyChanged ||
        tasksDroppedByFolderDelete ||
        !const ListEquality<TaskItem>().equals(liveTasks, finalTasks)) {
      outTasks = finalTasks;
    }
  } else if (tasksDroppedByFolderDelete) {
    outTasks = tasksInValidLists;
  }

  return ReconciledRemoteDelta(
    groups: outGroups,
    lists: outLists,
    tasks: outTasks,
    remoteSettings: outSettings,
    hasUnhandledEntity: hasUnhandledEntity,
  );
}

String _resolveRealtimeDeleteId(RealtimeEvent event) {
  final eventId = event.id?.trim();
  if (eventId != null && eventId.isNotEmpty) return eventId;
  return (event.payload?['Id'] as String?)?.trim() ?? '';
}

Map<String, dynamic> _normalizeRealtimePayload(RealtimeEvent event) {
  final payloadMap = Map<String, dynamic>.from(event.payload!);
  final payloadId = (payloadMap['Id'] as String?)?.trim();
  final eventId = event.id?.trim();
  if ((payloadId == null || payloadId.isEmpty) &&
      eventId != null &&
      eventId.isNotEmpty) {
    payloadMap['Id'] = eventId;
  }
  return payloadMap;
}

/// Converts a single [RealtimeEvent] into a [RemoteDelta], or returns `null`
/// when the event requires a fallback delta/full sync pass.
RemoteDelta? parseRealtimeEventToDelta(RealtimeEvent event) {
  switch (event.entityType) {
    case RealtimeEventEntityType.task:
      final op = event.op;
      if (op == RealtimeEventOperation.unsupported) return null;
      if (op == RealtimeEventOperation.deleted) {
        final remoteId = _resolveRealtimeDeleteId(event);
        if (remoteId.isEmpty) return null;
        return RemoteDelta(
          tasks: [
            (
              remote: RemoteTodoTask(
                id: remoteId,
                subject: '',
                isDeleted: true,
              ),
              fallbackFolderRemoteId: null,
              preserveStepsWhenMissing: false,
              preserveAttachmentsWhenMissing: false,
            ),
          ],
        );
      }
      if (event.payload == null) return null;
      final payloadMap = _normalizeRealtimePayload(event);
      final parsed = RemoteTodoTask.fromJson(payloadMap);
      if (parsed.id.isEmpty) return null;
      return RemoteDelta(
        tasks: [
          (
            remote: parsed,
            fallbackFolderRemoteId: null,
            preserveStepsWhenMissing: !payloadMap.containsKey('Subtasks'),
            preserveAttachmentsWhenMissing: !payloadMap.containsKey(
              'LinkedEntities',
            ),
          ),
        ],
      );

    case RealtimeEventEntityType.taskFolder:
      final op = event.op;
      if (op == RealtimeEventOperation.unsupported) return null;
      if (op == RealtimeEventOperation.deleted) {
        final remoteId = _resolveRealtimeDeleteId(event);
        if (remoteId.isEmpty) return null;
        return RemoteDelta(
          folders: [RemoteTodoFolder(id: remoteId, name: '', isDeleted: true)],
        );
      }
      if (event.payload == null) return null;
      final payloadMap = _normalizeRealtimePayload(event);
      final parsed = RemoteTodoFolder.fromJson(payloadMap);
      if (parsed.id.isEmpty) return null;
      if (parsed.isIgnoredSpecialFolder) return const RemoteDelta();
      return RemoteDelta(folders: [parsed]);

    case RealtimeEventEntityType.folderGroup:
      final op = event.op;
      if (op == RealtimeEventOperation.unsupported) return null;
      if (op == RealtimeEventOperation.deleted) {
        final remoteId = _resolveRealtimeDeleteId(event);
        if (remoteId.isEmpty) return null;
        return RemoteDelta(
          groups: [RemoteFolderGroup(id: remoteId, name: '', isDeleted: true)],
        );
      }
      if (event.payload == null) return null;
      final payloadMap = _normalizeRealtimePayload(event);
      final parsed = RemoteFolderGroup.fromJson(payloadMap);
      if (parsed.id.isEmpty) return null;
      return RemoteDelta(groups: [parsed]);

    case RealtimeEventEntityType.setting:
      final op = event.op;
      if ((op != RealtimeEventOperation.updated &&
              op != RealtimeEventOperation.created) ||
          event.payload == null) {
        return null;
      }
      final payload = event.payload!;
      final rawKey = (payload['Key'] ?? payload['key']) as String?;
      final key = (rawKey?.trim().isNotEmpty == true)
          ? rawKey!.trim()
          : (event.id?.trim() ?? '');
      final rawVal = payload['Value'] ?? payload['value'];
      if (key.isEmpty || rawVal == null) return null;
      return RemoteDelta(remoteSettings: {key: rawVal.toString()});

    case RealtimeEventEntityType.keepAlive:
    case RealtimeEventEntityType.unknown:
      return null;
  }
}

/// Parses a batch of [RealtimeEvent]s into a single merged [RemoteDelta] and
/// records the first unparseable event (if any) for fallback sync scheduling.
({RemoteDelta delta, RealtimeEvent? firstUnhandled}) parseRealtimeEventsBatch(
  Iterable<RealtimeEvent> events,
) {
  final groups = <RemoteFolderGroup>[];
  final folders = <RemoteTodoFolder>[];
  final tasks = <RemoteTaskChange>[];
  final settings = <String, String>{};
  RealtimeEvent? firstUnhandled;

  for (final event in events) {
    final parsed = parseRealtimeEventToDelta(event);
    if (parsed == null) {
      firstUnhandled ??= event;
      continue;
    }
    groups.addAll(parsed.groups);
    folders.addAll(parsed.folders);
    tasks.addAll(parsed.tasks);
    if (parsed.remoteSettings != null) {
      settings.addAll(parsed.remoteSettings!);
    }
  }

  return (
    delta: RemoteDelta(
      groups: groups,
      folders: folders,
      tasks: tasks,
      remoteSettings: settings.isEmpty ? null : settings,
    ),
    firstUnhandled: firstUnhandled,
  );
}
