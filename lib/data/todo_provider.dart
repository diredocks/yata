import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../models/account.dart';
import '../models/default_lists.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../sync/microsoft/substrate_push_engine.dart';
import '../sync/sync_store.dart';
import 'custom_background_service.dart';
import 'preferences.dart';
import 'sync_outbox.dart';
import 'todo_database.dart';
import 'todo_repository.dart';
import 'todo_settings_store.dart';
import 'todo_settings_sync.dart';
import 'todo_state.dart';
import 'todo_sync_reconciler.dart';

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

final customBackgroundServiceProvider = Provider<CustomBackgroundService>((
  ref,
) {
  return CustomBackgroundService();
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

  static bool isSameDay(DateTime a, DateTime b) => isSameCalendarDay(a, b);

  /// Recomputes [TaskItem.isInMyDay] from [TaskItem.myDayDate],
  /// [TaskItem.dueDate], and [TaskItem.postponedDay], matching `MyDayContract.kt`.
  static TaskItem syncMyDayFlag(
    TaskItem task, {
    required DateTime now,
    required bool showDueTodayInMyDay,
  }) => computeTaskMyDayFlag(
    task,
    now: now,
    showDueTodayInMyDay: showDueTodayInMyDay,
  );

  /// Whether completing [task] should immediately spawn the next local occurrence.
  ///
  /// For synced Microsoft account tasks (`remoteId != null`), Exchange/Substrate
  /// spawns the next instance on completion PATCH.
  bool shouldSpawnRecurringLocally(TaskItem task) =>
      task.remoteId == null ||
      ref.read(accountProvider).activeAccount is! MicrosoftAccount;

  /// Updates [task]'s due date, clearing recurrence if removed and updating My Day.
  static TaskItem applyDueDate(
    TaskItem task,
    DateTime? dueDate, {
    required DateTime now,
    required bool showDueTodayInMyDay,
  }) {
    final clearPostponed =
        dueDate != null &&
        showDueTodayInMyDay &&
        task.postponedDay != null &&
        isSameDay(dueDate, task.postponedDay!);
    return syncMyDayFlag(
      task.copyWith(
        dueDate: dueDate,
        recurrence: dueDate == null ? RecurrenceType.none : task.recurrence,
        rawRecurrence: dueDate == null ? null : task.rawRecurrence,
        postponedDay: clearPostponed ? null : task.postponedDay,
      ),
      now: now,
      showDueTodayInMyDay: showDueTodayInMyDay,
    );
  }

  /// Updates [task]'s recurrence preset or custom rule.
  static TaskItem applyRecurrence(
    TaskItem task,
    RecurrenceType recurrence, {
    required DateTime now,
    required bool showDueTodayInMyDay,
    DateTime? fallbackDueDate,
    Map<String, dynamic>? rawRecurrence,
  }) {
    final hasRecurrence =
        recurrence != RecurrenceType.none ||
        (rawRecurrence != null && rawRecurrence.isNotEmpty);
    final nextDue = (hasRecurrence && task.dueDate == null)
        ? fallbackDueDate
        : task.dueDate;
    return syncMyDayFlag(
      task.copyWith(
        recurrence: recurrence,
        rawRecurrence: recurrence == RecurrenceType.none ? null : rawRecurrence,
        dueDate: nextDue,
      ),
      now: now,
      showDueTodayInMyDay: showDueTodayInMyDay,
    );
  }

  @override
  TodoState build() {
    final repository = ref.watch(todoRepositoryProvider);
    final settingsStore = ref.watch(todoSettingsStoreProvider);
    final settings = settingsStore.load();
    final now = DateTime.now();
    final todayKey = _todayKey(now);
    final synced = syncTasksMyDayFlags(
      repository.readCachedTasks(),
      now: now,
      showDueTodayInMyDay: settings.showDueTodayInMyDay,
    );
    if (synced.changed) {
      repository.saveTasks(synced.tasks);
    }
    if (settings.lastMyDayResetDate != todayKey) {
      settingsStore.saveLastMyDayResetDate(todayKey);
    }

    return TodoState(
      lists: normalizeSmartLists(repository.readCachedLists()),
      groups: [...repository.readCachedGroups()],
      tasks: [...synced.tasks],
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
      customBackgrounds: settings.customBackgrounds,
    );
  }

  void addCustomBackground(CustomBackground background) {
    final updated = [
      background,
      ...state.customBackgrounds.where((b) => b.id != background.id),
    ];
    state = state.copyWith(customBackgrounds: updated);
    unawaited(settings.saveCustomBackgrounds(updated));
  }

  void deleteCustomBackground(CustomBackground background) {
    final updatedBackgrounds = state.customBackgrounds
        .where(
          (b) => b.id != background.id && b.filePath != background.filePath,
        )
        .toList(growable: false);
    final updatedLists = [
      for (final list in state.lists)
        if (list.customBackgroundPath == background.filePath)
          list.copyWith(customBackgroundPath: null)
        else
          list,
    ];
    final listsChanged = !const ListEquality<TodoList>().equals(
      state.lists,
      updatedLists,
    );
    state = state.copyWith(
      customBackgrounds: updatedBackgrounds,
      lists: listsChanged ? updatedLists : state.lists,
    );
    unawaited(settings.saveCustomBackgrounds(updatedBackgrounds));
    if (listsChanged) {
      unawaited(repository.saveLists(updatedLists));
    }
    unawaited(
      ref.read(customBackgroundServiceProvider).deleteFile(background.filePath),
    );
  }

  Map<String, String> _listRemoteById() => {
    for (final l in state.lists)
      if (l.remoteId != null) l.id: l.remoteId!,
  };

  /// Updates one or more settings in O(1) without diffing entity collections,
  /// optionally persisting derived task updates (such as My Day flags) without
  /// enqueuing task outbox ops.
  void mutateSetting(
    TodoState nextState, {
    List<TaskItem>? derivedTasks,
    Future<void> Function()? persistLocal,
  }) {
    final changedKeys = detectGlobalSettingChanges(state, nextState);
    final outbox = repository.outbox;
    for (final key in changedKeys) {
      outbox.enqueueSetting(key);
    }
    final syncNeeded = changedKeys.isNotEmpty;
    state = nextState.copyWith(
      tasks: derivedTasks ?? nextState.tasks,
      mutationVersion: syncNeeded
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
    if (syncNeeded || derivedTasks != null) {
      unawaited(
        repository.persistSyncBatch(
          fullTasks: derivedTasks,
          saveOutbox: syncNeeded,
        ),
      );
    }
    if (persistLocal != null) {
      unawaited(persistLocal());
    }
  }

  /// Updates a single task by [taskId] in O(1) and persists the touched row
  /// and outbox delta in one atomic SQLite transaction.
  void mutateTask(
    String taskId,
    TaskItem Function(TaskItem current) transform, {
    bool clearSelectedTaskId = false,
  }) {
    final index = state.tasks.indexWhere((t) => t.id == taskId);
    if (index < 0) return;
    final prev = state.tasks[index];
    final next = transform(prev);
    if (identical(prev, next) || prev == next) {
      if (clearSelectedTaskId && state.selectedTaskId != null) {
        state = state.copyWith(selectedTaskId: null);
      }
      return;
    }

    final tracked = enqueueTaskUpsertToOutbox(
      prev: prev,
      next: next,
      nowUtc: DateTime.now().toUtc(),
      outbox: repository.outbox,
      prevListRemoteById: _listRemoteById(),
    );
    final nextTasks = List<TaskItem>.of(state.tasks);
    nextTasks[index] = tracked.task;

    state = state.copyWith(
      tasks: nextTasks,
      selectedTaskId: clearSelectedTaskId ? null : state.selectedTaskId,
      mutationVersion: tracked.syncNeeded
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
    unawaited(
      repository.persistSyncBatch(
        upsertTasks: [tracked.task],
        saveOutbox: tracked.syncNeeded,
      ),
    );
  }

  /// Inserts a single new task and persists it with its outbox op in one
  /// atomic SQLite transaction.
  void addTask(TaskItem task, {bool addToTop = false, int? insertAt}) {
    _insertTask(task, addToTop: addToTop, insertAt: insertAt);
  }

  /// Restores a previously deleted [task] (e.g. via Undo).
  ///
  /// If its pending deletion has not been pushed yet, cancels the queued delete
  /// op and keeps the existing remote identity. Otherwise the remote task is
  /// already deleted (or being deleted), so stale remote IDs are cleared to
  /// recreate the task cleanly instead of triggering Delete-Wins on a 404 PATCH.
  void restoreTask(TaskItem task, {int? insertAt}) {
    if (state.tasks.any((t) => t.id == task.id)) return;
    final cancelledPendingDelete = repository.outbox.cancelPendingDeletes(
      SyncEntityType.task,
      task.id,
    );
    final restored = cancelledPendingDelete
        ? task
        : _stripRemoteIdentityForRestore(task);
    _insertTask(
      restored,
      insertAt: insertAt,
      forceSaveOutbox: cancelledPendingDelete,
    );
  }

  void _insertTask(
    TaskItem task, {
    bool addToTop = false,
    int? insertAt,
    bool forceSaveOutbox = false,
  }) {
    if (state.tasks.any((t) => t.id == task.id)) return;
    final tracked = enqueueTaskUpsertToOutbox(
      prev: null,
      next: task,
      nowUtc: DateTime.now().toUtc(),
      outbox: repository.outbox,
      prevListRemoteById: _listRemoteById(),
    );
    final nextTasks = List<TaskItem>.of(state.tasks);
    if (insertAt != null && insertAt >= 0 && insertAt <= nextTasks.length) {
      nextTasks.insert(insertAt, tracked.task);
    } else if (addToTop) {
      nextTasks.insert(0, tracked.task);
    } else {
      nextTasks.add(tracked.task);
    }
    state = state.copyWith(
      tasks: nextTasks,
      mutationVersion: tracked.syncNeeded
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
    unawaited(
      repository.persistSyncBatch(
        fullTasks: (addToTop || insertAt != null) ? nextTasks : null,
        upsertTasks: (addToTop || insertAt != null) ? const [] : [tracked.task],
        saveOutbox: forceSaveOutbox || tracked.syncNeeded,
      ),
    );
  }

  static TaskItem _stripRemoteIdentityForRestore(TaskItem task) {
    if (task.remoteId == null &&
        task.remoteParentFolderId == null &&
        task.changeKey == null &&
        task.steps.every((s) => s.remoteId == null) &&
        task.attachments.every((a) => a.remoteId == null)) {
      return task;
    }
    return task.copyWith(
      remoteId: null,
      remoteParentFolderId: null,
      changeKey: null,
      steps: [
        for (final step in task.steps)
          step.remoteId == null ? step : step.copyWith(remoteId: null),
      ],
      attachments: [
        for (final att in task.attachments)
          att.remoteId == null ? att : att.copyWith(remoteId: null),
      ],
    );
  }

  /// Deletes one or more tasks by [taskIds] and persists the deletions and
  /// outbox ops in one atomic SQLite transaction.
  void deleteTasks(Set<String> taskIds) {
    if (taskIds.isEmpty) return;
    final outbox = repository.outbox;
    final removedIds = <String>[];
    final remaining = <TaskItem>[];
    for (final task in state.tasks) {
      if (taskIds.contains(task.id)) {
        removedIds.add(task.id);
        outbox.enqueueDelete(
          entityType: SyncEntityType.task,
          localId: task.id,
          remoteId: task.remoteId,
        );
      } else {
        remaining.add(task);
      }
    }
    if (removedIds.isEmpty) return;

    final clearSelected =
        state.selectedTaskId != null && taskIds.contains(state.selectedTaskId);
    state = state.copyWith(
      tasks: remaining,
      selectedTaskId: clearSelected ? null : state.selectedTaskId,
      mutationVersion: state.mutationVersion + 1,
    );
    unawaited(
      repository.persistSyncBatch(deleteTaskIds: removedIds, saveOutbox: true),
    );
  }

  /// Updates a single list by [listId] in O(1) and persists lists + outbox in
  /// one atomic SQLite transaction.
  void mutateList(
    String listId,
    TodoList Function(TodoList current) transform, {
    Map<String, bool>? completedExpandedByList,
  }) {
    final index = state.lists.indexWhere((l) => l.id == listId);
    if (index < 0) return;
    final prev = state.lists[index];
    final next = transform(prev);
    final tracked = enqueueListUpsertToOutbox(
      prev: prev,
      next: next,
      nowUtc: DateTime.now().toUtc(),
      outbox: repository.outbox,
    );
    final nextLists = List<TodoList>.of(state.lists);
    nextLists[index] = tracked.list;

    state = state.copyWith(
      lists: nextLists,
      completedExpandedByList:
          completedExpandedByList ?? state.completedExpandedByList,
      mutationVersion: tracked.syncNeeded
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
    unawaited(
      repository.persistSyncBatch(
        lists: nextLists,
        saveOutbox: tracked.syncNeeded,
      ),
    );
  }

  /// Explicit multi-entity atomic mutation primitive for batch actions,
  /// reorders, group/list management, and list duplication/deletion.
  ///
  /// Only entities named in [touchedGroupIds], [deletedGroupIds],
  /// [touchedListIds], [deletedListIds], [touchedTaskIds], or [deletedTaskIds]
  /// are inspected for outbox enqueuing; untouched rows are never diffed.
  void mutateEntities({
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? tasks,
    Set<String> touchedGroupIds = const {},
    Set<String> deletedGroupIds = const {},
    Set<String> touchedListIds = const {},
    Set<String> deletedListIds = const {},
    Set<String> touchedTaskIds = const {},
    Set<String> deletedTaskIds = const {},
    String? selectedListId,
    bool clearSelectedTaskId = false,
  }) {
    final nowUtc = DateTime.now().toUtc();
    final outbox = repository.outbox;
    var syncNeeded = false;

    var nextGroups = groups ?? state.groups;
    if (groups != null &&
        (touchedGroupIds.isNotEmpty || deletedGroupIds.isNotEmpty)) {
      final prevGroupById = {for (final g in state.groups) g.id: g};
      for (final id in deletedGroupIds) {
        final prev = prevGroupById[id];
        if (prev != null) {
          syncNeeded = true;
          outbox.enqueueDelete(
            entityType: SyncEntityType.group,
            localId: prev.id,
            remoteId: prev.remoteId,
          );
        }
      }
      if (touchedGroupIds.isNotEmpty) {
        nextGroups = [
          for (final g in groups)
            if (touchedGroupIds.contains(g.id))
              () {
                final res = enqueueGroupUpsertToOutbox(
                  prev: prevGroupById[g.id],
                  next: g,
                  nowUtc: nowUtc,
                  outbox: outbox,
                );
                if (res.syncNeeded) syncNeeded = true;
                return res.group;
              }()
            else
              g,
        ];
      }
    }

    final prevListRemoteById = _listRemoteById();
    var nextLists = lists ?? state.lists;
    if (lists != null &&
        (touchedListIds.isNotEmpty || deletedListIds.isNotEmpty)) {
      final prevListById = {for (final l in state.lists) l.id: l};
      for (final id in deletedListIds) {
        final prev = prevListById[id];
        if (prev != null && !prev.isSmartList) {
          syncNeeded = true;
          outbox.enqueueDelete(
            entityType: SyncEntityType.list,
            localId: prev.id,
            remoteId: prev.remoteId,
          );
        }
      }
      if (touchedListIds.isNotEmpty) {
        nextLists = [
          for (final l in lists)
            if (touchedListIds.contains(l.id))
              () {
                final res = enqueueListUpsertToOutbox(
                  prev: prevListById[l.id],
                  next: l,
                  nowUtc: nowUtc,
                  outbox: outbox,
                );
                if (res.syncNeeded) syncNeeded = true;
                return res.list;
              }()
            else
              l,
        ];
      }
    }

    var nextTasks = tasks ?? state.tasks;
    if (tasks != null &&
        (touchedTaskIds.isNotEmpty ||
            deletedTaskIds.isNotEmpty ||
            deletedListIds.isNotEmpty)) {
      final prevTaskById = {for (final t in state.tasks) t.id: t};
      if (deletedListIds.isNotEmpty) {
        final nextTaskIdSet = {for (final t in tasks) t.id};
        for (final prev in state.tasks) {
          if (!nextTaskIdSet.contains(prev.id) &&
              deletedListIds.contains(prev.listId)) {
            if (outbox.cancelPendingUpserts(SyncEntityType.task, prev.id)) {
              syncNeeded = true;
            }
          }
        }
      }
      for (final id in deletedTaskIds) {
        final prev = prevTaskById[id];
        if (prev != null && !deletedListIds.contains(prev.listId)) {
          syncNeeded = true;
          outbox.enqueueDelete(
            entityType: SyncEntityType.task,
            localId: prev.id,
            remoteId: prev.remoteId,
          );
        }
      }
      if (touchedTaskIds.isNotEmpty) {
        nextTasks = [
          for (final t in tasks)
            if (touchedTaskIds.contains(t.id))
              () {
                final res = enqueueTaskUpsertToOutbox(
                  prev: prevTaskById[t.id],
                  next: t,
                  nowUtc: nowUtc,
                  outbox: outbox,
                  prevListRemoteById: prevListRemoteById,
                );
                if (res.syncNeeded) syncNeeded = true;
                return res.task;
              }()
            else
              t,
        ];
      }
    }

    state = state.copyWith(
      groups: nextGroups,
      lists: nextLists,
      tasks: nextTasks,
      selectedListId: selectedListId ?? state.selectedListId,
      selectedTaskId: clearSelectedTaskId ? null : state.selectedTaskId,
      mutationVersion: syncNeeded
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
    unawaited(
      repository.persistSyncBatch(
        groups: groups != null ? nextGroups : null,
        lists: lists != null ? nextLists : null,
        fullTasks: tasks != null ? nextTasks : null,
        saveOutbox: syncNeeded,
      ),
    );
  }

  SyncStore get _syncStore =>
      SyncStore(repository: repository, settings: settings);

  /// Commits server-assigned IDs/metadata and acknowledges pushed Outbox ops
  /// immediately after a Push pass, without waiting for Pull.
  Future<void> commitPushBatch(OutboxPushOutcome outcome) async {
    final result = _syncStore.commitPushToState(
      currentState: state,
      outcome: outcome,
    );
    state = result.nextState;
    await result.persisted;
  }

  /// Applies pulled or realtime remote snapshots/patches without bumping
  /// [TodoState.mutationVersion] or enqueuing to Outbox.
  Future<void> applyRemoteState({
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? tasks,
    Map<String, String>? remoteSettings,
  }) async {
    final result = _syncStore.applyRemoteState(
      currentState: state,
      groups: groups,
      lists: lists,
      tasks: tasks,
      remoteSettings: remoteSettings,
    );
    state = result.nextState;
    await result.persisted;
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
    final target = state.lists.firstWhereOrNull((l) => l.id == listId);
    final shouldSyncListShowCompleted =
        target != null &&
        target.smartType != SmartListType.all &&
        target.smartType != SmartListType.completed &&
        target.showCompleted != expanded;
    if (shouldSyncListShowCompleted) {
      mutateList(
        listId,
        (list) => list.copyWith(showCompleted: expanded),
        completedExpandedByList: nextExpanded,
      );
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
