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

    final nextGroups = [
      for (final current in currentState.groups)
        if (outcome.pushedGroups[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.group, current.id)
              ? current.copyWith(remoteId: pushed.remoteId ?? current.remoteId)
              : pushed.copyWith(isExpanded: current.isExpanded)
        else
          current,
    ];

    final nextLists = [
      for (final current in currentState.lists)
        if (outcome.pushedLists[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.list, current.id)
              ? current.copyWith(remoteId: pushed.remoteId ?? current.remoteId)
              : pushed.copyWith(icon: current.icon)
        else
          current,
    ];

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

    final nextGroups = outcome.pushedGroups.isNotEmpty
        ? repository
              .readCachedGroups()
              .map(
                (g) => outcome.pushedGroups[g.id] == null
                    ? g
                    : (outbox.hasPending(SyncEntityType.group, g.id)
                          ? g.copyWith(
                              remoteId:
                                  outcome.pushedGroups[g.id]!.remoteId ??
                                  g.remoteId,
                            )
                          : outcome.pushedGroups[g.id]!.copyWith(
                              isExpanded: g.isExpanded,
                            )),
              )
              .toList(growable: false)
        : repository.readCachedGroups();

    final cachedLists = repository.readCachedLists() ?? const <TodoList>[];
    final nextLists = outcome.pushedLists.isNotEmpty
        ? cachedLists
              .map(
                (l) => outcome.pushedLists[l.id] == null
                    ? l
                    : (outbox.hasPending(SyncEntityType.list, l.id)
                          ? l.copyWith(
                              remoteId:
                                  outcome.pushedLists[l.id]!.remoteId ??
                                  l.remoteId,
                            )
                          : outcome.pushedLists[l.id]!.copyWith(icon: l.icon)),
              )
              .toList(growable: false)
        : cachedLists;

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

  /// Applies pulled or realtime remote snapshots/patches to [currentState]
  /// and persists changed entities and settings to SQLite / prefs.
  ({TodoState nextState, Future<void> persisted}) applyRemoteState({
    required TodoState currentState,
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? tasks,
    SyncedSettingsPatch? settingsPatch,
    bool protectPendingOutbox = false,
  }) {
    final outbox = repository.outbox;

    final reconciledGroups = groups == null
        ? currentState.groups
        : (protectPendingOutbox
              ? _mergePulled<ListGroup>(
                  outbox: outbox,
                  currentItems: currentState.groups,
                  pulledItems: groups,
                  type: SyncEntityType.group,
                  idOf: (g) => g.id,
                  mergeLocalPending: (current, pulled) => current.copyWith(
                    remoteId: pulled.remoteId ?? current.remoteId,
                  ),
                  mergeClean: (current, pulled) =>
                      pulled.copyWith(isExpanded: current.isExpanded),
                )
              : groups);
    final sortedGroups = groups != null
        ? sortGroupsByOrder(reconciledGroups)
        : reconciledGroups;

    var reconciledLists = lists == null
        ? currentState.lists
        : (protectPendingOutbox
              ? _mergePulled<TodoList>(
                  outbox: outbox,
                  currentItems: currentState.lists,
                  pulledItems: lists,
                  type: SyncEntityType.list,
                  idOf: (l) => l.id,
                  mergeLocalPending: (current, pulled) => current.copyWith(
                    remoteId: pulled.remoteId ?? current.remoteId,
                  ),
                  mergeClean: (current, pulled) => isSyncableFolderList(current)
                      ? pulled.copyWith(icon: current.icon)
                      : current,
                )
              : lists);

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
    if (settingsPatch != null) {
      final applied = applySyncedSettingsPatch(
        settings: settings,
        current: currentState,
        snapshot: null,
        patch: settingsPatch,
        lists: reconciledLists,
        dirtySettings: pendingSettings,
      );
      nextState = applied.state;
      listsModifiedBySettings = !identical(applied.lists, reconciledLists);
      reconciledLists = applied.lists;
      settingsPersistFutures.addAll(applied.persistFutures);
    }

    final sortedLists = (lists != null || danglingGroupCleared)
        ? sortListsPreservingSmartLists(reconciledLists)
        : reconciledLists;

    final expandedOutcome = (lists != null || settingsPatch != null)
        ? recomputeCompletedExpandedByList(
            currentExpanded: nextState.completedExpandedByList,
            lists: sortedLists,
            dirtyListIds: outbox.pendingLocalIds(SyncEntityType.list),
            dirtySettingKeys: pendingSettings,
            settingsPatch: settingsPatch,
            includeSyncableFolders: lists != null,
          )
        : (expanded: nextState.completedExpandedByList, changed: false);

    final validListIds = {for (final l in sortedLists) l.id};
    var reconciledTasks = tasks == null
        ? nextState.tasks
        : (protectPendingOutbox
              ? _mergePulled<TaskItem>(
                  outbox: outbox,
                  currentItems: nextState.tasks,
                  pulledItems: tasks,
                  type: SyncEntityType.task,
                  idOf: (t) => t.id,
                  mergeLocalPending: (current, pulled) => current.copyWith(
                    changeKey: pulled.changeKey ?? current.changeKey,
                  ),
                  mergeClean: (current, pulled) => pulled,
                )
              : tasks);
    if (tasks != null) {
      reconciledTasks = reconciledTasks
          .where((t) => validListIds.contains(t.listId))
          .toList();
    }

    final myDayResult = (tasks != null || settingsPatch != null)
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

  static List<T> _mergePulled<T>({
    required SyncOutboxQueue outbox,
    required List<T> currentItems,
    required List<T> pulledItems,
    required SyncEntityType type,
    required String Function(T) idOf,
    required T Function(T current, T pulled) mergeLocalPending,
    required T Function(T current, T pulled) mergeClean,
  }) {
    final pulledById = {for (final item in pulledItems) idOf(item): item};
    final currentIds = {for (final item in currentItems) idOf(item)};
    final result = <T>[];
    for (final current in currentItems) {
      final id = idOf(current);
      final pulled = pulledById[id];
      if (pulled == null) {
        if (outbox.hasPending(type, id)) {
          result.add(current);
        }
        continue;
      }
      result.add(
        outbox.hasPending(type, id)
            ? mergeLocalPending(current, pulled)
            : mergeClean(current, pulled),
      );
    }
    for (final pulled in pulledItems) {
      final id = idOf(pulled);
      if (!currentIds.contains(id) && !outbox.hasPending(type, id)) {
        result.add(pulled);
      }
    }
    return result;
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
