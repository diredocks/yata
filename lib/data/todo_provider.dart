import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'todo_local_storage.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../account/account_provider.dart';

export '../account/account_provider.dart' show sharedPreferencesProvider;

final todoLocalStorageProvider = Provider<TodoLocalStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final activeAccountId = ref.watch(
    accountProvider.select((s) => s.activeAccountId),
  );
  return TodoLocalStorage(prefs, accountId: activeAccountId);
});

@immutable
class TodoState {
  const TodoState({
    required this.lists,
    required this.groups,
    required this.tasks,
    required this.selectedListId,
    this.selectedTaskId,
    this.sortOption = TaskSortOption.defaultOrder,
    this.showCompleted = true,
    this.themeMode = ThemeMode.system,
    this.addNewTasksOnTop = true,
    this.moveStarredTasksToTop = true,
    this.playCompletionSound = true,
    this.confirmBeforeDeleting = true,
    this.showDueTodayInMyDay = true,
    this.startOfWeek = WeekStart.system,
    this.showSmartListImportant = true,
    this.showSmartListPlanned = true,
    this.showSmartListAll = false,
    this.showSmartListCompleted = false,
    this.autoHideEmptySmartLists = false,
    this.useDynamicColor = true,
    this.remindersEnabled = true,
    this.pinReminders = false,
    this.dueTodayNotificationsEnabled = false,
    this.dueTodayNotificationHour = 9,
    this.dueTodayNotificationMinute = 0,
    this.routineNotificationEnabled = false,
    this.routineNotificationHour = 8,
    this.routineNotificationMinute = 30,
    this.quickAddNotificationEnabled = false,
    this.completedExpandedByList = const {},
    this.mutationVersion = 0,
  });

  final List<TodoList> lists;
  final List<ListGroup> groups;
  final List<TaskItem> tasks;
  final String selectedListId;
  final String? selectedTaskId;
  final TaskSortOption sortOption;
  final bool showCompleted;
  final ThemeMode themeMode;
  final bool addNewTasksOnTop;
  final bool moveStarredTasksToTop;
  final bool playCompletionSound;
  final bool confirmBeforeDeleting;
  final bool showDueTodayInMyDay;
  final WeekStart startOfWeek;
  final bool showSmartListImportant;
  final bool showSmartListPlanned;
  final bool showSmartListAll;
  final bool showSmartListCompleted;
  final bool autoHideEmptySmartLists;
  final bool useDynamicColor;
  final bool remindersEnabled;
  final bool pinReminders;
  final bool dueTodayNotificationsEnabled;
  final int dueTodayNotificationHour;
  final int dueTodayNotificationMinute;
  final bool routineNotificationEnabled;
  final int routineNotificationHour;
  final int routineNotificationMinute;
  final bool quickAddNotificationEnabled;
  final Map<String, bool> completedExpandedByList;
  final int mutationVersion;

  bool isCompletedExpanded(String listId) =>
      completedExpandedByList[listId] ?? true;

  TodoList get selectedList {
    return lists.firstWhere(
      (list) => list.id == selectedListId,
      orElse: () => lists.first,
    );
  }

  TaskItem? get selectedTask {
    if (selectedTaskId == null) return null;
    for (final task in tasks) {
      if (task.id == selectedTaskId) return task;
    }
    return null;
  }

  List<TaskItem> tasksForList(TodoList list) {
    final Iterable<TaskItem> filtered = switch (list.smartType) {
      SmartListType.myDay => tasks.where((t) => t.isInMyDay),
      SmartListType.important => tasks.where((t) => t.isImportant),
      SmartListType.planned =>
        tasks.where((t) => t.dueDate != null || t.reminderAt != null),
      SmartListType.all => tasks.where((t) => !t.isCompleted),
      SmartListType.completed => tasks.where((t) => t.isCompleted),
      SmartListType.tasks => tasks.where((t) => t.listId == 'tasks'),
      null => tasks.where((t) => t.listId == list.id),
    };

    final result = filtered.toList();
    _sortTasks(result, list);
    return result;
  }

