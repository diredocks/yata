import '../data/sync_outbox.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../data/todo_settings_sync.dart';
import '../data/todo_state.dart';
import '../data/todo_sync_reconciler.dart';
import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft/substrate_push_engine.dart';

/// Unified persistence and reconciliation facade shared by foreground
/// (`TodoNotifier`) and headless background sync passes.
class SyncStore {
  const SyncStore({required this.repository, required this.settings});

  final TodoRepository repository;
  final TodoSettingsStore settings;

  static ({List<TodoList> lists, bool changed}) _clearDanglingGroupIds(
    List<TodoList> lists,
    Set<String> validGroupIds,
  ) {
    var changed = false;
    final cleaned = <TodoList>[];
    for (final list in lists) {
      if (list.groupId != null && !validGroupIds.contains(list.groupId)) {
        changed = true;
        cleaned.add(list.copyWith(groupId: null));
      } else {
        cleaned.add(list);
      }
    }
    return (lists: changed ? cleaned : lists, changed: changed);
  }

  static ({String selectedListId, String? selectedTaskId}) _sanitizeSelection({
    required TodoState state,
    required List<TodoList> lists,
    required List<TaskItem> tasks,
    bool checkList = true,
    bool checkTask = true,
  }) {
    final selectedListId =
        !checkList || lists.any((l) => l.id == state.selectedListId)
        ? state.selectedListId
        : 'my_day';
    final selectedTaskId = !checkTask
        ? state.selectedTaskId
        : (state.selectedTaskId != null &&
                  tasks.any((t) => t.id == state.selectedTaskId)
              ? state.selectedTaskId
              : null);
    return (selectedListId: selectedListId, selectedTaskId: selectedTaskId);
  }

  bool _pruneOutbox({
    required List<ListGroup> groups,
    required List<TodoList>? lists,
    required List<TaskItem> tasks,
  }) {
    return repository.outbox.pruneOrphanedEntities(
      validGroupIds: {for (final g in groups) g.id},
      validListIds: lists != null ? {for (final l in lists) l.id} : null,
      validTaskIds: {for (final t in tasks) t.id},
    );
  }

  ({
    List<ListGroup> nextGroups,
    List<TodoList> nextLists,
    List<TaskItem> nextTasks,
    List<TaskItem> updatedTasks,
    Set<String> deletedTaskIds,
    bool groupsMutated,
    bool listsMutated,
  })
  _applyPushToEntities({
    required OutboxPushOutcome outcome,
    required List<ListGroup> currentGroups,
    required List<TodoList>? currentLists,
    required List<TaskItem> currentTasks,
    required bool isHeadless,
  }) {
    final outbox = repository.outbox;
    outbox.ackBatch(outcome.ackedSeqs);

    Set<String> deletedIdsOf(SyncEntityType type) => {
      for (final e in outcome.deletedEntities)
        if (e.type == type) e.localId,
    };

    final deletedGroupIds = deletedIdsOf(SyncEntityType.group);
    final mergedGroups = _mergePushedGroups(
      outbox: outbox,
      currentGroups: currentGroups,
      pushedGroups: outcome.pushedGroups,
    );
    final nextGroups = deletedGroupIds.isEmpty
        ? mergedGroups
        : [
            for (final g in mergedGroups)
              if (!deletedGroupIds.contains(g.id)) g,
          ];
    final groupsRemoved = nextGroups.length != mergedGroups.length;
    final validGroupIds = {for (final g in nextGroups) g.id};

    final mergedLists = _mergePushedLists(
      outbox: outbox,
      currentLists: currentLists ?? const <TodoList>[],
      pushedLists: outcome.pushedLists,
    );
    final smartListIds = {
      for (final l in mergedLists)
        if (l.isSmartList) l.id,
    };
    final removedListIds = deletedIdsOf(
      SyncEntityType.list,
    ).difference(smartListIds);
    final survivingLists = removedListIds.isEmpty
        ? mergedLists
        : [
            for (final l in mergedLists)
              if (!removedListIds.contains(l.id)) l,
          ];
    final listsRemoved = survivingLists.length != mergedLists.length;
    final cleanedLists = _clearDanglingGroupIds(survivingLists, validGroupIds);
    final nextLists = cleanedLists.lists;

    final deletedTaskIds = deletedIdsOf(SyncEntityType.task);
    final updatedTasks = <TaskItem>[];
    final nextTasks = <TaskItem>[];
    final seenTaskIds = <String>{};
    for (final current in currentTasks) {
      seenTaskIds.add(current.id);
      final pushed = outcome.pushedTasks[current.id];
      final resolved = pushed != null
          ? ((isHeadless || outbox.hasPending(SyncEntityType.task, current.id))
                ? _mergePushedTaskServerFields(current, pushed)
                : pushed)
          : current;
      if (deletedTaskIds.contains(current.id) ||
          removedListIds.contains(resolved.listId)) {
        deletedTaskIds.add(current.id);
        continue;
      }
      if (pushed != null) {
        updatedTasks.add(resolved);
      }
      nextTasks.add(resolved);
    }

    if (isHeadless) {
      for (final pushed in outcome.pushedTasks.values) {
        if (seenTaskIds.contains(pushed.id) ||
            deletedTaskIds.contains(pushed.id) ||
            removedListIds.contains(pushed.listId)) {
          continue;
        }
        updatedTasks.add(pushed);
        nextTasks.add(pushed);
      }
    }

    _pruneOutbox(
      groups: nextGroups,
      lists: currentLists == null ? null : nextLists,
      tasks: nextTasks,
    );

    return (
      nextGroups: nextGroups,
      nextLists: nextLists,
      nextTasks: nextTasks,
      updatedTasks: updatedTasks,
      deletedTaskIds: deletedTaskIds,
      groupsMutated: outcome.pushedGroups.isNotEmpty || groupsRemoved,
      listsMutated:
          outcome.pushedLists.isNotEmpty ||
          listsRemoved ||
          cleanedLists.changed,
    );
  }

