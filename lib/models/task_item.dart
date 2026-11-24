import 'package:freezed_annotation/freezed_annotation.dart';

import 'utc_date_time_json.dart';

part 'task_item.freezed.dart';
part 'task_item.g.dart';

enum RecurrenceType { none, daily, weekdays, weekly, monthly, yearly }

@freezed
abstract class TaskStep with _$TaskStep {
  const factory TaskStep({
    required String id,
    required String title,
    @Default(false) bool isCompleted,
    String? remoteId,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? orderDateTime,
  }) = _TaskStep;

  factory TaskStep.fromJson(Map<String, dynamic> json) =>
      _$TaskStepFromJson(json);
}

@freezed
abstract class TaskItem with _$TaskItem {
  const TaskItem._();

  const factory TaskItem({
    required String id,
    required String listId,
    required String title,
    @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson)
    required DateTime createdAt,
    @Default(false) bool isCompleted,
    @Default(false) bool isImportant,
    @Default(false) bool isInMyDay,
    DateTime? myDayDate,
    DateTime? postponedDay,
    DateTime? dueDate,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? reminderAt,
    @Default(RecurrenceType.none)
    @JsonKey(unknownEnumValue: RecurrenceType.none)
    RecurrenceType recurrence,
    Map<String, dynamic>? rawRecurrence,
    @Default('') String note,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? noteUpdatedAt,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? completedAt,
    @Default(<TaskStep>[]) List<TaskStep> steps,
    String? remoteId,
    String? remoteParentFolderId,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? orderDateTime,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? committedOrder,
    String? changeKey,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? updatedAt,
  }) = _TaskItem;

  factory TaskItem.fromJson(Map<String, dynamic> json) =>
      _$TaskItemFromJson(json);

  bool get hasRecurrence =>
      recurrence != RecurrenceType.none ||
      (rawRecurrence != null && rawRecurrence!.isNotEmpty);

  int get completedStepsCount => steps.where((step) => step.isCompleted).length;

  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }
}
