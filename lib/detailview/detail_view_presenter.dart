import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_item.dart';
import '../providers/todo_provider.dart';
import '../tasksview/tasks_view_presenter.dart';
import 'recurrence/task_pickers.dart';

/// Presenter for `detailview/DetailViewFragment`, matching `detailview/DetailViewPresenter`.
class DetailViewPresenter {
  DetailViewPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void toggleTaskCompleted(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskCompleted(taskId);
  }

  void toggleTaskImportant(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskImportant(taskId);
  }

  void toggleTaskMyDay(String taskId) {
    final now = DateTime.now();
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(
            isInMyDay: !task.isInMyDay,
            myDayDate: !task.isInMyDay ? now : null,
            clearMyDayDate: task.isInMyDay,
          )
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void updateTaskTitle(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId) task.copyWith(title: trimmed) else task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void updateTaskNote(String taskId, String note) {
    final now = DateTime.now();
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(note: note, noteUpdatedAt: now)
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void moveTaskToList(String taskId, String targetListId) {
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId) task.copyWith(listId: targetListId) else task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void setTaskDueDate(String taskId, DateTime? dueDate) {
    final now = DateTime.now();
    final autoMyDay = dueDate != null &&
        _state.showDueTodayInMyDay &&
        _isSameDay(dueDate, now);
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
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

  void setTaskReminder(String taskId, DateTime? reminderAt) {
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(
            reminderAt: reminderAt,
            clearReminderAt: reminderAt == null,
          )
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void setTaskRecurrence(String taskId, RecurrenceType recurrence) {
    final now = DateTime.now();
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          () {
            final nextDue =
                (recurrence != RecurrenceType.none && task.dueDate == null)
                    ? defaultDueDateForRecurrence(
                        recurrence,
                        reminderAt: task.reminderAt,
                      )
                    : task.dueDate;
            final autoMyDay = nextDue != null &&
                _state.showDueTodayInMyDay &&
                _isSameDay(nextDue, now);
            return task.copyWith(
              recurrence: recurrence,
              dueDate: nextDue,
              isInMyDay: autoMyDay ? true : task.isInMyDay,
              myDayDate: autoMyDay ? now : task.myDayDate,
            );
          }()
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void deleteTask(String taskId) {
    final updated = _state.tasks.where((t) => t.id != taskId).toList();
    _store.commit(
      _state.copyWith(
        tasks: updated,
        clearSelectedTaskId: _state.selectedTaskId == taskId,
      ),
    );
    _store.storage.saveTasks(updated);
  }

  void addStep(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final newStep = TaskStep(id: _store.nextId('step'), title: trimmed);
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(steps: [...task.steps, newStep])
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void toggleStepCompleted(String taskId, String stepId) {
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(
            steps: [
              for (final step in task.steps)
                if (step.id == stepId)
                  step.copyWith(isCompleted: !step.isCompleted)
                else
                  step,
            ],
          )
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void deleteStep(String taskId, String stepId) {
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(
            steps: task.steps.where((s) => s.id != stepId).toList(),
          )
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void renameStep(String taskId, String stepId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(
            steps: [
              for (final step in task.steps)
                if (step.id == stepId) step.copyWith(title: trimmed) else step,
            ],
          )
        else
          task,
    ];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void promoteStepToTask(String taskId, String stepId) {
    TaskItem? promoted;
    final updated = <TaskItem>[];
    for (final task in _state.tasks) {
      if (task.id == taskId) {
        final step = task.steps.where((s) => s.id == stepId).firstOrNull;
        if (step != null) {
          promoted = TaskItem(
            id: _store.nextId('task'),
            listId: task.listId,
            title: step.title,
            createdAt: DateTime.now(),
            isCompleted: step.isCompleted,
            completedAt: step.isCompleted ? DateTime.now() : null,
          );
          updated.add(
            task.copyWith(
              steps: task.steps.where((s) => s.id != stepId).toList(),
            ),
          );
        } else {
          updated.add(task);
        }
      } else {
        updated.add(task);
      }
    }
    if (promoted != null) {
      if (_state.addNewTasksOnTop) {
        updated.insert(0, promoted);
      } else {
        updated.add(promoted);
      }
    }
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }
}

final detailViewPresenterProvider = Provider<DetailViewPresenter>((ref) {
  return DetailViewPresenter(ref);
});
