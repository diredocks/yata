// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SyncJob _$SyncJobFromJson(Map<String, dynamic> json) => _SyncJob(
  jobId: json['jobId'] as String,
  accountKey: json['accountKey'] as String,
  lane: $enumDecode(_$SyncJobLaneEnumMap, json['lane']),
  jobType: $enumDecode(_$SyncJobTypeEnumMap, json['jobType']),
  status:
      $enumDecodeNullable(_$SyncJobStatusEnumMap, json['status']) ??
      SyncJobStatus.pending,
  payload:
      json['payload'] as Map<String, dynamic>? ?? const <String, dynamic>{},
  progress: (json['progress'] as num?)?.toInt() ?? 0,
  attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
  nextRetryAt: nullableUtcDateTimeFromJson(json['nextRetryAt'] as String?),
  errorMessage: json['errorMessage'] as String?,
  createdAt: utcDateTimeFromJson(json['createdAt'] as String),
  updatedAt: utcDateTimeFromJson(json['updatedAt'] as String),
);

Map<String, dynamic> _$SyncJobToJson(_SyncJob instance) => <String, dynamic>{
  'jobId': instance.jobId,
  'accountKey': instance.accountKey,
  'lane': _$SyncJobLaneEnumMap[instance.lane]!,
  'jobType': _$SyncJobTypeEnumMap[instance.jobType]!,
  'status': _$SyncJobStatusEnumMap[instance.status]!,
  'payload': instance.payload,
  'progress': instance.progress,
  'attemptCount': instance.attemptCount,
  'nextRetryAt': nullableUtcDateTimeToJson(instance.nextRetryAt),
  'errorMessage': instance.errorMessage,
  'createdAt': utcDateTimeToJson(instance.createdAt),
  'updatedAt': utcDateTimeToJson(instance.updatedAt),
};

const _$SyncJobLaneEnumMap = {
  SyncJobLane.metadata: 'metadata',
  SyncJobLane.transfer: 'transfer',
};

const _$SyncJobTypeEnumMap = {
  SyncJobType.pushMetadata: 'pushMetadata',
  SyncJobType.pullDelta: 'pullDelta',
  SyncJobType.pullFull: 'pullFull',
  SyncJobType.uploadAttachment: 'uploadAttachment',
  SyncJobType.downloadAttachment: 'downloadAttachment',
};

const _$SyncJobStatusEnumMap = {
  SyncJobStatus.pending: 'pending',
  SyncJobStatus.running: 'running',
  SyncJobStatus.failed: 'failed',
  SyncJobStatus.completed: 'completed',
};

BackgroundJobProgressEvent _$BackgroundJobProgressEventFromJson(
  Map<String, dynamic> json,
) => BackgroundJobProgressEvent(
  accountKey: json['accountKey'] as String,
  jobId: json['jobId'] as String,
  lane: $enumDecode(_$SyncJobLaneEnumMap, json['lane']),
  status: $enumDecode(_$SyncJobStatusEnumMap, json['status']),
  progress: (json['progress'] as num?)?.toInt() ?? 0,
  taskId: json['taskId'] as String?,
  attachmentId: json['attachmentId'] as String?,
  localPath: json['localPath'] as String?,
  errorMessage: json['errorMessage'] as String?,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$BackgroundJobProgressEventToJson(
  BackgroundJobProgressEvent instance,
) => <String, dynamic>{
  'accountKey': instance.accountKey,
  'jobId': instance.jobId,
  'lane': _$SyncJobLaneEnumMap[instance.lane]!,
  'status': _$SyncJobStatusEnumMap[instance.status]!,
  'progress': instance.progress,
  'taskId': instance.taskId,
  'attachmentId': instance.attachmentId,
  'localPath': instance.localPath,
  'errorMessage': instance.errorMessage,
  'kind': instance.$type,
};

BackgroundDbChangedEvent _$BackgroundDbChangedEventFromJson(
  Map<String, dynamic> json,
) => BackgroundDbChangedEvent(
  accountKey: json['accountKey'] as String,
  lane: $enumDecodeNullable(_$SyncJobLaneEnumMap, json['lane']),
  reason: json['reason'] as String?,
  $type: json['kind'] as String?,
);

Map<String, dynamic> _$BackgroundDbChangedEventToJson(
  BackgroundDbChangedEvent instance,
) => <String, dynamic>{
  'accountKey': instance.accountKey,
  'lane': _$SyncJobLaneEnumMap[instance.lane],
  'reason': instance.reason,
  'kind': instance.$type,
};
