import 'dart:async';

import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/sync_job.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../data/todo_state.dart';
import '../detailview/attachments/attachment_service.dart';
import '../models/account.dart';
import '../models/default_lists.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'background_sync_bridge.dart';
import 'microsoft/cloud_sync_service.dart';
import 'microsoft/substrate_push_engine.dart';

final _log = appLogFor('SyncWorkerEngine');

/// Summary returned by a single [SyncWorkerEngine.drain] pass.
class SyncWorkerDrainResult {
  const SyncWorkerDrainResult({
    required this.processedCount,
    required this.failedCount,
    required this.hasRetryableFailures,
    required this.hasPendingTransfers,
  });

  final int processedCount;
  final int failedCount;
  final bool hasRetryableFailures;
  final bool hasPendingTransfers;
}

/// Callback that executes a widget sync job inside the worker context.
typedef WidgetSyncJobRunner = Future<AppResult<Unit>> Function(String reason);

/// Callback that downloads a remote attachment and returns its local file path.
typedef AttachmentDownloadRunner = AsyncAppResult<String> Function(
  TaskAttachment attachment,
);

/// Pure-Dart, UI-independent background job executor.
///
/// Owns serialized execution of persisted [SyncJob] records across the
/// `metadata` (fast) and `transfer` (slow binary) lanes, updating SQLite
/// directly and broadcasting lightweight progress / DB-change events via
/// [onEvent].
class SyncWorkerEngine {
  SyncWorkerEngine({
    required this.account,
    required this.repository,
    required this.settings,
    required this.cloudSync,
    required this.idGenerator,
    this.downloadAttachment,
    this.runWidgetSync,
    this.onPushCommitted,
    this.onPullApplied,
    void Function(BackgroundWorkerEvent event)? onEvent,
    DateTime Function()? nowUtc,
  }) : _onEvent = onEvent ?? BackgroundWorkerEventBus.emit,
       _nowUtc = nowUtc ?? _defaultNowUtc;

  final MicrosoftAccount account;
  final TodoRepository repository;
  final TodoSettingsStore settings;
  final CloudSyncService cloudSync;
  final String Function(String prefix) idGenerator;
  final AttachmentDownloadRunner? downloadAttachment;
  final WidgetSyncJobRunner? runWidgetSync;
  final Future<void> Function(OutboxPushOutcome outcome)? onPushCommitted;
  final Future<void> Function(SyncOutcome outcome, SyncKind kind)?
  onPullApplied;
  final void Function(BackgroundWorkerEvent event) _onEvent;
  final DateTime Function() _nowUtc;

  static DateTime _defaultNowUtc() => DateTime.now().toUtc();

