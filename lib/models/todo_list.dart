import 'package:freezed_annotation/freezed_annotation.dart';

import 'utc_date_time_json.dart';

part 'todo_list.freezed.dart';
part 'todo_list.g.dart';

enum SmartListType { myDay, important, planned, all, completed, tasks }

enum WeekStart {
  system,
  sunday,
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
}

extension WeekStartX on WeekStart {
  /// Resolves this [WeekStart] to a `DateTime` weekday (`1` = Monday .. `7` = Sunday).
  ///
  /// [WeekStart.system] defaults to [DateTime.monday] when no platform locale
  /// override is supplied.
  int get resolvedWeekday => switch (this) {
    WeekStart.system || WeekStart.monday => DateTime.monday,
    WeekStart.tuesday => DateTime.tuesday,
    WeekStart.wednesday => DateTime.wednesday,
    WeekStart.thursday => DateTime.thursday,
    WeekStart.friday => DateTime.friday,
    WeekStart.saturday => DateTime.saturday,
    WeekStart.sunday => DateTime.sunday,
  };
}

enum ListThemeColor {
  blue,
  rose,
  teal,
  green,
  purple,
  red,
  grey,
  lightBlue,
  lightRose,
  lightTeal,
  lightGreen,
  lightPurple,
  lightRed,
  lightGrey,
}

enum ListThemePhoto {
  beach,
  desert,
  fern,
  field,
  gradient,
  lighthouse,
  safari,
  sea,
  tvTower,
}

enum TaskSortOption {
  defaultOrder,
  importance,
  dueDate,
  addedToMyDay,
  alphabetical,
  creationDate,
}

extension TaskSortOptionDefaults on TaskSortOption {
  bool get defaultAscending {
    return switch (this) {
      TaskSortOption.defaultOrder => false,
      TaskSortOption.importance => false,
      TaskSortOption.dueDate => true,
      TaskSortOption.addedToMyDay => false,
      TaskSortOption.alphabetical => true,
      TaskSortOption.creationDate => false,
    };
  }
}

enum PlannedDueDateFilter { overdue, today, tomorrow, thisWeek, later, all }

enum PlannedGroupOption { ungroup, byDueDate, byList }

@freezed
abstract class TodoList with _$TodoList {
  const TodoList._();

  const factory TodoList({
    required String id,
    required String title,
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    SmartListType? smartType,
    String? groupId,
    String? emoji,
    @Default(ListThemeColor.blue)
    @JsonKey(unknownEnumValue: ListThemeColor.blue)
    ListThemeColor themeColor,
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    ListThemePhoto? themePhoto,
    String? customBackgroundPath,
    @Default(TaskSortOption.defaultOrder)
    @JsonKey(unknownEnumValue: TaskSortOption.defaultOrder)
    TaskSortOption sortOption,
    @Default(true) bool sortAscending,
    @Default(true) bool showCompleted,
    String? remoteId,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? orderDateTime,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? updatedAt,
  }) = _TodoList;

  factory TodoList.fromJson(Map<String, dynamic> json) =>
      _$TodoListFromJson(json);

  bool get isSmartList => smartType != null;

  bool get canHoldTasks => !isSmartList || smartType == SmartListType.tasks;
}

@freezed
abstract class ListGroup with _$ListGroup {
  const factory ListGroup({
    required String id,
    required String title,
    @Default(true) bool isExpanded,
    String? remoteId,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? orderDateTime,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? updatedAt,
  }) = _ListGroup;

  factory ListGroup.fromJson(Map<String, dynamic> json) =>
      _$ListGroupFromJson(json);
}