  /// Merges server-assigned identifiers/metadata from [outcome] into
  /// [currentState], updates the outbox, and persists touched rows to SQLite.
  ({TodoState nextState, Future<void> persisted}) commitPushToState({
    required TodoState currentState,
    required OutboxPushOutcome outcome,
  }) {
    final applied = _applyPushToEntities(
      outcome: outcome,
      currentGroups: currentState.groups,
      currentLists: currentState.lists,
      currentTasks: currentState.tasks,
      isHeadless: false,
    );

    final selection = _sanitizeSelection(
      state: currentState,
      lists: applied.nextLists,
      tasks: applied.nextTasks,
    );

    final persisted = repository
        .persistSyncBatch(
          groups: applied.groupsMutated ? applied.nextGroups : null,
          lists: applied.listsMutated ? applied.nextLists : null,
          upsertTasks: applied.updatedTasks,
          deleteTaskIds: applied.deletedTaskIds,
          saveOutbox: true,
        )
        .then((_) {});

    return (
      nextState: currentState.copyWith(
        groups: applied.nextGroups,
        lists: applied.nextLists,
        tasks: applied.nextTasks,
        selectedListId: selection.selectedListId,
        selectedTaskId: selection.selectedTaskId,
      ),
      persisted: persisted,
    );
  }

  /// Headless background push commit: reloads fresh entity rows from SQLite
  /// without resetting [repository.outbox], then commits server metadata in one
  /// atomic transaction.
  Future<void> commitPushHeadless(OutboxPushOutcome outcome) async {
    await repository.reloadEntities();
    final applied = _applyPushToEntities(
      outcome: outcome,
      currentGroups: repository.readCachedGroups(),
      currentLists: repository.readCachedLists(),
      currentTasks: repository.readCachedTasks(),
      isHeadless: true,
    );

    await repository.persistSyncBatch(
      groups: applied.groupsMutated ? applied.nextGroups : null,
      lists: applied.listsMutated ? applied.nextLists : null,
      upsertTasks: applied.updatedTasks,
      deleteTaskIds: applied.deletedTaskIds,
      saveOutbox: true,
    );
    await repository.flushPendingWrites();
  }

