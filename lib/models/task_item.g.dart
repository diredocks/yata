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
  orderDateTime: json['orderDateTime'] == null
      ? null
      : DateTime.parse(json['orderDateTime'] as String),
);

Map<String, dynamic> _$TaskStepToJson(_TaskStep instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'isCompleted': instance.isCompleted,
  'remoteId': instance.remoteId,
  'orderDateTime': instance.orderDateTime?.toIso8601String(),
};

_TaskItem _$TaskItemFromJson(Map<String, dynamic> json) => _TaskItem(
  id: json['id'] as String,
  listId: json['listId'] as String,
  title: json['title'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
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
  reminderAt: json['reminderAt'] == null
      ? null
      : DateTime.parse(json['reminderAt'] as String),
  recurrence:
      $enumDecodeNullable(
        _$RecurrenceTypeEnumMap,
        json['recurrence'],
        unknownValue: RecurrenceType.none,
      ) ??
      RecurrenceType.none,
  note: json['note'] as String? ?? '',
  noteUpdatedAt: json['noteUpdatedAt'] == null
      ? null
      : DateTime.parse(json['noteUpdatedAt'] as String),
  completedAt: json['completedAt'] == null
      ? null
      : DateTime.parse(json['completedAt'] as String),
  steps:
      (json['steps'] as List<dynamic>?)
          ?.map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <TaskStep>[],
  remoteId: json['remoteId'] as String?,
  remoteParentFolderId: json['remoteParentFolderId'] as String?,
  orderDateTime: json['orderDateTime'] == null
      ? null
      : DateTime.parse(json['orderDateTime'] as String),
  committedOrder: json['committedOrder'] == null
      ? null
      : DateTime.parse(json['committedOrder'] as String),
  changeKey: json['changeKey'] as String?,
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$TaskItemToJson(_TaskItem instance) => <String, dynamic>{
  'id': instance.id,
  'listId': instance.listId,
  'title': instance.title,
  'createdAt': instance.createdAt.toIso8601String(),
  'isCompleted': instance.isCompleted,
  'isImportant': instance.isImportant,
  'isInMyDay': instance.isInMyDay,
  'myDayDate': instance.myDayDate?.toIso8601String(),
  'postponedDay': instance.postponedDay?.toIso8601String(),
  'dueDate': instance.dueDate?.toIso8601String(),
  'reminderAt': instance.reminderAt?.toIso8601String(),
  'recurrence': _$RecurrenceTypeEnumMap[instance.recurrence]!,
  'note': instance.note,
  'noteUpdatedAt': instance.noteUpdatedAt?.toIso8601String(),
  'completedAt': instance.completedAt?.toIso8601String(),
  'steps': instance.steps.map((e) => e.toJson()).toList(),
  'remoteId': instance.remoteId,
  'remoteParentFolderId': instance.remoteParentFolderId,
  'orderDateTime': instance.orderDateTime?.toIso8601String(),
  'committedOrder': instance.committedOrder?.toIso8601String(),
  'changeKey': instance.changeKey,
  'updatedAt': instance.updatedAt?.toIso8601String(),
};

const _$RecurrenceTypeEnumMap = {
  RecurrenceType.none: 'none',
  RecurrenceType.daily: 'daily',
  RecurrenceType.weekdays: 'weekdays',
  RecurrenceType.weekly: 'weekly',
  RecurrenceType.monthly: 'monthly',
  RecurrenceType.yearly: 'yearly',
};
