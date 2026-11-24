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

bool _deepJsonEquals(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepJsonEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepJsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

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
  final prevById = {
    for (final s in prev?.steps ?? const <TaskStep>[]) s.id: s,
  };
  final dirty = <String>{};
  for (final step in next.steps) {
    final prevStep = prevById[step.id];
    if (prevStep == null ||
        prevStep.title != step.title ||
        prevStep.isCompleted != step.isCompleted ||
        prevStep.orderDateTime != step.orderDateTime) {
      dirty.add(step.id);
    }
  }
  return dirty;
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
  if (prev.isImportant != next.isImportant) fields.add(TaskDirtyField.importance);
  if (prev.dueDate != next.dueDate) fields.add(TaskDirtyField.dueDate);
  if (prev.reminderAt != next.reminderAt) fields.add(TaskDirtyField.reminder);
  if (prev.recurrence != next.recurrence ||
      !_deepJsonEquals(prev.rawRecurrence, next.rawRecurrence)) {
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
  final stepRemoved = prev.steps.any(
    (ps) => !next.steps.any((ns) => ns.id == ps.id),
  );
  if (dirtySteps.isNotEmpty || stepRemoved) {
    fields.add(TaskDirtyField.steps);
  }
  return fields;
}

/// Decodes `"<entityId>::<enumName>"` entries into a per-entity enum set map.
Map<String, Set<T>> decodeEntityFieldMap<T extends Enum>(
  Iterable<String> entries,
  List<T> values,
) {
  final byName = {for (final v in values) v.name: v};
  final result = <String, Set<T>>{};
  for (final raw in entries) {
    final sep = raw.lastIndexOf('::');
    if (sep <= 0 || sep + 2 >= raw.length) continue;
    final entityId = raw.substring(0, sep);
    final field = byName[raw.substring(sep + 2)];
    if (field == null) continue;
    (result[entityId] ??= <T>{}).add(field);
  }
  return result;
}

/// Encodes a per-entity enum set map into `"<entityId>::<enumName>"` entries.
List<String> encodeEntityFieldMap<T extends Enum>(Map<String, Set<T>> map) {
  final result = <String>[];
  for (final entry in map.entries) {
    for (final field in entry.value) {
      result.add('${entry.key}::${field.name}');
    }
  }
  return result;
}

/// Decodes `"<entityId>::<childId>"` entries into a per-entity string set map.
Map<String, Set<String>> decodeEntityStringSetMap(Iterable<String> entries) {
  final result = <String, Set<String>>{};
  for (final raw in entries) {
    final sep = raw.indexOf('::');
    if (sep <= 0 || sep + 2 >= raw.length) continue;
    final entityId = raw.substring(0, sep);
    final childId = raw.substring(sep + 2);
    (result[entityId] ??= <String>{}).add(childId);
  }
  return result;
}

/// Encodes a per-entity string set map into `"<entityId>::<childId>"` entries.
List<String> encodeEntityStringSetMap(Map<String, Set<String>> map) {
  final result = <String>[];
  for (final entry in map.entries) {
    for (final childId in entry.value) {
      result.add('${entry.key}::$childId');
    }
  }
  return result;
}