  /// Applies reconciled remote state/settings to [currentState] synchronously
  /// and returns futures covering changed entity/preference persistence.
  ({TodoState nextState, Future<void> persisted}) applyRemoteState({
    required TodoState currentState,
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? tasks,
    Map<String, String>? remoteSettings,
  }) {
    final outbox = repository.outbox;
    final sortedGroups = groups != null
        ? sortGroupsByOrder(groups)
        : currentState.groups;

    final cleanedLists = (groups != null || lists != null)
        ? _clearDanglingGroupIds(lists ?? currentState.lists, {
            for (final g in sortedGroups) g.id,
          })
        : (lists: lists ?? currentState.lists, changed: false);
    var reconciledLists = cleanedLists.lists;
    final danglingGroupCleared = cleanedLists.changed;

    final pendingSettings = outbox.pendingLocalIds(SyncEntityType.setting);
    var nextState = currentState;
    final settingsPersistFutures = <Future<void>>[];
    var listsModifiedBySettings = false;
    var updatedShowCompletedSmartListIds = const <String>{};
    if (remoteSettings != null && remoteSettings.isNotEmpty) {
      final applied = applyRemoteSettingsWire(
        settings: settings,
        current: currentState,
        remoteSettings: remoteSettings,
        lists: reconciledLists,
        dirtySettings: pendingSettings,
      );
      nextState = applied.state;
      listsModifiedBySettings = !identical(applied.lists, reconciledLists);
      reconciledLists = applied.lists;
      settingsPersistFutures.addAll(applied.persistFutures);
      updatedShowCompletedSmartListIds =
          applied.updatedShowCompletedSmartListIds;
    }

    final sortedLists = (lists != null || danglingGroupCleared)
        ? sortListsPreservingSmartLists(reconciledLists)
        : reconciledLists;

    final expandedOutcome =
        (lists != null || updatedShowCompletedSmartListIds.isNotEmpty)
        ? recomputeCompletedExpandedByList(
            currentExpanded: nextState.completedExpandedByList,
            lists: sortedLists,
            dirtyListIds: outbox.pendingLocalIds(SyncEntityType.list),
            updatedShowCompletedSmartListIds: updatedShowCompletedSmartListIds,
            includeSyncableFolders: lists != null,
          )
        : (expanded: nextState.completedExpandedByList, changed: false);

    final validListIds = {for (final l in sortedLists) l.id};
    var reconciledTasks = tasks ?? nextState.tasks;
    if (tasks != null) {
      reconciledTasks = reconciledTasks
          .where((t) => validListIds.contains(t.listId))
          .toList();
    }

    final myDayResult = (tasks != null || remoteSettings != null)
        ? syncTasksMyDayFlags(
            reconciledTasks,
            now: DateTime.now(),
            showDueTodayInMyDay: nextState.showDueTodayInMyDay,
          )
        : (tasks: reconciledTasks, changed: false);
    final syncedTasks = myDayResult.tasks;

    final selection = _sanitizeSelection(
      state: nextState,
      lists: sortedLists,
      tasks: syncedTasks,
      checkList: lists != null,
      checkTask: tasks != null || lists != null,
    );

    final outboxPruned = (groups != null || lists != null || tasks != null)
        ? _pruneOutbox(
            groups: sortedGroups,
            lists: sortedLists,
            tasks: syncedTasks,
          )
        : false;

    final shouldSaveLists =
        lists != null || danglingGroupCleared || listsModifiedBySettings;
    final shouldSaveTasks = tasks != null || myDayResult.changed;
    final hasDbBatch =
        groups != null || shouldSaveLists || shouldSaveTasks || outboxPruned;
    final persistFutures = <Future<Object?>>[
      ...settingsPersistFutures,
      if (hasDbBatch)
        repository.persistSyncBatch(
          groups: groups != null ? sortedGroups : null,
          lists: shouldSaveLists ? sortedLists : null,
          fullTasks: shouldSaveTasks ? syncedTasks : null,
          saveOutbox: outboxPruned,
        ),
      if (expandedOutcome.changed)
        settings.saveCompletedExpandedByList(expandedOutcome.expanded),
    ];

    return (
      nextState: nextState.copyWith(
        groups: sortedGroups,
        lists: sortedLists,
        tasks: syncedTasks,
        selectedListId: selection.selectedListId,
        selectedTaskId: selection.selectedTaskId,
        completedExpandedByList: expandedOutcome.expanded,
      ),
      persisted: persistFutures.isEmpty
          ? Future<void>.value()
          : Future.wait(persistFutures).then((_) {}),
    );
  }

  static List<ListGroup> _mergePushedGroups({
    required SyncOutboxQueue outbox,
    required List<ListGroup> currentGroups,
    required Map<String, ListGroup> pushedGroups,
  }) {
    if (pushedGroups.isEmpty) return currentGroups;
    return [
      for (final current in currentGroups)
        if (pushedGroups[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.group, current.id)
              ? current.copyWith(remoteId: pushed.remoteId ?? current.remoteId)
              : pushed.copyWith(isExpanded: current.isExpanded)
        else
          current,
    ];
  }

  static List<TodoList> _mergePushedLists({
    required SyncOutboxQueue outbox,
    required List<TodoList> currentLists,
    required Map<String, TodoList> pushedLists,
  }) {
    if (pushedLists.isEmpty) return currentLists;
    return [
      for (final current in currentLists)
        if (pushedLists[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.list, current.id)
              ? current.copyWith(remoteId: pushed.remoteId ?? current.remoteId)
              : pushed
        else
          current,
    ];
  }

  static TaskItem _mergePushedTaskServerFields(
    TaskItem current,
    TaskItem pushed,
  ) {
    final stepRemoteById = {
      for (final s in pushed.steps)
        if (s.remoteId != null) s.id: s.remoteId!,
    };
    final pushedAttById = {for (final a in pushed.attachments) a.id: a};
    return current.copyWith(
      remoteId: current.remoteId ?? pushed.remoteId,
      remoteParentFolderId:
          current.remoteParentFolderId ?? pushed.remoteParentFolderId,
      changeKey: pushed.changeKey ?? current.changeKey,
      steps: [
        for (final step in current.steps)
          step.copyWith(remoteId: step.remoteId ?? stepRemoteById[step.id]),
      ],
      attachments: [
        for (final att in current.attachments)
          if (pushedAttById[att.id] case final pAtt?)
            att.copyWith(
              remoteId: att.remoteId ?? pAtt.remoteId,
              size: pAtt.size > 0 ? pAtt.size : att.size,
              contentType: pAtt.contentType ?? att.contentType,
              lastModifiedDateTime:
                  pAtt.lastModifiedDateTime ?? att.lastModifiedDateTime,
              isTransferring: pAtt.remoteId != null
                  ? false
                  : att.isTransferring,
            )
          else
            att,
      ],
    );
  }
}
