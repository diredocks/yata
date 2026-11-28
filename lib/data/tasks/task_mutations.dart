import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../../sync/microsoft/substrate_time_codecs.dart';
import '../ordering/order_date_time.dart';
import 'recurrence.dart';
import '../state/todo_provider.dart';
import '../account/account_provider.dart';
import 'my_day.dart';

class TaskMutations {
  TaskMutations(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void addTask({
    required String title,
    String? targetListId,
    bool isInMyDay = false,
    bool isImportant = false,
    DateTime? dueDate,
    DateTime? reminderAt,
    RecurrenceType recurrence = RecurrenceType.none,
    Map<String, dynamic>? rawRecurrence,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final currentList = _state.selectedList;
    final resolvedListId =
        targetListId ?? (currentList.isSmartList ? 'tasks' : currentList.id);

    final now = DateTime.now();
    final effectiveDueDate =
        dueDate ??
        (currentList.smartType == SmartListType.planned ? now : null);
    final committedToMyDay =
        isInMyDay || currentList.smartType == SmartListType.myDay;
    final orderDateTime = computeNewOrderDateTime(
      existingOrders: _state.tasks
          .where((t) => t.listId == resolvedListId)
          .map((t) => t.orderDateTime),
      addToTop: _state.addNewTasksOnTop,
      fallbackNow: now,
    );
    final committedOrder = committedToMyDay
        ? computeNewOrderDateTime(
            existingOrders: _state.tasks
                .where((t) => t.isInMyDay)
                .map((t) => t.committedOrder),
            addToTop: _state.addNewTasksOnTop,
            fallbackNow: now,
          )
        : null;
    final newTask = syncMyDayFlag(
      TaskItem(
        id: _store.nextId('task'),
        listId: resolvedListId,
        title: trimmed,
        createdAt: now.toUtc(),
        isInMyDay: committedToMyDay,
        myDayDate: committedToMyDay ? now : null,
        orderDateTime: orderDateTime,
        committedOrder: committedOrder,
        isImportant:
            isImportant || currentList.smartType == SmartListType.important,
        dueDate: effectiveDueDate,
        reminderAt: reminderAt?.toUtc(),
        recurrence: recurrence,
        rawRecurrence: normalizeRawRecurrence(rawRecurrence),
      ),
      now: now,
      showDueTodayInMyDay: _state.showDueTodayInMyDay,
    );

    _store.addTask(newTask, addToTop: _state.addNewTasksOnTop);
  }

  void toggleTaskCompleted(String taskId) {
    final target = _state.tasks.firstWhereOrNull((t) => t.id == taskId);
    if (target == null) return;
    setTaskCompleted(taskId, completed: !target.isCompleted);
  }

  void setTaskCompleted(String taskId, {required bool completed}) {
    final target = _state.tasks.firstWhereOrNull((t) => t.id == taskId);
    if (target == null || target.isCompleted == completed) return;

    final now = DateTime.now();
    final willSpawn =
        completed &&
        target.hasRecurrence &&
        shouldSpawnRecurringLocally(
          target,
          activeAccount: _ref.read(accountProvider).activeAccount,
        );
    if (!willSpawn) {
      _store.mutateTask(
        taskId,
        (task) => task.copyWith(
          isCompleted: completed,
          completedAt: completed ? now.toUtc() : null,
        ),
      );
      return;
    }

    final nextOccurrence = _buildNextRecurringTask(target, now);
    final updated = [
      for (final task in _state.tasks)
        if (task.id == taskId)
          task.copyWith(isCompleted: true, completedAt: now.toUtc())
        else
          task,
    ];
    if (_state.addNewTasksOnTop) {
      updated.insert(0, nextOccurrence);
    } else {
      updated.add(nextOccurrence);
    }
    _store.mutateEntities(
      tasks: updated,
      touchedTaskIds: {taskId, nextOccurrence.id},
    );
  }

  void toggleTaskImportant(String taskId) {
    final target = _state.tasks.firstWhereOrNull((t) => t.id == taskId);
    if (target == null) return;

    final nextImportant = !target.isImportant;
    if (!nextImportant || !_state.moveStarredTasksToTop) {
      _store.mutateTask(
        taskId,
        (task) => task.copyWith(isImportant: nextImportant),
      );
      return;
    }

    final topOrder = computeNewOrderDateTime(
      existingOrders: _state.tasks
          .where((t) => t.listId == target.listId && t.id != target.id)
          .map((t) => t.orderDateTime),
      addToTop: true,
    );
    final topCommitted = target.isInMyDay
        ? computeNewOrderDateTime(
            existingOrders: _state.tasks
                .where((t) => t.isInMyDay && t.id != target.id)
                .map((t) => t.committedOrder),
            addToTop: true,
          )
        : target.committedOrder;
    final movedToTop = target.copyWith(
      isImportant: true,
      orderDateTime: topOrder,
      committedOrder: topCommitted,
    );
    final updated = [
      movedToTop,
      for (final task in _state.tasks)
        if (task.id != taskId) task,
    ];
    _store.mutateEntities(tasks: updated, touchedTaskIds: {taskId});
  }

  TaskItem _buildNextRecurringTask(TaskItem task, DateTime now) {
    final baseDate = task.dueDate ?? DateTime(now.year, now.month, now.day);
    final nextDue = computeNextDueDate(
      baseDate,
      task.recurrence,
      rawRecurrence: task.rawRecurrence,
    );
    DateTime? nextReminder;
    if (task.reminderAt case final reminderAt?) {
      final localReminder = reminderAt.toLocal();
      nextReminder = DateTime(
        nextDue.year,
        nextDue.month,
        nextDue.day,
        localReminder.hour,
        localReminder.minute,
      ).toUtc();
    }
    return syncMyDayFlag(
      TaskItem(
        id: _store.nextId('task'),
        listId: task.listId,
        title: task.title,
        createdAt: now.toUtc(),
        orderDateTime: computeNewOrderDateTime(
          existingOrders: _state.tasks
              .where((t) => t.listId == task.listId)
              .map((t) => t.orderDateTime),
          addToTop: _state.addNewTasksOnTop,
          fallbackNow: now,
        ),
        isImportant: task.isImportant,
        dueDate: nextDue,
        reminderAt: nextReminder,
        recurrence: task.recurrence,
        rawRecurrence: normalizeRawRecurrence(task.rawRecurrence),
        note: task.note,
        steps: [
          for (final step in task.steps)
            TaskStep(
              id: _store.nextId('step'),
              title: step.title,
              orderDateTime: step.orderDateTime,
            ),
        ],
      ),
      now: now,
      showDueTodayInMyDay: _state.showDueTodayInMyDay,
    );
  }
}

final taskMutationsProvider = Provider<TaskMutations>((ref) {
  return TaskMutations(ref);
});
