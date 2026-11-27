import 'package:collection/collection.dart';

import '../../core/logging/app_logger.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_state.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../sync_guard.dart';
import 'microsoft_todo_api.dart';

final _log = appLogFor('SyncEngine');

class OutboxPushOutcome {
  const OutboxPushOutcome({
    required this.ackedSeqs,
    required this.pushedGroups,
    required this.pushedLists,
    required this.pushedTasks,
    required this.followUpPullFolderRemoteIds,
    this.deletedEntities = const {},
  });

  static const empty = OutboxPushOutcome(
    ackedSeqs: [],
    pushedGroups: {},
    pushedLists: {},
    pushedTasks: {},
    followUpPullFolderRemoteIds: {},
  );

  final List<int> ackedSeqs;
  final Map<String, ListGroup> pushedGroups;
  final Map<String, TodoList> pushedLists;
  final Map<String, TaskItem> pushedTasks;

  /// Folders needing one targeted task pull (recurring task completion or
  /// attachment upload where the server creates extra entities/links).
  final Set<String> followUpPullFolderRemoteIds;
  final Set<SyncEntityKey> deletedEntities;

  bool get didWork =>
      ackedSeqs.isNotEmpty ||
      pushedGroups.isNotEmpty ||
      pushedLists.isNotEmpty ||
      pushedTasks.isNotEmpty ||
      deletedEntities.isNotEmpty;
}

/// Filters which Outbox operations a push pass drains so slow attachment
/// uploads can run on a dedicated transfer lane without blocking metadata sync.
enum PushLaneFilter { all, metadataOnly, attachmentsOnly }

/// Shared per-pass push state, live entity resolution, and commit helpers
/// used by entity-specific push handlers and the stage runner.
class PushContext {
  PushContext({
    required this.todoApi,
    required this.readState,
    required this.startOfWeek,
    required this.outbox,
    required this.nowUtc,
    this.onItemCommitted,
  });

  final MicrosoftTodoApi todoApi;
  final TodoState Function() readState;
  final WeekStart startOfWeek;
  final SyncOutboxQueue outbox;
  final DateTime nowUtc;
  final Future<void> Function(OutboxPushOutcome itemOutcome)? onItemCommitted;

  final List<int> _ackedSeqs = [];
  final Map<String, ListGroup> _pushedGroups = {};
  final Map<String, TodoList> _pushedLists = {};
  final Map<String, TaskItem> _pushedTasks = {};
  final Map<String, String> _sessionRemoteIds = {};
  final Set<String> _followUpPullFolderRemoteIds = {};
  final Set<String> _deletedRemoteKeys = {};
  final Set<SyncEntityKey> _deletedEntities = {};

  OutboxPushOutcome buildOutcome() => OutboxPushOutcome(
    ackedSeqs: _ackedSeqs,
    pushedGroups: _pushedGroups,
    pushedLists: _pushedLists,
    pushedTasks: _pushedTasks,
    followUpPullFolderRemoteIds: _followUpPullFolderRemoteIds,
    deletedEntities: _deletedEntities,
  );

  void recordCreatedRemoteId(
    SyncEntityType type,
    String localId,
    String remoteId,
  ) {
    _sessionRemoteIds[SyncOutboxQueue.remoteKey(type, localId)] = remoteId;
    outbox.backfillRemoteId(type, localId, remoteId);
  }

  String? resolveSessionRemoteId(SyncEntityType type, String localId) =>
      _sessionRemoteIds[SyncOutboxQueue.remoteKey(type, localId)];

  void markDeletedRemoteKey(SyncEntityType type, String remoteId) {
    _deletedRemoteKeys.add(SyncOutboxQueue.remoteKey(type, remoteId));
  }

  Future<void> commitOp({
    required int seq,
    ListGroup? group,
    TodoList? list,
    TaskItem? task,
    SyncEntityKey? deletedEntity,
    String? followUpFolderRemoteId,
  }) async {
    _ackedSeqs.add(seq);
    if (group != null) _pushedGroups[group.id] = group;
    if (list != null) _pushedLists[list.id] = list;
    if (task != null) _pushedTasks[task.id] = task;
    if (deletedEntity != null) _deletedEntities.add(deletedEntity);
    if (followUpFolderRemoteId != null) {
      _followUpPullFolderRemoteIds.add(followUpFolderRemoteId);
    }
    if (onItemCommitted == null) return;
    await onItemCommitted!(
      OutboxPushOutcome(
        ackedSeqs: [seq],
        pushedGroups: group != null ? {group.id: group} : const {},
        pushedLists: list != null ? {list.id: list} : const {},
        pushedTasks: task != null ? {task.id: task} : const {},
        followUpPullFolderRemoteIds: followUpFolderRemoteId != null
            ? {followUpFolderRemoteId}
            : const {},
        deletedEntities: deletedEntity != null ? {deletedEntity} : const {},
      ),
    );
  }

