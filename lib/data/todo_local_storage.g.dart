// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_local_storage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PendingStepDeletion _$PendingStepDeletionFromJson(Map<String, dynamic> json) =>
    _PendingStepDeletion(
      taskRemoteId: json['taskRemoteId'] as String,
      stepRemoteId: json['stepRemoteId'] as String,
    );

Map<String, dynamic> _$PendingStepDeletionToJson(
  _PendingStepDeletion instance,
) => <String, dynamic>{
  'taskRemoteId': instance.taskRemoteId,
  'stepRemoteId': instance.stepRemoteId,
};