  static void _sortTasks(List<TaskItem> result, TodoList list) {
    final dir = list.sortAscending ? 1 : -1;
    switch (list.sortOption) {
      case TaskSortOption.defaultOrder:
        if (list.smartType != SmartListType.completed) return;
        result.sort((a, b) {
          final aTime = a.completedAt ?? a.createdAt;
          final bTime = b.completedAt ?? b.createdAt;
          return bTime.compareTo(aTime);
        });
      case TaskSortOption.importance:
        result.sort((a, b) {
          final aVal = a.isImportant ? 1 : 0;
          final bVal = b.isImportant ? 1 : 0;
          return aVal.compareTo(bVal) * dir;
        });
      case TaskSortOption.dueDate:
        result.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!) * dir;
        });
      case TaskSortOption.addedToMyDay:
        result.sort((a, b) {
          if (a.isInMyDay != b.isInMyDay) {
            return a.isInMyDay ? -1 : 1;
          }
          final aDate = a.myDayDate ?? a.createdAt;
          final bDate = b.myDayDate ?? b.createdAt;
          return aDate.compareTo(bDate) * dir;
        });
      case TaskSortOption.alphabetical:
        result.sort(
          (a, b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()) * dir,
        );
      case TaskSortOption.creationDate:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt) * dir);
    }
  }

  int activeCountForList(TodoList list) {
    if (list.smartType == SmartListType.completed) {
      return 0;
    }
    return tasksForList(list).where((t) => !t.isCompleted).length;
  }

  bool isSmartListVisible(TodoList list) {
    final visibleByToggle = switch (list.smartType) {
      SmartListType.myDay => true,
      SmartListType.important => showSmartListImportant,
      SmartListType.planned => showSmartListPlanned,
      SmartListType.all => showSmartListAll,
      SmartListType.completed => showSmartListCompleted,
      SmartListType.tasks => true,
      null => true,
    };
    if (!visibleByToggle) return false;

    if (autoHideEmptySmartLists &&
        list.smartType != SmartListType.myDay &&
        list.smartType != SmartListType.tasks) {
      final matching = tasksForList(list);
      if (matching.isEmpty) return false;
      if (list.smartType == SmartListType.completed) return true;
      final activeCount = matching.where((t) => !t.isCompleted).length;
      if (activeCount == 0 && !list.showCompleted) return false;
    }
    return true;
  }

  TodoState copyWith({
    List<TodoList>? lists,
    List<ListGroup>? groups,
    List<TaskItem>? tasks,
    String? selectedListId,
    String? selectedTaskId,
    bool clearSelectedTaskId = false,
    TaskSortOption? sortOption,
    bool? showCompleted,
    ThemeMode? themeMode,
    bool? addNewTasksOnTop,
    bool? moveStarredTasksToTop,
    bool? playCompletionSound,
    bool? confirmBeforeDeleting,
    bool? showDueTodayInMyDay,
    WeekStart? startOfWeek,
    bool? showSmartListImportant,
    bool? showSmartListPlanned,
    bool? showSmartListAll,
    bool? showSmartListCompleted,
    bool? autoHideEmptySmartLists,
    bool? useDynamicColor,
    bool? remindersEnabled,
    bool? pinReminders,
    bool? dueTodayNotificationsEnabled,
    int? dueTodayNotificationHour,
    int? dueTodayNotificationMinute,
    bool? routineNotificationEnabled,
    int? routineNotificationHour,
    int? routineNotificationMinute,
    bool? quickAddNotificationEnabled,
    Map<String, bool>? completedExpandedByList,
    int? mutationVersion,
  }) {
    return TodoState(
      lists: lists ?? this.lists,
      groups: groups ?? this.groups,
      tasks: tasks ?? this.tasks,
      selectedListId: selectedListId ?? this.selectedListId,
      selectedTaskId:
          clearSelectedTaskId ? null : (selectedTaskId ?? this.selectedTaskId),
      sortOption: sortOption ?? this.sortOption,
      showCompleted: showCompleted ?? this.showCompleted,
      themeMode: themeMode ?? this.themeMode,
      addNewTasksOnTop: addNewTasksOnTop ?? this.addNewTasksOnTop,
      moveStarredTasksToTop:
          moveStarredTasksToTop ?? this.moveStarredTasksToTop,
      playCompletionSound: playCompletionSound ?? this.playCompletionSound,
      confirmBeforeDeleting:
          confirmBeforeDeleting ?? this.confirmBeforeDeleting,
      showDueTodayInMyDay: showDueTodayInMyDay ?? this.showDueTodayInMyDay,
      startOfWeek: startOfWeek ?? this.startOfWeek,
      showSmartListImportant:
          showSmartListImportant ?? this.showSmartListImportant,
      showSmartListPlanned: showSmartListPlanned ?? this.showSmartListPlanned,
      showSmartListAll: showSmartListAll ?? this.showSmartListAll,
      showSmartListCompleted:
          showSmartListCompleted ?? this.showSmartListCompleted,
      autoHideEmptySmartLists:
          autoHideEmptySmartLists ?? this.autoHideEmptySmartLists,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      pinReminders: pinReminders ?? this.pinReminders,
      dueTodayNotificationsEnabled:
          dueTodayNotificationsEnabled ?? this.dueTodayNotificationsEnabled,
      dueTodayNotificationHour:
          dueTodayNotificationHour ?? this.dueTodayNotificationHour,
      dueTodayNotificationMinute:
          dueTodayNotificationMinute ?? this.dueTodayNotificationMinute,
      routineNotificationEnabled:
          routineNotificationEnabled ?? this.routineNotificationEnabled,
      routineNotificationHour:
          routineNotificationHour ?? this.routineNotificationHour,
      routineNotificationMinute:
          routineNotificationMinute ?? this.routineNotificationMinute,
      quickAddNotificationEnabled:
          quickAddNotificationEnabled ?? this.quickAddNotificationEnabled,
      completedExpandedByList:
          completedExpandedByList ?? this.completedExpandedByList,
      mutationVersion: mutationVersion ?? this.mutationVersion,
    );
  }
}

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
    final dueToday = showDueTodayInMyDay &&
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
      sortOption: snapshot.sortOption,
      showCompleted: snapshot.showCompleted,
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
    final prevLists = state.lists;
    final prevTasks = state.tasks;
    final nowUtc = DateTime.now().toUtc();

    final listsChanged = !identical(prevLists, nextState.lists);
    final tasksChanged = !identical(prevTasks, nextState.tasks);

    var stampedLists = nextState.lists;
    var listSyncNeeded = false;
    if (listsChanged) {
      final prevListById = {for (final l in prevLists) l.id: l};
      final nextListIds = {for (final l in nextState.lists) l.id};

      final deletedListRemoteIds = [
        ...storage.loadPendingDeletedListRemoteIds(),
      ];
      for (final prev in prevLists) {
        if (!nextListIds.contains(prev.id) && prev.remoteId != null) {
          listSyncNeeded = true;
          if (!deletedListRemoteIds.contains(prev.remoteId)) {
            deletedListRemoteIds.add(prev.remoteId!);
          }
        }
      }
      storage.savePendingDeletedListRemoteIds(deletedListRemoteIds);

      final nextLists = <TodoList>[];
      for (final list in nextState.lists) {
        final prev = prevListById[list.id];
        if (!list.isSmartList && (prev == null || prev.title != list.title)) {
          listSyncNeeded = true;
          nextLists.add(list.copyWith(updatedAt: nowUtc));
        } else {
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
      final listById = {for (final l in prevLists) l.id: l};

      final deletedTasks = [...storage.loadPendingDeletedTasks()];
      for (final prev in prevTasks) {
        if (!nextTaskIds.contains(prev.id) && prev.remoteId != null) {
          taskSyncNeeded = true;
          final listRemoteId = listById[prev.listId]?.remoteId;
          if (listRemoteId != null &&
              !deletedTasks.any((d) => d.taskRemoteId == prev.remoteId)) {
            deletedTasks.add(
              PendingTaskDeletion(
                listRemoteId: listRemoteId,
                taskRemoteId: prev.remoteId!,
              ),
            );
          }
        }
      }
      storage.savePendingDeletedTasks(deletedTasks);

      final nextTasks = <TaskItem>[];
      for (final task in nextState.tasks) {
        if (_taskNeedsSyncStamp(prevTaskById[task.id], task)) {
          taskSyncNeeded = true;
          nextTasks.add(task.copyWith(updatedAt: nowUtc));
        } else {
          nextTasks.add(task);
        }
      }
      stampedTasks = nextTasks;
    }

    state = nextState.copyWith(
      lists: stampedLists,
      tasks: stampedTasks,
      mutationVersion: (listSyncNeeded || taskSyncNeeded)
          ? state.mutationVersion + 1
          : state.mutationVersion,
    );
  }

  static bool _taskNeedsSyncStamp(TaskItem? prev, TaskItem next) {
    if (prev == null) return true;
    if (prev.title != next.title ||
        prev.listId != next.listId ||
        prev.isCompleted != next.isCompleted ||
        prev.isImportant != next.isImportant ||
        prev.dueDate != next.dueDate ||
        prev.reminderAt != next.reminderAt ||
        prev.recurrence != next.recurrence ||
        prev.note != next.note ||
        prev.steps.length != next.steps.length) {
      return true;
    }
    for (var i = 0; i < prev.steps.length; i++) {
      if (prev.steps[i].title != next.steps[i].title ||
          prev.steps[i].isCompleted != next.steps[i].isCompleted) {
        return true;
      }
    }
    return false;
  }

  List<TodoList> _reconcileSyncedLists({
    required List<TodoList> outcomeLists,
    required List<TodoList> snapshotLists,
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
      final titleEditedLocally = snap != null && current.title != snap.title;
      reconciled.add(
        current.copyWith(
          title: titleEditedLocally ? current.title : outcome.title,
          remoteId: outcome.remoteId ?? current.remoteId,
          updatedAt: titleEditedLocally
              ? current.updatedAt
              : (outcome.updatedAt ?? current.updatedAt),
        ),
      );
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
      if (snap != null && identical(snap, current)) {
        existingAndLocal.add(outcome);
      } else {
        existingAndLocal.add(
          current.copyWith(remoteId: outcome.remoteId ?? current.remoteId),
        );
      }
    }

    return state.addNewTasksOnTop
        ? [...newRemoteTasks, ...existingAndLocal]
        : [...existingAndLocal, ...newRemoteTasks];
  }

  Future<void> applySyncResult({
    required List<TodoList> lists,
    required List<TaskItem> tasks,
    List<TodoList>? snapshotLists,
    List<TaskItem>? snapshotTasks,
    List<String>? processedDeletedListRemoteIds,
    List<PendingTaskDeletion>? processedDeletedTasks,
  }) async {
    final reconciledLists = snapshotLists != null
        ? _reconcileSyncedLists(
            outcomeLists: lists,
            snapshotLists: snapshotLists,
          )
        : lists;
    final validListIds = {for (final l in reconciledLists) l.id};
    final reconciledTasks = snapshotTasks != null
        ? _reconcileSyncedTasks(
            outcomeTasks: tasks,
            snapshotTasks: snapshotTasks,
            validListIds: validListIds,
          )
        : tasks;

    final now = DateTime.now();
    final syncedTasks = [
      for (final task in reconciledTasks)
        syncMyDayFlag(
          task,
          now: now,
          showDueTodayInMyDay: state.showDueTodayInMyDay,
        ),
    ];

    final remainingDeletedLists = processedDeletedListRemoteIds == null
        ? const <String>[]
        : storage
            .loadPendingDeletedListRemoteIds()
            .where((id) => !processedDeletedListRemoteIds.contains(id))
            .toList();
    final processedTaskIds = processedDeletedTasks == null
        ? const <String>{}
        : {for (final d in processedDeletedTasks) d.taskRemoteId};
    final remainingDeletedTasks = processedDeletedTasks == null
        ? const <PendingTaskDeletion>[]
        : storage
            .loadPendingDeletedTasks()
            .where((d) => !processedTaskIds.contains(d.taskRemoteId))
            .toList();

    await storage.saveLists(reconciledLists);
    await storage.saveTasks(syncedTasks);
    await storage.savePendingDeletedListRemoteIds(remainingDeletedLists);
    await storage.savePendingDeletedTasks(remainingDeletedTasks);

    final validSelectedListId =
        reconciledLists.any((l) => l.id == state.selectedListId)
            ? state.selectedListId
            : 'my_day';

    state = state.copyWith(
      lists: reconciledLists,
      tasks: syncedTasks,
      selectedListId: validSelectedListId,
    );
  }

  void selectList(String listId) {
    state = state.copyWith(
      selectedListId: listId,
      clearSelectedTaskId: true,
    );
    storage.saveSelectedListId(listId);
  }

  void setLastEnteredListId(String? listId) {
    storage.saveLastEnteredListId(listId);
  }

  void setCompletedExpanded(String listId, bool expanded) {
    final next = Map<String, bool>.from(state.completedExpandedByList)
      ..[listId] = expanded;
    state = state.copyWith(completedExpandedByList: next);
    storage.saveCompletedExpandedByList(next);
  }

  void selectTask(String? taskId) {
    state = state.copyWith(
      selectedTaskId: taskId,
      clearSelectedTaskId: taskId == null,
    );
  }
}

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);
