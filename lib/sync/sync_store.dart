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

  /// Merges server-assigned identifiers/metadata from [outcome] into
  /// [currentState], updates the outbox, and persists touched rows to SQLite.
  ({TodoState nextState, Future<void> persisted}) commitPushToState({
    required TodoState currentState,
    required OutboxPushOutcome outcome,
  }) {
    final outbox = repository.outbox;
    outbox.ackBatch(outcome.ackedSeqs, outcome.clearedRemoteIdKeys);

    final nextGroups = _mergePushedGroups(
      outbox: outbox,
      currentGroups: currentState.groups,
      pushedGroups: outcome.pushedGroups,
    );
    final nextLists = _mergePushedLists(
      outbox: outbox,
      currentLists: currentState.lists,
      pushedLists: outcome.pushedLists,
    );

    final updatedTasks = <TaskItem>[];
    final nextTasks = [
      for (final current in currentState.tasks)
        if (outcome.pushedTasks[current.id] case final pushed?)
          () {
            final resolved = outbox.hasPending(SyncEntityType.task, current.id)
                ? _mergePushedTaskServerFields(current, pushed)
                : pushed;
            updatedTasks.add(resolved);
            return resolved;
          }()
        else
          current,
    ];

    outbox.pruneOrphanedEntities(
      validGroupIds: {for (final g in nextGroups) g.id},
      validListIds: {for (final l in nextLists) l.id},
      validTaskIds: {for (final t in nextTasks) t.id},
    );

    final persistFutures = <Future<Object?>>[
      if (outcome.pushedGroups.isNotEmpty) repository.saveGroups(nextGroups),
      if (outcome.pushedLists.isNotEmpty) repository.saveLists(nextLists),
      if (updatedTasks.isNotEmpty) repository.upsertTasks(updatedTasks),
      repository.saveOutbox(),
    ];

    return (
      nextState: currentState.copyWith(
        groups: nextGroups,
        lists: nextLists,
        tasks: nextTasks,
      ),
      persisted: Future.wait(persistFutures).then((_) {}),
    );
  }

  /// Headless background push commit: reloads fresh entity rows from SQLite
  /// without resetting [repository.outbox], then commits server metadata.
  Future<void> commitPushHeadless(OutboxPushOutcome outcome) async {
    await repository.reloadEntities();
    final outbox = repository.outbox;
    outbox.ackBatch(outcome.ackedSeqs, outcome.clearedRemoteIdKeys);

    final freshTasksById = {
      for (final t in repository.readCachedTasks()) t.id: t,
    };
    final updatedTasks = <TaskItem>[
      for (final pushedTask in outcome.pushedTasks.values)
        freshTasksById[pushedTask.id] == null
            ? pushedTask
            : _mergePushedTaskServerFields(
                freshTasksById[pushedTask.id]!,
                pushedTask,
              ),
    ];

    final nextGroups = _mergePushedGroups(
      outbox: outbox,
      currentGroups: repository.readCachedGroups(),
      pushedGroups: outcome.pushedGroups,
    );
    final nextLists = _mergePushedLists(
      outbox: outbox,
      currentLists: repository.readCachedLists() ?? const <TodoList>[],
      pushedLists: outcome.pushedLists,
    );

    final currentTasksById = Map<String, TaskItem>.of(freshTasksById);
    for (final updated in updatedTasks) {
      currentTasksById[updated.id] = updated;
    }
    outbox.pruneOrphanedEntities(
      validGroupIds: {for (final g in nextGroups) g.id},
      validListIds: {for (final l in nextLists) l.id},
      validTaskIds: currentTasksById.keys.toSet(),
    );

    if (updatedTasks.isNotEmpty) {
      await repository.upsertTasks(updatedTasks);
    }
    if (outcome.pushedGroups.isNotEmpty) {
      await repository.saveGroups(nextGroups);
    }
    if (outcome.pushedLists.isNotEmpty) {
      await repository.saveLists(nextLists);
    }
    await repository.saveOutbox();
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

    var reconciledLists = lists ?? currentState.lists;
    var danglingGroupCleared = false;
    if (groups != null || lists != null) {
      final validGroupIds = {for (final g in sortedGroups) g.id};
      final cleanedLists = <TodoList>[];
      for (final list in reconciledLists) {
        if (list.groupId != null && !validGroupIds.contains(list.groupId)) {
          danglingGroupCleared = true;
          cleanedLists.add(list.copyWith(groupId: null));
        } else {
          cleanedLists.add(list);
        }
      }
      if (danglingGroupCleared) {
        reconciledLists = cleanedLists;
      }
    }

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

    final validSelectedListId = lists != null
        ? (sortedLists.any((l) => l.id == nextState.selectedListId)
              ? nextState.selectedListId
              : 'my_day')
        : nextState.selectedListId;
    final validSelectedTaskId = (tasks != null || lists != null)
        ? (nextState.selectedTaskId != null &&
                  syncedTasks.any((t) => t.id == nextState.selectedTaskId)
              ? nextState.selectedTaskId
              : null)
        : nextState.selectedTaskId;

    final shouldSaveLists =
        lists != null || danglingGroupCleared || listsModifiedBySettings;
    final shouldSaveTasks = tasks != null || myDayResult.changed;
    final persistFutures = <Future<Object?>>[
      ...settingsPersistFutures,
      if (groups != null) repository.saveGroups(sortedGroups),
      if (shouldSaveLists) repository.saveLists(sortedLists),
      if (shouldSaveTasks) repository.saveTasks(syncedTasks),
      if (expandedOutcome.changed)
        settings.saveCompletedExpandedByList(expandedOutcome.expanded),
    ];

    return (
      nextState: nextState.copyWith(
        groups: sortedGroups,
        lists: sortedLists,
        tasks: syncedTasks,
        selectedListId: validSelectedListId,
        selectedTaskId: validSelectedTaskId,
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
              : pushed.copyWith(icon: current.icon)
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
              isTransferring: pAtt.remoteId != null ? false : att.isTransferring,
            )
          else
            att,
      ],
    );
  }
}
