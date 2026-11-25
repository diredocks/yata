import 'package:collection/collection.dart';

import '../data/todo_sorting.dart';
import '../detailview/recurrence/task_pickers.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

/// Bucket categories for the Planned smart list when using default order.
enum PlannedBucket { earlier, today, tomorrow, thisWeek, later }

/// Resolves the localized display title for a [TodoList].
String localizedListTitle(AppLocalizations l10n, TodoList list) {
  return switch (list.smartType) {
    SmartListType.myDay => l10n.myDay,
    SmartListType.important => l10n.important,
    SmartListType.planned => l10n.planned,
    SmartListType.all => l10n.all,
    SmartListType.completed => l10n.completedList,
    SmartListType.tasks => l10n.tasks,
    null => list.title,
  };
}

/// Resolves the origin list name for a task shown inside a smart list.
String? resolveOriginListName(
  AppLocalizations l10n,
  List<TodoList> lists,
  String listId,
) {
  final list = lists.firstWhereOrNull((l) => l.id == listId);
  if (list == null) return null;
  return list.smartType == SmartListType.tasks ? l10n.tasks : list.title;
}

/// Splits [allTasks] into active and completed display lists for [currentList].
({List<TaskItem> active, List<TaskItem> completed}) splitTasksForDisplay(
  List<TaskItem> allTasks,
  TodoList currentList,
) {
  final smartType = currentList.smartType;
  if (smartType == SmartListType.completed) {
    return (active: allTasks, completed: const <TaskItem>[]);
  }
  if (smartType == SmartListType.important) {
    final active = currentList.showCompleted
        ? allTasks
        : allTasks.where((t) => !t.isCompleted).toList();
    return (active: active, completed: const <TaskItem>[]);
  }

  final active = allTasks.where((t) => !t.isCompleted).toList();
  if (smartType == SmartListType.all) {
    return (active: active, completed: const <TaskItem>[]);
  }

  final completed = allTasks.where((t) => t.isCompleted).toList();
  if (currentList.sortOption == TaskSortOption.defaultOrder) {
    completed.sort(compareCompletedTasksDesc);
  }
  return (active: active, completed: completed);
}

/// Groups Planned tasks into chronological buckets relative to [now].
List<({PlannedBucket bucket, List<TaskItem> tasks})> groupPlannedTasks(
  List<TaskItem> tasks,
  WeekStart startOfWeek, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final tomorrow = today.add(const Duration(days: 1));
  final nextWeekStart = computeNextWeekDate(today, startOfWeek);

  final buckets = <PlannedBucket, List<TaskItem>>{
    for (final b in PlannedBucket.values) b: <TaskItem>[],
  };

  for (final task in tasks) {
    final date = task.dueDate ?? task.reminderAt?.toLocal();
    if (date == null) {
      buckets[PlannedBucket.later]!.add(task);
      continue;
    }
    final day = DateTime(date.year, date.month, date.day);
    final bucket = _classifyPlannedDay(day, today, tomorrow, nextWeekStart);
    buckets[bucket]!.add(task);
  }

  return [
    for (final b in PlannedBucket.values)
      if (buckets[b]!.isNotEmpty) (bucket: b, tasks: buckets[b]!),
  ];
}

PlannedBucket _classifyPlannedDay(
  DateTime day,
  DateTime today,
  DateTime tomorrow,
  DateTime nextWeekStart,
) {
  if (day.isBefore(today)) return PlannedBucket.earlier;
  if (day == today) return PlannedBucket.today;
  if (day == tomorrow) return PlannedBucket.tomorrow;
  if (day.isBefore(nextWeekStart)) return PlannedBucket.thisWeek;
  return PlannedBucket.later;
}

/// Groups tasks by their owning list for the Completed and All smart lists.
List<({String listId, String title, List<TaskItem> tasks})> groupTasksByList(
  AppLocalizations l10n,
  List<TaskItem> tasks,
  List<TodoList> lists,
) {
  final grouped = <String, List<TaskItem>>{};
  for (final task in tasks) {
    grouped.putIfAbsent(task.listId, () => []).add(task);
  }
  return [
    for (final entry in grouped.entries)
      (
        listId: entry.key,
        title: resolveOriginListName(l10n, lists, entry.key) ?? l10n.tasks,
        tasks: entry.value,
      ),
  ];
}
