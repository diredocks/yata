import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../homeview/home_view_ordering.dart';
import '../models/default_lists.dart';
import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'todo_database.dart';
import 'todo_repository.dart';
import 'todo_settings_store.dart';
import 'todo_settings_sync.dart';
import 'todo_state.dart';
import 'todo_sync_reconciler.dart';

export '../account/account_provider.dart' show sharedPreferencesProvider;
export 'todo_database.dart';
export 'todo_settings_sync.dart';
export 'todo_state.dart';

final todoDatabaseProvider = Provider<TodoDatabase?>((ref) {
  if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
    return null;
  }
  final db = TodoDatabase();
  ref.onDispose(() => unawaited(db.close()));
  return db;
});

final todoSettingsStoreProvider = Provider<TodoSettingsStore>((ref) {
  return TodoSettingsStore(
    ref.watch(sharedPreferencesProvider),
    accountId: ref.watch(accountProvider.select((s) => s.activeAccountId)),
  );
});

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return TodoRepository.forSession(
    ref.watch(todoDatabaseProvider) ?? sharedFallbackTodoDatabase,
    ref.watch(todoSettingsStoreProvider),
  );
});

class TodoNotifier extends Notifier<TodoState> {
  int _idCounter = 0;

  String nextId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  TodoRepository get repository => ref.read(todoRepositoryProvider);

  TodoSettingsStore get settings => ref.read(todoSettingsStoreProvider);

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
    final repository = ref.watch(todoRepositoryProvider);
    final settingsStore = ref.watch(todoSettingsStoreProvider);
    final settings = settingsStore.load();
    final now = DateTime.now();
    final todayKey = _todayKey(now);
    var changed = false;
    final tasks = <TaskItem>[];
    for (final task in repository.readCachedTasks()) {
      final synced = syncMyDayFlag(
        task,
        now: now,
        showDueTodayInMyDay: settings.showDueTodayInMyDay,
      );
      if (!identical(synced, task)) {
        changed = true;
      }
      tasks.add(synced);
    }
    if (changed) {
      repository.saveTasks(tasks);
    }
    if (settings.lastMyDayResetDate != todayKey) {
      settingsStore.saveLastMyDayResetDate(todayKey);
    }

