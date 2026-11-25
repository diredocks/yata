import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../homeview/home_view_ordering.dart';
import '../models/account.dart';
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

  /// Updates [task]'s recurrence preset, clearing any preserved raw custom rule.
  static TaskItem applyRecurrence(
    TaskItem task,
    RecurrenceType recurrence, {
    required DateTime now,
    required bool showDueTodayInMyDay,
    DateTime? fallbackDueDate,
  }) {
    final nextDue = (recurrence != RecurrenceType.none && task.dueDate == null)
        ? fallbackDueDate
        : task.dueDate;
    return syncMyDayFlag(
      task.copyWith(
        recurrence: recurrence,
        rawRecurrence: null,
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
    );
  }

  void commit(TodoState nextState) {
    final tracked = trackLocalCommit(
      prevState: state,
      nextState: nextState,
      nowUtc: DateTime.now().toUtc(),
      dirtyGroupIds: repository.loadDirtyGroupIds().toSet(),
      dirtyGroupFields: repository.loadDirtyGroupFields(),
      dirtyListIds: repository.loadDirtyListIds().toSet(),
      dirtyListFields: repository.loadDirtyListFields(),
      dirtyTaskIds: repository.loadDirtyTaskIds().toSet(),
      dirtyTaskFields: repository.loadDirtyTaskFields(),
      dirtyStepIds: repository.loadDirtyStepIds(),
      taskBaseNotes: repository.loadTaskBaseNotes(),
      dirtySettingKeys: settings.loadDirtySettingKeys().toSet(),
      loadDeletedGroupRemoteIds: repository.loadPendingDeletedGroupRemoteIds,
      loadDeletedListRemoteIds: repository.loadPendingDeletedListRemoteIds,
      loadDeletedTaskRemoteIds: repository.loadPendingDeletedTaskRemoteIds,
      loadDeletedSteps: repository.loadPendingDeletedSteps,
    );

    if (tracked.pendingDeletedGroupRemoteIds != null) {
      repository.savePendingDeletedGroupRemoteIds(
        tracked.pendingDeletedGroupRemoteIds!,
      );
    }
    if (tracked.pendingDeletedListRemoteIds != null) {
      repository.savePendingDeletedListRemoteIds(
        tracked.pendingDeletedListRemoteIds!,
      );
    }
    if (tracked.pendingDeletedTaskRemoteIds != null) {
      repository.savePendingDeletedTaskRemoteIds(
        tracked.pendingDeletedTaskRemoteIds!,
      );
    }
    if (tracked.pendingDeletedSteps != null) {
      repository.savePendingDeletedSteps(tracked.pendingDeletedSteps!);
    }

    repository.saveDirtyGroupIds(tracked.dirtyGroupIds);
    repository.saveDirtyGroupFields(tracked.dirtyGroupFields);
    repository.saveDirtyListIds(tracked.dirtyListIds);
    repository.saveDirtyListFields(tracked.dirtyListFields);
    repository.saveDirtyTaskIds(tracked.dirtyTaskIds);
    repository.saveDirtyTaskFields(tracked.dirtyTaskFields);
    repository.saveDirtyStepIds(tracked.dirtyStepIds);
    repository.saveTaskBaseNotes(tracked.taskBaseNotes);
    settings.saveDirtySettingKeys(tracked.dirtySettingKeys);

    state = nextState.copyWith(
      groups: tracked.groups,
      lists: tracked.lists,
      tasks: tracked.tasks,
      mutationVersion: tracked.syncNeeded
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
    SyncedDirtyFields syncedDirtyFields = const SyncedDirtyFields(),
  }) async {
    List<T> filterProcessed<T>(List<T> pending, List<T>? processed) {
      if (processed == null) return pending;
      final processedSet = processed.toSet();
      return pending.where((item) => !processedSet.contains(item)).toList();
    }

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
    reconcileEntityDirtyFields<ListGroup, GroupDirtyField>(
      dirtyFields: nextGroupFields,
      syncedIds: syncedGroupIds ?? const <String>{},
      syncedFields: syncedDirtyFields.groupFields,
      preserveDirtyIds: preserveDirtyGroups,
      snapshotItems: snapshotGroups,
      currentItems: state.groups,
      idOf: (g) => g.id,
      diffFields: diffGroupDirtyFields,
    );

    final nextListFields = repository.loadDirtyListFields();
    reconcileEntityDirtyFields<TodoList, ListDirtyField>(
      dirtyFields: nextListFields,
      syncedIds: syncedListIds ?? const <String>{},
      syncedFields: syncedDirtyFields.listFields,
      preserveDirtyIds: preserveDirtyLists,
      snapshotItems: snapshotLists,
      currentItems: state.lists,
      idOf: (l) => l.id,
      diffFields: diffListDirtyFields,
    );

    final nextTaskFields = repository.loadDirtyTaskFields();
    reconcileEntityDirtyFields<TaskItem, TaskDirtyField>(
      dirtyFields: nextTaskFields,
      syncedIds: syncedTaskIds ?? const <String>{},
      syncedFields: syncedDirtyFields.taskFields,
      preserveDirtyIds: preserveDirtyTasks,
      snapshotItems: snapshotTasks,
      currentItems: state.tasks,
      idOf: (t) => t.id,
      diffFields: diffTaskDirtyFields,
    );

    final nextStepIds = repository.loadDirtyStepIds();
    final nextBaseNotes = repository.loadTaskBaseNotes();
    reconcileTaskExtraDirtyState(
      nextStepIds: nextStepIds,
      nextBaseNotes: nextBaseNotes,
      syncedTaskIds: syncedTaskIds ?? const <String>{},
      syncedTaskFields: syncedDirtyFields.taskFields,
      syncedStepIds: syncedDirtyFields.stepIds,
      preserveDirtyTasks: preserveDirtyTasks,
      snapshotTasks: snapshotTasks,
      currentTasks: state.tasks,
    );

    final remainingDirtyGroups = (repository.loadDirtyGroupIds().toSet()
      ..removeAll(syncedGroupIds ?? const {})
      ..addAll(nextGroupFields.keys)
      ..addAll(preserveDirtyGroups));
    final remainingDirtyLists = (repository.loadDirtyListIds().toSet()
      ..removeAll(syncedListIds ?? const {})
      ..addAll(nextListFields.keys)
      ..addAll(preserveDirtyLists));
    final remainingDirtyTasks = (repository.loadDirtyTaskIds().toSet()
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

    final expandedOutcome = recomputeCompletedExpandedByList(
      currentExpanded: nextState.completedExpandedByList,
      lists: sortedLists,
      dirtyListIds: remainingDirtyLists,
      dirtySettingKeys: remainingDirtySettings,
      settingsPatch: settingsPatch,
    );

    final syncedTasks = syncTasksMyDayFlags(
      reconciledTasks,
      now: DateTime.now(),
      showDueTodayInMyDay: nextState.showDueTodayInMyDay,
    ).tasks;

    final midSyncDeletedGroups = collectMidSyncRemoteDeletions<ListGroup>(
      snapshotItems: snapshotGroups,
      currentItems: state.groups,
      outcomeItems: groups ?? const <ListGroup>[],
      idOf: (g) => g.id,
      remoteIdOf: (g) => g.remoteId,
      existingDeletedRemoteIds: filterProcessed(
        repository.loadPendingDeletedGroupRemoteIds(),
        processedDeletedGroupRemoteIds,
      ),
    );
    final remainingDeletedGroups = midSyncDeletedGroups.deletedRemoteIds;

    final midSyncDeletedLists = collectMidSyncRemoteDeletions<TodoList>(
      snapshotItems: snapshotLists,
      currentItems: state.lists,
      outcomeItems: lists,
      idOf: (l) => l.id,
      remoteIdOf: (l) => l.remoteId,
      existingDeletedRemoteIds: filterProcessed(
        repository.loadPendingDeletedListRemoteIds(),
        processedDeletedListRemoteIds,
      ),
      canDeleteRemotely: (l) => !l.isSmartList,
    );
    final remainingDeletedLists = midSyncDeletedLists.deletedRemoteIds;

    final midSyncDeletedTasks = collectMidSyncRemoteDeletions<TaskItem>(
      snapshotItems: snapshotTasks,
      currentItems: state.tasks,
      outcomeItems: tasks,
      idOf: (t) => t.id,
      remoteIdOf: (t) => t.remoteId,
      existingDeletedRemoteIds: filterProcessed(
        repository.loadPendingDeletedTaskRemoteIds(),
        processedDeletedTaskRemoteIds,
      ),
    );
    final remainingDeletedTasks = midSyncDeletedTasks.deletedRemoteIds;

    final midSyncDeletedSteps = collectMidSyncStepDeletions(
      snapshotTasks: snapshotTasks,
      currentTasks: state.tasks,
      outcomeTasks: tasks,
      existingDeletedSteps: filterProcessed(
        repository.loadPendingDeletedSteps(),
        processedDeletedSteps,
      ),
    );
    final remainingDeletedSteps = midSyncDeletedSteps.deletedSteps;

    final queuedMidSyncDeletions =
        midSyncDeletedGroups.added ||
        midSyncDeletedLists.added ||
        midSyncDeletedTasks.added ||
        midSyncDeletedSteps.added;

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
      if (expandedOutcome.changed)
        settings.saveCompletedExpandedByList(expandedOutcome.expanded),
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
      completedExpandedByList: expandedOutcome.expanded,
      mutationVersion: queuedMidSyncDeletions
          ? nextState.mutationVersion + 1
          : nextState.mutationVersion,
    );

    await Future.wait(persistFutures);
  }

  /// Applies a remote task snapshot update (e.g. from realtime events) without
  /// bumping [TodoState.mutationVersion] or marking tasks dirty.
  Future<void> applyRemoteTasksSnapshot(List<TaskItem> nextTasks) async {
    final syncedTasks = syncTasksMyDayFlags(
      nextTasks,
      now: DateTime.now(),
      showDueTodayInMyDay: state.showDueTodayInMyDay,
    ).tasks;
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
    final expandedOutcome = recomputeCompletedExpandedByList(
      currentExpanded: state.completedExpandedByList,
      lists: sortedLists,
      dirtyListIds: repository.loadDirtyListIds().toSet(),
    );
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
      if (expandedOutcome.changed)
        settings.saveCompletedExpandedByList(expandedOutcome.expanded),
    ];
    state = state.copyWith(
      lists: sortedLists,
      tasks: effectiveTasks,
      selectedListId: validSelectedListId,
      selectedTaskId: validSelectedTaskId,
      completedExpandedByList: expandedOutcome.expanded,
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

    final expandedOutcome = recomputeCompletedExpandedByList(
      currentExpanded: nextState.completedExpandedByList,
      lists: nextLists,
      dirtySettingKeys: remainingDirtySettings,
      settingsPatch: patch,
      includeSyncableFolders: false,
    );

    final synced = syncTasksMyDayFlags(
      nextState.tasks,
      now: DateTime.now(),
      showDueTodayInMyDay: nextState.showDueTodayInMyDay,
    );

    final listsChanged = !identical(nextLists, state.lists);
    final persistFutures = <Future<Object?>>[
      ...applied.persistFutures,
      if (listsChanged) repository.saveLists(nextLists),
      if (synced.changed) repository.saveTasks(synced.tasks),
      if (expandedOutcome.changed)
        settings.saveCompletedExpandedByList(expandedOutcome.expanded),
    ];

    state = nextState.copyWith(
      lists: nextLists,
      tasks: synced.tasks,
      completedExpandedByList: expandedOutcome.expanded,
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
