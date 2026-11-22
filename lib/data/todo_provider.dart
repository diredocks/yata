import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'todo_local_storage.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../account/account_provider.dart';
import '../homeview/home_view_ordering.dart';
import '../sync/todo_wire_codecs.dart';

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
    this.plannedDueDateFilter = PlannedDueDateFilter.all,
    this.plannedGroupOption = PlannedGroupOption.byDueDate,
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
  final PlannedDueDateFilter plannedDueDateFilter;
  final PlannedGroupOption plannedGroupOption;
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

  bool isCompletedExpanded(String listId) {
    final explicit = completedExpandedByList[listId];
    if (explicit != null) return explicit;
    final list = lists.where((l) => l.id == listId).firstOrNull;
    return list?.showCompleted ?? true;
  }

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
      SmartListType.planned => tasks.where(
          (t) =>
              (t.dueDate != null || t.reminderAt != null) &&
              _matchesPlannedFilter(t),
        ),
      SmartListType.all => tasks.where((t) => !t.isCompleted),
      SmartListType.completed => tasks.where((t) => t.isCompleted),
      SmartListType.tasks => tasks.where((t) => t.listId == 'tasks'),
      null => tasks.where((t) => t.listId == list.id),
    };

    final result = filtered.toList();
    _sortTasks(result, list);
    return result;
  }

  bool _matchesPlannedFilter(TaskItem task) {
    if (plannedDueDateFilter == PlannedDueDateFilter.all) {
      return true;
    }
    final target = task.dueDate ?? task.reminderAt;
    if (target == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDay = DateTime(target.year, target.month, target.day);

    final firstWeekday = switch (startOfWeek) {
      WeekStart.sunday => DateTime.sunday,
      WeekStart.saturday => DateTime.saturday,
      WeekStart.monday || WeekStart.system => DateTime.monday,
    };
    final offsetFromWeekStart = (today.weekday - firstWeekday + 7) % 7;
    final weekStart = today.subtract(Duration(days: offsetFromWeekStart));
    final weekEndInclusive = weekStart.add(const Duration(days: 6));

    return switch (plannedDueDateFilter) {
      PlannedDueDateFilter.all => true,
      PlannedDueDateFilter.overdue => targetDay.isBefore(today),
      PlannedDueDateFilter.today => targetDay == today,
      PlannedDueDateFilter.tomorrow =>
        targetDay == today.add(const Duration(days: 1)),
      PlannedDueDateFilter.thisWeek =>
        !targetDay.isBefore(today) && !targetDay.isAfter(weekEndInclusive),
      PlannedDueDateFilter.later => targetDay.isAfter(weekEndInclusive),
    };
  }

  static int _compareNullableDesc(DateTime? a, DateTime? b) {
    if (a != null && b != null) {
      return b.compareTo(a);
    }
    if (a != null) return -1;
    if (b != null) return 1;
    return 0;
  }

  static void _sortTasks(List<TaskItem> result, TodoList list) {
    final dir = list.sortAscending ? 1 : -1;
    switch (list.sortOption) {
      case TaskSortOption.defaultOrder:
        if (list.smartType == SmartListType.completed) {
          result.sort((a, b) {
            final aTime = a.completedAt ?? a.createdAt;
            final bTime = b.completedAt ?? b.createdAt;
            return bTime.compareTo(aTime);
          });
          return;
        }
        final isMyDay = list.smartType == SmartListType.myDay;
        final hasAnyOrder = isMyDay
            ? result.any(
                (t) => t.committedOrder != null || t.orderDateTime != null,
              )
            : result.any((t) => t.orderDateTime != null);
        if (!hasAnyOrder) return;
        final indexById = {
          for (var i = 0; i < result.length; i++) result[i].id: i,
        };
        result.sort((a, b) {
          if (isMyDay) {
            final cmpCommitted = _compareNullableDesc(
              a.committedOrder,
              b.committedOrder,
            );
            if (cmpCommitted != 0) return cmpCommitted;
          }
          final cmpOrder = _compareNullableDesc(
            a.orderDateTime,
            b.orderDateTime,
          );
          if (cmpOrder != 0) return cmpOrder;
          final cmpCreated = a.createdAt.compareTo(b.createdAt);
          if (cmpCreated != 0) return cmpCreated;
          return (indexById[a.id] ?? 0).compareTo(indexById[b.id] ?? 0);
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
      if (activeCount == 0 &&
          list.smartType == SmartListType.important &&
          !list.showCompleted) {
        return false;
      }
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
    PlannedDueDateFilter? plannedDueDateFilter,
    PlannedGroupOption? plannedGroupOption,
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
      plannedDueDateFilter: plannedDueDateFilter ?? this.plannedDueDateFilter,
      plannedGroupOption: plannedGroupOption ?? this.plannedGroupOption,
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
            final changedSmartKeys = _smartListChangedSettingKeys(prev, list);
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

    final changedGlobalSettingKeys = _detectGlobalSettingChanges(
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
      mutationVersion: (groupSyncNeeded ||
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
    if (prev.title != next.title ||
        prev.listId != next.listId ||
        prev.isCompleted != next.isCompleted ||
        prev.completedAt != next.completedAt ||
        prev.isImportant != next.isImportant ||
        prev.isInMyDay != next.isInMyDay ||
        prev.myDayDate != next.myDayDate ||
        prev.postponedDay != next.postponedDay ||
        prev.dueDate != next.dueDate ||
        prev.reminderAt != next.reminderAt ||
        prev.recurrence != next.recurrence ||
        prev.note != next.note ||
        prev.orderDateTime != next.orderDateTime ||
        prev.committedOrder != next.committedOrder ||
        prev.steps.length != next.steps.length) {
      return true;
    }
    for (var i = 0; i < prev.steps.length; i++) {
      if (prev.steps[i].title != next.steps[i].title ||
          prev.steps[i].isCompleted != next.steps[i].isCompleted ||
          prev.steps[i].orderDateTime != next.steps[i].orderDateTime) {
        return true;
      }
    }
    return false;
  }

  static Set<String> _smartListChangedSettingKeys(
    TodoList prev,
    TodoList next,
  ) {
    final mapping = _smartListSettingKeyMap[next.id];
    if (mapping == null) return const {};
    final changed = <String>{};
    if (mapping.showCompletedKey != null &&
        prev.showCompleted != next.showCompleted) {
      changed.add(mapping.showCompletedKey!);
    }
    if (mapping.themeColorKey != null &&
        (prev.themeColor != next.themeColor ||
            prev.themePhoto != next.themePhoto)) {
      changed.add(mapping.themeColorKey!);
    }
    if (mapping.sortTypeKey != null && prev.sortOption != next.sortOption) {
      changed.add(mapping.sortTypeKey!);
    }
    if (mapping.sortAscKey != null &&
        prev.sortAscending != next.sortAscending) {
      changed.add(mapping.sortAscKey!);
    }
    return changed;
  }

  static Set<String> _detectGlobalSettingChanges(
    TodoState prev,
    TodoState next,
  ) {
    final changed = <String>{};
    if (prev.confirmBeforeDeleting != next.confirmBeforeDeleting) {
      changed.add(TodoSettingKeys.confirmOnDelete);
    }
    if (prev.playCompletionSound != next.playCompletionSound) {
      changed.add(TodoSettingKeys.soundOnCompletion);
    }
    if (prev.showDueTodayInMyDay != next.showDueTodayInMyDay) {
      changed.add(TodoSettingKeys.myDayShowDueTasks);
    }
    if (prev.addNewTasksOnTop != next.addNewTasksOnTop) {
      changed.add(TodoSettingKeys.addTasksToTop);
    }
    if (prev.moveStarredTasksToTop != next.moveStarredTasksToTop) {
      changed.add(TodoSettingKeys.moveStarredTasksToTop);
    }
    if (prev.startOfWeek != next.startOfWeek) {
      changed.add(TodoSettingKeys.startWeekFrom);
    }
    if (prev.remindersEnabled != next.remindersEnabled) {
      changed.add(TodoSettingKeys.reminderNotifications);
    }
    if (prev.dueTodayNotificationsEnabled !=
        next.dueTodayNotificationsEnabled) {
      changed.add(TodoSettingKeys.dueDateNotifications);
    }
    if (prev.dueTodayNotificationHour != next.dueTodayNotificationHour ||
        prev.dueTodayNotificationMinute != next.dueTodayNotificationMinute) {
      changed.add(TodoSettingKeys.dueDateNotificationTime);
    }
    if (prev.pinReminders != next.pinReminders) {
      changed.add(TodoSettingKeys.pinReminders);
    }
    if (prev.routineNotificationEnabled != next.routineNotificationEnabled) {
      changed.add(TodoSettingKeys.routineNotification);
    }
    if (prev.routineNotificationHour != next.routineNotificationHour ||
        prev.routineNotificationMinute != next.routineNotificationMinute) {
      changed.add(TodoSettingKeys.routineNotificationConfiguration);
    }
    if (prev.showSmartListImportant != next.showSmartListImportant) {
      changed.add(TodoSettingKeys.smartListStarredEnabled);
    }
    if (prev.showSmartListPlanned != next.showSmartListPlanned) {
      changed.add(TodoSettingKeys.smartListPlannedEnabled);
    }
    if (prev.showSmartListAll != next.showSmartListAll) {
      changed.add(TodoSettingKeys.smartListAllEnabled);
    }
    if (prev.showSmartListCompleted != next.showSmartListCompleted) {
      changed.add(TodoSettingKeys.smartListCompletedEnabled);
    }
    if (prev.autoHideEmptySmartLists != next.autoHideEmptySmartLists) {
      changed.add(TodoSettingKeys.smartListsAutoHide);
    }
    if (prev.plannedDueDateFilter != next.plannedDueDateFilter) {
      changed.add(TodoSettingKeys.smartListPlannedDueDateFilter);
    }
    if (prev.plannedGroupOption != next.plannedGroupOption) {
      changed.add(TodoSettingKeys.smartListPlannedGroupType);
    }
    return changed;
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
          current.copyWith(
            remoteId: outcome.remoteId ?? current.remoteId,
          ),
        );
      } else {
        reconciled.add(
          outcome.copyWith(isExpanded: current.isExpanded),
        );
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
          current.copyWith(
            remoteId: outcome.remoteId ?? current.remoteId,
          ),
        );
      } else {
        reconciled.add(
          outcome.copyWith(icon: current.icon),
        );
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
      final editedDuringSync = snap != null && _taskNeedsSyncStamp(snap, current);
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
          list.copyWith(clearGroupId: true)
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
      final applied = await _applySettingsPatch(
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
        final showKey = _smartListSettingKeyMap[list.id]?.showCompletedKey;
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
              (s) => !processedStepKeys
                  .contains('${s.taskRemoteId}::${s.stepRemoteId}'),
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

  Future<({TodoState state, List<TodoList> lists})> _applySettingsPatch({
    required TodoState current,
    required TodoState? snapshot,
    required SyncedSettingsPatch patch,
    required List<TodoList> lists,
    required Set<String> dirtySettings,
  }) async {
    bool canApplySetting(String key) {
      if (dirtySettings.contains(key)) return false;
      if (snapshot == null) return true;
      return extractSettingValueForKey(current, key) ==
          extractSettingValueForKey(snapshot, key);
    }

    var next = current;
    if (patch.confirmBeforeDeleting != null &&
        canApplySetting(TodoSettingKeys.confirmOnDelete)) {
      next = next.copyWith(confirmBeforeDeleting: patch.confirmBeforeDeleting);
      await storage.saveConfirmBeforeDeleting(next.confirmBeforeDeleting);
    }
    if (patch.playCompletionSound != null &&
        canApplySetting(TodoSettingKeys.soundOnCompletion)) {
      next = next.copyWith(playCompletionSound: patch.playCompletionSound);
      await storage.savePlayCompletionSound(next.playCompletionSound);
    }
    if (patch.showDueTodayInMyDay != null &&
        canApplySetting(TodoSettingKeys.myDayShowDueTasks)) {
      next = next.copyWith(showDueTodayInMyDay: patch.showDueTodayInMyDay);
      await storage.saveShowDueTodayInMyDay(next.showDueTodayInMyDay);
    }
    if (patch.addNewTasksOnTop != null &&
        canApplySetting(TodoSettingKeys.addTasksToTop)) {
      next = next.copyWith(addNewTasksOnTop: patch.addNewTasksOnTop);
      await storage.saveAddNewTasksOnTop(next.addNewTasksOnTop);
    }
    if (patch.moveStarredTasksToTop != null &&
        canApplySetting(TodoSettingKeys.moveStarredTasksToTop)) {
      next = next.copyWith(moveStarredTasksToTop: patch.moveStarredTasksToTop);
      await storage.saveMoveStarredTasksToTop(next.moveStarredTasksToTop);
    }
    if (patch.startOfWeek != null &&
        canApplySetting(TodoSettingKeys.startWeekFrom)) {
      next = next.copyWith(startOfWeek: patch.startOfWeek);
      await storage.saveStartOfWeek(next.startOfWeek);
    }
    if (patch.remindersEnabled != null &&
        canApplySetting(TodoSettingKeys.reminderNotifications)) {
      next = next.copyWith(remindersEnabled: patch.remindersEnabled);
      await storage.saveRemindersEnabled(next.remindersEnabled);
    }
    if (patch.dueTodayNotificationsEnabled != null &&
        canApplySetting(TodoSettingKeys.dueDateNotifications)) {
      next = next.copyWith(
        dueTodayNotificationsEnabled: patch.dueTodayNotificationsEnabled,
      );
      await storage.saveDueTodayNotificationsEnabled(
        next.dueTodayNotificationsEnabled,
      );
    }
    if (patch.dueTodayNotificationTime != null &&
        canApplySetting(TodoSettingKeys.dueDateNotificationTime)) {
      final t = patch.dueTodayNotificationTime!;
      next = next.copyWith(
        dueTodayNotificationHour: t.hour,
        dueTodayNotificationMinute: t.minute,
      );
      await storage.saveDueTodayNotificationTime(t.hour, t.minute);
    }
    if (patch.pinReminders != null &&
        canApplySetting(TodoSettingKeys.pinReminders)) {
      next = next.copyWith(pinReminders: patch.pinReminders);
      await storage.savePinReminders(next.pinReminders);
    }
    if (patch.routineNotificationEnabled != null &&
        canApplySetting(TodoSettingKeys.routineNotification)) {
      next = next.copyWith(
        routineNotificationEnabled: patch.routineNotificationEnabled,
      );
      await storage.saveRoutineNotificationEnabled(
        next.routineNotificationEnabled,
      );
    }
    if (patch.routineNotificationTime != null &&
        canApplySetting(TodoSettingKeys.routineNotificationConfiguration)) {
      final t = patch.routineNotificationTime!;
      next = next.copyWith(
        routineNotificationHour: t.hour,
        routineNotificationMinute: t.minute,
      );
      await storage.saveRoutineNotificationTime(t.hour, t.minute);
    }
    if (patch.showSmartListImportant != null &&
        canApplySetting(TodoSettingKeys.smartListStarredEnabled)) {
      next =
          next.copyWith(showSmartListImportant: patch.showSmartListImportant);
      await storage.saveShowSmartListImportant(next.showSmartListImportant);
    }
    if (patch.showSmartListPlanned != null &&
        canApplySetting(TodoSettingKeys.smartListPlannedEnabled)) {
      next = next.copyWith(showSmartListPlanned: patch.showSmartListPlanned);
      await storage.saveShowSmartListPlanned(next.showSmartListPlanned);
    }
    if (patch.showSmartListAll != null &&
        canApplySetting(TodoSettingKeys.smartListAllEnabled)) {
      next = next.copyWith(showSmartListAll: patch.showSmartListAll);
      await storage.saveShowSmartListAll(next.showSmartListAll);
    }
    if (patch.showSmartListCompleted != null &&
        canApplySetting(TodoSettingKeys.smartListCompletedEnabled)) {
      next =
          next.copyWith(showSmartListCompleted: patch.showSmartListCompleted);
      await storage.saveShowSmartListCompleted(next.showSmartListCompleted);
    }
    if (patch.autoHideEmptySmartLists != null &&
        canApplySetting(TodoSettingKeys.smartListsAutoHide)) {
      next = next.copyWith(
        autoHideEmptySmartLists: patch.autoHideEmptySmartLists,
      );
      await storage.saveAutoHideEmptySmartLists(next.autoHideEmptySmartLists);
    }
    if (patch.plannedDueDateFilter != null &&
        canApplySetting(TodoSettingKeys.smartListPlannedDueDateFilter)) {
      next = next.copyWith(plannedDueDateFilter: patch.plannedDueDateFilter);
      await storage.savePlannedDueDateFilter(next.plannedDueDateFilter);
    }
    if (patch.plannedGroupOption != null &&
        canApplySetting(TodoSettingKeys.smartListPlannedGroupType)) {
      next = next.copyWith(plannedGroupOption: patch.plannedGroupOption);
      await storage.savePlannedGroupOption(next.plannedGroupOption);
    }

    if (patch.smartListPatches.isEmpty) {
      return (state: next, lists: lists);
    }

    final updatedLists = [
      for (final list in lists)
        _applySmartListPatch(
          list: list,
          patch: patch.smartListPatches[list.id],
          mapping: _smartListSettingKeyMap[list.id],
          canApplySetting: canApplySetting,
        ),
    ];
    return (state: next, lists: updatedLists);
  }

  static TodoList _applySmartListPatch({
    required TodoList list,
    required SmartListSettingsPatch? patch,
    required _SmartListSettingKeys? mapping,
    required bool Function(String key) canApplySetting,
  }) {
    if (patch == null || mapping == null) return list;
    var updated = list;
    if (patch.showCompleted != null &&
        mapping.showCompletedKey != null &&
        canApplySetting(mapping.showCompletedKey!)) {
      updated = updated.copyWith(showCompleted: patch.showCompleted);
    }
    if (patch.hasTheme &&
        mapping.themeColorKey != null &&
        canApplySetting(mapping.themeColorKey!)) {
      updated = updated.copyWith(
        themeColor: patch.themeColor ?? updated.themeColor,
        themePhoto: patch.themePhoto,
        clearThemePhoto: patch.clearThemePhoto,
      );
    }
    if (patch.sortOption != null &&
        mapping.sortTypeKey != null &&
        canApplySetting(mapping.sortTypeKey!)) {
      updated = updated.copyWith(sortOption: patch.sortOption);
    }
    if (patch.sortAscending != null &&
        mapping.sortAscKey != null &&
        canApplySetting(mapping.sortAscKey!)) {
      updated = updated.copyWith(sortAscending: patch.sortAscending);
    }
    return updated;
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
    final nextExpanded = Map<String, bool>.from(state.completedExpandedByList)
      ..[listId] = expanded;
    final target = state.lists.where((l) => l.id == listId).firstOrNull;
    final shouldSyncListShowCompleted = target != null &&
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
    state = state.copyWith(
      selectedTaskId: taskId,
      clearSelectedTaskId: taskId == null,
    );
  }
}

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);

class _SmartListSettingKeys {
  const _SmartListSettingKeys({
    this.showCompletedKey,
    this.themeColorKey,
    this.sortTypeKey,
    this.sortAscKey,
  });

  final String? showCompletedKey;
  final String? themeColorKey;
  final String? sortTypeKey;
  final String? sortAscKey;
}

const Map<String, _SmartListSettingKeys> _smartListSettingKeyMap = {
  'my_day': _SmartListSettingKeys(
    showCompletedKey: TodoSettingKeys.myDayShowCompletedTasks,
    themeColorKey: TodoSettingKeys.myDayThemeColor,
    sortTypeKey: TodoSettingKeys.myDaySortType,
    sortAscKey: TodoSettingKeys.myDaySortAscending,
  ),
  'important': _SmartListSettingKeys(
    showCompletedKey: TodoSettingKeys.smartListStarredShowCompletedTasks,
    themeColorKey: TodoSettingKeys.smartListStarredThemeColor,
    sortTypeKey: TodoSettingKeys.smartListStarredSortType,
    sortAscKey: TodoSettingKeys.smartListStarredSortAscending,
  ),
  'planned': _SmartListSettingKeys(
    showCompletedKey: TodoSettingKeys.plannedShowCompletedTasks,
    themeColorKey: TodoSettingKeys.plannedThemeColor,
  ),
  'all': _SmartListSettingKeys(
    themeColorKey: TodoSettingKeys.smartListAllThemeColor,
    sortTypeKey: TodoSettingKeys.smartListAllSortType,
    sortAscKey: TodoSettingKeys.smartListAllSortAscending,
  ),
  'completed': _SmartListSettingKeys(
    themeColorKey: TodoSettingKeys.smartListCompletedThemeColor,
    sortTypeKey: TodoSettingKeys.smartListCompletedSortType,
    sortAscKey: TodoSettingKeys.smartListCompletedSortAscending,
  ),
};

class SmartListSettingsPatch {
  const SmartListSettingsPatch({
    this.showCompleted,
    this.hasTheme = false,
    this.themeColor,
    this.themePhoto,
    this.clearThemePhoto = false,
    this.sortOption,
    this.sortAscending,
  });

  final bool? showCompleted;
  final bool hasTheme;
  final ListThemeColor? themeColor;
  final ListThemePhoto? themePhoto;
  final bool clearThemePhoto;
  final TaskSortOption? sortOption;
  final bool? sortAscending;

  SmartListSettingsPatch merge({
    bool? showCompleted,
    bool? hasTheme,
    ListThemeColor? themeColor,
    ListThemePhoto? themePhoto,
    bool? clearThemePhoto,
    TaskSortOption? sortOption,
    bool? sortAscending,
  }) {
    return SmartListSettingsPatch(
      showCompleted: showCompleted ?? this.showCompleted,
      hasTheme: (hasTheme ?? false) || this.hasTheme,
      themeColor: themeColor ?? this.themeColor,
      themePhoto: (clearThemePhoto ?? false)
          ? null
          : (themePhoto ?? this.themePhoto),
      clearThemePhoto: (clearThemePhoto ?? false) || this.clearThemePhoto,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

class SyncedSettingsPatch {
  const SyncedSettingsPatch({
    this.confirmBeforeDeleting,
    this.playCompletionSound,
    this.showDueTodayInMyDay,
    this.addNewTasksOnTop,
    this.moveStarredTasksToTop,
    this.startOfWeek,
    this.remindersEnabled,
    this.dueTodayNotificationsEnabled,
    this.dueTodayNotificationTime,
    this.pinReminders,
    this.routineNotificationEnabled,
    this.routineNotificationTime,
    this.showSmartListImportant,
    this.showSmartListPlanned,
    this.showSmartListAll,
    this.showSmartListCompleted,
    this.autoHideEmptySmartLists,
    this.plannedDueDateFilter,
    this.plannedGroupOption,
    this.smartListPatches = const {},
  });

  final bool? confirmBeforeDeleting;
  final bool? playCompletionSound;
  final bool? showDueTodayInMyDay;
  final bool? addNewTasksOnTop;
  final bool? moveStarredTasksToTop;
  final WeekStart? startOfWeek;
  final bool? remindersEnabled;
  final bool? dueTodayNotificationsEnabled;
  final TimeOfDay? dueTodayNotificationTime;
  final bool? pinReminders;
  final bool? routineNotificationEnabled;
  final TimeOfDay? routineNotificationTime;
  final bool? showSmartListImportant;
  final bool? showSmartListPlanned;
  final bool? showSmartListAll;
  final bool? showSmartListCompleted;
  final bool? autoHideEmptySmartLists;
  final PlannedDueDateFilter? plannedDueDateFilter;
  final PlannedGroupOption? plannedGroupOption;
  final Map<String, SmartListSettingsPatch> smartListPatches;
}

/// Encodes local [state] field corresponding to Substrate setting [key].
String? extractSettingValueForKey(TodoState state, String key) {
  switch (key) {
    case TodoSettingKeys.confirmOnDelete:
      return encodeBoolSetting(state.confirmBeforeDeleting);
    case TodoSettingKeys.soundOnCompletion:
      return encodeBoolSetting(state.playCompletionSound);
    case TodoSettingKeys.myDayShowDueTasks:
      return encodeBoolSetting(state.showDueTodayInMyDay);
    case TodoSettingKeys.addTasksToTop:
      return encodeBoolSetting(state.addNewTasksOnTop);
    case TodoSettingKeys.moveStarredTasksToTop:
      return encodeBoolSetting(state.moveStarredTasksToTop);
    case TodoSettingKeys.startWeekFrom:
      return encodeIntSetting(encodeWeekStart(state.startOfWeek));
    case TodoSettingKeys.reminderNotifications:
      return encodeBoolSetting(state.remindersEnabled);
    case TodoSettingKeys.dueDateNotifications:
      return encodeBoolSetting(state.dueTodayNotificationsEnabled);
    case TodoSettingKeys.dueDateNotificationTime:
      return encodeTimeOfDaySetting(
        TimeOfDay(
          hour: state.dueTodayNotificationHour,
          minute: state.dueTodayNotificationMinute,
        ),
      );
    case TodoSettingKeys.pinReminders:
      return encodeBoolSetting(state.pinReminders);
    case TodoSettingKeys.routineNotification:
      return encodeRoutineNotificationEnabled(
        state.routineNotificationEnabled,
      );
    case TodoSettingKeys.routineNotificationConfiguration:
      return encodeRoutineConfig(
        TimeOfDay(
          hour: state.routineNotificationHour,
          minute: state.routineNotificationMinute,
        ),
      );
    case TodoSettingKeys.smartListStarredEnabled:
      return encodeBoolSetting(state.showSmartListImportant);
    case TodoSettingKeys.smartListPlannedEnabled:
      return encodeBoolSetting(state.showSmartListPlanned);
    case TodoSettingKeys.smartListAllEnabled:
      return encodeBoolSetting(state.showSmartListAll);
    case TodoSettingKeys.smartListCompletedEnabled:
      return encodeBoolSetting(state.showSmartListCompleted);
    case TodoSettingKeys.smartListsAutoHide:
      return encodeBoolSetting(state.autoHideEmptySmartLists);
    case TodoSettingKeys.smartListPlannedDueDateFilter:
      return encodeIntSetting(
        encodePlannedDueDateFilter(state.plannedDueDateFilter),
      );
    case TodoSettingKeys.smartListPlannedGroupType:
      return encodeIntSetting(
        encodePlannedGroupOption(state.plannedGroupOption),
      );
  }

  for (final entry in _smartListSettingKeyMap.entries) {
    final list = state.lists.where((l) => l.id == entry.key).firstOrNull;
    if (list == null) continue;
    final mapping = entry.value;
    if (key == mapping.showCompletedKey) {
      return encodeBoolSetting(list.showCompleted);
    }
    if (key == mapping.themeColorKey) {
      return encodeThemeColor(list.themeColor, list.themePhoto);
    }
    if (key == mapping.sortTypeKey) {
      return encodeIntSetting(encodeSortType(list.sortOption));
    }
    if (key == mapping.sortAscKey) {
      return encodeBoolSetting(list.sortAscending);
    }
  }
  return null;
}

/// Converts raw Substrate `GET settings` map into a [SyncedSettingsPatch].
SyncedSettingsPatch buildSyncedSettingsPatchFromWire(
  Map<String, String> remoteSettings, {
  Set<String> skipKeys = const {},
}) {
  String? getVal(String key) =>
      skipKeys.contains(key) ? null : remoteSettings[key];

  bool? boolOrNull(String key) {
    final raw = getVal(key);
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'enabled') return true;
    if (lower == 'false' || lower == '0' || lower == 'disabled') return false;
    return null;
  }

  final smartPatches = <String, SmartListSettingsPatch>{};
  for (final entry in _smartListSettingKeyMap.entries) {
    final listId = entry.key;
    final mapping = entry.value;
    var patch = const SmartListSettingsPatch();
    var touched = false;

    if (mapping.showCompletedKey != null) {
      final show = boolOrNull(mapping.showCompletedKey!);
      if (show != null) {
        patch = patch.merge(showCompleted: show);
        touched = true;
      }
    }
    if (mapping.themeColorKey != null) {
      final rawTheme = getVal(mapping.themeColorKey!);
      if (rawTheme != null && rawTheme.trim().isNotEmpty) {
        final decoded = decodeThemeColor(rawTheme);
        patch = patch.merge(
          hasTheme: true,
          themeColor: decoded.themeColor,
          themePhoto: decoded.themePhoto,
          clearThemePhoto: decoded.themePhoto == null,
        );
        touched = true;
      }
    }
    if (mapping.sortTypeKey != null) {
      final rawSort = getVal(mapping.sortTypeKey!);
      if (rawSort != null) {
        patch = patch.merge(sortOption: decodeSortType(rawSort));
        touched = true;
      }
    }
    if (mapping.sortAscKey != null) {
      final asc = boolOrNull(mapping.sortAscKey!);
      if (asc != null) {
        patch = patch.merge(sortAscending: asc);
        touched = true;
      }
    }

    if (touched) {
      smartPatches[listId] = patch;
    }
  }

  final rawWeek = getVal(TodoSettingKeys.startWeekFrom);
  final rawDueFilter = getVal(TodoSettingKeys.smartListPlannedDueDateFilter);
  final rawGroupType = getVal(TodoSettingKeys.smartListPlannedGroupType);
  final rawDueTime = getVal(TodoSettingKeys.dueDateNotificationTime);
  final rawRoutineConfig =
      getVal(TodoSettingKeys.routineNotificationConfiguration);

  return SyncedSettingsPatch(
    confirmBeforeDeleting: boolOrNull(TodoSettingKeys.confirmOnDelete),
    playCompletionSound: boolOrNull(TodoSettingKeys.soundOnCompletion),
    showDueTodayInMyDay: boolOrNull(TodoSettingKeys.myDayShowDueTasks),
    addNewTasksOnTop: boolOrNull(TodoSettingKeys.addTasksToTop),
    moveStarredTasksToTop: boolOrNull(TodoSettingKeys.moveStarredTasksToTop),
    startOfWeek: rawWeek != null ? decodeWeekStart(rawWeek) : null,
    remindersEnabled: boolOrNull(TodoSettingKeys.reminderNotifications),
    dueTodayNotificationsEnabled:
        boolOrNull(TodoSettingKeys.dueDateNotifications),
    dueTodayNotificationTime:
        rawDueTime != null ? decodeTimeOfDaySetting(rawDueTime) : null,
    pinReminders: boolOrNull(TodoSettingKeys.pinReminders),
    routineNotificationEnabled: boolOrNull(TodoSettingKeys.routineNotification),
    routineNotificationTime:
        rawRoutineConfig != null ? decodeRoutineConfigTime(rawRoutineConfig) : null,
    showSmartListImportant:
        boolOrNull(TodoSettingKeys.smartListStarredEnabled),
    showSmartListPlanned: boolOrNull(TodoSettingKeys.smartListPlannedEnabled),
    showSmartListAll: boolOrNull(TodoSettingKeys.smartListAllEnabled),
    showSmartListCompleted:
        boolOrNull(TodoSettingKeys.smartListCompletedEnabled),
    autoHideEmptySmartLists: boolOrNull(TodoSettingKeys.smartListsAutoHide),
    plannedDueDateFilter:
        rawDueFilter != null ? decodePlannedDueDateFilter(rawDueFilter) : null,
    plannedGroupOption:
        rawGroupType != null ? decodePlannedGroupOption(rawGroupType) : null,
    smartListPatches: smartPatches,
  );
}
