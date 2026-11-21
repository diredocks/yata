import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_item.dart';
import '../providers/todo_provider.dart';

/// Batch action presenter matching `tasksview/TasksActionPresenter`.
class TasksActionPresenter {
  TasksActionPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void batchSetMyDay(Set<String> taskIds, bool value) {
    final now = DateTime.now();
    final updated = [
      for (final task in _state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(
            isInMyDay: value,
            myDayDate: value ? now : null,
            clearMyDayDate: !value,
          )
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void batchToggleMyDay(Set<String> taskIds) {
    final selected = _state.tasks.where((t) => taskIds.contains(t.id));
    final allInMyDay =
        selected.isNotEmpty && selected.every((t) => t.isInMyDay);
    batchSetMyDay(taskIds, !allInMyDay);
  }

  void batchSetImportant(Set<String> taskIds, bool value) {
    final updated = [
      for (final task in _state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(isImportant: value)
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
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
            isCompleted: false,
            clearCompletedAt: true,
            steps: [
              for (final step in task.steps)
                TaskStep(id: _store.nextId('step'), title: step.title),
            ],
          ),
    ];
    if (copies.isEmpty) return;
    final updated = _state.addNewTasksOnTop
        ? [...copies, ..._state.tasks]
        : [..._state.tasks, ...copies];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void batchSetDueDate(Set<String> taskIds, DateTime? dueDate) {
    final now = DateTime.now();
    final autoMyDay = dueDate != null &&
        _state.showDueTodayInMyDay &&
        _isSameDay(dueDate, now);
    final updated = [
      for (final task in _state.tasks)
        if (taskIds.contains(task.id))
          () {
            final wasDueToday =
                task.dueDate != null && _isSameDay(task.dueDate!, now);
            final leavingToday =
                wasDueToday && (dueDate == null || !_isSameDay(dueDate, now));
            return task.copyWith(
              dueDate: dueDate,
              clearDueDate: dueDate == null,
              recurrence:
                  dueDate == null ? RecurrenceType.none : task.recurrence,
              isInMyDay: autoMyDay
                  ? true
                  : (leavingToday ? false : task.isInMyDay),
              myDayDate: autoMyDay ? now : task.myDayDate,
              clearMyDayDate: leavingToday && !autoMyDay,
            );
          }()
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void batchMoveToList(Set<String> taskIds, String targetListId) {
    final updated = [
      for (final task in _state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(listId: targetListId)
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void batchDeleteTasks(Set<String> taskIds) {
    final updated =
        _state.tasks.where((t) => !taskIds.contains(t.id)).toList();
    _store.commit(
      _state.copyWith(
        tasks: updated,
        clearSelectedTaskId: _state.selectedTaskId != null &&
            taskIds.contains(_state.selectedTaskId),
      ),
    );
    _store.storage.saveTasks(updated);
  }
}

final tasksActionPresenterProvider = Provider<TasksActionPresenter>((ref) {
  return TasksActionPresenter(ref);
});
