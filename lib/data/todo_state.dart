import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';

import '../models/task_item.dart';
import '../models/todo_list.dart';

part 'todo_state.freezed.dart';

@freezed
abstract class TodoState with _$TodoState {
  const TodoState._();

  const factory TodoState({
    required List<TodoList> lists,
    required List<ListGroup> groups,
    required List<TaskItem> tasks,
    required String selectedListId,
    String? selectedTaskId,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool addNewTasksOnTop,
    @Default(true) bool moveStarredTasksToTop,
    @Default(true) bool playCompletionSound,
    @Default(true) bool confirmBeforeDeleting,
    @Default(true) bool showDueTodayInMyDay,
    @Default(WeekStart.system) WeekStart startOfWeek,
    @Default(true) bool showSmartListImportant,
    @Default(true) bool showSmartListPlanned,
    @Default(false) bool showSmartListAll,
    @Default(false) bool showSmartListCompleted,
    @Default(false) bool autoHideEmptySmartLists,
    @Default(PlannedDueDateFilter.all)
    PlannedDueDateFilter plannedDueDateFilter,
    @Default(PlannedGroupOption.byDueDate)
    PlannedGroupOption plannedGroupOption,
    @Default(true) bool useDynamicColor,
    @Default(true) bool remindersEnabled,
    @Default(false) bool pinReminders,
    @Default(true) bool accurateReminders,
    @Default(false) bool dueTodayNotificationsEnabled,
    @Default(9) int dueTodayNotificationHour,
    @Default(0) int dueTodayNotificationMinute,
    @Default(false) bool routineNotificationEnabled,
    @Default(8) int routineNotificationHour,
    @Default(30) int routineNotificationMinute,
    @Default(<int>[1, 2, 3, 4, 5, 6, 7]) List<int> routineNotificationDays,
    @Default(false) bool quickAddNotificationEnabled,
    @Default(<String, bool>{}) Map<String, bool> completedExpandedByList,
    @Default(0) int mutationVersion,
  }) = _TodoState;

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
}
