import 'package:collection/collection.dart';

import '../models/task_item.dart';

/// Orders tasks newest-completed first, falling back to creation time and id
/// so the result is deterministic.
final Comparator<TaskItem> compareCompletedTasksDesc =
    ((TaskItem a, TaskItem b) => (b.completedAt ?? b.createdAt).compareTo(
          a.completedAt ?? a.createdAt,
        ))
        .then((a, b) => b.createdAt.compareTo(a.createdAt))
        .then((a, b) => a.id.compareTo(b.id));