    return TodoState(
      lists: normalizeSmartLists(repository.readCachedLists()),
      groups: [...repository.readCachedGroups()],
      tasks: tasks,
      selectedListId: settings.selectedListId,
      themeMode: settings.themeMode,
      addNewTasksOnTop: settings.addNewTasksOnTop,
      moveStarredTasksToTop: settings.moveStarredTasksToTop,
      playCompletionSound: settings.playCompletionSound,
      confirmBeforeDeleting: settings.confirmBeforeDeleting,
      showDueTodayInMyDay: settings.showDueTodayInMyDay,
      startOfWeek: settings.startOfWeek,
      showSmartListImportant: settings.showSmartListImportant,
      showSmartListPlanned: settings.showSmartListPlanned,
      showSmartListAll: settings.showSmartListAll,
      showSmartListCompleted: settings.showSmartListCompleted,
      autoHideEmptySmartLists: settings.autoHideEmptySmartLists,
      plannedDueDateFilter: settings.plannedDueDateFilter,
      plannedGroupOption: settings.plannedGroupOption,
      useDynamicColor: settings.useDynamicColor,
      remindersEnabled: settings.remindersEnabled,
      pinReminders: settings.pinReminders,
      accurateReminders: settings.accurateReminders,
      dueTodayNotificationsEnabled: settings.dueTodayNotificationsEnabled,
      dueTodayNotificationHour: settings.dueTodayNotificationHour,
      dueTodayNotificationMinute: settings.dueTodayNotificationMinute,
      routineNotificationEnabled: settings.routineNotificationEnabled,
      routineNotificationHour: settings.routineNotificationHour,
      routineNotificationMinute: settings.routineNotificationMinute,
      routineNotificationDays: settings.routineNotificationDays,
      quickAddNotificationEnabled: settings.quickAddNotificationEnabled,
      completedExpandedByList: settings.completedExpandedByList,
    );
  }

  void commit(TodoState nextState) {
    final prevState = state;
    final prevGroups = prevState.groups;
    final prevLists = prevState.lists;
    final prevTasks = prevState.tasks;
    final nowUtc = DateTime.now().toUtc();

    final dirtyGroups = repository.loadDirtyGroupIds().toSet();
    final dirtyLists = repository.loadDirtyListIds().toSet();
    final dirtyTasks = repository.loadDirtyTaskIds().toSet();
    final dirtySettings = settings.loadDirtySettingKeys().toSet();

    var stampedGroups = nextState.groups;
    var groupSyncNeeded = false;
    if (!identical(prevGroups, nextState.groups)) {
      final prevGroupById = {for (final g in prevGroups) g.id: g};
      final groupDeletions = collectPendingRemoteDeletions<ListGroup>(
        prevItems: prevGroups,
        nextIds: {for (final g in nextState.groups) g.id},
        idOf: (g) => g.id,
        remoteIdOf: (g) => g.remoteId,
        dirtyIds: dirtyGroups,
        existingDeletedRemoteIds: repository.loadPendingDeletedGroupRemoteIds(),
      );
      groupSyncNeeded = groupDeletions.changed;
      repository.savePendingDeletedGroupRemoteIds(
        groupDeletions.deletedRemoteIds,
      );

      stampedGroups = [
        for (final group in nextState.groups)
          () {
            final prev = prevGroupById[group.id];
            if (prev == null || isGroupSyncDirty(prev, group)) {
              groupSyncNeeded = true;
              dirtyGroups.add(group.id);
              return group.copyWith(updatedAt: nowUtc);
            }
            return group;
          }(),
      ];
    }

    var stampedLists = nextState.lists;
    var listSyncNeeded = false;
    if (!identical(prevLists, nextState.lists)) {
      final prevListById = {for (final l in prevLists) l.id: l};
      final listDeletions = collectPendingRemoteDeletions<TodoList>(
        prevItems: prevLists,
        nextIds: {for (final l in nextState.lists) l.id},
        idOf: (l) => l.id,
        remoteIdOf: (l) => l.remoteId,
        dirtyIds: dirtyLists,
        existingDeletedRemoteIds: repository.loadPendingDeletedListRemoteIds(),
        canDeleteRemotely: (l) => !l.isSmartList,
      );
      listSyncNeeded = listDeletions.changed;
      repository.savePendingDeletedListRemoteIds(
        listDeletions.deletedRemoteIds,
      );

      stampedLists = [
        for (final list in nextState.lists)
          () {
            final prev = prevListById[list.id];
            if (isSyncableFolderList(list)) {
              if (prev == null || isListSyncDirty(prev, list)) {
                listSyncNeeded = true;
                dirtyLists.add(list.id);
                return list.copyWith(updatedAt: nowUtc);
              }
              return list;
            }
            if (prev != null) {
              final changedSmartKeys = smartListChangedSettingKeys(prev, list);
              if (changedSmartKeys.isNotEmpty) {
                listSyncNeeded = true;
                dirtySettings.addAll(changedSmartKeys);
              }
            }
            return list;
          }(),
      ];
    }

    var stampedTasks = nextState.tasks;
    var taskSyncNeeded = false;
    if (!identical(prevTasks, nextState.tasks)) {
      final prevTaskById = {for (final t in prevTasks) t.id: t};
      final taskDeletions = collectPendingRemoteDeletions<TaskItem>(
        prevItems: prevTasks,
        nextIds: {for (final t in nextState.tasks) t.id},
        idOf: (t) => t.id,
        remoteIdOf: (t) => t.remoteId,
        dirtyIds: dirtyTasks,
        existingDeletedRemoteIds: repository.loadPendingDeletedTaskRemoteIds(),
      );
      taskSyncNeeded = taskDeletions.changed;
      repository.savePendingDeletedTaskRemoteIds(
        taskDeletions.deletedRemoteIds,
      );

      final stepDeletions = collectPendingStepDeletions(
        prevTaskById: prevTaskById,
        nextTasks: nextState.tasks,
        existingDeletedSteps: repository.loadPendingDeletedSteps(),
      );
      if (stepDeletions.changed) taskSyncNeeded = true;
      repository.savePendingDeletedSteps(stepDeletions.deletedSteps);

      final prevListRemoteById = {
        for (final l in prevLists)
          if (l.remoteId != null) l.id: l.remoteId!,
      };
      stampedTasks = [
        for (final task in nextState.tasks)
          () {
            final prev = prevTaskById[task.id];
            if (!doesTaskNeedSyncStamp(prev, task)) return task;
            taskSyncNeeded = true;
            dirtyTasks.add(task.id);
            final resolvedRemoteParent =
                (prev != null &&
                    prev.listId != task.listId &&
                    task.remoteId != null &&
                    task.remoteParentFolderId == null)
                ? prevListRemoteById[prev.listId]
                : task.remoteParentFolderId;
            return task.copyWith(
              remoteParentFolderId: resolvedRemoteParent,
              updatedAt: nowUtc,
            );
          }(),
      ];
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

    repository.saveDirtyGroupIds(dirtyGroups);
    repository.saveDirtyListIds(dirtyLists);
    repository.saveDirtyTaskIds(dirtyTasks);
    settings.saveDirtySettingKeys(dirtySettings);

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
    List<T> filterProcessed<T>(List<T> pending, List<T>? processed) =>
        processed == null
        ? pending
        : pending.where((item) => !processed.contains(item)).toList();

    final preserveDirtyGroups = <String>{};
    final preserveDirtyLists = <String>{};
    final preserveDirtyTasks = <String>{};

    final reconciledGroups = groups == null
        ? state.groups
        : (snapshotGroups != null
              ? reconcileSyncedGroups(
                  currentGroups: state.groups,
                  outcomeGroups: groups,
                  snapshotGroups: snapshotGroups,
                  preserveDirtyGroupIds: preserveDirtyGroups,
                )
              : groups);

    var reconciledLists = snapshotLists != null
        ? reconcileSyncedLists(
            currentLists: state.lists,
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
        ? reconcileSyncedTasks(
            currentTasks: state.tasks,
            outcomeTasks: tasks,
            snapshotTasks: snapshotTasks,
            validListIds: validListIds,
            preserveDirtyTaskIds: preserveDirtyTasks,
            addNewTasksOnTop: state.addNewTasksOnTop,
          )
        : tasks;

    final remainingDirtyGroups = repository.loadDirtyGroupIds().toSet()
      ..removeAll(syncedGroupIds ?? const {})
      ..addAll(preserveDirtyGroups);
    final remainingDirtyLists = repository.loadDirtyListIds().toSet()
      ..removeAll(syncedListIds ?? const {})
      ..addAll(preserveDirtyLists);
    final remainingDirtyTasks = repository.loadDirtyTaskIds().toSet()
      ..removeAll(syncedTaskIds ?? const {})
      ..addAll(preserveDirtyTasks);
    final remainingDirtySettings = settings.loadDirtySettingKeys().toSet()
      ..removeAll(syncedSettingKeys ?? const {});

    var nextState = state;
    final settingsPersistFutures = <Future<void>>[];
    if (settingsPatch != null) {
      final applied = applySyncedSettingsPatch(
        settings: settings,
        current: state,
        snapshot: snapshotState,
        patch: settingsPatch,
        lists: reconciledLists,
        dirtySettings: remainingDirtySettings,
      );
      nextState = applied.state;
      reconciledLists = applied.lists;
      settingsPersistFutures.addAll(applied.persistFutures);
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
      if (isSyncableFolderList(list)) {
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

    final remainingDeletedGroups = filterProcessed(
      repository.loadPendingDeletedGroupRemoteIds(),
      processedDeletedGroupRemoteIds,
    );
    final remainingDeletedLists = filterProcessed(
      repository.loadPendingDeletedListRemoteIds(),
      processedDeletedListRemoteIds,
    );
    final remainingDeletedTasks = filterProcessed(
      repository.loadPendingDeletedTaskRemoteIds(),
      processedDeletedTaskRemoteIds,
    );
    final remainingDeletedSteps = filterProcessed(
      repository.loadPendingDeletedSteps(),
      processedDeletedSteps,
    );

    final validSelectedListId =
        sortedLists.any((l) => l.id == nextState.selectedListId)
        ? nextState.selectedListId
        : 'my_day';

    // Commit repository caches and Riverpod state synchronously before awaiting
    // SQLite/prefs persistence so concurrent UI edits cannot be overwritten.
    final persistFutures = <Future<Object?>>[
      ...settingsPersistFutures,
      repository.saveGroups(sortedGroups),
      repository.saveLists(sortedLists),
      repository.saveTasks(syncedTasks),
      if (expandedChanged) settings.saveCompletedExpandedByList(nextExpanded),
      repository.savePendingDeletedGroupRemoteIds(remainingDeletedGroups),
      repository.savePendingDeletedListRemoteIds(remainingDeletedLists),
      repository.savePendingDeletedTaskRemoteIds(remainingDeletedTasks),
      repository.savePendingDeletedSteps(remainingDeletedSteps),
      repository.saveDirtyGroupIds(remainingDirtyGroups),
      repository.saveDirtyListIds(remainingDirtyLists),
      repository.saveDirtyTaskIds(remainingDirtyTasks),
      settings.saveDirtySettingKeys(remainingDirtySettings),
    ];

    state = nextState.copyWith(
      groups: sortedGroups,
      lists: sortedLists,
      tasks: syncedTasks,
      selectedListId: validSelectedListId,
      completedExpandedByList: nextExpanded,
    );

    await Future.wait(persistFutures);
  }

  void selectList(String listId) {
    state = state.copyWith(selectedListId: listId, selectedTaskId: null);
    settings.saveSelectedListId(listId);
  }

  void setLastEnteredListId(String? listId) {
    settings.saveLastEnteredListId(listId);
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
      repository.saveLists(state.lists);
    } else {
      state = state.copyWith(completedExpandedByList: nextExpanded);
    }
    settings.saveCompletedExpandedByList(nextExpanded);
  }

  void selectTask(String? taskId) {
    state = state.copyWith(selectedTaskId: taskId);
  }
}

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);