  Future<void> commitRemoteDeletion(
    SyncOutboxOp op,
    SyncEntityKey entity, {
    String? remoteId,
  }) async {
    final effectiveRemoteId =
        remoteId ?? resolveSessionRemoteId(entity.type, entity.localId);
    if (effectiveRemoteId != null) {
      markDeletedRemoteKey(entity.type, effectiveRemoteId);
    }
    switch (entity.type) {
      case SyncEntityType.group:
        _pushedGroups.remove(entity.localId);
      case SyncEntityType.list:
        _pushedLists.remove(entity.localId);
      case SyncEntityType.task:
        _pushedTasks.remove(entity.localId);
      case SyncEntityType.step:
      case SyncEntityType.attachment:
      case SyncEntityType.setting:
        break;
    }
    _log.info(
      'push DELETE-WINS ${entity.type.name} local=${entity.localId} '
      'remote=${shortSyncId(effectiveRemoteId)}',
    );
    await commitOp(seq: op.seq, deletedEntity: entity);
  }

  T? _resolveEntity<T extends Object>({
    required SyncEntityType entityType,
    required String localId,
    required Map<String, T> pushed,
    required List<T> Function(TodoState state) selector,
    required String Function(T item) idOf,
    required String? Function(T item) remoteIdOf,
    required T Function(T item, String remoteId) withRemoteId,
  }) {
    if (_deletedEntities.contains((type: entityType, localId: localId))) {
      return null;
    }
    final match = selector(
      readState(),
    ).firstWhereOrNull((e) => idOf(e) == localId);
    final raw = match == null ? null : (pushed[localId] ?? match);
    if (raw == null) return null;
    final rawRemoteId = remoteIdOf(raw);
    final resolvedRemoteId =
        rawRemoteId ?? resolveSessionRemoteId(entityType, localId);
    final resolved = rawRemoteId == null && resolvedRemoteId != null
        ? withRemoteId(raw, resolvedRemoteId)
        : raw;
    final effectiveRemoteId = remoteIdOf(resolved);
    if (effectiveRemoteId != null &&
        _deletedRemoteKeys.contains(
          SyncOutboxQueue.remoteKey(entityType, effectiveRemoteId),
        )) {
      return null;
    }
    return resolved;
  }

  ListGroup? resolveGroup(String localId) => _resolveEntity(
    entityType: SyncEntityType.group,
    localId: localId,
    pushed: _pushedGroups,
    selector: (s) => s.groups,
    idOf: (g) => g.id,
    remoteIdOf: (g) => g.remoteId,
    withRemoteId: (g, remoteId) => g.copyWith(remoteId: remoteId),
  );

  TodoList? resolveList(String localId) => _resolveEntity(
    entityType: SyncEntityType.list,
    localId: localId,
    pushed: _pushedLists,
    selector: (s) => s.lists,
    idOf: (l) => l.id,
    remoteIdOf: (l) => l.remoteId,
    withRemoteId: (l, remoteId) => l.copyWith(remoteId: remoteId),
  );

  TaskItem? resolveTask(String localId) {
    final resolved = _resolveEntity(
      entityType: SyncEntityType.task,
      localId: localId,
      pushed: _pushedTasks,
      selector: (s) => s.tasks,
      idOf: (t) => t.id,
      remoteIdOf: (t) => t.remoteId,
      withRemoteId: (t, remoteId) => t.copyWith(remoteId: remoteId),
    );
    if (resolved != null &&
        _deletedEntities.contains((
          type: SyncEntityType.list,
          localId: resolved.listId,
        ))) {
      return null;
    }
    return resolved;
  }

  String? resolveGroupRemoteId(String? groupId) {
    if (groupId == null) return null;
    final liveGroup = resolveGroup(groupId);
    if (liveGroup == null) return null;
    return liveGroup.remoteId ??
        resolveSessionRemoteId(SyncEntityType.group, groupId);
  }

  String? resolveLiveListRemoteId(String listId) {
    final liveList = resolveList(listId);
    if (liveList == null) return null;
    return liveList.remoteId ??
        resolveSessionRemoteId(SyncEntityType.list, listId);
  }

  String? resolveParentTaskRemoteId(SyncOutboxOp op) =>
      op.parentRemoteId ??
      (op.parentLocalId != null
          ? (resolveTask(op.parentLocalId!)?.remoteId ??
                resolveSessionRemoteId(SyncEntityType.task, op.parentLocalId!))
          : null);

  Set<T>? decodeEnumFields<T extends Enum>(
    Set<String> rawFields,
    List<T> values,
  ) {
    if (rawFields.isEmpty) return null;
    final byName = values.asNameMap();
    final result = rawFields.map((name) => byName[name]).nonNulls.toSet();
    return result.isEmpty ? null : result;
  }
}
