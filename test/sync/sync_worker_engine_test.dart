import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/sync_job.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/background_sync_bridge.dart';
import 'package:yata/sync/microsoft/cloud_sync_service.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/sync_worker_engine.dart';

import '../helpers/microsoft_sync_fakes.dart';

class _RecordingBackgroundScheduler implements BackgroundSyncScheduler {
  _RecordingBackgroundScheduler({this.handlesTransfersInBackground = false});

  @override
  final bool handlesTransfersInBackground;

  final List<
    ({SyncJobLane lane, String reason, bool requiresNetwork, bool expedited})
  >
  enqueued = [];

  @override
  Future<void> registerBackgroundEntrypoint(Function entrypoint) async {}

  @override
  Future<void> enqueueSync({
    required SyncJobLane lane,
    required String reason,
    bool requiresNetwork = true,
    bool expedited = false,
  }) async {
    enqueued.add((
      lane: lane,
      reason: reason,
      requiresNetwork: requiresNetwork,
      expedited: expedited,
    ));
  }

  @override
  Future<void> notifyBackgroundRunCompleted({
    required String lane,
    required bool shouldRetry,
    required bool hasPendingTransfers,
  }) async {}
}

void main() {
  group('Row-level Drift persistence & SyncJobRecords', () {
    test('upsertTask and deleteTask modify individual rows and emit watchTasks updates', () async {
      SharedPreferences.setMockInitialValues({});
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TodoRepository(db, accountKey: 'acct_row');

      final t1 = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'First',
        createdAt: DateTime.utc(2026, 11, 20),
      );
      final t2 = TaskItem(
        id: 't2',
        listId: 'tasks',
        title: 'Second',
        createdAt: DateTime.utc(2026, 11, 21),
      );

      await repo.saveTasks([t1, t2]);
      await repo.flushPendingWrites();

      await repo.upsertTask(t1.copyWith(title: 'First Updated'));
      await repo.flushPendingWrites();

      final afterUpsert = await repo.watchTasks().first;
      expect(afterUpsert.map((t) => '${t.id}:${t.title}').toList(), [
        't1:First Updated',
        't2:Second',
      ]);

      await repo.deleteTask('t1');
      await repo.flushPendingWrites();

      final afterDelete = await repo.watchTasks().first;
      expect(afterDelete.map((t) => t.id).toList(), ['t2']);
    });

    test('SyncJobRecords persists lanes, backoff readiness, and clears completed rows', () async {
      SharedPreferences.setMockInitialValues({});
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TodoRepository(db, accountKey: 'acct_jobs');
      final now = DateTime.utc(2026, 11, 27, 8);

      final metaJob = SyncJob(
        jobId: 'job_meta',
        accountKey: 'acct_jobs',
        lane: SyncJobLane.metadata,
        jobType: SyncJobType.pushMetadata,
        createdAt: now,
        updatedAt: now,
      );
      final delayedTransfer = SyncJob(
        jobId: 'job_transfer',
        accountKey: 'acct_jobs',
        lane: SyncJobLane.transfer,
        jobType: SyncJobType.uploadAttachment,
        status: SyncJobStatus.failed,
        attemptCount: 2,
        nextRetryAt: now.add(const Duration(seconds: 30)),
        createdAt: now,
        updatedAt: now,
      );
      final completedJob = SyncJob(
        jobId: 'job_done',
        accountKey: 'acct_jobs',
        lane: SyncJobLane.metadata,
        jobType: SyncJobType.pullDelta,
        status: SyncJobStatus.completed,
        progress: 100,
        createdAt: now,
        updatedAt: now,
      );

      await repo.upsertSyncJob(metaJob);
      await repo.upsertSyncJob(delayedTransfer);
      await repo.upsertSyncJob(completedJob);
      await repo.flushPendingWrites();

      final runnableNow = (await repo.loadSyncJobs(
        onlyRunnable: true,
        nowUtc: now,
      )).getOrThrow();
      expect(runnableNow.map((j) => j.jobId).toList(), ['job_meta']);

      final runnableLater = (await repo.loadSyncJobs(
        onlyRunnable: true,
        nowUtc: now.add(const Duration(seconds: 31)),
      )).getOrThrow();
      expect(runnableLater.map((j) => j.jobId).toList(), [
        'job_meta',
        'job_transfer',
      ]);

      await repo.clearCompletedSyncJobs();
      await repo.flushPendingWrites();
      final remaining = (await repo.loadSyncJobs()).getOrThrow();
      expect(remaining.map((j) => j.jobId).toList(), [
        'job_meta',
        'job_transfer',
      ]);
    });
  });

  group('SyncWorkerEngine fast/slow lanes & headless execution', () {
    test('isolates metadata lane from attachment upload lane and drains transfers independently', () async {
      final tmpDir = await Directory.systemTemp.createTemp('yata_worker_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final stagedFile = File(p.join(tmpDir.path, 'spec.pdf'));
      await stagedFile.writeAsBytes([1, 2, 3, 4, 5]);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final account = MicrosoftAccount(
        id: 'acct_lane',
        displayName: 'Lane Tester',
        email: 'lane@example.com',
        microsoftUserId: 'cid_lane',
        createdAt: DateTime.utc(2026, 11, 20),
      );
      final settings = TodoSettingsStore(prefs, accountId: account.id);
      final repo = TodoRepository.forSession(db, settings);

      final api = FakeSubstrateApi();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        account.id,
        MicrosoftAuthTokens(
          accessToken: 'tok',
          refreshToken: 'ref',
          expiresAt: DateTime.utc(2099, 1, 1),
          userId: 'cid_lane',
        ),
      );
      final auth = FakeAuthClient();
      final cloudSync = CloudSyncService(
        authClient: auth,
        todoApi: api,
        tokenStorage: tokenStorage,
      );

      final tasksList = TodoList(
        id: 'tasks',
        title: 'Tasks',
        remoteId: 'rf-default',
        smartType: SmartListType.tasks,
      );
      final attachment = TaskAttachment(
        id: 'att_1',
        displayName: 'spec.pdf',
        localPath: stagedFile.path,
        size: 5,
        contentType: 'application/pdf',
        isTransferring: true,
      );
      final task = TaskItem(
        id: 't_1',
        listId: 'tasks',
        title: 'Upload Spec',
        createdAt: DateTime.utc(2026, 11, 27),
        attachments: [attachment],
      );

      await repo.saveLists([tasksList]);
      await repo.saveTasks([task]);
      repo.outbox.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: task.id,
      );
      repo.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: attachment.id,
        parentLocalId: task.id,
      );
      await repo.saveOutbox();
      await repo.flushPendingWrites();

      final events = <BackgroundWorkerEvent>[];
      final engine = SyncWorkerEngine(
        account: account,
        repository: repo,
        settings: settings,
        cloudSync: cloudSync,
        idGenerator: (prefix) => '${prefix}_gen',
        onEvent: events.add,
      );

      await engine.enqueueJob(
        jobId: 'j_meta',
        lane: SyncJobLane.metadata,
        jobType: SyncJobType.pushMetadata,
      );
      await engine.enqueueJob(
        jobId: 'j_upload',
        lane: SyncJobLane.transfer,
        jobType: SyncJobType.uploadAttachment,
      );

      // Drain ONLY metadata lane: task is created, attachment NOT uploaded yet.
      final metaDrain = (await engine.drain(lane: SyncJobLane.metadata))
          .getOrThrow();
      expect(metaDrain.processedCount, 1);
      expect(metaDrain.hasPendingTransfers, isTrue);
      expect(
        api.callLog.any((c) => c.contains('POST') && c.contains('task')),
        isTrue,
      );
      expect(
        api.callLog.any((c) => c.toLowerCase().contains('attachment')),
        isFalse,
      );
      expect(
        repo.outbox.hasPending(SyncEntityType.attachment, attachment.id),
        isTrue,
      );

      // Now drain transfer lane: attachment uploads and clears isTransferring.
      final transferDrain = (await engine.drain(lane: SyncJobLane.transfer))
          .getOrThrow();
      expect(transferDrain.processedCount, 1);
      expect(transferDrain.hasPendingTransfers, isFalse);

      final updatedTask = repo.readCachedTasks().single;
      expect(updatedTask.attachments.single.remoteId, isNotNull);
      expect(updatedTask.attachments.single.isTransferring, isFalse);
      expect(events.whereType<BackgroundDbChangedEvent>(), isNotEmpty);
    });

    test('executes downloadAttachment headless and applies exponential backoff on retryable errors', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final account = MicrosoftAccount(
        id: 'acct_dl',
        displayName: 'DL Tester',
        email: 'dl@example.com',
        microsoftUserId: 'cid_dl',
        createdAt: DateTime.utc(2026, 11, 20),
      );
      final settings = TodoSettingsStore(prefs, accountId: account.id);
      final repo = TodoRepository.forSession(db, settings);

      final task = TaskItem(
        id: 't_dl',
        listId: 'tasks',
        title: 'Has Remote File',
        createdAt: DateTime.utc(2026, 11, 27),
        attachments: [
          const TaskAttachment(
            id: 'att_dl',
            remoteId: 'remote_att_1',
            displayName: 'report.pdf',
            webLink: 'https://example.com/report.pdf',
            isTransferring: true,
          ),
        ],
      );
      await repo.saveTasks([task]);
      await repo.flushPendingWrites();

      var clock = DateTime.utc(2026, 11, 27, 10, 0, 0);
      var attempts = 0;
      final engine = SyncWorkerEngine(
        account: account,
        repository: repo,
        settings: settings,
        cloudSync: CloudSyncService(
          authClient: FakeAuthClient(),
          todoApi: FakeSubstrateApi(),
          tokenStorage: AuthTokenStorage(prefs),
        ),
        idGenerator: (prefix) => '${prefix}_gen',
        nowUtc: () => clock,
        downloadAttachment: (_) async {
          attempts++;
          if (attempts == 1) {
            return const Failure(
              AppError.network(message: 'Offline', isRetryable: true),
            );
          }
          return const Success('/tmp/report.pdf');
        },
      );

      await engine.enqueueJob(
        jobId: 'j_dl',
        lane: SyncJobLane.transfer,
        jobType: SyncJobType.downloadAttachment,
        payload: {'taskId': 't_dl', 'attachmentId': 'att_dl'},
      );

      // First attempt fails with retryable error and schedules backoff.
      final first = (await engine.drain(lane: SyncJobLane.transfer))
          .getOrThrow();
      expect(first.failedCount, 1);
      expect(first.hasRetryableFailures, isTrue);

      // Immediately draining again skips the job while in backoff window.
      final duringBackoff = (await engine.drain(lane: SyncJobLane.transfer))
          .getOrThrow();
      expect(duringBackoff.processedCount, 0);
      expect(attempts, 1);

      // Advance clock past 2s backoff -> retry succeeds and persists localPath.
      clock = clock.add(const Duration(seconds: 5));
      final second = (await engine.drain(lane: SyncJobLane.transfer))
          .getOrThrow();
      expect(second.processedCount, 1);
      expect(second.failedCount, 0);

      final storedTask = repo.readCachedTasks().single;
      expect(storedTask.attachments.single.localPath, '/tmp/report.pdf');
      expect(storedTask.attachments.single.isTransferring, isFalse);
    });

    test('SyncNotifier.onAppPaused enqueues durable background sync on transfer lane when attachments are pending', () async {
      final scheduler = _RecordingBackgroundScheduler();
      final h = await createSyncTestHarness(
        accountId: 'acct_bg_handoff',
        extraOverrides: [
          backgroundSyncSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      addTearDown(h.container.dispose);

      final repo = h.container.read(todoProvider.notifier).repository;
      repo.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_pending',
        parentLocalId: 'task_1',
      );

      h.container.read(syncProvider.notifier).onAppPaused();
      await pumpEventQueue();

      expect(scheduler.enqueued, hasLength(1));
      expect(scheduler.enqueued.single.lane, SyncJobLane.transfer);
      expect(scheduler.enqueued.single.requiresNetwork, isTrue);
    });

    test('background-owned transfer lane prevents duplicate upload when pausing mid-upload', () async {
      final tmpDir = await Directory.systemTemp.createTemp('yata_bg_dedup_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final file = File(p.join(tmpDir.path, 'photo.jpg'));
      await file.writeAsBytes([1, 2, 3, 4]);

      var uploadCalls = 0;
      final fakeApi = FakeSubstrateApi()
        ..onUploadAttachment =
            (taskRemoteId, fileName, bytes, contentType) async {
              uploadCalls++;
              return RemoteFileUpload(
                id: 'remote_att_$uploadCalls',
                size: bytes.length,
                contentType: contentType,
              );
            };

      final scheduler = _RecordingBackgroundScheduler(
        handlesTransfersInBackground: true,
      );
      final h = await createSyncTestHarness(
        accountId: 'acct_no_dup_upload',
        api: fakeApi,
        defaultTasksFolderRemoteId: 'rf-default',
        tasks: [
          TaskItem(
            id: 't_att',
            listId: 'tasks',
            title: 'Task with photo',
            createdAt: DateTime.utc(2026, 11, 20),
            remoteId: 'rt-att',
            remoteParentFolderId: 'rf-default',
            attachments: [
              TaskAttachment(
                id: 'att_local_1',
                displayName: 'photo.jpg',
                localPath: file.path,
                size: 4,
                isTransferring: true,
              ),
            ],
          ),
        ],
        extraOverrides: [
          backgroundSyncSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      addTearDown(h.container.dispose);

      final repo = h.container.read(todoProvider.notifier).repository;
      repo.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_local_1',
        parentLocalId: 't_att',
        parentRemoteId: 'rt-att',
      );
      await repo.saveOutbox();
      await repo.flushPendingWrites();

      // Foreground push + immediate background switch must never upload in foreground.
      final notifier = h.container.read(syncProvider.notifier);
      notifier.schedulePushOnlySync(delay: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      notifier.onAppPaused();
      await pumpEventQueue();

      expect(uploadCalls, 0);
      expect(
        scheduler.enqueued.where((e) => e.lane == SyncJobLane.transfer),
        isNotEmpty,
      );
    });
  });
}
