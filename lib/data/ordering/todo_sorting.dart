import 'package:collection/collection.dart';

import '../../models/task_item.dart';

DateTime _completionDayUtc(TaskItem task) {
  final dt = (task.completedAt ?? task.createdAt).toUtc();
  return DateTime.utc(dt.year, dt.month, dt.day);
}

DateTime _completedTieBreakTimeUtc(TaskItem task) =>
    (task.updatedAt ?? task.completedAt ?? task.createdAt).toUtc();

/// Orders tasks newest-completed first (matching Microsoft To Do:
/// `completed_date` descending, then `last_modified_time` descending), falling
/// back to creation time and id so the result is deterministic.
final Comparator<TaskItem> compareCompletedTasksDesc =
    ((TaskItem a, TaskItem b) =>
            _completionDayUtc(b).compareTo(_completionDayUtc(a)))
        .then(
          (a, b) =>
              _completedTieBreakTimeUtc(b)
                  .compareTo(_completedTieBreakTimeUtc(a)),
        )
        .then((a, b) => b.createdAt.compareTo(a.createdAt))
        .then((a, b) => a.id.compareTo(b.id));
