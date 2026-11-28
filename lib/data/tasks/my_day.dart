import '../../core/time/calendar_day.dart';
import '../../models/task_item.dart';

/// Recomputes [TaskItem.isInMyDay] from [TaskItem.myDayDate],
/// [TaskItem.dueDate], and [TaskItem.postponedDay], matching `MyDayContract.kt`.
TaskItem syncMyDayFlag(
  TaskItem task, {
  required DateTime now,
  required bool showDueTodayInMyDay,
}) {
  final committedToday =
      task.myDayDate != null && isSameCalendarDay(task.myDayDate!, now);
  final postponedToday =
      task.postponedDay != null && isSameCalendarDay(task.postponedDay!, now);
  final dueToday =
      showDueTodayInMyDay &&
      task.dueDate != null &&
      isSameCalendarDay(task.dueDate!, now);
  final effectiveInMyDay = committedToday || (dueToday && !postponedToday);
  if (task.isInMyDay == effectiveInMyDay) return task;
  return task.copyWith(isInMyDay: effectiveInMyDay);
}

/// Applies [syncMyDayFlag] across all [tasks] and reports whether any changed.
({List<TaskItem> tasks, bool changed}) syncTasksMyDayFlags(
  List<TaskItem> tasks, {
  required DateTime now,
  required bool showDueTodayInMyDay,
}) {
  var changed = false;
  final synced = <TaskItem>[];
  for (final task in tasks) {
    final next = syncMyDayFlag(
      task,
      now: now,
      showDueTodayInMyDay: showDueTodayInMyDay,
    );
    changed |= !identical(next, task);
    synced.add(next);
  }
  return (tasks: changed ? synced : tasks, changed: changed);
}

/// Local date key (`yyyy-MM-dd`) stored as the last My Day reset marker.
String myDayResetDateKey(DateTime now) =>
    now.toIso8601String().substring(0, 10);
