import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_item.dart';
import '../data/todo_provider.dart';

/// Batch action presenter matching `tasksview/TasksActionPresenter`.
class TasksActionPresenter {
  TasksActionPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void _commitTasks(List<TaskItem> updated, {bool clearSelectedTaskId = false}) {
    _store.commit(
      _state.copyWith(
        tasks: updated,
        clearSelectedTaskId: clearSelectedTaskId,
      ),
    );
    _store.storage.saveTasks(updated);
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
    _mapSelectedTasks(taskIds, (task) {
      return TodoNotifier.syncMyDayFlag(
        task.copyWith(
          myDayDate: value ? now : null,
          clearMyDayDate: !value,
          postponedDay: !value &&
                  task.dueDate != null &&
                  TodoNotifier.isSameDay(task.dueDate!, now)
              ? now
              : task.postponedDay,
          clearPostponedDay: value,
        ),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void batchAddToMyDay(Set<String> taskIds) {
    batchSetMyDay(taskIds, true);
  }

  void batchToggleMyDay(Set<String> taskIds) {
    final selected = _state.tasks.where((t) => taskIds.contains(t.id));
    final allInMyDay =
        selected.isNotEmpty && selected.every((t) => t.isInMyDay);
    batchSetMyDay(taskIds, !allInMyDay);
  }

  void batchSetImportant(Set<String> taskIds, bool value) {
    final movedToTop = <TaskItem>[];
    final rest = <TaskItem>[];
    for (final task in _state.tasks) {
      if (!taskIds.contains(task.id)) {
        rest.add(task);
        continue;
      }
      final next = task.copyWith(isImportant: value);
      if (value && _state.moveStarredTasksToTop && !task.isImportant) {
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

  void batchToggleImportant(Set<String> taskIds) {
    final selected = _state.tasks.where((t) => taskIds.contains(t.id));
    final allImportant =
        selected.isNotEmpty && selected.every((t) => t.isImportant);
    batchSetImportant(taskIds, !allImportant);
  }

  void batchCopyToList(Set<String> taskIds, String targetListId) {
    final now = DateTime.now();
    final copies = <TaskItem>[
      for (final task in _state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(
            id: _store.nextId('task'),
            listId: targetListId,
            createdAt: now,
            steps: [
              for (final step in task.steps)
                TaskStep(
                  id: _store.nextId('step'),
                  title: step.title,
                  isCompleted: step.isCompleted,
                ),
            ],
          ),
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
      final clearPostponed = dueDate != null &&
          _state.showDueTodayInMyDay &&
          task.postponedDay != null &&
          TodoNotifier.isSameDay(dueDate, task.postponedDay!);
      return TodoNotifier.syncMyDayFlag(
        task.copyWith(
          dueDate: dueDate,
          clearDueDate: dueDate == null,
          recurrence: dueDate == null ? RecurrenceType.none : task.recurrence,
          clearPostponedDay: clearPostponed,
        ),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void batchMoveToList(Set<String> taskIds, String targetListId) {
    _mapSelectedTasks(
      taskIds,
      (task) => task.copyWith(listId: targetListId),
    );
  }

  void batchDeleteTasks(Set<String> taskIds) {
    final updated =
        _state.tasks.where((t) => !taskIds.contains(t.id)).toList();
    _commitTasks(
      updated,
      clearSelectedTaskId: _state.selectedTaskId != null &&
          taskIds.contains(_state.selectedTaskId),
    );
  }
}

final tasksActionPresenterProvider = Provider<TasksActionPresenter>((ref) {
  return TasksActionPresenter(ref);
});
