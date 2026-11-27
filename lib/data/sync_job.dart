import 'dart:math';

import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/utc_date_time_json.dart';

part 'sync_job.freezed.dart';
part 'sync_job.g.dart';

/// Execution lane for background sync work so slow binary transfers never
/// block fast metadata mutations.
enum SyncJobLane { metadata, transfer }

/// Supported durable background job kinds persisted in SQLite.
enum SyncJobType {
  pushMetadata,
  pullDelta,
  pullFull,
  uploadAttachment,
  downloadAttachment,
}

/// Lifecycle state of a persisted background job.
enum SyncJobStatus { pending, running, failed, completed }

/// A durable background job persisted in SQLite.
@Freezed(when: FreezedWhenOptions.none, map: FreezedMapOptions.none)
abstract class SyncJob with _$SyncJob {
  const SyncJob._();

  const factory SyncJob({
    required String jobId,
    required String accountKey,
    required SyncJobLane lane,
    required SyncJobType jobType,
    @Default(SyncJobStatus.pending) SyncJobStatus status,
    @Default(<String, dynamic>{}) Map<String, dynamic> payload,
    @Default(0) int progress,
    @Default(0) int attemptCount,
    @JsonKey(
      fromJson: nullableUtcDateTimeFromJson,
      toJson: nullableUtcDateTimeToJson,
    )
    DateTime? nextRetryAt,
    String? errorMessage,
    @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson)
    required DateTime createdAt,
    @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson)
    required DateTime updatedAt,
  }) = _SyncJob;

  factory SyncJob.fromJson(Map<String, dynamic> json) =>
      _$SyncJobFromJson(json);

  bool get isTerminal => status == SyncJobStatus.completed;

  bool isReadyAt(DateTime nowUtc) {
    if (status != SyncJobStatus.pending && status != SyncJobStatus.failed) {
      return false;
    }
    final retryAt = nextRetryAt;
    if (retryAt == null) return true;
    return !retryAt.isAfter(nowUtc);
  }

  /// Bounded exponential backoff: 2s, 4s, 8s, 16s, 32s, capped at 5 minutes.
  static Duration computeBackoffDelay(int attemptCount) {
    final clamped = max(1, min(attemptCount, 8));
    final seconds = min(300, 1 << clamped);
    return Duration(seconds: seconds);
  }
}

/// Summary returned by a single `SyncWorkerEngine.drain` pass.
@Freezed(when: FreezedWhenOptions.none, map: FreezedMapOptions.none)
abstract class SyncWorkerDrainResult with _$SyncWorkerDrainResult {
  const factory SyncWorkerDrainResult({
    @Default(0) int processedCount,
    @Default(0) int failedCount,
    @Default(false) bool hasRetryableFailures,
    @Default(false) bool hasPendingTransfers,
  }) = _SyncWorkerDrainResult;
}

/// Lightweight event emitted by the background worker over `IsolateNameServer`
/// or an in-process stream so an attached UI can reflect progress without
/// owning the transfer lifecycle.
@Freezed(
  unionKey: 'kind',
  when: FreezedWhenOptions.none,
  map: FreezedMapOptions.none,
)
sealed class BackgroundWorkerEvent with _$BackgroundWorkerEvent {
  const BackgroundWorkerEvent._();

  @FreezedUnionValue('progress')
  const factory BackgroundWorkerEvent.progress({
    required String accountKey,
    required String jobId,
    required SyncJobLane lane,
    required SyncJobStatus status,
    @Default(0) int progress,
    String? taskId,
    String? attachmentId,
    String? localPath,
    String? errorMessage,
  }) = BackgroundJobProgressEvent;

  @FreezedUnionValue('db_changed')
  const factory BackgroundWorkerEvent.dbChanged({
    required String accountKey,
    SyncJobLane? lane,
    String? reason,
  }) = BackgroundDbChangedEvent;

  factory BackgroundWorkerEvent.fromJson(Map<String, dynamic> json) =>
      _$BackgroundWorkerEventFromJson(json);

  Map<String, Object?> toWireMap() => toJson();

  static BackgroundWorkerEvent? fromWireMap(Object? raw) {
    if (raw is! Map) return null;
    try {
      return BackgroundWorkerEvent.fromJson(Map<String, dynamic>.from(raw));
    } on Object {
      return null;
    }
  }
}
