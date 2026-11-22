import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'todo_local_storage.dart';
import 'todo_settings_sync.dart';
import 'todo_state.dart';

export '../account/account_provider.dart' show sharedPreferencesProvider;
export 'todo_settings_sync.dart';
export 'todo_state.dart';

final todoLocalStorageProvider = Provider<TodoLocalStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final activeAccountId = ref.watch(
    accountProvider.select((s) => s.activeAccountId),
  );
  return TodoLocalStorage(prefs, accountId: activeAccountId);
});

class TodoNotifier extends Notifier<TodoState> {
  int _idCounter = 0;

  String nextId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  TodoLocalStorage get storage => ref.read(todoLocalStorageProvider);

  String _todayKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Recomputes [TaskItem.isInMyDay] from [TaskItem.myDayDate],
  /// [TaskItem.dueDate], and [TaskItem.postponedDay], matching `MyDayContract.kt`.
  static TaskItem syncMyDayFlag(
    TaskItem task, {
    required DateTime now,
    required bool showDueTodayInMyDay,
  }) {
    final committedToday =
        task.myDayDate != null && isSameDay(task.myDayDate!, now);
    final postponedToday =
        task.postponedDay != null && isSameDay(task.postponedDay!, now);
    final dueToday =
        showDueTodayInMyDay &&
        task.dueDate != null &&
        isSameDay(task.dueDate!, now);
    final effectiveInMyDay = committedToday || (dueToday && !postponedToday);
    if (task.isInMyDay == effectiveInMyDay) return task;
    return task.copyWith(isInMyDay: effectiveInMyDay);
  }

  @override
  TodoState build() {
    final storage = ref.watch(todoLocalStorageProvider);
    final snapshot = storage.load();
    final now = DateTime.now();
    final todayKey = _todayKey(now);
    var changed = false;
    final tasks = <TaskItem>[];
    for (final task in snapshot.tasks) {
      final synced = syncMyDayFlag(
        task,
        now: now,
        showDueTodayInMyDay: snapshot.showDueTodayInMyDay,
      );
      if (!identical(synced, task)) {
        changed = true;
      }
      tasks.add(synced);
    }
    if (changed) {
      storage.saveTasks(tasks);
    }
    if (snapshot.lastMyDayResetDate != todayKey) {
      storage.saveLastMyDayResetDate(todayKey);
    }

    return TodoState(
      lists: snapshot.lists,
      groups: snapshot.groups,
      tasks: tasks,
      selectedListId: snapshot.selectedListId,
      themeMode: snapshot.themeMode,
      addNewTasksOnTop: snapshot.addNewTasksOnTop,
      moveStarredTasksToTop: snapshot.moveStarredTasksToTop,
      playCompletionSound: snapshot.playCompletionSound,
      confirmBeforeDeleting: snapshot.confirmBeforeDeleting,
      showDueTodayInMyDay: snapshot.showDueTodayInMyDay,
      startOfWeek: snapshot.startOfWeek,
      showSmartListImportant: snapshot.showSmartListImportant,
      showSmartListPlanned: snapshot.showSmartListPlanned,
      showSmartListAll: snapshot.showSmartListAll,
      showSmartListCompleted: snapshot.showSmartListCompleted,
      autoHideEmptySmartLists: snapshot.autoHideEmptySmartLists,
      plannedDueDateFilter: snapshot.plannedDueDateFilter,
      plannedGroupOption: snapshot.plannedGroupOption,
      useDynamicColor: snapshot.useDynamicColor,
      remindersEnabled: snapshot.remindersEnabled,
      pinReminders: snapshot.pinReminders,
      dueTodayNotificationsEnabled: snapshot.dueTodayNotificationsEnabled,
      dueTodayNotificationHour: snapshot.dueTodayNotificationHour,
      dueTodayNotificationMinute: snapshot.dueTodayNotificationMinute,
      routineNotificationEnabled: snapshot.routineNotificationEnabled,
      routineNotificationHour: snapshot.routineNotificationHour,
      routineNotificationMinute: snapshot.routineNotificationMinute,
      quickAddNotificationEnabled: snapshot.quickAddNotificationEnabled,
      completedExpandedByList: storage.loadCompletedExpandedByList(),
    );
  }

