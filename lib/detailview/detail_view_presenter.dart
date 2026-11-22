import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_item.dart';
import '../data/todo_provider.dart';
import '../sync/todo_wire_codecs.dart';
import '../tasksview/tasks_view_presenter.dart';
import 'recurrence/task_pickers.dart';

/// Presenter for `detailview/DetailViewFragment`, matching `detailview/DetailViewPresenter`.
class DetailViewPresenter {
  DetailViewPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void _commitTasks(
    List<TaskItem> updated, {
    bool clearSelectedTaskId = false,
  }) {
    _store.commit(
      _state.copyWith(tasks: updated, clearSelectedTaskId: clearSelectedTaskId),
    );
    _store.storage.saveTasks(updated);
  }

  void _updateTaskById(
    String taskId,
    TaskItem Function(TaskItem task) transform,
  ) {
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId) transform(task) else task,
    ];
    _commitTasks(updated);
  }

  void toggleTaskCompleted(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskCompleted(taskId);
  }

  void toggleTaskImportant(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskImportant(taskId);
  }

  void toggleTaskMyDay(String taskId) {
    final now = DateTime.now();
    _updateTaskById(taskId, (task) {
      final adding = !task.isInMyDay;
      final dueToday =
          task.dueDate != null && TodoNotifier.isSameDay(task.dueDate!, now);
      final committedOrder = adding
          ? computeNewOrderDateTime(
              existingOrders: _state.tasks
                  .where((t) => t.isInMyDay)
                  .map((t) => t.committedOrder),
              addToTop: _state.addNewTasksOnTop,
              fallbackNow: now,
            )
          : null;
      return TodoNotifier.syncMyDayFlag(
        task.copyWith(
          myDayDate: adding ? now : null,
          clearMyDayDate: !adding,
          committedOrder: committedOrder,
          clearCommittedOrder: !adding,
          postponedDay: !adding && dueToday ? now : task.postponedDay,
          clearPostponedDay: adding,
        ),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void updateTaskTitle(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _updateTaskById(taskId, (task) => task.copyWith(title: trimmed));
  }

  void updateTaskNote(String taskId, String note) {
    final now = DateTime.now();
    var changed = false;
    final updated = <TaskItem>[];
    for (final task in _state.tasks) {
      if (task.id == taskId && task.note != note) {
        changed = true;
        updated.add(task.copyWith(note: note, noteUpdatedAt: now));
      } else {
        updated.add(task);
      }
    }
    if (!changed) return;
    _commitTasks(updated);
  }

  void moveTaskToList(String taskId, String targetListId) {
    _updateTaskById(taskId, (task) => task.copyWith(listId: targetListId));
  }

  void setTaskDueDate(String taskId, DateTime? dueDate) {
    final now = DateTime.now();
    _updateTaskById(taskId, (task) {
      final clearPostponed =
          dueDate != null &&
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

  void setTaskReminder(String taskId, DateTime? reminderAt) {
    _updateTaskById(
      taskId,
      (task) => task.copyWith(
        reminderAt: reminderAt,
        clearReminderAt: reminderAt == null,
      ),
    );
  }

  void setTaskRecurrence(String taskId, RecurrenceType recurrence) {
    final now = DateTime.now();
    _updateTaskById(taskId, (task) {
      final nextDue =
          (recurrence != RecurrenceType.none && task.dueDate == null)
          ? defaultDueDateForRecurrence(recurrence, reminderAt: task.reminderAt)
          : task.dueDate;
      return TodoNotifier.syncMyDayFlag(
        task.copyWith(recurrence: recurrence, dueDate: nextDue),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void deleteTask(String taskId) {
    final updated = _state.tasks.where((t) => t.id != taskId).toList();
    _commitTasks(updated, clearSelectedTaskId: _state.selectedTaskId == taskId);
  }

  void addStep(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _updateTaskById(
      taskId,
      (task) => task.copyWith(
        steps: [
          ...task.steps,
          TaskStep(
            id: _store.nextId('step'),
            title: trimmed,
            orderDateTime: computeNewOrderDateTime(
              existingOrders: task.steps.map((s) => s.orderDateTime),
              addToTop: false,
            ),
          ),
        ],
      ),
    );
  }

  void toggleStepCompleted(String taskId, String stepId) {
    _updateTaskById(
      taskId,
      (task) => task.copyWith(
        steps: [
          for (final step in task.steps)
            if (step.id == stepId)
              step.copyWith(isCompleted: !step.isCompleted)
            else
              step,
        ],
      ),
    );
  }

  void deleteStep(String taskId, String stepId) {
    _updateTaskById(
      taskId,
      (task) => task.copyWith(
        steps: task.steps.where((s) => s.id != stepId).toList(),
      ),
    );
  }

  void renameStep(String taskId, String stepId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      deleteStep(taskId, stepId);
      return;
    }
    _updateTaskById(
      taskId,
      (task) => task.copyWith(
        steps: [
          for (final step in task.steps)
            if (step.id == stepId) step.copyWith(title: trimmed) else step,
        ],
      ),
    );
  }

  void promoteStepToTask(String taskId, String stepId) {
    TaskItem? promoted;
    final updated = <TaskItem>[];
    for (final task in _state.tasks) {
      if (task.id != taskId) {
        updated.add(task);
        continue;
      }
      final step = task.steps.where((s) => s.id == stepId).firstOrNull;
      if (step == null || step.isCompleted) {
        updated.add(task);
        continue;
      }
      final now = DateTime.now();
      promoted = TaskItem(
        id: _store.nextId('task'),
        listId: task.listId,
        title: step.title,
        createdAt: now,
        orderDateTime: computeNewOrderDateTime(
          existingOrders: _state.tasks
              .where((t) => t.listId == task.listId)
              .map((t) => t.orderDateTime),
          addToTop: _state.addNewTasksOnTop,
          fallbackNow: now,
        ),
        isCompleted: false,
      );
      updated.add(
        task.copyWith(steps: task.steps.where((s) => s.id != stepId).toList()),
      );
    }
    if (promoted == null) return;
    if (_state.addNewTasksOnTop) {
      updated.insert(0, promoted);
    } else {
      updated.add(promoted);
    }
    _commitTasks(updated);
  }
}

final detailViewPresenterProvider = Provider<DetailViewPresenter>((ref) {
  return DetailViewPresenter(ref);
});
