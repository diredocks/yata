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
          () {
            final adding = !task.isInMyDay;
            final dueToday = task.dueDate != null &&
                TodoNotifier.isSameDay(task.dueDate!, now);
            return TodoNotifier.syncMyDayFlag(
              task.copyWith(
                myDayDate: adding ? now : null,
                clearMyDayDate: !adding,
                postponedDay: !adding && dueToday ? now : task.postponedDay,
                clearPostponedDay: adding,
              ),
              now: now,
              showDueTodayInMyDay: _state.showDueTodayInMyDay,
            );
          }()
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
    var changed = false;
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId && task.note != note)
          () {
            changed = true;
            return task.copyWith(note: note, noteUpdatedAt: now);
          }()
        else
          task,
    ];
    if (!changed) return;
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
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          () {
            final clearPostponed = dueDate != null &&
                _state.showDueTodayInMyDay &&
                task.postponedDay != null &&
                TodoNotifier.isSameDay(dueDate, task.postponedDay!);
            return TodoNotifier.syncMyDayFlag(
              task.copyWith(
                dueDate: dueDate,
                clearDueDate: dueDate == null,
                recurrence:
                    dueDate == null ? RecurrenceType.none : task.recurrence,
                clearPostponedDay: clearPostponed,
              ),
              now: now,
              showDueTodayInMyDay: _state.showDueTodayInMyDay,
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
            return TodoNotifier.syncMyDayFlag(
              task.copyWith(
                recurrence: recurrence,
                dueDate: nextDue,
              ),
              now: now,
              showDueTodayInMyDay: _state.showDueTodayInMyDay,
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
    if (trimmed.isEmpty) {
      deleteStep(taskId, stepId);
      return;
    }
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
        if (step != null && !step.isCompleted) {
          promoted = TaskItem(
            id: _store.nextId('task'),
            listId: task.listId,
            title: step.title,
            createdAt: DateTime.now(),
            isCompleted: false,
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
