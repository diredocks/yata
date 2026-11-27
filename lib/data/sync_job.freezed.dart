// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sync_job.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SyncJob {

 String get jobId; String get accountKey; SyncJobLane get lane; SyncJobType get jobType; SyncJobStatus get status; Map<String, dynamic> get payload; int get progress; int get attemptCount;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get nextRetryAt; String? get errorMessage;@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime get createdAt;@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime get updatedAt;
/// Create a copy of SyncJob
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncJobCopyWith<SyncJob> get copyWith => _$SyncJobCopyWithImpl<SyncJob>(this as SyncJob, _$identity);

  /// Serializes this SyncJob to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as SyncJob;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncJob&&(identical(other.jobId, _this.jobId) || other.jobId == _this.jobId)&&(identical(other.accountKey, _this.accountKey) || other.accountKey == _this.accountKey)&&(identical(other.lane, _this.lane) || other.lane == _this.lane)&&(identical(other.jobType, _this.jobType) || other.jobType == _this.jobType)&&(identical(other.status, _this.status) || other.status == _this.status)&&const DeepCollectionEquality().equals(other.payload, _this.payload)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.attemptCount, _this.attemptCount) || other.attemptCount == _this.attemptCount)&&(identical(other.nextRetryAt, _this.nextRetryAt) || other.nextRetryAt == _this.nextRetryAt)&&(identical(other.errorMessage, _this.errorMessage) || other.errorMessage == _this.errorMessage)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as SyncJob;
  return Object.hash(runtimeType,_this.jobId,_this.accountKey,_this.lane,_this.jobType,_this.status,const DeepCollectionEquality().hash(_this.payload),_this.progress,_this.attemptCount,_this.nextRetryAt,_this.errorMessage,_this.createdAt,_this.updatedAt);
}

@override
String toString() {
  final _this = this as SyncJob;
  return 'SyncJob(jobId: ${_this.jobId}, accountKey: ${_this.accountKey}, lane: ${_this.lane}, jobType: ${_this.jobType}, status: ${_this.status}, payload: ${_this.payload}, progress: ${_this.progress}, attemptCount: ${_this.attemptCount}, nextRetryAt: ${_this.nextRetryAt}, errorMessage: ${_this.errorMessage}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $SyncJobCopyWith<$Res>  {
  factory $SyncJobCopyWith(SyncJob value, $Res Function(SyncJob) _then) = _$SyncJobCopyWithImpl;
@useResult
$Res call({
 String jobId, String accountKey, SyncJobLane lane, SyncJobType jobType, SyncJobStatus status, Map<String, dynamic> payload, int progress, int attemptCount,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? nextRetryAt, String? errorMessage,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime createdAt,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime updatedAt
});




}
/// @nodoc
class _$SyncJobCopyWithImpl<$Res>
    implements $SyncJobCopyWith<$Res> {
  _$SyncJobCopyWithImpl(this._self, this._then);

  final SyncJob _self;
  final $Res Function(SyncJob) _then;

/// Create a copy of SyncJob
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? jobId = null,Object? accountKey = null,Object? lane = null,Object? jobType = null,Object? status = null,Object? payload = null,Object? progress = null,Object? attemptCount = null,Object? nextRetryAt = freezed,Object? errorMessage = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(SyncJob(
jobId: null == jobId ? _self.jobId : jobId // ignore: cast_nullable_to_non_nullable
as String,accountKey: null == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as String,lane: null == lane ? _self.lane : lane // ignore: cast_nullable_to_non_nullable
as SyncJobLane,jobType: null == jobType ? _self.jobType : jobType // ignore: cast_nullable_to_non_nullable
as SyncJobType,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SyncJobStatus,payload: null == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,attemptCount: null == attemptCount ? _self.attemptCount : attemptCount // ignore: cast_nullable_to_non_nullable
as int,nextRetryAt: freezed == nextRetryAt ? _self.nextRetryAt : nextRetryAt // ignore: cast_nullable_to_non_nullable
as DateTime?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}



/// @nodoc
@JsonSerializable()

class _SyncJob extends SyncJob {
  const _SyncJob({required this.jobId, required this.accountKey, required this.lane, required this.jobType, this.status = SyncJobStatus.pending,  Map<String, dynamic> payload = const <String, dynamic>{}, this.progress = 0, this.attemptCount = 0, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.nextRetryAt, this.errorMessage, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) required this.createdAt, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) required this.updatedAt}): _payload = payload,super._();
  factory _SyncJob.fromJson(Map<String, dynamic> json) => _$SyncJobFromJson(json);

@override final  String jobId;
@override final  String accountKey;
@override final  SyncJobLane lane;
@override final  SyncJobType jobType;
@override@JsonKey() final  SyncJobStatus status;
 final  Map<String, dynamic> _payload;
@override@JsonKey() Map<String, dynamic> get payload {
  if (_payload is EqualUnmodifiableMapView) return _payload;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_payload);
}

