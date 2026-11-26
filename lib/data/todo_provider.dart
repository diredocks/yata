import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../homeview/home_view_ordering.dart';
import '../models/account.dart';
import '../models/default_lists.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../theme/custom_background_service.dart';
import 'sync_outbox.dart';
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

  void commit(TodoState nextState) {
    final tracked = enqueueLocalCommitToOutbox(
      prevState: state,
      nextState: nextState,
      nowUtc: DateTime.now().toUtc(),
      outbox: repository.outbox,
    );

    if (tracked.syncNeeded) {
      repository.saveOutbox();
    }

    state = nextState.copyWith(
      groups: tracked.groups,
      lists: tracked.lists,
      tasks: tracked.tasks,
      mutationVersion: tracked.syncNeeded
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
  }

  /// Commits server-assigned IDs/metadata and acknowledges pushed Outbox ops
  /// immediately after a Push pass, without waiting for Pull.
  Future<void> commitPushBatch({
    required List<int> ackedSeqs,
    required Map<String, ListGroup> pushedGroups,
    required Map<String, TodoList> pushedLists,
    required Map<String, TaskItem> pushedTasks,
    List<({SyncEntityType type, String localId})> clearedRemoteIdKeys =
        const [],
  }) async {
    final outbox = repository.outbox;
    for (final seq in ackedSeqs) {
      outbox.ackOp(seq);
    }
    for (final entry in clearedRemoteIdKeys) {
      outbox.clearRemoteId(entry.type, entry.localId);
    }

    final nextGroups = [
      for (final current in state.groups)
        if (pushedGroups[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.group, current.id)
              ? current.copyWith(remoteId: pushed.remoteId ?? current.remoteId)
              : pushed.copyWith(isExpanded: current.isExpanded)
        else
          current,
    ];

    final nextLists = [
      for (final current in state.lists)
        if (pushedLists[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.list, current.id)
              ? current.copyWith(remoteId: pushed.remoteId ?? current.remoteId)
              : pushed.copyWith(icon: current.icon)
        else
          current,
    ];

    final nextTasks = [
      for (final current in state.tasks)
        if (pushedTasks[current.id] case final pushed?)
          outbox.hasPending(SyncEntityType.task, current.id)
              ? () {
                  final stepRemoteById = {
                    for (final s in pushed.steps)
                      if (s.remoteId != null) s.id: s.remoteId!,
                  };
                  final pushedAttById = {
                    for (final a in pushed.attachments) a.id: a,
                  };
                  return current.copyWith(
                    remoteId: pushed.remoteId ?? current.remoteId,
                    remoteParentFolderId:
                        pushed.remoteParentFolderId ??
                        current.remoteParentFolderId,
                    changeKey: pushed.changeKey ?? current.changeKey,
                    steps: [
                      for (final step in current.steps)
                        step.copyWith(
                          remoteId: step.remoteId ?? stepRemoteById[step.id],
                        ),
                    ],
                    attachments: [
                      for (final att in current.attachments)
                        if (pushedAttById[att.id] case final pAtt?)
                          att.copyWith(
                            remoteId: att.remoteId ?? pAtt.remoteId,
                            size: pAtt.size > 0 ? pAtt.size : att.size,
                            contentType: pAtt.contentType ?? att.contentType,
                            lastModifiedDateTime:
                                pAtt.lastModifiedDateTime ??
                                att.lastModifiedDateTime,
                            isTransferring: pAtt.remoteId != null
                                ? false
                                : att.isTransferring,
                          )
                        else
                          att,
                    ],
                  );
                }()
              : pushed
        else
          current,
    ];

    final validGroupIds = {for (final g in nextGroups) g.id};
    final validListIds = {for (final l in nextLists) l.id};
    final validTaskIds = {for (final t in nextTasks) t.id};
    outbox.pruneOrphanedEntities(
      validGroupIds: validGroupIds,
      validListIds: validListIds,
      validTaskIds: validTaskIds,
    );

    final persistFutures = <Future<Object?>>[
      if (pushedGroups.isNotEmpty) repository.saveGroups(nextGroups),
      if (pushedLists.isNotEmpty) repository.saveLists(nextLists),
      if (pushedTasks.isNotEmpty) repository.saveTasks(nextTasks),
      repository.saveOutbox(),
    ];

    state = state.copyWith(
      groups: nextGroups,
      lists: nextLists,
      tasks: nextTasks,
    );
    await Future.wait(persistFutures);
  }

  /// Applies pulled remote state while preserving any entity that currently
  /// has pending operations in the Outbox.
  Future<void> applyPulledState({
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? tasks,
    SyncedSettingsPatch? settingsPatch,
  }) async {
    final outbox = repository.outbox;

    List<T> mergePulled<T>({
      required List<T> currentItems,
      required List<T>? pulledItems,
      required SyncEntityType type,
      required String Function(T) idOf,
      required T Function(T current, T pulled) mergeLocalPending,
      required T Function(T current, T pulled) mergeClean,
    }) {
      if (pulledItems == null) return currentItems;
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

    final reconciledGroups = mergePulled<ListGroup>(
      currentItems: state.groups,
      pulledItems: groups,
      type: SyncEntityType.group,
      idOf: (g) => g.id,
      mergeLocalPending: (current, pulled) =>
          current.copyWith(remoteId: pulled.remoteId ?? current.remoteId),
      mergeClean: (current, pulled) =>
          pulled.copyWith(isExpanded: current.isExpanded),
    );

    var reconciledLists = mergePulled<TodoList>(
      currentItems: state.lists,
      pulledItems: lists,
      type: SyncEntityType.list,
      idOf: (l) => l.id,
      mergeLocalPending: (current, pulled) =>
          current.copyWith(remoteId: pulled.remoteId ?? current.remoteId),
      mergeClean: (current, pulled) => isSyncableFolderList(current)
          ? pulled.copyWith(icon: current.icon)
          : current,
    );

    final validGroupIds = {for (final g in reconciledGroups) g.id};
    reconciledLists = [
      for (final list in reconciledLists)
        if (list.groupId != null && !validGroupIds.contains(list.groupId))
          list.copyWith(groupId: null)
        else
          list,
    ];

    final validListIds = {for (final l in reconciledLists) l.id};
    final reconciledTasks = mergePulled<TaskItem>(
      currentItems: state.tasks,
      pulledItems: tasks,
      type: SyncEntityType.task,
      idOf: (t) => t.id,
      mergeLocalPending: (current, pulled) =>
          current.copyWith(changeKey: pulled.changeKey ?? current.changeKey),
      mergeClean: (current, pulled) => pulled,
    ).where((t) => validListIds.contains(t.listId)).toList();

    final pendingSettings = outbox.pendingLocalIds(SyncEntityType.setting);
    var nextState = state;
    final settingsPersistFutures = <Future<void>>[];
    if (settingsPatch != null) {
      final applied = applySyncedSettingsPatch(
        settings: settings,
        current: state,
        snapshot: null,
        patch: settingsPatch,
        lists: reconciledLists,
        dirtySettings: pendingSettings,
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
      dirtyListIds: outbox.pendingLocalIds(SyncEntityType.list),
      dirtySettingKeys: pendingSettings,
      settingsPatch: settingsPatch,
    );

    final syncedTasks = syncTasksMyDayFlags(
      reconciledTasks,
      now: DateTime.now(),
      showDueTodayInMyDay: nextState.showDueTodayInMyDay,
    ).tasks;

    final validSelectedListId =
        sortedLists.any((l) => l.id == nextState.selectedListId)
        ? nextState.selectedListId
        : 'my_day';
    final validSelectedTaskId =
        nextState.selectedTaskId != null &&
            syncedTasks.any((t) => t.id == nextState.selectedTaskId)
        ? nextState.selectedTaskId
        : null;

    final persistFutures = <Future<Object?>>[
      ...settingsPersistFutures,
      if (groups != null) repository.saveGroups(sortedGroups),
      if (lists != null || settingsPatch != null)
        repository.saveLists(sortedLists),
      if (tasks != null) repository.saveTasks(syncedTasks),
      if (expandedOutcome.changed)
        settings.saveCompletedExpandedByList(expandedOutcome.expanded),
    ];

    state = nextState.copyWith(
      groups: sortedGroups,
      lists: sortedLists,
      tasks: syncedTasks,
      selectedListId: validSelectedListId,
      selectedTaskId: validSelectedTaskId,
      completedExpandedByList: expandedOutcome.expanded,
    );
    await Future.wait(persistFutures);
  }

  /// Applies a remote task snapshot update (e.g. from realtime events) without
  /// bumping [TodoState.mutationVersion] or enqueuing to Outbox.
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

    final saveFuture = repository.saveTasks(syncedTasks);
    state = state.copyWith(
      tasks: syncedTasks,
      selectedTaskId: validSelectedTaskId,
    );
    await saveFuture;
  }

  /// Applies a remote folder-group snapshot (e.g. from realtime events) without
  /// bumping [TodoState.mutationVersion] or enqueuing to Outbox.
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
  /// bumping [TodoState.mutationVersion] or enqueuing to Outbox.
  Future<void> applyRemoteListsSnapshot({
    required List<TodoList> nextLists,
    List<TaskItem>? nextTasks,
  }) async {
    final sortedLists = sortListsPreservingSmartLists(nextLists);
    final expandedOutcome = recomputeCompletedExpandedByList(
      currentExpanded: state.completedExpandedByList,
      lists: sortedLists,
      dirtyListIds: repository.outbox.pendingLocalIds(SyncEntityType.list),
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
  /// without bumping [TodoState.mutationVersion] or enqueuing to Outbox.
  Future<void> applyRemoteSettingsPatch(SyncedSettingsPatch patch) async {
    final pendingSettings = repository.outbox.pendingLocalIds(
      SyncEntityType.setting,
    );
    final applied = applySyncedSettingsPatch(
      settings: settings,
      current: state,
      snapshot: null,
      patch: patch,
      lists: state.lists,
      dirtySettings: pendingSettings,
    );
    final nextState = applied.state;
    final nextLists = applied.lists;

    final expandedOutcome = recomputeCompletedExpandedByList(
      currentExpanded: nextState.completedExpandedByList,
      lists: nextLists,
      dirtySettingKeys: pendingSettings,
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
    final target = state.lists.firstWhereOrNull((l) => l.id == listId);
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