  /// Enqueues a durable job in SQLite if an equivalent active job is not
  /// already pending/running, and returns the persisted [SyncJob].
  AsyncAppResult<SyncJob> enqueueJob({
    required String jobId,
    required SyncJobLane lane,
    required SyncJobType jobType,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final now = _nowUtc();
    final job = SyncJob(
      jobId: jobId,
      accountKey: repository.accountKey,
      lane: lane,
      jobType: jobType,
      status: SyncJobStatus.pending,
      payload: payload,
      createdAt: now,
      updatedAt: now,
    );
    final saved = await repository.upsertSyncJob(job);
    return saved.map((_) => job);
  }

  /// Drains runnable jobs for [lane] (or both lanes when [lane] is null).
  AsyncAppResult<SyncWorkerDrainResult> drain({SyncJobLane? lane}) async {
    final now = _nowUtc();
    final loaded = await repository.loadSyncJobs(
      lane: lane,
      onlyRunnable: true,
      nowUtc: now,
    );
    if (loaded.isError()) return Failure(loaded.exceptionOrNull()!);

    final jobs = loaded.getOrThrow();
    var processed = 0;
    var failed = 0;
    var hasRetryable = false;

    for (final job in jobs) {
      final outcome = await _executeSingleJob(job);
      if (outcome.isSuccess()) {
        processed++;
      } else {
        failed++;
        if (outcome.exceptionOrNull()!.isRetryable) {
          hasRetryable = true;
        }
      }
    }

    final remainingTransfers = await repository.loadSyncJobs(
      lane: SyncJobLane.transfer,
    );
    final hasPendingTransfers = remainingTransfers
        .getOrElse((_) => const [])
        .any((j) => !j.isTerminal);

    if (processed > 0) {
      await repository.clearCompletedSyncJobs();
      _onEvent(
        BackgroundWorkerEvent(
          kind: BackgroundWorkerEvent.kindDbChanged,
          accountKey: repository.accountKey,
          lane: lane,
          reason: 'drain_completed',
        ),
      );
    }

    return Success(
      SyncWorkerDrainResult(
        processedCount: processed,
        failedCount: failed,
        hasRetryableFailures: hasRetryable,
        hasPendingTransfers: hasPendingTransfers,
      ),
    );
  }

  AsyncAppResult<Unit> _executeSingleJob(SyncJob job) async {
    final running = job.copyWith(
      status: SyncJobStatus.running,
      progress: job.lane == SyncJobLane.transfer ? 10 : 0,
      clearErrorMessage: true,
      updatedAt: _nowUtc(),
    );
    await repository.upsertSyncJob(running);
    _emitJobProgress(running);

    final result = await _dispatchJob(running);
    if (result.isSuccess()) {
      final done = running.copyWith(
        status: SyncJobStatus.completed,
        progress: 100,
        clearNextRetryAt: true,
        clearErrorMessage: true,
        updatedAt: _nowUtc(),
      );
      await repository.upsertSyncJob(done);
      _emitJobProgress(done);
      return const Success(unit);
    }

    final error = result.exceptionOrNull()!;
    final nextAttempts = running.attemptCount + 1;
    final retryAt = error.isRetryable
        ? _nowUtc().add(SyncJob.computeBackoffDelay(nextAttempts))
        : null;
    final failedJob = running.copyWith(
      status: SyncJobStatus.failed,
      attemptCount: nextAttempts,
      nextRetryAt: retryAt,
      clearNextRetryAt: !error.isRetryable,
      errorMessage: error.userMessage,
      updatedAt: _nowUtc(),
    );
    await repository.upsertSyncJob(failedJob);
    _emitJobProgress(failedJob);
    _log.warning(
      'Job ${job.jobId} (${job.jobType.name}) failed '
      'attempt=$nextAttempts retryable=${error.isRetryable}: ${error.describe()}',
    );
    return Failure(error);
  }

  AsyncAppResult<Unit> _dispatchJob(SyncJob job) {
    final reason = job.payload['reason'] as String? ?? job.jobType.name;
    return switch (job.jobType) {
      SyncJobType.pushMetadata => _runPush(
        laneFilter: PushLaneFilter.metadataOnly,
        reason: reason,
      ),
      SyncJobType.uploadAttachment => _runPush(
        laneFilter: PushLaneFilter.attachmentsOnly,
        reason: reason,
      ),
      SyncJobType.pullDelta => _runPull(SyncKind.delta, reason: reason),
      SyncJobType.pullFull => _runPull(SyncKind.full, reason: reason),
      SyncJobType.downloadAttachment => _runDownloadAttachment(job),
      SyncJobType.widgetSync => _runWidgetSync(reason),
    };
  }

  AsyncAppResult<Unit> _runPush({
    required PushLaneFilter laneFilter,
    required String reason,
  }) async {
    final snapshot = _buildSnapshotState();
    final result = await cloudSync.pushAccount(
      account: account,
      currentState: snapshot,
      repository: repository,
      settings: settings,
      readLatestState: _buildSnapshotState,
      onPushCommitted: onPushCommitted ?? _commitPushHeadless,
      reason: reason,
      laneFilter: laneFilter,
    );
    return result.map((_) => unit);
  }

  AsyncAppResult<Unit> _runPull(SyncKind kind, {required String reason}) async {
    final snapshot = _buildSnapshotState();
    final result = await cloudSync.pullAccount(
      account: account,
      currentState: snapshot,
      repository: repository,
      settings: settings,
      idGenerator: idGenerator,
      readLatestState: _buildSnapshotState,
      kind: kind,
      reason: reason,
    );
    if (result.isError()) return Failure(result.exceptionOrNull()!);
    final outcome = result.getOrThrow();
    if (outcome.cancelled) return const Success(unit);

    if (onPullApplied != null) {
      await onPullApplied!(outcome, kind);
    } else {
      await _applyPullHeadless(outcome, kind);
    }
    return const Success(unit);
  }

  AsyncAppResult<Unit> _runDownloadAttachment(SyncJob job) async {
    final taskId = job.payload['taskId'] as String?;
    final attachmentId = job.payload['attachmentId'] as String?;
    if (taskId == null || attachmentId == null) {
      return const Failure(
        AppError.validation(message: 'Missing taskId or attachmentId in job'),
      );
    }
    final task = repository.readCachedTasks().firstWhereOrNull(
      (t) => t.id == taskId,
    );
    final attachment = task?.attachments.firstWhereOrNull(
      (a) => a.id == attachmentId,
    );
    if (task == null || attachment == null) {
      return const Success(unit);
    }

    final runner = downloadAttachment;
    if (runner == null) {
      return const Failure(
        AppError.unknown(message: 'Attachment download runner unavailable'),
      );
    }

    final downloadRes = await runner(attachment);
    if (downloadRes.isError()) {
      await _updateTaskAttachmentRow(
        task,
        attachment.copyWith(isTransferring: false),
      );
      return Failure(downloadRes.exceptionOrNull()!);
    }

    final localPath = downloadRes.getOrThrow();
    await _updateTaskAttachmentRow(
      task,
      attachment.copyWith(localPath: localPath, isTransferring: false),
    );
    _onEvent(
      BackgroundWorkerEvent(
        kind: BackgroundWorkerEvent.kindProgress,
        accountKey: repository.accountKey,
        jobId: job.jobId,
        lane: SyncJobLane.transfer,
        status: SyncJobStatus.completed,
        progress: 100,
        taskId: taskId,
        attachmentId: attachmentId,
        localPath: localPath,
      ),
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> _runWidgetSync(String reason) {
    final runner = runWidgetSync;
    if (runner == null) return Future.value(const Success(unit));
    return runner(reason);
  }

  Future<void> _updateTaskAttachmentRow(
    TaskItem task,
    TaskAttachment updatedAttachment,
  ) async {
    final updatedTask = task.copyWith(
      attachments: [
        for (final item in task.attachments)
          if (item.id == updatedAttachment.id) updatedAttachment else item,
      ],
    );
    await repository.upsertTask(updatedTask);
    await repository.flushPendingWrites();
  }

  Future<void> _commitPushHeadless(OutboxPushOutcome outcome) async {
    final outbox = repository.outbox;
    for (final seq in outcome.ackedSeqs) {
      outbox.ackOp(seq);
    }
    for (final entry in outcome.clearedRemoteIdKeys) {
      outbox.clearRemoteId(entry.type, entry.localId);
    }
    for (final pushedTask in outcome.pushedTasks.values) {
      await repository.upsertTask(pushedTask);
    }
    if (outcome.pushedGroups.isNotEmpty) {
      final groups = [
        for (final g in repository.readCachedGroups())
          outcome.pushedGroups[g.id] ?? g,
      ];
      await repository.saveGroups(groups);
    }
    if (outcome.pushedLists.isNotEmpty) {
      final lists = [
        for (final l in repository.readCachedLists() ?? const <TodoList>[])
          outcome.pushedLists[l.id] ?? l,
      ];
      await repository.saveLists(lists);
    }
    await repository.saveOutbox();
    await repository.flushPendingWrites();
  }

  Future<void> _applyPullHeadless(SyncOutcome outcome, SyncKind kind) async {
    if (kind != SyncKind.pushOnly) {
      await repository.saveGroups(outcome.groups);
      await repository.saveLists(outcome.lists);
    }
    await repository.saveTasks(outcome.tasks);
    await repository.flushPendingWrites();
  }

  TodoState _buildSnapshotState() {
    final loaded = settings.load();
    return TodoState(
      lists: normalizeSmartLists(repository.readCachedLists()),
      groups: [...repository.readCachedGroups()],
      tasks: [...repository.readCachedTasks()],
      selectedListId: loaded.selectedListId,
      startOfWeek: loaded.startOfWeek,
      showDueTodayInMyDay: loaded.showDueTodayInMyDay,
      addNewTasksOnTop: loaded.addNewTasksOnTop,
      moveStarredTasksToTop: loaded.moveStarredTasksToTop,
      confirmBeforeDeleting: loaded.confirmBeforeDeleting,
      completedExpandedByList: loaded.completedExpandedByList,
    );
  }

  void _emitJobProgress(SyncJob job) {
    _onEvent(
      BackgroundWorkerEvent(
        kind: BackgroundWorkerEvent.kindProgress,
        accountKey: repository.accountKey,
        jobId: job.jobId,
        lane: job.lane,
        status: job.status,
        progress: job.progress,
        taskId: job.payload['taskId'] as String?,
        attachmentId: job.payload['attachmentId'] as String?,
        errorMessage: job.errorMessage,
      ),
    );
  }

  /// Helper that builds an attachment download runner backed by [CloudSyncService]
  /// and [AttachmentService] for headless background execution.
  static AttachmentDownloadRunner defaultAttachmentDownloader({
    required MicrosoftAccount account,
    required TodoSettingsStore settings,
    required CloudSyncService cloudSync,
    required AttachmentService attachmentService,
  }) {
    return (attachment) async {
      final webLink = attachment.webLink;
      if (webLink == null || webLink.trim().isEmpty) {
        return const Failure(
          AppError.unknown(message: 'Attachment has no download URL'),
        );
      }
      final ctxRes = await cloudSync.resolveContext(account, settings);
      if (ctxRes.isError()) return Failure(ctxRes.exceptionOrNull()!);
      final bytesRes = await cloudSync.todoApi.downloadAttachment(
        ctxRes.getOrThrow(),
        webLink,
      );
      if (bytesRes.isError()) return Failure(bytesRes.exceptionOrNull()!);
      return guardAsync(
        () => attachmentService.saveAttachmentBytes(
          attachmentId: attachment.id,
          fileName: attachment.displayName,
          bytes: bytesRes.getOrThrow(),
        ),
        operation: 'saveDownloadedAttachment',
      );
    };
  }
}