@override@JsonKey() final  int progress;
@override@JsonKey() final  int attemptCount;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? nextRetryAt;
@override final  String? errorMessage;
@override@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) final  DateTime createdAt;
@override@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) final  DateTime updatedAt;

/// Create a copy of SyncJob
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncJobCopyWith<_SyncJob> get copyWith => __$SyncJobCopyWithImpl<_SyncJob>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SyncJobToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncJob&&(identical(other.jobId, jobId) || other.jobId == jobId)&&(identical(other.accountKey, accountKey) || other.accountKey == accountKey)&&(identical(other.lane, lane) || other.lane == lane)&&(identical(other.jobType, jobType) || other.jobType == jobType)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.payload, _payload)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.attemptCount, attemptCount) || other.attemptCount == attemptCount)&&(identical(other.nextRetryAt, nextRetryAt) || other.nextRetryAt == nextRetryAt)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,jobId,accountKey,lane,jobType,status,const DeepCollectionEquality().hash(_payload),progress,attemptCount,nextRetryAt,errorMessage,createdAt,updatedAt);
}

@override
String toString() {
    return 'SyncJob(jobId: $jobId, accountKey: $accountKey, lane: $lane, jobType: $jobType, status: $status, payload: $payload, progress: $progress, attemptCount: $attemptCount, nextRetryAt: $nextRetryAt, errorMessage: $errorMessage, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SyncJobCopyWith<$Res> implements $SyncJobCopyWith<$Res> {
  factory _$SyncJobCopyWith(_SyncJob value, $Res Function(_SyncJob) _then) = __$SyncJobCopyWithImpl;
@override @useResult
$Res call({
 String jobId, String accountKey, SyncJobLane lane, SyncJobType jobType, SyncJobStatus status, Map<String, dynamic> payload, int progress, int attemptCount,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? nextRetryAt, String? errorMessage,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime createdAt,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime updatedAt
});




}
/// @nodoc
class __$SyncJobCopyWithImpl<$Res>
    implements _$SyncJobCopyWith<$Res> {
  __$SyncJobCopyWithImpl(this._self, this._then);

  final _SyncJob _self;
  final $Res Function(_SyncJob) _then;

/// Create a copy of SyncJob
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? jobId = null,Object? accountKey = null,Object? lane = null,Object? jobType = null,Object? status = null,Object? payload = null,Object? progress = null,Object? attemptCount = null,Object? nextRetryAt = freezed,Object? errorMessage = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_SyncJob(
jobId: null == jobId ? _self.jobId : jobId // ignore: cast_nullable_to_non_nullable
as String,accountKey: null == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as String,lane: null == lane ? _self.lane : lane // ignore: cast_nullable_to_non_nullable
as SyncJobLane,jobType: null == jobType ? _self.jobType : jobType // ignore: cast_nullable_to_non_nullable
as SyncJobType,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SyncJobStatus,payload: null == payload ? _self._payload : payload // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,attemptCount: null == attemptCount ? _self.attemptCount : attemptCount // ignore: cast_nullable_to_non_nullable
as int,nextRetryAt: freezed == nextRetryAt ? _self.nextRetryAt : nextRetryAt // ignore: cast_nullable_to_non_nullable
as DateTime?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$SyncWorkerDrainResult {

 int get processedCount; int get failedCount; bool get hasRetryableFailures; bool get hasPendingTransfers;
/// Create a copy of SyncWorkerDrainResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncWorkerDrainResultCopyWith<SyncWorkerDrainResult> get copyWith => _$SyncWorkerDrainResultCopyWithImpl<SyncWorkerDrainResult>(this as SyncWorkerDrainResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SyncWorkerDrainResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncWorkerDrainResult&&(identical(other.processedCount, _this.processedCount) || other.processedCount == _this.processedCount)&&(identical(other.failedCount, _this.failedCount) || other.failedCount == _this.failedCount)&&(identical(other.hasRetryableFailures, _this.hasRetryableFailures) || other.hasRetryableFailures == _this.hasRetryableFailures)&&(identical(other.hasPendingTransfers, _this.hasPendingTransfers) || other.hasPendingTransfers == _this.hasPendingTransfers));
}


@override
int get hashCode {
  final _this = this as SyncWorkerDrainResult;
  return Object.hash(runtimeType,_this.processedCount,_this.failedCount,_this.hasRetryableFailures,_this.hasPendingTransfers);
}

@override
String toString() {
  final _this = this as SyncWorkerDrainResult;
  return 'SyncWorkerDrainResult(processedCount: ${_this.processedCount}, failedCount: ${_this.failedCount}, hasRetryableFailures: ${_this.hasRetryableFailures}, hasPendingTransfers: ${_this.hasPendingTransfers})';
}


}

/// @nodoc
abstract mixin class $SyncWorkerDrainResultCopyWith<$Res>  {
  factory $SyncWorkerDrainResultCopyWith(SyncWorkerDrainResult value, $Res Function(SyncWorkerDrainResult) _then) = _$SyncWorkerDrainResultCopyWithImpl;
@useResult
$Res call({
 int processedCount, int failedCount, bool hasRetryableFailures, bool hasPendingTransfers
});




}
/// @nodoc
class _$SyncWorkerDrainResultCopyWithImpl<$Res>
    implements $SyncWorkerDrainResultCopyWith<$Res> {
  _$SyncWorkerDrainResultCopyWithImpl(this._self, this._then);

  final SyncWorkerDrainResult _self;
  final $Res Function(SyncWorkerDrainResult) _then;

/// Create a copy of SyncWorkerDrainResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? processedCount = null,Object? failedCount = null,Object? hasRetryableFailures = null,Object? hasPendingTransfers = null,}) {
  return _then(SyncWorkerDrainResult(
processedCount: null == processedCount ? _self.processedCount : processedCount // ignore: cast_nullable_to_non_nullable
as int,failedCount: null == failedCount ? _self.failedCount : failedCount // ignore: cast_nullable_to_non_nullable
as int,hasRetryableFailures: null == hasRetryableFailures ? _self.hasRetryableFailures : hasRetryableFailures // ignore: cast_nullable_to_non_nullable
as bool,hasPendingTransfers: null == hasPendingTransfers ? _self.hasPendingTransfers : hasPendingTransfers // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}



/// @nodoc


class _SyncWorkerDrainResult implements SyncWorkerDrainResult {
  const _SyncWorkerDrainResult({this.processedCount = 0, this.failedCount = 0, this.hasRetryableFailures = false, this.hasPendingTransfers = false});
  

@override@JsonKey() final  int processedCount;
@override@JsonKey() final  int failedCount;
@override@JsonKey() final  bool hasRetryableFailures;
@override@JsonKey() final  bool hasPendingTransfers;

/// Create a copy of SyncWorkerDrainResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncWorkerDrainResultCopyWith<_SyncWorkerDrainResult> get copyWith => __$SyncWorkerDrainResultCopyWithImpl<_SyncWorkerDrainResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncWorkerDrainResult&&(identical(other.processedCount, processedCount) || other.processedCount == processedCount)&&(identical(other.failedCount, failedCount) || other.failedCount == failedCount)&&(identical(other.hasRetryableFailures, hasRetryableFailures) || other.hasRetryableFailures == hasRetryableFailures)&&(identical(other.hasPendingTransfers, hasPendingTransfers) || other.hasPendingTransfers == hasPendingTransfers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,processedCount,failedCount,hasRetryableFailures,hasPendingTransfers);
}

@override
String toString() {
    return 'SyncWorkerDrainResult(processedCount: $processedCount, failedCount: $failedCount, hasRetryableFailures: $hasRetryableFailures, hasPendingTransfers: $hasPendingTransfers)';
}


}

/// @nodoc
abstract mixin class _$SyncWorkerDrainResultCopyWith<$Res> implements $SyncWorkerDrainResultCopyWith<$Res> {
  factory _$SyncWorkerDrainResultCopyWith(_SyncWorkerDrainResult value, $Res Function(_SyncWorkerDrainResult) _then) = __$SyncWorkerDrainResultCopyWithImpl;
@override @useResult
$Res call({
 int processedCount, int failedCount, bool hasRetryableFailures, bool hasPendingTransfers
});




}
/// @nodoc
class __$SyncWorkerDrainResultCopyWithImpl<$Res>
    implements _$SyncWorkerDrainResultCopyWith<$Res> {
  __$SyncWorkerDrainResultCopyWithImpl(this._self, this._then);

  final _SyncWorkerDrainResult _self;
  final $Res Function(_SyncWorkerDrainResult) _then;

/// Create a copy of SyncWorkerDrainResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? processedCount = null,Object? failedCount = null,Object? hasRetryableFailures = null,Object? hasPendingTransfers = null,}) {
  return _then(_SyncWorkerDrainResult(
processedCount: null == processedCount ? _self.processedCount : processedCount // ignore: cast_nullable_to_non_nullable
as int,failedCount: null == failedCount ? _self.failedCount : failedCount // ignore: cast_nullable_to_non_nullable
as int,hasRetryableFailures: null == hasRetryableFailures ? _self.hasRetryableFailures : hasRetryableFailures // ignore: cast_nullable_to_non_nullable
as bool,hasPendingTransfers: null == hasPendingTransfers ? _self.hasPendingTransfers : hasPendingTransfers // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

BackgroundWorkerEvent _$BackgroundWorkerEventFromJson(
  Map<String, dynamic> json
) {
        switch (json['kind']) {
                  case 'progress':
          return BackgroundJobProgressEvent.fromJson(
            json
          );
                case 'db_changed':
          return BackgroundDbChangedEvent.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'kind',
  'BackgroundWorkerEvent',
  'Invalid union type "${json['kind']}"!'
);
        }
      
}

/// @nodoc
mixin _$BackgroundWorkerEvent {

 String get accountKey; SyncJobLane? get lane;
/// Create a copy of BackgroundWorkerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundWorkerEventCopyWith<BackgroundWorkerEvent> get copyWith => _$BackgroundWorkerEventCopyWithImpl<BackgroundWorkerEvent>(this as BackgroundWorkerEvent, _$identity);

  /// Serializes this BackgroundWorkerEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as BackgroundWorkerEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundWorkerEvent&&(identical(other.accountKey, _this.accountKey) || other.accountKey == _this.accountKey)&&(identical(other.lane, _this.lane) || other.lane == _this.lane));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as BackgroundWorkerEvent;
  return Object.hash(runtimeType,_this.accountKey,_this.lane);
}

@override
String toString() {
  final _this = this as BackgroundWorkerEvent;
  return 'BackgroundWorkerEvent(accountKey: ${_this.accountKey}, lane: ${_this.lane})';
}


}

/// @nodoc
abstract mixin class $BackgroundWorkerEventCopyWith<$Res>  {
  factory $BackgroundWorkerEventCopyWith(BackgroundWorkerEvent value, $Res Function(BackgroundWorkerEvent) _then) = _$BackgroundWorkerEventCopyWithImpl;
@useResult
$Res call({
 String accountKey, SyncJobLane lane
});




}
/// @nodoc
class _$BackgroundWorkerEventCopyWithImpl<$Res>
    implements $BackgroundWorkerEventCopyWith<$Res> {
  _$BackgroundWorkerEventCopyWithImpl(this._self, this._then);

  final BackgroundWorkerEvent _self;
  final $Res Function(BackgroundWorkerEvent) _then;

/// Create a copy of BackgroundWorkerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountKey = null,Object? lane = null,}) {
  return _then(_self.copyWith(
accountKey: null == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as String,lane: null == lane ? _self.lane! : lane // ignore: cast_nullable_to_non_nullable
as SyncJobLane,
  ));
}

}



/// @nodoc
@JsonSerializable()

class BackgroundJobProgressEvent extends BackgroundWorkerEvent {
  const BackgroundJobProgressEvent({required this.accountKey, required this.jobId, required this.lane, required this.status, this.progress = 0, this.taskId, this.attachmentId, this.localPath, this.errorMessage,  String? $type}): $type = $type ?? 'progress',super._();
  factory BackgroundJobProgressEvent.fromJson(Map<String, dynamic> json) => _$BackgroundJobProgressEventFromJson(json);

@override final  String accountKey;
 final  String jobId;
@override final  SyncJobLane lane;
 final  SyncJobStatus status;
@JsonKey() final  int progress;
 final  String? taskId;
 final  String? attachmentId;
 final  String? localPath;
 final  String? errorMessage;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of BackgroundWorkerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundJobProgressEventCopyWith<BackgroundJobProgressEvent> get copyWith => _$BackgroundJobProgressEventCopyWithImpl<BackgroundJobProgressEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BackgroundJobProgressEventToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundJobProgressEvent&&(identical(other.accountKey, accountKey) || other.accountKey == accountKey)&&(identical(other.jobId, jobId) || other.jobId == jobId)&&(identical(other.lane, lane) || other.lane == lane)&&(identical(other.status, status) || other.status == status)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.attachmentId, attachmentId) || other.attachmentId == attachmentId)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,accountKey,jobId,lane,status,progress,taskId,attachmentId,localPath,errorMessage);
}

