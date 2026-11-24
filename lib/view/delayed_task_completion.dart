import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/task_item.dart';

/// Coordinates delayed task completion in list views, matching
/// `CompleteTaskDelayedUseCase.kt` (`b.a.MEDIUM = 300ms` when completing a task,
/// `INSTANT = 0ms` when uncompleting or in the Completed smart list).
///
/// Keeping the task row in place for 300ms lets `TaskCheckbox` play its fill,
/// checkmark, and confetti animations before the task moves or disappears.
class DelayedTaskCompletionController {
  static const mediumDelay = Duration(milliseconds: 300);

  final Map<String, Timer> _pendingTimers = {};

  bool isPending(String taskId) => _pendingTimers.containsKey(taskId);

  TaskItem effectiveTask(TaskItem task) {
    if (!task.isCompleted && isPending(task.id)) {
      return task.copyWith(isCompleted: true);
    }
    return task;
  }

  void toggle(
    TaskItem task, {
    bool instant = false,
    required void Function(String taskId, {required bool completed}) onCommit,
    required VoidCallback onStateChanged,
  }) {
    if (task.isCompleted || instant) {
      final existing = _pendingTimers.remove(task.id);
      existing?.cancel();
      if (existing != null) {
        onStateChanged();
      }
      onCommit(task.id, completed: !task.isCompleted);
      return;
    }

    // Completing an active task: if tapped again within 300ms, cancel it.
    final existing = _pendingTimers.remove(task.id);
    if (existing != null) {
      existing.cancel();
      onStateChanged();
      return;
    }

    _pendingTimers[task.id] = Timer(mediumDelay, () {
      _pendingTimers.remove(task.id);
      onCommit(task.id, completed: true);
    });
    onStateChanged();
  }

  void flush(
    void Function(String taskId, {required bool completed}) onCommit,
  ) {
    final pendingIds = _pendingTimers.keys.toList(growable: false);
    for (final id in pendingIds) {
      _pendingTimers.remove(id)?.cancel();
      onCommit(id, completed: true);
    }
  }

  void flushAndDispose(
    void Function(String taskId, {required bool completed}) onCommit,
  ) {
    flush(onCommit);
  }
}