  void commit(TodoState nextState) {
    final prevState = state;
    final prevGroups = prevState.groups;
    final prevLists = prevState.lists;
    final prevTasks = prevState.tasks;
    final nowUtc = DateTime.now().toUtc();

    final groupsChanged = !identical(prevGroups, nextState.groups);
    final listsChanged = !identical(prevLists, nextState.lists);
    final tasksChanged = !identical(prevTasks, nextState.tasks);

    final dirtyGroups = storage.loadDirtyGroupIds().toSet();
    final dirtyLists = storage.loadDirtyListIds().toSet();
    final dirtyTasks = storage.loadDirtyTaskIds().toSet();
    final dirtySettings = storage.loadDirtySettingKeys().toSet();

    var stampedGroups = nextState.groups;
    var groupSyncNeeded = false;
    if (groupsChanged) {
      final prevGroupById = {for (final g in prevGroups) g.id: g};
      final nextGroupIds = {for (final g in nextState.groups) g.id};

      final deletedGroupRemoteIds = [
        ...storage.loadPendingDeletedGroupRemoteIds(),
      ];
      for (final prev in prevGroups) {
        if (!nextGroupIds.contains(prev.id)) {
          dirtyGroups.remove(prev.id);
          if (prev.remoteId != null) {
            groupSyncNeeded = true;
            if (!deletedGroupRemoteIds.contains(prev.remoteId)) {
              deletedGroupRemoteIds.add(prev.remoteId!);
            }
          }
        }
      }
      storage.savePendingDeletedGroupRemoteIds(deletedGroupRemoteIds);

      final nextGroups = <ListGroup>[];
      for (final group in nextState.groups) {
        final prev = prevGroupById[group.id];
        if (prev == null || _groupSyncDirty(prev, group)) {
          groupSyncNeeded = true;
          dirtyGroups.add(group.id);
          nextGroups.add(group.copyWith(updatedAt: nowUtc));
        } else {
          nextGroups.add(group);
        }
      }
      stampedGroups = nextGroups;
    }

    var stampedLists = nextState.lists;
    var listSyncNeeded = false;
    if (listsChanged) {
      final prevListById = {for (final l in prevLists) l.id: l};
      final nextListIds = {for (final l in nextState.lists) l.id};

      final deletedListRemoteIds = [
        ...storage.loadPendingDeletedListRemoteIds(),
      ];
      for (final prev in prevLists) {
        if (!nextListIds.contains(prev.id)) {
          dirtyLists.remove(prev.id);
          if (!prev.isSmartList && prev.remoteId != null) {
            listSyncNeeded = true;
            if (!deletedListRemoteIds.contains(prev.remoteId)) {
              deletedListRemoteIds.add(prev.remoteId!);
            }
          }
        }
      }
      storage.savePendingDeletedListRemoteIds(deletedListRemoteIds);

      final nextLists = <TodoList>[];
      for (final list in nextState.lists) {
        final prev = prevListById[list.id];
        if (_isSyncableFolder(list)) {
          if (prev == null || _listSyncDirty(prev, list)) {
            listSyncNeeded = true;
            dirtyLists.add(list.id);
            nextLists.add(list.copyWith(updatedAt: nowUtc));
          } else {
            nextLists.add(list);
          }
        } else {
          if (prev != null) {
            final changedSmartKeys = smartListChangedSettingKeys(prev, list);
            if (changedSmartKeys.isNotEmpty) {
              listSyncNeeded = true;
              dirtySettings.addAll(changedSmartKeys);
            }
          }
          nextLists.add(list);
        }
      }
      stampedLists = nextLists;
    }

    var stampedTasks = nextState.tasks;
    var taskSyncNeeded = false;
    if (tasksChanged) {
      final prevTaskById = {for (final t in prevTasks) t.id: t};
      final nextTaskIds = {for (final t in nextState.tasks) t.id};

      final deletedTaskRemoteIds = [
        ...storage.loadPendingDeletedTaskRemoteIds(),
      ];
      for (final prev in prevTasks) {
        if (!nextTaskIds.contains(prev.id)) {
          dirtyTasks.remove(prev.id);
          if (prev.remoteId != null &&
              !deletedTaskRemoteIds.contains(prev.remoteId)) {
            taskSyncNeeded = true;
            deletedTaskRemoteIds.add(prev.remoteId!);
          }
        }
      }
      storage.savePendingDeletedTaskRemoteIds(deletedTaskRemoteIds);

      final deletedSteps = [...storage.loadPendingDeletedSteps()];
      for (final task in nextState.tasks) {
        final prev = prevTaskById[task.id];
        if (prev != null && prev.remoteId != null) {
          final nextStepIds = {for (final s in task.steps) s.id};
          for (final prevStep in prev.steps) {
            if (!nextStepIds.contains(prevStep.id) &&
                prevStep.remoteId != null) {
              final alreadyQueued = deletedSteps.any(
                (d) =>
                    d.taskRemoteId == prev.remoteId &&
                    d.stepRemoteId == prevStep.remoteId,
              );
              if (!alreadyQueued) {
                taskSyncNeeded = true;
                deletedSteps.add(
                  PendingStepDeletion(
                    taskRemoteId: prev.remoteId!,
                    stepRemoteId: prevStep.remoteId!,
                  ),
                );
              }
            }
          }
        }
      }
      storage.savePendingDeletedSteps(deletedSteps);

      final prevListRemoteById = {
        for (final l in prevLists)
          if (l.remoteId != null) l.id: l.remoteId!,
      };
      final nextTasks = <TaskItem>[];
      for (final task in nextState.tasks) {
        final prev = prevTaskById[task.id];
        if (_taskNeedsSyncStamp(prev, task)) {
          taskSyncNeeded = true;
          dirtyTasks.add(task.id);
          final resolvedRemoteParent =
              (prev != null &&
                  prev.listId != task.listId &&
                  task.remoteId != null &&
                  task.remoteParentFolderId == null)
              ? prevListRemoteById[prev.listId]
              : task.remoteParentFolderId;
          nextTasks.add(
            task.copyWith(
              remoteParentFolderId: resolvedRemoteParent,
              updatedAt: nowUtc,
            ),
          );
        } else {
          nextTasks.add(task);
        }
      }
      stampedTasks = nextTasks;
    }

    final changedGlobalSettingKeys = detectGlobalSettingChanges(
      prevState,
      nextState,
    );
    var settingSyncNeeded = false;
    if (changedGlobalSettingKeys.isNotEmpty) {
      settingSyncNeeded = true;
      dirtySettings.addAll(changedGlobalSettingKeys);
    }

    storage.saveDirtyGroupIds(dirtyGroups);
    storage.saveDirtyListIds(dirtyLists);
    storage.saveDirtyTaskIds(dirtyTasks);
    storage.saveDirtySettingKeys(dirtySettings);

    state = nextState.copyWith(
      groups: stampedGroups,
      lists: stampedLists,
      tasks: stampedTasks,
      mutationVersion:
          (groupSyncNeeded ||
              listSyncNeeded ||
              taskSyncNeeded ||
              settingSyncNeeded)
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
  }

  static bool _isSyncableFolder(TodoList list) =>
      !list.isSmartList || list.smartType == SmartListType.tasks;

  static bool _groupSyncDirty(ListGroup prev, ListGroup next) =>
      prev.title != next.title || prev.orderDateTime != next.orderDateTime;

  static bool _listSyncDirty(TodoList prev, TodoList next) =>
      prev.title != next.title ||
      prev.emoji != next.emoji ||
      prev.groupId != next.groupId ||
      prev.themeColor != next.themeColor ||
      prev.themePhoto != next.themePhoto ||
      prev.sortOption != next.sortOption ||
      prev.sortAscending != next.sortAscending ||
      prev.showCompleted != next.showCompleted ||
      prev.orderDateTime != next.orderDateTime;

  static bool _taskNeedsSyncStamp(TaskItem? prev, TaskItem next) {
    if (prev == null) return true;
    if (prev.steps.length != next.steps.length) return true;
    final normalizedPrev = prev.copyWith(
      remoteId: next.remoteId,
      remoteParentFolderId: next.remoteParentFolderId,
      changeKey: next.changeKey,
      updatedAt: next.updatedAt,
      noteUpdatedAt: next.noteUpdatedAt,
      steps: [
        for (var i = 0; i < prev.steps.length; i++)
          prev.steps[i].copyWith(
            id: next.steps[i].id,
            remoteId: next.steps[i].remoteId,
          ),
      ],
    );
    return normalizedPrev != next;
  }

  List<ListGroup> _reconcileSyncedGroups({
    required List<ListGroup> outcomeGroups,
    required List<ListGroup> snapshotGroups,
    required Set<String> preserveDirtyGroupIds,
  }) {
    final snapshotById = {for (final g in snapshotGroups) g.id: g};
    final currentById = {for (final g in state.groups) g.id: g};
    final outcomeById = {for (final g in outcomeGroups) g.id: g};

    final reconciled = <ListGroup>[];
    for (final current in state.groups) {
      final outcome = outcomeById[current.id];
      final snap = snapshotById[current.id];
      if (outcome == null) {
        if (snap == null) {
          reconciled.add(current);
        }
        continue;
      }
      final editedDuringSync = snap != null && _groupSyncDirty(snap, current);
      if (editedDuringSync) {
        preserveDirtyGroupIds.add(current.id);
        reconciled.add(
          current.copyWith(remoteId: outcome.remoteId ?? current.remoteId),
        );
      } else {
        reconciled.add(outcome.copyWith(isExpanded: current.isExpanded));
      }
    }

    for (final outcome in outcomeGroups) {
      if (!snapshotById.containsKey(outcome.id) &&
          !currentById.containsKey(outcome.id)) {
        reconciled.add(outcome);
      }
    }
    return reconciled;
  }

  List<TodoList> _reconcileSyncedLists({
    required List<TodoList> outcomeLists,
    required List<TodoList> snapshotLists,
    required Set<String> preserveDirtyListIds,
  }) {
    final snapshotById = {for (final l in snapshotLists) l.id: l};
    final currentById = {for (final l in state.lists) l.id: l};
    final outcomeById = {for (final l in outcomeLists) l.id: l};

    final reconciled = <TodoList>[];
    for (final current in state.lists) {
      final outcome = outcomeById[current.id];
      final snap = snapshotById[current.id];
      if (outcome == null) {
        if (snap == null) {
          reconciled.add(current);
        }
        continue;
      }
      if (!_isSyncableFolder(current)) {
        reconciled.add(current);
        continue;
      }
      final editedDuringSync = snap != null && _listSyncDirty(snap, current);
      if (editedDuringSync) {
        preserveDirtyListIds.add(current.id);
        reconciled.add(
          current.copyWith(remoteId: outcome.remoteId ?? current.remoteId),
        );
      } else {
        reconciled.add(outcome.copyWith(icon: current.icon));
      }
    }

    for (final outcome in outcomeLists) {
      if (!snapshotById.containsKey(outcome.id) &&
          !currentById.containsKey(outcome.id)) {
        reconciled.add(outcome);
      }
    }
    return reconciled;
  }

  List<TaskItem> _reconcileSyncedTasks({
    required List<TaskItem> outcomeTasks,
    required List<TaskItem> snapshotTasks,
    required Set<String> validListIds,
    required Set<String> preserveDirtyTaskIds,
  }) {
    final snapshotById = {for (final t in snapshotTasks) t.id: t};
    final currentById = {for (final t in state.tasks) t.id: t};
    final outcomeById = {for (final t in outcomeTasks) t.id: t};

    final newRemoteTasks = <TaskItem>[
      for (final outcome in outcomeTasks)
        if (!snapshotById.containsKey(outcome.id) &&
            !currentById.containsKey(outcome.id) &&
            validListIds.contains(outcome.listId))
          outcome,
    ];

    final existingAndLocal = <TaskItem>[];
    for (final current in state.tasks) {
      if (!validListIds.contains(current.listId)) continue;
      final outcome = outcomeById[current.id];
      final snap = snapshotById[current.id];
      if (outcome == null) {
        if (snap == null) {
          existingAndLocal.add(current);
        }
        continue;
      }
      final editedDuringSync =
          snap != null && _taskNeedsSyncStamp(snap, current);
      if (!editedDuringSync) {
        existingAndLocal.add(outcome);
      } else {
        preserveDirtyTaskIds.add(current.id);
        final outcomeStepRemoteById = {
          for (final s in outcome.steps)
            if (s.remoteId != null) s.id: s.remoteId!,
        };
        final mergedSteps = [
          for (final step in current.steps)
            step.copyWith(
              remoteId: step.remoteId ?? outcomeStepRemoteById[step.id],
            ),
        ];
        existingAndLocal.add(
          current.copyWith(
            remoteId: outcome.remoteId ?? current.remoteId,
            remoteParentFolderId:
                outcome.remoteParentFolderId ?? current.remoteParentFolderId,
            changeKey: outcome.changeKey ?? current.changeKey,
            steps: mergedSteps,
          ),
        );
      }
    }

    return state.addNewTasksOnTop
        ? [...newRemoteTasks, ...existingAndLocal]
        : [...existingAndLocal, ...newRemoteTasks];
  }

  Future<void> applySyncResult({
    List<ListGroup>? groups,
    required List<TodoList> lists,
    required List<TaskItem> tasks,
    SyncedSettingsPatch? settingsPatch,
    List<ListGroup>? snapshotGroups,
    List<TodoList>? snapshotLists,
    List<TaskItem>? snapshotTasks,
    TodoState? snapshotState,
    List<String>? processedDeletedGroupRemoteIds,
    List<String>? processedDeletedListRemoteIds,
    List<String>? processedDeletedTaskRemoteIds,
    List<PendingStepDeletion>? processedDeletedSteps,
    Set<String>? syncedGroupIds,
    Set<String>? syncedListIds,
    Set<String>? syncedTaskIds,
    Set<String>? syncedSettingKeys,
  }) async {
    final preserveDirtyGroups = <String>{};
    final preserveDirtyLists = <String>{};
    final preserveDirtyTasks = <String>{};

    final reconciledGroups = groups == null
        ? state.groups
        : (snapshotGroups != null
              ? _reconcileSyncedGroups(
                  outcomeGroups: groups,
                  snapshotGroups: snapshotGroups,
                  preserveDirtyGroupIds: preserveDirtyGroups,
                )
              : groups);

    var reconciledLists = snapshotLists != null
        ? _reconcileSyncedLists(
            outcomeLists: lists,
            snapshotLists: snapshotLists,
            preserveDirtyListIds: preserveDirtyLists,
          )
        : lists;

    final validGroupIds = {for (final g in reconciledGroups) g.id};
    reconciledLists = [
      for (final list in reconciledLists)
        if (list.groupId != null && !validGroupIds.contains(list.groupId))
          list.copyWith(groupId: null)
        else
          list,
    ];

    final validListIds = {for (final l in reconciledLists) l.id};
    final reconciledTasks = snapshotTasks != null
        ? _reconcileSyncedTasks(
            outcomeTasks: tasks,
            snapshotTasks: snapshotTasks,
            validListIds: validListIds,
            preserveDirtyTaskIds: preserveDirtyTasks,
          )
        : tasks;

    final remainingDirtyGroups = storage.loadDirtyGroupIds().toSet()
      ..removeAll(syncedGroupIds ?? const {})
      ..addAll(preserveDirtyGroups);
    final remainingDirtyLists = storage.loadDirtyListIds().toSet()
      ..removeAll(syncedListIds ?? const {})
      ..addAll(preserveDirtyLists);
    final remainingDirtyTasks = storage.loadDirtyTaskIds().toSet()
      ..removeAll(syncedTaskIds ?? const {})
      ..addAll(preserveDirtyTasks);
    final remainingDirtySettings = storage.loadDirtySettingKeys().toSet()
      ..removeAll(syncedSettingKeys ?? const {});

    var nextState = state;
    if (settingsPatch != null) {
      final applied = await applySyncedSettingsPatch(
        storage: storage,
        current: state,
        snapshot: snapshotState,
        patch: settingsPatch,
        lists: reconciledLists,
        dirtySettings: remainingDirtySettings,
      );
      nextState = applied.state;
      reconciledLists = applied.lists;
    }

    final sortedGroups = sortGroupsByOrder(reconciledGroups);
    final sortedLists = sortListsPreservingSmartLists(reconciledLists);

    final nextExpanded = Map<String, bool>.from(
      nextState.completedExpandedByList,
    );
    var expandedChanged = false;
    for (final list in sortedLists) {
      if (list.smartType == SmartListType.all ||
          list.smartType == SmartListType.completed ||
          list.smartType == SmartListType.important) {
        continue;
      }
      if (_isSyncableFolder(list)) {
        if (list.remoteId != null && !remainingDirtyLists.contains(list.id)) {
          if (nextExpanded[list.id] != list.showCompleted) {
            nextExpanded[list.id] = list.showCompleted;
            expandedChanged = true;
          }
        }
      } else {
        final showKey = smartListSettingKeyMap[list.id]?.showCompletedKey;
        final patchedShow =
            settingsPatch?.smartListPatches[list.id]?.showCompleted;
        if (patchedShow != null &&
            showKey != null &&
            !remainingDirtySettings.contains(showKey)) {
          if (nextExpanded[list.id] != list.showCompleted) {
            nextExpanded[list.id] = list.showCompleted;
            expandedChanged = true;
          }
        }
      }
    }

    final now = DateTime.now();
    final syncedTasks = [
      for (final task in reconciledTasks)
        syncMyDayFlag(
          task,
          now: now,
          showDueTodayInMyDay: nextState.showDueTodayInMyDay,
        ),
    ];

    final remainingDeletedGroups = processedDeletedGroupRemoteIds == null
        ? storage.loadPendingDeletedGroupRemoteIds()
        : storage
              .loadPendingDeletedGroupRemoteIds()
              .where((id) => !processedDeletedGroupRemoteIds.contains(id))
              .toList();
    final remainingDeletedLists = processedDeletedListRemoteIds == null
        ? storage.loadPendingDeletedListRemoteIds()
        : storage
              .loadPendingDeletedListRemoteIds()
              .where((id) => !processedDeletedListRemoteIds.contains(id))
              .toList();
    final remainingDeletedTasks = processedDeletedTaskRemoteIds == null
        ? storage.loadPendingDeletedTaskRemoteIds()
        : storage
              .loadPendingDeletedTaskRemoteIds()
              .where((id) => !processedDeletedTaskRemoteIds.contains(id))
              .toList();
    final processedStepKeys = processedDeletedSteps == null
        ? const <String>{}
        : {
            for (final s in processedDeletedSteps)
              '${s.taskRemoteId}::${s.stepRemoteId}',
          };
    final remainingDeletedSteps = processedDeletedSteps == null
        ? storage.loadPendingDeletedSteps()
        : storage
              .loadPendingDeletedSteps()
              .where(
                (s) => !processedStepKeys.contains(
                  '${s.taskRemoteId}::${s.stepRemoteId}',
                ),
              )
              .toList();

    await storage.saveGroups(sortedGroups);
    await storage.saveLists(sortedLists);
    await storage.saveTasks(syncedTasks);
    if (expandedChanged) {
      await storage.saveCompletedExpandedByList(nextExpanded);
    }
    await storage.savePendingDeletedGroupRemoteIds(remainingDeletedGroups);
    await storage.savePendingDeletedListRemoteIds(remainingDeletedLists);
    await storage.savePendingDeletedTaskRemoteIds(remainingDeletedTasks);
    await storage.savePendingDeletedSteps(remainingDeletedSteps);
    await storage.saveDirtyGroupIds(remainingDirtyGroups);
    await storage.saveDirtyListIds(remainingDirtyLists);
    await storage.saveDirtyTaskIds(remainingDirtyTasks);
    await storage.saveDirtySettingKeys(remainingDirtySettings);

    final validSelectedListId =
        sortedLists.any((l) => l.id == nextState.selectedListId)
        ? nextState.selectedListId
        : 'my_day';

    state = nextState.copyWith(
      groups: sortedGroups,
      lists: sortedLists,
      tasks: syncedTasks,
      selectedListId: validSelectedListId,
      completedExpandedByList: nextExpanded,
    );
  }

  void selectList(String listId) {
    state = state.copyWith(selectedListId: listId, selectedTaskId: null);
    storage.saveSelectedListId(listId);
  }

  void setLastEnteredListId(String? listId) {
    storage.saveLastEnteredListId(listId);
  }

  void setCompletedExpanded(String listId, bool expanded) {
    final nextExpanded = Map<String, bool>.from(state.completedExpandedByList)
      ..[listId] = expanded;
    final target = state.lists.where((l) => l.id == listId).firstOrNull;
    final shouldSyncListShowCompleted =
        target != null &&
        target.smartType != SmartListType.all &&
        target.smartType != SmartListType.completed &&
        target.showCompleted != expanded;
    if (shouldSyncListShowCompleted) {
      final updatedLists = [
        for (final list in state.lists)
          if (list.id == listId)
            list.copyWith(showCompleted: expanded)
          else
            list,
      ];
      commit(
        state.copyWith(
          lists: updatedLists,
          completedExpandedByList: nextExpanded,
        ),
      );
      storage.saveLists(state.lists);
    } else {
      state = state.copyWith(completedExpandedByList: nextExpanded);
    }
    storage.saveCompletedExpandedByList(nextExpanded);
  }

  void selectTask(String? taskId) {
    state = state.copyWith(selectedTaskId: taskId);
  }
}

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);