@override
String toString() {
    return 'BackgroundWorkerEvent.progress(accountKey: $accountKey, jobId: $jobId, lane: $lane, status: $status, progress: $progress, taskId: $taskId, attachmentId: $attachmentId, localPath: $localPath, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $BackgroundJobProgressEventCopyWith<$Res> implements $BackgroundWorkerEventCopyWith<$Res> {
  factory $BackgroundJobProgressEventCopyWith(BackgroundJobProgressEvent value, $Res Function(BackgroundJobProgressEvent) _then) = _$BackgroundJobProgressEventCopyWithImpl;
@override @useResult
$Res call({
 String accountKey, String jobId, SyncJobLane lane, SyncJobStatus status, int progress, String? taskId, String? attachmentId, String? localPath, String? errorMessage
});




}
/// @nodoc
class _$BackgroundJobProgressEventCopyWithImpl<$Res>
    implements $BackgroundJobProgressEventCopyWith<$Res> {
  _$BackgroundJobProgressEventCopyWithImpl(this._self, this._then);

  final BackgroundJobProgressEvent _self;
  final $Res Function(BackgroundJobProgressEvent) _then;

/// Create a copy of BackgroundWorkerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountKey = null,Object? jobId = null,Object? lane = null,Object? status = null,Object? progress = null,Object? taskId = freezed,Object? attachmentId = freezed,Object? localPath = freezed,Object? errorMessage = freezed,}) {
  return _then(BackgroundJobProgressEvent(
accountKey: null == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as String,jobId: null == jobId ? _self.jobId : jobId // ignore: cast_nullable_to_non_nullable
as String,lane: null == lane ? _self.lane : lane // ignore: cast_nullable_to_non_nullable
as SyncJobLane,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SyncJobStatus,progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as int,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String?,attachmentId: freezed == attachmentId ? _self.attachmentId : attachmentId // ignore: cast_nullable_to_non_nullable
as String?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
@JsonSerializable()

class BackgroundDbChangedEvent extends BackgroundWorkerEvent {
  const BackgroundDbChangedEvent({required this.accountKey, this.lane, this.reason,  String? $type}): $type = $type ?? 'db_changed',super._();
  factory BackgroundDbChangedEvent.fromJson(Map<String, dynamic> json) => _$BackgroundDbChangedEventFromJson(json);

@override final  String accountKey;
@override final  SyncJobLane? lane;
 final  String? reason;

@JsonKey(name: 'kind')
final String $type;


/// Create a copy of BackgroundWorkerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackgroundDbChangedEventCopyWith<BackgroundDbChangedEvent> get copyWith => _$BackgroundDbChangedEventCopyWithImpl<BackgroundDbChangedEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$BackgroundDbChangedEventToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BackgroundDbChangedEvent&&(identical(other.accountKey, accountKey) || other.accountKey == accountKey)&&(identical(other.lane, lane) || other.lane == lane)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,accountKey,lane,reason);
}

@override
String toString() {
    return 'BackgroundWorkerEvent.dbChanged(accountKey: $accountKey, lane: $lane, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BackgroundDbChangedEventCopyWith<$Res> implements $BackgroundWorkerEventCopyWith<$Res> {
  factory $BackgroundDbChangedEventCopyWith(BackgroundDbChangedEvent value, $Res Function(BackgroundDbChangedEvent) _then) = _$BackgroundDbChangedEventCopyWithImpl;
@override @useResult
$Res call({
 String accountKey, SyncJobLane? lane, String? reason
});




}
/// @nodoc
class _$BackgroundDbChangedEventCopyWithImpl<$Res>
    implements $BackgroundDbChangedEventCopyWith<$Res> {
  _$BackgroundDbChangedEventCopyWithImpl(this._self, this._then);

  final BackgroundDbChangedEvent _self;
  final $Res Function(BackgroundDbChangedEvent) _then;

/// Create a copy of BackgroundWorkerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountKey = null,Object? lane = freezed,Object? reason = freezed,}) {
  return _then(BackgroundDbChangedEvent(
accountKey: null == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as String,lane: freezed == lane ? _self.lane : lane // ignore: cast_nullable_to_non_nullable
as SyncJobLane?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
