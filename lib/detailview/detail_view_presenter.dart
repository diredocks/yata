import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_date_time.dart';
import '../data/todo_provider.dart';
import '../models/task_item.dart';
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
    _store.mutateTask(taskId, (task) {
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
          committedOrder: committedOrder,
          postponedDay: adding
              ? null
              : (!adding && dueToday ? now : task.postponedDay),
        ),
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      );
    });
  }

  void updateTaskTitle(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _store.mutateTask(taskId, (task) => task.copyWith(title: trimmed));
  }

  void updateTaskNote(String taskId, String note) {
    final nowUtc = DateTime.now().toUtc();
    _store.mutateTask(
      taskId,
      (task) => task.note == note
          ? task
          : task.copyWith(note: note, noteUpdatedAt: nowUtc),
    );
  }

  void moveTaskToList(String taskId, String targetListId) {
    _store.mutateTask(taskId, (task) => task.copyWith(listId: targetListId));
  }

  void setTaskDueDate(String taskId, DateTime? dueDate) {
    final now = DateTime.now();
    _store.mutateTask(
      taskId,
      (task) => TodoNotifier.applyDueDate(
        task,
        dueDate,
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
      ),
    );
  }

  void setTaskReminder(String taskId, DateTime? reminderAt) {
    _store.mutateTask(
      taskId,
      (task) => task.copyWith(reminderAt: reminderAt?.toUtc()),
    );
  }

  void setTaskRecurrence(
    String taskId,
    RecurrenceType recurrence, {
    Map<String, dynamic>? rawRecurrence,
  }) {
    final now = DateTime.now();
    _store.mutateTask(
      taskId,
      (task) => TodoNotifier.applyRecurrence(
        task,
        recurrence,
        now: now,
        showDueTodayInMyDay: _state.showDueTodayInMyDay,
        fallbackDueDate: defaultDueDateForRecurrence(
          recurrence,
          reminderAt: task.reminderAt,
        ),
        rawRecurrence: rawRecurrence,
      ),
    );
  }

  void deleteTask(String taskId) {
    _store.deleteTasks({taskId});
  }

  String nextAttachmentId() => _store.nextId('att');

  void addAttachment(String taskId, TaskAttachment attachment) {
    _store.mutateTask(
      taskId,
      (task) => task.copyWith(attachments: [...task.attachments, attachment]),
    );
  }

  void updateAttachment(String taskId, TaskAttachment attachment) {
    _store.mutateTask(
      taskId,
      (task) => task.copyWith(
        attachments: [
          for (final item in task.attachments)
            if (item.id == attachment.id) attachment else item,
        ],
      ),
    );
  }

  void deleteAttachment(String taskId, String attachmentId) {
    _store.mutateTask(
      taskId,
      (task) => task.copyWith(
        attachments: task.attachments
            .where((a) => a.id != attachmentId)
            .toList(),
      ),
    );
  }

  void addStep(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _store.mutateTask(
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
    _store.mutateTask(
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
    _store.mutateTask(
      taskId,
      (task) => task.copyWith(
        steps: task.steps.where((s) => s.id != stepId).toList(),
      ),
    );
  }

  void reorderSteps(String taskId, int oldIndex, int newIndex) {
    final task = _state.tasks.firstWhereOrNull((t) => t.id == taskId);
    if (task == null) return;
    final steps = task.steps;
    if (oldIndex < 0 || oldIndex >= steps.length) return;
    if (newIndex < 0 || newIndex >= steps.length || oldIndex == newIndex) {
      return;
    }

    final reordered = [...steps];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final newPositions = computeReorderedOrderDateTimes([
      for (final s in reordered) s.orderDateTime,
    ], newIndex);
    for (final entry in newPositions.entries) {
      reordered[entry.key] = reordered[entry.key].copyWith(
        orderDateTime: entry.value,
      );
    }

    _store.mutateTask(taskId, (t) => t.copyWith(steps: reordered));
  }

  void renameStep(String taskId, String stepId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) {
      deleteStep(taskId, stepId);
      return;
    }
    _store.mutateTask(
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
      final step = task.steps.firstWhereOrNull((s) => s.id == stepId);
      if (step == null || step.isCompleted) {
        updated.add(task);
        continue;
      }
      final nowUtc = DateTime.now().toUtc();
      promoted = TaskItem(
        id: _store.nextId('task'),
        listId: task.listId,
        title: step.title,
        createdAt: nowUtc,
        orderDateTime: computeNewOrderDateTime(
          existingOrders: _state.tasks
              .where((t) => t.listId == task.listId)
              .map((t) => t.orderDateTime),
          addToTop: _state.addNewTasksOnTop,
          fallbackNow: nowUtc,
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
    _store.mutateEntities(
      tasks: updated,
      touchedTaskIds: {taskId, promoted.id},
    );
  }
}

final detailViewPresenterProvider = Provider<DetailViewPresenter>((ref) {
  return DetailViewPresenter(ref);
});
