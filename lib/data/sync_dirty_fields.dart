import 'package:collection/collection.dart';

import '../models/task_item.dart';
import '../models/todo_list.dart';

/// Per-field dirty markers for [ListGroup] pushed incrementally in Phase 4.
enum GroupDirtyField { name, orderDateTime }

/// Per-field dirty markers for [TodoList] pushed incrementally in Phase 5.
enum ListDirtyField { name, group, theme, sort, showCompleted, orderDateTime }

/// Per-field dirty markers for [TaskItem] pushed incrementally in Phase 10a.
enum TaskDirtyField {
  subject,
  body,
  status,
  importance,
  dueDate,
  reminder,
  recurrence,
  orderDateTime,
  myDay,
  committedOrder,
  postponedDay,
  parentFolder,
  steps,
}

/// Recursively compares JSON-like maps, lists, and scalar values.
bool deepJsonEquals(dynamic a, dynamic b) => _deepJsonEquality.equals(a, b);

const _deepJsonEquality = DeepCollectionEquality();

/// Computes changed fields between [prev] and [next] [ListGroup].
Set<GroupDirtyField> diffGroupDirtyFields(ListGroup? prev, ListGroup next) {
  if (prev == null) return GroupDirtyField.values.toSet();
  return {
    if (prev.title != next.title) GroupDirtyField.name,
    if (prev.orderDateTime != next.orderDateTime) GroupDirtyField.orderDateTime,
  };
}

/// Computes changed fields between [prev] and [next] [TodoList].
Set<ListDirtyField> diffListDirtyFields(TodoList? prev, TodoList next) {
  if (prev == null) return ListDirtyField.values.toSet();
  return {
    if (prev.title != next.title || prev.emoji != next.emoji)
      ListDirtyField.name,
    if (prev.groupId != next.groupId) ListDirtyField.group,
    if (prev.themeColor != next.themeColor ||
        prev.themePhoto != next.themePhoto)
      ListDirtyField.theme,
    if (prev.sortOption != next.sortOption ||
        prev.sortAscending != next.sortAscending)
      ListDirtyField.sort,
    if (prev.showCompleted != next.showCompleted) ListDirtyField.showCompleted,
    if (prev.orderDateTime != next.orderDateTime) ListDirtyField.orderDateTime,
  };
}

/// Returns the local IDs of [TaskStep] items in [next] that were added or
/// modified relative to [prev].
Set<String> diffDirtyStepIds(TaskItem? prev, TaskItem next) {
  final prevById = {for (final s in prev?.steps ?? const <TaskStep>[]) s.id: s};
  bool isDirty(TaskStep step) {
    final prevStep = prevById[step.id];
    return prevStep == null ||
        prevStep.title != step.title ||
        prevStep.isCompleted != step.isCompleted ||
        prevStep.orderDateTime != step.orderDateTime;
  }

  return {
    for (final step in next.steps)
      if (isDirty(step)) step.id,
  };
}

/// Computes changed fields between [prev] and [next] [TaskItem].
Set<TaskDirtyField> diffTaskDirtyFields(TaskItem? prev, TaskItem next) {
  if (prev == null) return TaskDirtyField.values.toSet();
  final fields = <TaskDirtyField>{};
  if (prev.title != next.title) fields.add(TaskDirtyField.subject);
  if (prev.note != next.note) fields.add(TaskDirtyField.body);
  if (prev.isCompleted != next.isCompleted ||
      prev.completedAt != next.completedAt) {
    fields.add(TaskDirtyField.status);
  }
  if (prev.isImportant != next.isImportant) {
    fields.add(TaskDirtyField.importance);
  }
  if (prev.dueDate != next.dueDate) fields.add(TaskDirtyField.dueDate);
  if (prev.reminderAt != next.reminderAt) fields.add(TaskDirtyField.reminder);
  if (prev.recurrence != next.recurrence ||
      !deepJsonEquals(prev.rawRecurrence, next.rawRecurrence)) {
    fields.add(TaskDirtyField.recurrence);
  }
  if (prev.orderDateTime != next.orderDateTime) {
    fields.add(TaskDirtyField.orderDateTime);
  }
  if (prev.isInMyDay != next.isInMyDay || prev.myDayDate != next.myDayDate) {
    fields.add(TaskDirtyField.myDay);
  }
  if (prev.committedOrder != next.committedOrder) {
    fields.add(TaskDirtyField.committedOrder);
  }
  if (prev.postponedDay != next.postponedDay) {
    fields.add(TaskDirtyField.postponedDay);
  }
  if (prev.listId != next.listId) fields.add(TaskDirtyField.parentFolder);

  final dirtySteps = diffDirtyStepIds(prev, next);
  final nextStepIds = {for (final s in next.steps) s.id};
  final stepRemoved = prev.steps.any((s) => !nextStepIds.contains(s.id));
  if (dirtySteps.isNotEmpty || stepRemoved) {
    fields.add(TaskDirtyField.steps);
  }
  return fields;
}
