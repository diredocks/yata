import 'package:material_ui/material_ui.dart';

import '../models/task_item.dart';
import '../models/todo_list.dart';

@immutable
class TodoState {
  const TodoState({
    required this.lists,
    required this.groups,
    required this.tasks,
    required this.selectedListId,
    this.selectedTaskId,
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
      selectedTaskId: clearSelectedTaskId
          ? null
          : (selectedTaskId ?? this.selectedTaskId),
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
