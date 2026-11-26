import '../models/task_item.dart';

enum SuggestionBucketType { today, yesterday, overdue, upcoming, recentlyAdded }

class SuggestionBucket {
  const SuggestionBucket({required this.type, required this.tasks});

  final SuggestionBucketType type;
  final List<TaskItem> tasks;
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Groups incomplete tasks that are not currently in My Day into local
/// suggestion buckets matching the original app's `TodayBucket`, `CatchUpBucket`,
/// `OverdueBucket`, `UpcomingBucket`, and `AddedBucket`.
List<SuggestionBucket> computeMyDaySuggestions(
  List<TaskItem> tasks, {
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final todayTasks = <TaskItem>[];
  final yesterdayTasks = <TaskItem>[];
  final overdueTasks = <TaskItem>[];
  final upcomingTasks = <TaskItem>[];
  final recentlyAddedTasks = <TaskItem>[];

  for (final task in tasks) {
    if (task.isCompleted || task.isInMyDay) continue;

    final due = task.dueDate != null ? _dateOnly(task.dueDate!) : null;
    if (due != null && due == today) {
      todayTasks.add(task);
      continue;
    }

    final prevMyDay = task.myDayDate != null
        ? _dateOnly(task.myDayDate!)
        : null;
    final postponed = task.postponedDay != null
        ? _dateOnly(task.postponedDay!)
        : null;
    final wasInPreviousMyDay =
        (prevMyDay != null && prevMyDay.isBefore(today)) ||
        (postponed != null && postponed.isBefore(today));
    if (wasInPreviousMyDay) {
      yesterdayTasks.add(task);
      continue;
    }

    if (due != null && due.isBefore(today)) {
      overdueTasks.add(task);
      continue;
    }

    if (due != null && due.isAfter(today)) {
      upcomingTasks.add(task);
      continue;
    }

    recentlyAddedTasks.add(task);
  }

  overdueTasks.sort((a, b) => b.dueDate!.compareTo(a.dueDate!));
  upcomingTasks.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  recentlyAddedTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  return [
    if (todayTasks.isNotEmpty)
      SuggestionBucket(type: SuggestionBucketType.today, tasks: todayTasks),
    if (yesterdayTasks.isNotEmpty)
      SuggestionBucket(
        type: SuggestionBucketType.yesterday,
        tasks: yesterdayTasks,
      ),
    if (overdueTasks.isNotEmpty)
      SuggestionBucket(type: SuggestionBucketType.overdue, tasks: overdueTasks),
    if (upcomingTasks.isNotEmpty)
      SuggestionBucket(
        type: SuggestionBucketType.upcoming,
        tasks: upcomingTasks,
      ),
    if (recentlyAddedTasks.isNotEmpty)
      SuggestionBucket(
        type: SuggestionBucketType.recentlyAdded,
        tasks: recentlyAddedTasks,
      ),
  ];
}
