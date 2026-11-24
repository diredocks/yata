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
import 'sync_dirty_fields.dart';
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
    final dirtyGroupFields = repository.loadDirtyGroupFields();
    final dirtyLists = repository.loadDirtyListIds().toSet();
    final dirtyListFields = repository.loadDirtyListFields();
    final dirtyTasks = repository.loadDirtyTaskIds().toSet();
    final dirtyTaskFields = repository.loadDirtyTaskFields();
    final dirtyStepIds = repository.loadDirtyStepIds();
    final taskBaseNotes = repository.loadTaskBaseNotes();
    final dirtySettings = settings.loadDirtySettingKeys().toSet();

    var stampedGroups = nextState.groups;
    var groupSyncNeeded = false;
    if (!identical(prevGroups, nextState.groups)) {
      final nextGroupIds = {for (final g in nextState.groups) g.id};
      dirtyGroupFields.removeWhere((id, _) => !nextGroupIds.contains(id));

      final prevGroupById = {for (final g in prevGroups) g.id: g};
      final groupDeletions = collectPendingRemoteDeletions<ListGroup>(
        prevItems: prevGroups,
        nextIds: nextGroupIds,
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
              final changed = diffGroupDirtyFields(prev, group);
              if (changed.isNotEmpty) {
                (dirtyGroupFields[group.id] ??= <GroupDirtyField>{}).addAll(
                  changed,
                );
              }
              return group.copyWith(updatedAt: nowUtc);
            }
            return group;
          }(),
      ];
    }

    var stampedLists = nextState.lists;
    var listSyncNeeded = false;
    if (!identical(prevLists, nextState.lists)) {
      final nextListIds = {for (final l in nextState.lists) l.id};
      dirtyListFields.removeWhere((id, _) => !nextListIds.contains(id));

      final prevListById = {for (final l in prevLists) l.id: l};
      final listDeletions = collectPendingRemoteDeletions<TodoList>(
        prevItems: prevLists,
        nextIds: nextListIds,
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
                final changed = diffListDirtyFields(prev, list);
                if (changed.isNotEmpty) {
                  (dirtyListFields[list.id] ??= <ListDirtyField>{}).addAll(
                    changed,
                  );
                }
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
      final nextTaskIds = {for (final t in nextState.tasks) t.id};
      dirtyTaskFields.removeWhere((id, _) => !nextTaskIds.contains(id));
      dirtyStepIds.removeWhere((id, _) => !nextTaskIds.contains(id));
      taskBaseNotes.removeWhere((id, _) => !nextTaskIds.contains(id));

      final prevTaskById = {for (final t in prevTasks) t.id: t};
      final taskDeletions = collectPendingRemoteDeletions<TaskItem>(
        prevItems: prevTasks,
        nextIds: nextTaskIds,
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
            final changedFields = diffTaskDirtyFields(prev, task);
            if (changedFields.isNotEmpty) {
              (dirtyTaskFields[task.id] ??= <TaskDirtyField>{}).addAll(
                changedFields,
              );
            }
            final changedSteps = diffDirtyStepIds(prev, task);
            if (changedSteps.isNotEmpty) {
              (dirtyStepIds[task.id] ??= <String>{}).addAll(changedSteps);
            }
            if (changedFields.contains(TaskDirtyField.body) &&
                prev != null &&
                !taskBaseNotes.containsKey(task.id)) {
              taskBaseNotes[task.id] = prev.note;
            }
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
    repository.saveDirtyGroupFields(dirtyGroupFields);
    repository.saveDirtyListIds(dirtyLists);
    repository.saveDirtyListFields(dirtyListFields);
    repository.saveDirtyTaskIds(dirtyTasks);
    repository.saveDirtyTaskFields(dirtyTaskFields);
    repository.saveDirtyStepIds(dirtyStepIds);
    repository.saveTaskBaseNotes(taskBaseNotes);
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
    Map<String, Set<GroupDirtyField>>? syncedGroupFields,
    Map<String, Set<ListDirtyField>>? syncedListFields,
    Map<String, Set<TaskDirtyField>>? syncedTaskFields,
    Map<String, Set<String>>? syncedStepIds,
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

    final nextGroupFields = repository.loadDirtyGroupFields();
    for (final id in syncedGroupIds ?? const <String>{}) {
      final pushed = syncedGroupFields?[id];
      if (pushed == null) {
        nextGroupFields.remove(id);
      } else {
        final cur = nextGroupFields[id];
        if (cur != null) {
          cur.removeAll(pushed);
          if (cur.isEmpty) nextGroupFields.remove(id);
        }
      }
    }
    if (preserveDirtyGroups.isNotEmpty) {
      final snapById = {
        for (final g in snapshotGroups ?? const <ListGroup>[]) g.id: g,
      };
      final curById = {for (final g in state.groups) g.id: g};
      for (final id in preserveDirtyGroups) {
        final cur = curById[id];
        if (cur == null) continue;
        final mid = diffGroupDirtyFields(snapById[id], cur);
        if (mid.isNotEmpty) {
          (nextGroupFields[id] ??= <GroupDirtyField>{}).addAll(mid);
        }
      }
    }

    final nextListFields = repository.loadDirtyListFields();
    for (final id in syncedListIds ?? const <String>{}) {
      final pushed = syncedListFields?[id];
      if (pushed == null) {
        nextListFields.remove(id);
      } else {
        final cur = nextListFields[id];
        if (cur != null) {
          cur.removeAll(pushed);
          if (cur.isEmpty) nextListFields.remove(id);
        }
      }
    }
    if (preserveDirtyLists.isNotEmpty) {
      final snapById = {
        for (final l in snapshotLists ?? const <TodoList>[]) l.id: l,
      };
      final curById = {for (final l in state.lists) l.id: l};
      for (final id in preserveDirtyLists) {
        final cur = curById[id];
        if (cur == null) continue;
        final mid = diffListDirtyFields(snapById[id], cur);
        if (mid.isNotEmpty) {
          (nextListFields[id] ??= <ListDirtyField>{}).addAll(mid);
        }
      }
    }

    final nextTaskFields = repository.loadDirtyTaskFields();
    final nextStepIds = repository.loadDirtyStepIds();
    final nextBaseNotes = repository.loadTaskBaseNotes();
    for (final id in syncedTaskIds ?? const <String>{}) {
      final pushedFields = syncedTaskFields?[id];
      if (pushedFields == null) {
        nextTaskFields.remove(id);
        nextStepIds.remove(id);
        nextBaseNotes.remove(id);
      } else {
        final curFields = nextTaskFields[id];
        if (curFields != null) {
          curFields.removeAll(pushedFields);
          if (curFields.isEmpty) nextTaskFields.remove(id);
        }
        final pushedSteps = syncedStepIds?[id];
        if (pushedSteps == null) {
          if (pushedFields.contains(TaskDirtyField.steps)) {
            nextStepIds.remove(id);
          }
        } else {
          final curSteps = nextStepIds[id];
          if (curSteps != null) {
            curSteps.removeAll(pushedSteps);
            if (curSteps.isEmpty) nextStepIds.remove(id);
          }
        }
        if (pushedFields.contains(TaskDirtyField.body) &&
            nextTaskFields[id]?.contains(TaskDirtyField.body) != true) {
          nextBaseNotes.remove(id);
        }
      }
    }
    if (preserveDirtyTasks.isNotEmpty) {
      final snapById = {
        for (final t in snapshotTasks ?? const <TaskItem>[]) t.id: t,
      };
      final curById = {for (final t in state.tasks) t.id: t};
      for (final id in preserveDirtyTasks) {
        final cur = curById[id];
        if (cur == null) continue;
        final snap = snapById[id];
        final midFields = diffTaskDirtyFields(snap, cur);
        final midSteps = diffDirtyStepIds(snap, cur);
        if (midFields.isNotEmpty) {
          (nextTaskFields[id] ??= <TaskDirtyField>{}).addAll(midFields);
        }
        if (midSteps.isNotEmpty) {
          (nextStepIds[id] ??= <String>{}).addAll(midSteps);
        }
        if (midFields.contains(TaskDirtyField.body) &&
            snap != null &&
            !nextBaseNotes.containsKey(id)) {
          nextBaseNotes[id] = snap.note;
        }
      }
    }

    final remainingDirtyGroups =
        (repository.loadDirtyGroupIds().toSet()
          ..removeAll(syncedGroupIds ?? const {})
          ..addAll(nextGroupFields.keys)
          ..addAll(preserveDirtyGroups));
    final remainingDirtyLists =
        (repository.loadDirtyListIds().toSet()
          ..removeAll(syncedListIds ?? const {})
          ..addAll(nextListFields.keys)
          ..addAll(preserveDirtyLists));
    final remainingDirtyTasks =
        (repository.loadDirtyTaskIds().toSet()
          ..removeAll(syncedTaskIds ?? const {})
          ..addAll(nextTaskFields.keys)
          ..addAll(preserveDirtyTasks));
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

    final validGroupIdsPost = {for (final g in sortedGroups) g.id};
    final validListIdsPost = {for (final l in sortedLists) l.id};
    final validTaskIdsPost = {for (final t in syncedTasks) t.id};
    remainingDirtyGroups.retainWhere(validGroupIdsPost.contains);
    remainingDirtyLists.retainWhere(validListIdsPost.contains);
    remainingDirtyTasks.retainWhere(validTaskIdsPost.contains);
    nextGroupFields.removeWhere((id, _) => !validGroupIdsPost.contains(id));
    nextListFields.removeWhere((id, _) => !validListIdsPost.contains(id));
    nextTaskFields.removeWhere((id, _) => !validTaskIdsPost.contains(id));
    nextStepIds.removeWhere((id, _) => !validTaskIdsPost.contains(id));
    nextBaseNotes.removeWhere(
      (id, _) =>
          !validTaskIdsPost.contains(id) ||
          nextTaskFields[id]?.contains(TaskDirtyField.body) != true,
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
      repository.saveDirtyGroupFields(nextGroupFields),
      repository.saveDirtyListIds(remainingDirtyLists),
      repository.saveDirtyListFields(nextListFields),
      repository.saveDirtyTaskIds(remainingDirtyTasks),
      repository.saveDirtyTaskFields(nextTaskFields),
      repository.saveDirtyStepIds(nextStepIds),
      repository.saveTaskBaseNotes(nextBaseNotes),
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

  /// Applies a remote task snapshot update (e.g. from realtime events) without
  /// bumping [TodoState.mutationVersion] or marking tasks dirty.
  Future<void> applyRemoteTasksSnapshot(List<TaskItem> nextTasks) async {
    final now = DateTime.now();
    final syncedTasks = [
      for (final task in nextTasks)
        syncMyDayFlag(
          task,
          now: now,
          showDueTodayInMyDay: state.showDueTodayInMyDay,
        ),
    ];
    final validSelectedTaskId =
        state.selectedTaskId != null &&
            syncedTasks.any((t) => t.id == state.selectedTaskId)
        ? state.selectedTaskId
        : null;

    // Update repository cache & Riverpod state synchronously BEFORE awaiting
    // SQLite so concurrent edits or sync starts see the latest tasks
    // immediately.
    final saveFuture = repository.saveTasks(syncedTasks);
    state = state.copyWith(
      tasks: syncedTasks,
      selectedTaskId: validSelectedTaskId,
    );
    await saveFuture;
  }

  /// Applies a remote folder-group snapshot (e.g. from realtime events) without
  /// bumping [TodoState.mutationVersion] or marking groups dirty.
  Future<void> applyRemoteGroupsSnapshot(List<ListGroup> nextGroups) async {
    final sortedGroups = sortGroupsByOrder(nextGroups);
    final validGroupIds = {for (final g in sortedGroups) g.id};
    var listsChanged = false;
    final updatedLists = [
      for (final list in state.lists)
        if (list.groupId != null && !validGroupIds.contains(list.groupId))
          () {
            listsChanged = true;
            return list.copyWith(groupId: null);
          }()
        else
          list,
    ];
    final persistFutures = <Future<Object?>>[
      repository.saveGroups(sortedGroups),
      if (listsChanged) repository.saveLists(updatedLists),
    ];
    state = state.copyWith(
      groups: sortedGroups,
      lists: listsChanged ? updatedLists : state.lists,
    );
    await Future.wait(persistFutures);
  }

  /// Applies a remote folder/list snapshot (e.g. from realtime events) without
  /// bumping [TodoState.mutationVersion] or marking lists dirty.
  Future<void> applyRemoteListsSnapshot({
    required List<TodoList> nextLists,
    List<TaskItem>? nextTasks,
  }) async {
    final sortedLists = sortListsPreservingSmartLists(nextLists);
    final dirtyListIds = repository.loadDirtyListIds().toSet();
    final nextExpanded = Map<String, bool>.from(state.completedExpandedByList);
    var expandedChanged = false;
    for (final list in sortedLists) {
      if (isSyncableFolderList(list) &&
          list.remoteId != null &&
          !dirtyListIds.contains(list.id) &&
          nextExpanded[list.id] != list.showCompleted) {
        nextExpanded[list.id] = list.showCompleted;
        expandedChanged = true;
      }
    }
    final validSelectedListId =
        sortedLists.any((l) => l.id == state.selectedListId)
        ? state.selectedListId
        : 'my_day';
    final effectiveTasks = nextTasks ?? state.tasks;
    final validSelectedTaskId =
        state.selectedTaskId != null &&
            effectiveTasks.any((t) => t.id == state.selectedTaskId)
        ? state.selectedTaskId
        : null;

    final persistFutures = <Future<Object?>>[
      repository.saveLists(sortedLists),
      if (nextTasks != null) repository.saveTasks(effectiveTasks),
      if (expandedChanged) settings.saveCompletedExpandedByList(nextExpanded),
    ];
    state = state.copyWith(
      lists: sortedLists,
      tasks: effectiveTasks,
      selectedListId: validSelectedListId,
      selectedTaskId: validSelectedTaskId,
      completedExpandedByList: nextExpanded,
    );
    await Future.wait(persistFutures);
  }

  /// Applies a remote setting patch (e.g. from realtime `Setting` events)
  /// without bumping [TodoState.mutationVersion] or marking settings dirty.
  Future<void> applyRemoteSettingsPatch(SyncedSettingsPatch patch) async {
    final remainingDirtySettings = settings.loadDirtySettingKeys().toSet();
    final applied = applySyncedSettingsPatch(
      settings: settings,
      current: state,
      snapshot: null,
      patch: patch,
      lists: state.lists,
      dirtySettings: remainingDirtySettings,
    );
    final nextState = applied.state;
    final nextLists = applied.lists;

    final nextExpanded = Map<String, bool>.from(
      nextState.completedExpandedByList,
    );
    var expandedChanged = false;
    for (final list in nextLists) {
      if (isSyncableFolderList(list) ||
          list.smartType == SmartListType.all ||
          list.smartType == SmartListType.completed ||
          list.smartType == SmartListType.important) {
        continue;
      }
      final showKey = smartListSettingKeyMap[list.id]?.showCompletedKey;
      final patchedShow = patch.smartListPatches[list.id]?.showCompleted;
      if (patchedShow != null &&
          showKey != null &&
          !remainingDirtySettings.contains(showKey) &&
          nextExpanded[list.id] != list.showCompleted) {
        nextExpanded[list.id] = list.showCompleted;
        expandedChanged = true;
      }
    }

    final now = DateTime.now();
    var tasksChanged = false;
    final updatedTasks = [
      for (final task in nextState.tasks)
        () {
          final updated = syncMyDayFlag(
            task,
            now: now,
            showDueTodayInMyDay: nextState.showDueTodayInMyDay,
          );
          if (!identical(updated, task)) tasksChanged = true;
          return updated;
        }(),
    ];

    final listsChanged = !identical(nextLists, state.lists);
    final persistFutures = <Future<Object?>>[
      ...applied.persistFutures,
      if (listsChanged) repository.saveLists(nextLists),
      if (tasksChanged) repository.saveTasks(updatedTasks),
      if (expandedChanged) settings.saveCompletedExpandedByList(nextExpanded),
    ];

    state = nextState.copyWith(
      lists: nextLists,
      tasks: tasksChanged ? updatedTasks : nextState.tasks,
      completedExpandedByList: nextExpanded,
    );
    if (persistFutures.isNotEmpty) {
      await Future.wait(persistFutures);
    }
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
