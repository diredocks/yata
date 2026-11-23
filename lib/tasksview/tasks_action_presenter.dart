import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_item.dart';
import '../data/todo_provider.dart';
import '../sync/todo_wire_codecs.dart';

/// Batch action presenter matching `tasksview/TasksActionPresenter`.
class TasksActionPresenter {
  TasksActionPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void _commitTasks(
    List<TaskItem> updated, {
    bool clearSelectedTaskId = false,
  }) {
    _store.commit(
      _state.copyWith(
        tasks: updated,
        selectedTaskId: clearSelectedTaskId ? null : _state.selectedTaskId,
      ),
    );
    _store.repository.saveTasks(updated);
  }

  void _mapSelectedTasks(
    Set<String> taskIds,
    TaskItem Function(TaskItem task) transform,
  ) {
    final updated = [
      for (final task in _state.tasks)
        if (taskIds.contains(task.id)) transform(task) else task,
    ];
    _commitTasks(updated);
  }

  void batchSetMyDay(Set<String> taskIds, bool value) {
    final now = DateTime.now();
    final committedOrder = value
        ? computeNewOrderDateTime(
            existingOrders: _state.tasks
                .where((t) => t.isInMyDay)
                .map((t) => t.committedOrder),
            addToTop: _state.addNewTasksOnTop,
            fallbackNow: now,
          )
        : null;
    _mapSelectedTasks(taskIds, (task) {
      return TodoNotifier.syncMyDayFlag(
        task.copyWith(
          myDayDate: value ? now : null,
          committedOrder: committedOrder,
          postponedDay: value
              ? null
              : (!value &&
                        task.dueDate != null &&
                        TodoNotifier.isSameDay(task.dueDate!, now)
                    ? now
                    : task.postponedDay),
        ),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void batchAddToMyDay(Set<String> taskIds) {
    batchSetMyDay(taskIds, true);
  }

  void batchSetImportant(Set<String> taskIds, bool value) {
    final movedToTop = <TaskItem>[];
    final rest = <TaskItem>[];
    final maxOrderByList = <String, DateTime>{};
    DateTime? maxCommittedOrder;

    for (final t in _state.tasks) {
      if (t.orderDateTime != null) {
        final prev = maxOrderByList[t.listId];
        if (prev == null || t.orderDateTime!.isAfter(prev)) {
          maxOrderByList[t.listId] = t.orderDateTime!;
        }
      }
      if (t.isInMyDay && t.committedOrder != null) {
        if (maxCommittedOrder == null ||
            t.committedOrder!.isAfter(maxCommittedOrder)) {
          maxCommittedOrder = t.committedOrder!;
        }
      }
    }

    var bumpIndex = 0;
    for (final task in _state.tasks) {
      if (!taskIds.contains(task.id)) {
        rest.add(task);
        continue;
      }
      var next = task.copyWith(isImportant: value);
      if (value && _state.moveStarredTasksToTop && !task.isImportant) {
        bumpIndex += 1;
        final existingListMax = maxOrderByList[task.listId];
        final bumpedOrder = computeNewOrderDateTime(
          existingOrders: [existingListMax],
          addToTop: true,
        ).add(Duration(milliseconds: 1000 * (taskIds.length - bumpIndex + 1)));
        maxOrderByList[task.listId] = bumpedOrder;

        var bumpedCommitted = next.committedOrder;
        if (task.isInMyDay) {
          bumpedCommitted =
              computeNewOrderDateTime(
                existingOrders: [maxCommittedOrder],
                addToTop: true,
              ).add(
                Duration(milliseconds: 1000 * (taskIds.length - bumpIndex + 1)),
              );
          maxCommittedOrder = bumpedCommitted;
        }

        next = next.copyWith(
          orderDateTime: bumpedOrder,
          committedOrder: bumpedCommitted,
        );
        movedToTop.add(next);
      } else {
        rest.add(next);
      }
    }
    _commitTasks([...movedToTop, ...rest]);
  }

  void batchMarkImportant(Set<String> taskIds) {
    batchSetImportant(taskIds, true);
  }

  void batchCopyToList(Set<String> taskIds, String targetListId) {
    final now = DateTime.now();
    final baseOrder = computeNewOrderDateTime(
      existingOrders: _state.tasks
          .where((t) => t.listId == targetListId)
          .map((t) => t.orderDateTime),
      addToTop: _state.addNewTasksOnTop,
      fallbackNow: now,
    );
    var copyIndex = 0;
    final copies = <TaskItem>[
      for (final task in _state.tasks)
        if (taskIds.contains(task.id))
          () {
            final stepOffset = Duration(seconds: copyIndex++);
            final order = _state.addNewTasksOnTop
                ? baseOrder.add(stepOffset)
                : baseOrder.subtract(stepOffset);
            return task.copyWith(
              id: _store.nextId('task'),
              listId: targetListId,
              createdAt: now,
              remoteId: null,
              remoteParentFolderId: null,
              changeKey: null,
              orderDateTime: order,
              committedOrder: null,
              steps: [
                for (final step in task.steps)
                  TaskStep(
                    id: _store.nextId('step'),
                    title: step.title,
                    isCompleted: step.isCompleted,
                    orderDateTime: step.orderDateTime,
                  ),
              ],
            );
          }(),
    ];
    if (copies.isEmpty) return;
    final updated = _state.addNewTasksOnTop
        ? [...copies, ..._state.tasks]
        : [..._state.tasks, ...copies];
    _commitTasks(updated);
  }

  void batchSetDueDate(Set<String> taskIds, DateTime? dueDate) {
    final now = DateTime.now();
    _mapSelectedTasks(taskIds, (task) {
      final clearPostponed =
          dueDate != null &&
          _state.showDueTodayInMyDay &&
          task.postponedDay != null &&
          TodoNotifier.isSameDay(dueDate, task.postponedDay!);
      return TodoNotifier.syncMyDayFlag(
        task.copyWith(
          dueDate: dueDate,
          recurrence: dueDate == null ? RecurrenceType.none : task.recurrence,
          postponedDay: clearPostponed ? null : task.postponedDay,
        ),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void batchMoveToList(Set<String> taskIds, String targetListId) {
    _mapSelectedTasks(taskIds, (task) => task.copyWith(listId: targetListId));
  }

  void batchDeleteTasks(Set<String> taskIds) {
    final updated = _state.tasks.where((t) => !taskIds.contains(t.id)).toList();
    _commitTasks(
      updated,
      clearSelectedTaskId:
          _state.selectedTaskId != null &&
          taskIds.contains(_state.selectedTaskId),
    );
  }
}

final tasksActionPresenterProvider = Provider<TasksActionPresenter>((ref) {
  return TasksActionPresenter(ref);
});
