// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TaskStep _$TaskStepFromJson(Map<String, dynamic> json) => _TaskStep(
  id: json['id'] as String,
  title: json['title'] as String,
  isCompleted: json['isCompleted'] as bool? ?? false,
  remoteId: json['remoteId'] as String?,
  orderDateTime: nullableUtcDateTimeFromJson(json['orderDateTime'] as String?),
);

Map<String, dynamic> _$TaskStepToJson(_TaskStep instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'isCompleted': instance.isCompleted,
  'remoteId': instance.remoteId,
  'orderDateTime': nullableUtcDateTimeToJson(instance.orderDateTime),
};

_TaskItem _$TaskItemFromJson(Map<String, dynamic> json) => _TaskItem(
  id: json['id'] as String,
  listId: json['listId'] as String,
  title: json['title'] as String,
  createdAt: utcDateTimeFromJson(json['createdAt'] as String),
  isCompleted: json['isCompleted'] as bool? ?? false,
  isImportant: json['isImportant'] as bool? ?? false,
  isInMyDay: json['isInMyDay'] as bool? ?? false,
  myDayDate: json['myDayDate'] == null
      ? null
      : DateTime.parse(json['myDayDate'] as String),
  postponedDay: json['postponedDay'] == null
      ? null
      : DateTime.parse(json['postponedDay'] as String),
  dueDate: json['dueDate'] == null
      ? null
      : DateTime.parse(json['dueDate'] as String),
  reminderAt: nullableUtcDateTimeFromJson(json['reminderAt'] as String?),
  recurrence:
      $enumDecodeNullable(
        _$RecurrenceTypeEnumMap,
        json['recurrence'],
        unknownValue: RecurrenceType.none,
      ) ??
      RecurrenceType.none,
  rawRecurrence: json['rawRecurrence'] as Map<String, dynamic>?,
  note: json['note'] as String? ?? '',
  noteUpdatedAt: nullableUtcDateTimeFromJson(json['noteUpdatedAt'] as String?),
  completedAt: nullableUtcDateTimeFromJson(json['completedAt'] as String?),
  steps:
      (json['steps'] as List<dynamic>?)
          ?.map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <TaskStep>[],
  remoteId: json['remoteId'] as String?,
  remoteParentFolderId: json['remoteParentFolderId'] as String?,
  orderDateTime: nullableUtcDateTimeFromJson(json['orderDateTime'] as String?),
  committedOrder: nullableUtcDateTimeFromJson(
    json['committedOrder'] as String?,
  ),
  changeKey: json['changeKey'] as String?,
  updatedAt: nullableUtcDateTimeFromJson(json['updatedAt'] as String?),
);

Map<String, dynamic> _$TaskItemToJson(_TaskItem instance) => <String, dynamic>{
  'id': instance.id,
  'listId': instance.listId,
  'title': instance.title,
  'createdAt': utcDateTimeToJson(instance.createdAt),
  'isCompleted': instance.isCompleted,
  'isImportant': instance.isImportant,
  'isInMyDay': instance.isInMyDay,
  'myDayDate': instance.myDayDate?.toIso8601String(),
  'postponedDay': instance.postponedDay?.toIso8601String(),
  'dueDate': instance.dueDate?.toIso8601String(),
  'reminderAt': nullableUtcDateTimeToJson(instance.reminderAt),
  'recurrence': _$RecurrenceTypeEnumMap[instance.recurrence]!,
  'rawRecurrence': instance.rawRecurrence,
  'note': instance.note,
  'noteUpdatedAt': nullableUtcDateTimeToJson(instance.noteUpdatedAt),
  'completedAt': nullableUtcDateTimeToJson(instance.completedAt),
  'steps': instance.steps.map((e) => e.toJson()).toList(),
  'remoteId': instance.remoteId,
  'remoteParentFolderId': instance.remoteParentFolderId,
  'orderDateTime': nullableUtcDateTimeToJson(instance.orderDateTime),
  'committedOrder': nullableUtcDateTimeToJson(instance.committedOrder),
  'changeKey': instance.changeKey,
  'updatedAt': nullableUtcDateTimeToJson(instance.updatedAt),
};

const _$RecurrenceTypeEnumMap = {
  RecurrenceType.none: 'none',
  RecurrenceType.daily: 'daily',
  RecurrenceType.weekdays: 'weekdays',
  RecurrenceType.weekly: 'weekly',
  RecurrenceType.monthly: 'monthly',
  RecurrenceType.yearly: 'yearly',
};
