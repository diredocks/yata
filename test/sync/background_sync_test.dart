import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/background_sync_bridge.dart';
import 'package:yata/sync/background_sync_entrypoint.dart';
import 'package:yata/sync/microsoft/cloud_sync_service.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';

import '../helpers/microsoft_sync_fakes.dart';

class _RecordingBackgroundScheduler implements BackgroundSyncScheduler {
  _RecordingBackgroundScheduler({this.handlesTransfersInBackground = false});

  @override
  final bool handlesTransfersInBackground;

  final List<
    ({
      BackgroundSyncLane lane,
      String reason,
      bool requiresNetwork,
      bool expedited,
    })
  >
  enqueued = [];

  @override
  Future<void> registerBackgroundEntrypoint(Function entrypoint) async {}

  @override
  Future<void> enqueueSync({
    required BackgroundSyncLane lane,
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
  group('Row-level Drift persistence & BackgroundDbChangedEvent', () {
    test('upsertTask and deleteTask modify individual rows in SQLite', () async {
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
      await repo.preload();

      expect(
        repo.readCachedTasks().map((t) => '${t.id}:${t.title}').toList(),
        ['t1:First Updated', 't2:Second'],
      );

      await repo.deleteTask('t1');
      await repo.flushPendingWrites();
      await repo.preload();

      expect(repo.readCachedTasks().map((t) => t.id).toList(), ['t2']);
    });

    test('BackgroundDbChangedEvent round-trips over wire maps and rejects invalid payloads', () {
      const event = BackgroundDbChangedEvent(
        accountKey: 'acct_1',
        lane: BackgroundSyncLane.transfer,
        reason: 'upload',
      );
      final decoded = BackgroundDbChangedEvent.fromWireMap(event.toWireMap());
      expect(decoded, event);

      expect(BackgroundDbChangedEvent.fromWireMap('not a map'), isNull);
      expect(BackgroundDbChangedEvent.fromWireMap(<String, Object?>{}), isNull);
      expect(
        BackgroundDbChangedEvent.fromWireMap({'accountKey': ''}),
        isNull,
      );
      expect(
        BackgroundDbChangedEvent.fromWireMap({'accountKey': 'acct_1'}),
        const BackgroundDbChangedEvent(accountKey: 'acct_1'),
      );
    });
  });

  group('runBackgroundOutboxPass fast/slow lanes & headless execution', () {
    test('isolates metadata lane from attachment upload lane and commits directly to SQLite', () async {
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

      final events = <BackgroundDbChangedEvent>[];

      // Drain ONLY metadata lane: task is created, attachment NOT uploaded yet.
      final metaOutcome = await runBackgroundOutboxPass(
        account: account,
        repository: repo,
        settings: settings,
        cloudSync: cloudSync,
        lane: BackgroundSyncLane.metadata,
        reason: 'bg_meta',
        onDbChanged: events.add,
      );
      expect(metaOutcome.didMutateDb, isTrue);
      expect(metaOutcome.hasPendingTransfers, isTrue);
      expect(metaOutcome.shouldRetry, isFalse);
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
      expect(events.last.lane, BackgroundSyncLane.metadata);

      // Drain transfer lane: attachment uploads and clears isTransferring.
      final transferOutcome = await runBackgroundOutboxPass(
        account: account,
        repository: repo,
        settings: settings,
        cloudSync: cloudSync,
        lane: BackgroundSyncLane.transfer,
        reason: 'bg_transfer',
        onDbChanged: events.add,
      );
      expect(transferOutcome.didMutateDb, isTrue);
      expect(transferOutcome.hasPendingTransfers, isFalse);
      expect(transferOutcome.shouldRetry, isFalse);

      await repo.preload();
      final updatedTask = repo.readCachedTasks().single;
      expect(updatedTask.attachments.single.remoteId, isNotNull);
      expect(updatedTask.attachments.single.isTransferring, isFalse);
      expect(events.last.lane, BackgroundSyncLane.transfer);
    });

    test('returns shouldRetry on retryable failure and no-ops without API calls when lane has no ops', () async {
      final tmpDir = await Directory.systemTemp.createTemp('yata_retry_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final stagedFile = File(p.join(tmpDir.path, 'doc.txt'));
      await stagedFile.writeAsBytes([1, 2, 3]);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final account = MicrosoftAccount(
        id: 'acct_retry',
        displayName: 'Retry Tester',
        email: 'retry@example.com',
        microsoftUserId: 'cid_retry',
        createdAt: DateTime.utc(2026, 11, 20),
      );
      final settings = TodoSettingsStore(prefs, accountId: account.id);
      final repo = TodoRepository.forSession(db, settings);

      final api = FakeSubstrateApi()
        ..onUploadAttachment = (_, _, _, _) async {
          throw const AppError.network(message: 'Offline', isRetryable: true);
        };
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        account.id,
        MicrosoftAuthTokens(
          accessToken: 'tok',
          refreshToken: 'ref',
          expiresAt: DateTime.utc(2099, 1, 1),
          userId: 'cid_retry',
        ),
      );
      final cloudSync = CloudSyncService(
        authClient: FakeAuthClient(),
        todoApi: api,
        tokenStorage: tokenStorage,
      );

      final task = TaskItem(
        id: 't_r',
        listId: 'tasks',
        title: 'Has File',
        remoteId: 'rt_r',
        remoteParentFolderId: 'rf-default',
        createdAt: DateTime.utc(2026, 11, 27),
        attachments: [
          TaskAttachment(
            id: 'att_r',
            displayName: 'doc.txt',
            localPath: stagedFile.path,
            size: 3,
            isTransferring: true,
          ),
        ],
      );
      await repo.saveTasks([task]);
      repo.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_r',
        parentLocalId: 't_r',
        parentRemoteId: 'rt_r',
      );
      await repo.saveOutbox();
      await repo.flushPendingWrites();

      // Metadata lane should be a 0-API-call no-op and signal pending transfer.
      final events = <BackgroundDbChangedEvent>[];
      final metaOutcome = await runBackgroundOutboxPass(
        account: account,
        repository: repo,
        settings: settings,
        cloudSync: cloudSync,
        lane: BackgroundSyncLane.metadata,
        reason: 'bg_meta',
        onDbChanged: events.add,
      );
      expect(metaOutcome.didMutateDb, isFalse);
      expect(metaOutcome.shouldRetry, isFalse);
      expect(metaOutcome.hasPendingTransfers, isTrue);
      expect(api.callLog, isEmpty);
      expect(events, isEmpty);

      // Transfer lane fails with retryable error -> shouldRetry=true.
      final transferOutcome = await runBackgroundOutboxPass(
        account: account,
        repository: repo,
        settings: settings,
        cloudSync: cloudSync,
        lane: BackgroundSyncLane.transfer,
        reason: 'bg_transfer',
        onDbChanged: events.add,
      );
      expect(transferOutcome.didMutateDb, isFalse);
      expect(transferOutcome.shouldRetry, isTrue);
      expect(events, isEmpty);
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
      expect(scheduler.enqueued.single.lane, BackgroundSyncLane.transfer);
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
        scheduler.enqueued.where((e) => e.lane == BackgroundSyncLane.transfer),
        isNotEmpty,
      );
    });
  });
}
