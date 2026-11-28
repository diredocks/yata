import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/sync/sync_outbox.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/data/storage/todo_repository.dart';
import 'package:yata/data/lists/todo_settings_store.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/background_sync_bridge.dart';
import 'package:yata/app/background_sync_entrypoint.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/microsoft/substrate_push_engine.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/sync_store.dart';

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
    test(
      'upsertTask and deleteTask modify individual rows in SQLite',
      () async {
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
      },
    );

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
      expect(BackgroundDbChangedEvent.fromWireMap({'accountKey': ''}), isNull);
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

      final settings = TodoSettingsStore(prefs, accountId: 'acct_lane');
      final repo = TodoRepository.forSession(db, settings);

      final api = FakeSubstrateApi();

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
        repository: repo,
        settings: settings,
        todoApi: api,
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
        repository: repo,
        settings: settings,
        todoApi: api,
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

      final settings = TodoSettingsStore(prefs, accountId: 'acct_retry');
      final repo = TodoRepository.forSession(db, settings);

      final api = FakeSubstrateApi()
        ..onUploadAttachment = (_, _, _, _) async {
          throw const AppError.network(message: 'Offline', isRetryable: true);
        };

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
        repository: repo,
        settings: settings,
        todoApi: api,
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
        repository: repo,
        settings: settings,
        todoApi: api,
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
      notifier.schedulePush(delay: const Duration(milliseconds: 10));
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

  group('Row-level outbox, SQLite sync metadata & SyncStore', () {
    test('row-level outbox saves and acks preserve concurrent ops from another repository scope', () async {
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final repoA = TodoRepository(
        db,
        accountKey: 'acct_iso',
        scopeKey: 'scope_a',
      );
      final repoB = TodoRepository(
        db,
        accountKey: 'acct_iso',
        scopeKey: 'scope_b',
      );

      repoA.outbox.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: 't_1',
      );
      await repoA.saveOutbox();
      await repoA.flushPendingWrites();
      final seq1 = repoA.outbox.ops.single.seq;

      // Another isolate/scope loads outbox, appends op2 (with seq > seq1), and saves.
      (await repoB.preload()).getOrThrow();
      repoB.outbox.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: 't_2',
      );
      await repoB.saveOutbox();
      await repoB.flushPendingWrites();
      expect(repoB.outbox.ops.map((op) => op.localId).toList(), ['t_1', 't_2']);

      // Scope A acks only seq1 and writes row-level delta -> seq2 stays intact in SQLite.
      repoA.outbox.ackOp(seq1);
      await repoA.saveOutbox();
      await repoA.flushPendingWrites();

      (await repoA.preload()).getOrThrow();
      expect(repoA.outbox.ops.map((op) => op.localId).toList(), ['t_2']);
    });

    test('SQLite sync metadata persists deltaLinks and endpoint TTL across preload', () async {
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final writer = TodoRepository(
        db,
        accountKey: 'acct_meta',
        scopeKey: 'meta_writer',
      );
      final reader = TodoRepository(
        db,
        accountKey: 'acct_meta',
        scopeKey: 'meta_reader',
      );

      await writer.saveSyncMetaBatch(
        groupsDeltaLink: 'dl-groups',
        updateGroupsDeltaLink: true,
        foldersDeltaLink: 'dl-folders',
        updateFoldersDeltaLink: true,
        taskDeltaLinks: const {'rf-1': 'dl-t1', 'rf-2': 'dl-t2'},
      );
      await writer.saveCachedEndpointUrl('https://substrate.example/api/v1/');
      await writer.flushPendingWrites();

      (await reader.preload()).getOrThrow();
      expect(reader.loadGroupsDeltaLink(), 'dl-groups');
      expect(reader.loadFoldersDeltaLink(), 'dl-folders');
      expect(reader.loadTaskDeltaLinks(), {'rf-1': 'dl-t1', 'rf-2': 'dl-t2'});
      expect(
        reader.loadCachedEndpointUrl(),
        'https://substrate.example/api/v1/',
      );
      expect(reader.loadCachedEndpointUrl(maxAge: Duration.zero), isNull);

      await reader.saveSyncMetaBatch(
        groupsDeltaLink: null,
        updateGroupsDeltaLink: true,
      );
      await reader.flushPendingWrites();

      (await writer.preload()).getOrThrow();
      expect(writer.loadGroupsDeltaLink(), isNull);
      expect(writer.loadFoldersDeltaLink(), 'dl-folders');
    });

    test('SyncStore.commitPushHeadless preserves concurrent foreground task edit and remoteId mapping', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final fgRepo = TodoRepository(
        db,
        accountKey: 'acct_headless',
        scopeKey: 'fg',
      );
      final bgRepo = TodoRepository(
        db,
        accountKey: 'acct_headless',
        scopeKey: 'bg',
      );
      final settings = TodoSettingsStore(prefs, accountId: 'acct_headless');

      final initialTask = TaskItem(
        id: 't_1',
        listId: 'tasks',
        title: 'Initial Title',
        remoteId: 'rt_1',
        remoteParentFolderId: 'rf-default',
        createdAt: DateTime.utc(2026, 11, 27),
        attachments: const [
          TaskAttachment(
            id: 'att_1',
            displayName: 'photo.jpg',
            localPath: '/tmp/photo.jpg',
            size: 10,
            isTransferring: true,
          ),
        ],
      );
      await fgRepo.saveTasks([initialTask]);
      fgRepo.outbox.enqueueUpsert(
        entityType: SyncEntityType.attachment,
        localId: 'att_1',
        parentLocalId: 't_1',
        parentRemoteId: 'rt_1',
      );
      await fgRepo.saveOutbox();
      await fgRepo.flushPendingWrites();

      // Background scope loads snapshot, starts upload, and records server attachment remoteId.
      (await bgRepo.preload()).getOrThrow();
      final uploadSeq = bgRepo.outbox.ops.single.seq;

      // Foreground concurrently edits task title and writes it to SQLite.
      await fgRepo.upsertTask(initialTask.copyWith(title: 'Foreground Edit'));
      await fgRepo.flushPendingWrites();

      final pushedTask = initialTask.copyWith(
        changeKey: 'ck_after_upload',
        attachments: const [
          TaskAttachment(
            id: 'att_1',
            displayName: 'photo.jpg',
            remoteId: 'remote_att_1',
            size: 10,
            isTransferring: false,
          ),
        ],
      );
      await SyncStore(
        repository: bgRepo,
        settings: settings,
      ).commitPushHeadless(
        OutboxPushOutcome(
          ackedSeqs: [uploadSeq],
          pushedGroups: const {},
          pushedLists: const {},
          pushedTasks: {'t_1': pushedTask},
          followUpPullFolderRemoteIds: const {'rf-default'},
        ),
      );

      (await fgRepo.preload()).getOrThrow();
      final merged = fgRepo.readCachedTasks().single;
      expect(merged.title, 'Foreground Edit');
      expect(merged.changeKey, 'ck_after_upload');
      expect(merged.attachments.single.remoteId, 'remote_att_1');
      expect(merged.attachments.single.isTransferring, isFalse);
      expect(fgRepo.outbox.ops, isEmpty);
    });
  });
}
