import 'dart:math';

import 'package:flutter/foundation.dart';

/// Execution lane for background sync work so slow binary transfers never
/// block fast metadata mutations.
enum SyncJobLane { metadata, transfer }

/// Supported durable background job kinds persisted in `SyncJobRecords`.
enum SyncJobType {
  pushMetadata,
  pullDelta,
  pullFull,
  uploadAttachment,
  downloadAttachment,
  widgetSync,
}

/// Lifecycle state of a persisted background job.
enum SyncJobStatus { pending, running, failed, completed }

/// A durable background job persisted in SQLite (`SyncJobRecords`).
@immutable
class SyncJob {
  const SyncJob({
    required this.jobId,
    required this.accountKey,
    required this.lane,
    required this.jobType,
    this.status = SyncJobStatus.pending,
    this.payload = const <String, dynamic>{},
    this.progress = 0,
    this.attemptCount = 0,
    this.nextRetryAt,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final String jobId;
  final String accountKey;
  final SyncJobLane lane;
  final SyncJobType jobType;
  final SyncJobStatus status;
  final Map<String, dynamic> payload;
  final int progress;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

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

  SyncJob copyWith({
    SyncJobStatus? status,
    Map<String, dynamic>? payload,
    int? progress,
    int? attemptCount,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? updatedAt,
  }) {
    return SyncJob(
      jobId: jobId,
      accountKey: accountKey,
      lane: lane,
      jobType: jobType,
      status: status ?? this.status,
      payload: payload ?? this.payload,
      progress: progress ?? this.progress,
      attemptCount: attemptCount ?? this.attemptCount,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'jobId': jobId,
    'accountKey': accountKey,
    'lane': lane.name,
    'jobType': jobType.name,
    'status': status.name,
    'payload': payload,
    'progress': progress,
    'attemptCount': attemptCount,
    if (nextRetryAt != null)
      'nextRetryAtMs': nextRetryAt!.toUtc().millisecondsSinceEpoch,
    if (errorMessage != null) 'errorMessage': errorMessage,
    'createdAtMs': createdAt.toUtc().millisecondsSinceEpoch,
    'updatedAtMs': updatedAt.toUtc().millisecondsSinceEpoch,
  };

  factory SyncJob.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final nextRetryMs = (json['nextRetryAtMs'] as num?)?.toInt();
    return SyncJob(
      jobId: json['jobId'] as String,
      accountKey: json['accountKey'] as String,
      lane: SyncJobLane.values.byName(json['lane'] as String),
      jobType: SyncJobType.values.byName(json['jobType'] as String),
      status: SyncJobStatus.values.byName(json['status'] as String),
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      attemptCount: (json['attemptCount'] as num?)?.toInt() ?? 0,
      nextRetryAt: nextRetryMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextRetryMs, isUtc: true),
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAtMs'] as num).toInt(),
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAtMs'] as num).toInt(),
        isUtc: true,
      ),
    );
  }
}

/// Lightweight event emitted by the background worker over `IsolateNameServer`
/// or an in-process stream so an attached UI can reflect progress without
/// owning the transfer lifecycle.
@immutable
class BackgroundWorkerEvent {
  const BackgroundWorkerEvent({
    required this.kind,
    required this.accountKey,
    this.jobId,
    this.lane,
    this.status,
    this.progress,
    this.taskId,
    this.attachmentId,
    this.localPath,
    this.errorMessage,
    this.reason,
  });

  static const String kindProgress = 'progress';
  static const String kindDbChanged = 'db_changed';
  static const String kindSyncStatus = 'sync_status';

  final String kind;
  final String accountKey;
  final String? jobId;
  final SyncJobLane? lane;
  final SyncJobStatus? status;
  final int? progress;
  final String? taskId;
  final String? attachmentId;
  final String? localPath;
  final String? errorMessage;
  final String? reason;

  Map<String, Object?> toWireMap() => <String, Object?>{
    'kind': kind,
    'accountKey': accountKey,
    if (jobId != null) 'jobId': jobId,
    if (lane != null) 'lane': lane!.name,
    if (status != null) 'status': status!.name,
    if (progress != null) 'progress': progress,
    if (taskId != null) 'taskId': taskId,
    if (attachmentId != null) 'attachmentId': attachmentId,
    if (localPath != null) 'localPath': localPath,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (reason != null) 'reason': reason,
  };

  static BackgroundWorkerEvent? fromWireMap(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'] as String?;
    final accountKey = raw['accountKey'] as String?;
    if (kind == null || accountKey == null) return null;
    final laneName = raw['lane'] as String?;
    final statusName = raw['status'] as String?;
    return BackgroundWorkerEvent(
      kind: kind,
      accountKey: accountKey,
      jobId: raw['jobId'] as String?,
      lane: laneName == null ? null : SyncJobLane.values.byName(laneName),
      status: statusName == null
          ? null
          : SyncJobStatus.values.byName(statusName),
      progress: (raw['progress'] as num?)?.toInt(),
      taskId: raw['taskId'] as String?,
      attachmentId: raw['attachmentId'] as String?,
      localPath: raw['localPath'] as String?,
      errorMessage: raw['errorMessage'] as String?,
      reason: raw['reason'] as String?,
    );
  }
}
