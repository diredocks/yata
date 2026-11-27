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
import '../theme/custom_background_service.dart';
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
    SyncedSettingsPatch? settingsPatch,
    bool protectPendingOutbox = false,
  }) async {
    final result = _syncStore.applyRemoteState(
      currentState: state,
      groups: groups,
      lists: lists,
      tasks: tasks,
      settingsPatch: settingsPatch,
      protectPendingOutbox: protectPendingOutbox,
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
