import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_sync_reconciler.dart';
import 'package:yata/detailview/attachments/attachment_service.dart';
import 'package:yata/detailview/attachments/attachments_card_view.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_models.dart';
import 'package:yata/sync/microsoft/substrate_push_engine.dart';
import 'package:yata/sync/microsoft/substrate_sync_mappers.dart';
import 'package:yata/tasksview/recyclerview/task_list_tile.dart';
import 'package:yata/tasksview/tasks_action_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  group('TaskAttachment model & remote mapping', () {
    test('parses LinkedEntities with Map or String Preview and preserves localPath', () {
      final remote = RemoteTodoTask.fromJson({
        'Id': 'rt-1',
        'Subject': 'Task with files',
        'LinkedEntities': [
          {
            'Id': 'le-1',
            'DisplayName': 'report.pdf',
            'EntityType': 'file',
            'EntitySubType': 'exchange-file-attachment',
            'WebLink': '/api/v1/tasks/rt-1/attachments/le-1',
            'Preview': {
              'Size': 2048,
              'ContentType': 'application/pdf',
              'LastModifiedDateTime': '2026-11-26T10:00:00Z',
            },
          },
          {
            'Id': 'le-2',
            'DisplayName': 'photo.jpeg',
            'EntityType': 'file',
            'WebLink': '/api/v1/tasks/rt-1/attachments/le-2',
            'Preview': '{"Size":4096,"ContentType":"image/jpeg"}',
          },
        ],
      });

      expect(remote.linkedEntities, hasLength(2));
      expect(remote.linkedEntities[0].size, 2048);
      expect(remote.linkedEntities[0].contentType, 'application/pdf');
      expect(remote.linkedEntities[1].size, 4096);
      expect(remote.linkedEntities[1].contentType, 'image/jpeg');

      var seq = 0;
      final mapped = taskFromRemote(
        remote,
        localId: 'task-1',
        listId: 'list-1',
        existingSteps: const [],
        existingAttachments: const [
          TaskAttachment(
            id: 'att-local-1',
            displayName: 'report.pdf',
            remoteId: 'le-1',
            localPath: '/cached/report.pdf',
          ),
        ],
        idGenerator: (p) => '$p-${++seq}',
      );

      expect(mapped.attachments, hasLength(2));
      expect(mapped.attachments[0].id, 'att-local-1');
      expect(mapped.attachments[0].localPath, '/cached/report.pdf');
      expect(mapped.attachments[0].badgeLabel, 'PDF');
      expect(mapped.attachments[1].badgeLabel, 'JPG');
    });
  });

  group('AttachmentService', () {
    test(
      'enforces 25 MB cumulative per-task limit and stages/opens files',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final tempDir = await Directory.systemTemp.createTemp('yata_att_test_');
        addTearDown(() => tempDir.delete(recursive: true));

        final sourceFile = File('${tempDir.path}/source.txt');
        await sourceFile.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));

        String? openedPath;
        String? openedType;

        // Build service directly with test overrides.
        late AttachmentService service;
        final overrideContainer = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            attachmentServiceProvider.overrideWith((ref) {
              service = AttachmentService(
                ref,
                storageRootProvider: () async => tempDir,
                openFileFn: (path, {type}) async {
                  openedPath = path;
                  openedType = type;
                  return OpenResult(type: ResultType.done, message: 'done');
                },
              );
              return service;
            }),
          ],
        );
        addTearDown(overrideContainer.dispose);
        final account = await overrideContainer
            .read(accountProvider.notifier)
            .signInLocal(
              'Local',
              fallbackName: 'Local',
              fallbackEmail: 'local@local',
            );
        service = overrideContainer.read(attachmentServiceProvider);

        const existingAtt = TaskAttachment(
          id: 'att-1',
          displayName: 'big.bin',
          size: kMaxTaskAttachmentTotalBytes - 10,
        );
        final task = TaskItem(
          id: 't-1',
          listId: 'l-1',
          title: 'Test',
          createdAt: DateTime.now().toUtc(),
          attachments: const [existingAtt],
        );

        expect(service.exceedsTaskSizeLimit(task, 10), isFalse);
        expect(service.exceedsTaskSizeLimit(task, 11), isTrue);

        expect(
          AttachmentService.sanitizeFileName('../../evil:name?.pdf'),
          'evil_name_.pdf',
        );

        final staged = await service.stageLocalFile(
          attachmentId: 'att-2',
          sourcePath: sourceFile.path,
          fileName: 'notes.txt',
        );
        expect(staged.size, 5);
        expect(
          staged.localPath,
          p.join(tempDir.path, 'attachments', account.id, 'att-2', 'notes.txt'),
        );
        expect(await File(staged.localPath).exists(), isTrue);

        final openRes = await service.openAttachment(
          TaskAttachment(
            id: 'att-2',
            displayName: 'notes.txt',
            contentType: 'text/plain',
            localPath: staged.localPath,
          ),
        );
        expect(openRes.isSuccess(), isTrue);
        expect(openedPath, staged.localPath);
        expect(openedType, 'text/plain');
      },
    );
  });

  group('Attachment Outbox & Push Engine', () {
    test('uploads new attachment and deletes synced attachment via LinkedEntities', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('yata_push_att_');
      addTearDown(() => tempDir.delete(recursive: true));

      final localFile = File('${tempDir.path}/hello.txt');
      await localFile.writeAsString('hello attachment');

      final api = FakeSubstrateApi();
      final outbox = SyncOutboxQueue();
      final list = TodoList(id: 'l-1', title: 'Tasks', remoteId: 'rf-1');
      final taskBefore = TaskItem(
        id: 't-1',
        listId: 'l-1',
        title: 'Task 1',
        remoteId: 'rt-1',
        createdAt: DateTime.utc(2026, 11, 26),
      );
      final localAtt = TaskAttachment(
        id: 'att-1',
        displayName: 'hello.txt',
        contentType: 'text/plain',
        size: 16,
        localPath: localFile.path,
        isTransferring: true,
      );
      final taskWithAtt = taskBefore.copyWith(attachments: [localAtt]);

      final prevState = TodoState(
        groups: const [],
        lists: [list],
        tasks: [taskBefore],
        selectedListId: 'l-1',
      );
      final nextState = TodoState(
        groups: const [],
        lists: [list],
        tasks: [taskWithAtt],
        selectedListId: 'l-1',
      );

      final commitResult = enqueueLocalCommitToOutbox(
        prevState: prevState,
        nextState: nextState,
        nowUtc: DateTime.utc(2026, 11, 26),
        outbox: outbox,
      );

      expect(commitResult.syncNeeded, isTrue);
      expect(outbox.ops, hasLength(1));
      expect(outbox.ops.first.entityType, SyncEntityType.attachment);
      expect(outbox.ops.first.kind, SyncOpKind.upsert);
      expect(outbox.ops.first.localId, 'att-1');

      final pushEngine = SubstratePushEngine(api);
      final ctx = SubstrateRequestContext(
        baseUrl: 'https://substrate.office.com/todob2/api/v1/',
        accessToken: 'token',
        cid: 'cid123',
      );

      final pushOutcome = (await pushEngine.pushOutbox(
        ctx: ctx,
        currentState: nextState,
        outbox: outbox,
        nowUtc: DateTime.utc(2026, 11, 26),
      )).getOrThrow();

      expect(api.callLog, contains('POST tasks/rt-1/attachments (hello.txt)'));
      final pushedTask = pushOutcome.pushedTasks['t-1']!;
      expect(pushedTask.attachments.single.remoteId, isNotNull);
      expect(pushedTask.attachments.single.isTransferring, isFalse);

      // Now delete the synced attachment and verify DELETE linkedentities call.
      final db = TodoDatabase();
      addTearDown(db.close);
      final repo = TodoRepository(db);
      expect(repo.outbox, isNotNull);

      for (final seq in pushOutcome.ackedSeqs) {
        outbox.ackOp(seq);
      }

      final stateAfterUpload = nextState.copyWith(tasks: [pushedTask]);
      final stateAfterDelete = stateAfterUpload.copyWith(
        tasks: [pushedTask.copyWith(attachments: const [])],
      );

      enqueueLocalCommitToOutbox(
        prevState: stateAfterUpload,
        nextState: stateAfterDelete,
        nowUtc: DateTime.utc(2026, 11, 26),
        outbox: outbox,
      );

      expect(outbox.ops, hasLength(1));
      expect(outbox.ops.first.entityType, SyncEntityType.attachment);
      expect(outbox.ops.first.kind, SyncOpKind.delete);

      await pushEngine.pushOutbox(
        ctx: ctx,
        currentState: stateAfterDelete,
        outbox: outbox,
        nowUtc: DateTime.utc(2026, 11, 26),
      );

      expect(
        api.callLog,
        contains(
          'DELETE tasks/rt-1/linkedentities/${pushedTask.attachments.single.remoteId}',
        ),
      );
    });
  });

  group('Attachments UI widgets', () {
    testWidgets(
      'AttachmentsCardView renders attachments, states, and callbacks',
      (tester) async {
        var addTapped = false;
        TaskAttachment? tappedAtt;
        TaskAttachment? deletedAtt;

        final task = TaskItem(
          id: 't-1',
          listId: 'l-1',
          title: 'Task',
          createdAt: DateTime.utc(2026, 11, 26),
          attachments: const [
            TaskAttachment(
              id: 'att-1',
              displayName: 'spec.pdf',
              remoteId: 're-1',
              size: 1024 * 1024,
              localPath: '/tmp/spec.pdf',
            ),
            TaskAttachment(
              id: 'att-2',
              displayName: 'uploading.png',
              size: 2048,
              localPath: '/tmp/uploading.png',
              isTransferring: true,
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AttachmentsCardView(
                task: task,
                cardColor: Colors.white,
                onAddAttachment: () => addTapped = true,
                onTapAttachment: (a) => tappedAtt = a,
                onDeleteAttachment: (a) => deletedAtt = a,
              ),
            ),
          ),
        );

        expect(find.text('spec.pdf'), findsOneWidget);
        expect(find.text('1.0 MB · PDF'), findsOneWidget);
        expect(find.text('uploading.png'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Only 1 close button (uploading local-only attachment hides delete button).
        expect(find.byIcon(Icons.close), findsOneWidget);

        await tester.tap(find.text('spec.pdf'));
        expect(tappedAtt?.id, 'att-1');

        await tester.tap(find.byIcon(Icons.close));
        expect(deletedAtt?.id, 'att-1');

        await tester.tap(find.text('Add file'));
        expect(addTapped, isTrue);
      },
    );

    testWidgets('TaskListTile shows paperclip icon when task has attachments', (
      tester,
    ) async {
      final task = TaskItem(
        id: 't-1',
        listId: 'l-1',
        title: 'With attachment',
        createdAt: DateTime.utc(2026, 11, 26),
        attachments: const [
          TaskAttachment(id: 'att-1', displayName: 'doc.pdf'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TaskListTile(
              task: task,
              onTap: () {},
              onToggleCompleted: () {},
              onToggleImportant: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
    });
  });

  group('Per-account attachment storage & cleanup', () {
    test('isolates attachments by accountId and cleans up on batchDeleteTasks, deleteList, and signOut', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = await Directory.systemTemp.createTemp(
        'yata_att_cleanup_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final db = TodoDatabase();
      addTearDown(db.close);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          todoDatabaseProvider.overrideWithValue(db),
          attachmentServiceProvider.overrideWith(
            (ref) => AttachmentService(
              ref,
              storageRootProvider: () async => tempDir,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final accountNotifier = container.read(accountProvider.notifier);
      final attService = container.read(attachmentServiceProvider);
      final srcFile = File(p.join(tempDir.path, 'sample.txt'));
      await srcFile.writeAsString('payload');

      final acctB = await accountNotifier.signInLocal(
        'Account B',
        fallbackName: 'Account B',
        fallbackEmail: 'b@local',
      );
      final stagedB1 = await attService.stageLocalFile(
        attachmentId: 'att-b1',
        sourcePath: srcFile.path,
        fileName: 'b1.txt',
      );

      final acctA = await accountNotifier.signInLocal(
        'Account A',
        fallbackName: 'Account A',
        fallbackEmail: 'a@local',
      );
      final stagedA1 = await attService.stageLocalFile(
        attachmentId: 'att-a1',
        sourcePath: srcFile.path,
        fileName: 'a1.txt',
      );
      final stagedA2 = await attService.stageLocalFile(
        attachmentId: 'att-a2',
        sourcePath: srcFile.path,
        fileName: 'a2.txt',
      );
      final stagedA3 = await attService.stageLocalFile(
        attachmentId: 'att-a3',
        sourcePath: srcFile.path,
        fileName: 'a3.txt',
      );

      expect(
        stagedA1.localPath,
        p.join(tempDir.path, 'attachments', acctA.id, 'att-a1', 'a1.txt'),
      );
      expect(
        stagedB1.localPath,
        p.join(tempDir.path, 'attachments', acctB.id, 'att-b1', 'b1.txt'),
      );

      final list1 = const TodoList(id: 'l-1', title: 'List 1');
      final list2 = const TodoList(id: 'l-2', title: 'List 2');
      final task1 = TaskItem(
        id: 't-1',
        listId: 'l-1',
        title: 'Task 1',
        createdAt: DateTime.utc(2026, 11, 26),
        attachments: [
          TaskAttachment(
            id: 'att-a1',
            displayName: 'a1.txt',
            localPath: stagedA1.localPath,
          ),
        ],
      );
      final task2 = TaskItem(
        id: 't-2',
        listId: 'l-1',
        title: 'Task 2 (shared)',
        createdAt: DateTime.utc(2026, 11, 26),
        attachments: [
          TaskAttachment(
            id: 'att-a2',
            displayName: 'a2.txt',
            localPath: stagedA2.localPath,
          ),
        ],
      );
      final task2Copy = TaskItem(
        id: 't-2-copy',
        listId: 'l-1',
        title: 'Task 2 Copy',
        createdAt: DateTime.utc(2026, 11, 26),
        attachments: [
          TaskAttachment(
            id: 'att-a2',
            displayName: 'a2.txt',
            localPath: stagedA2.localPath,
          ),
        ],
      );
      final task3 = TaskItem(
        id: 't-3',
        listId: 'l-2',
        title: 'Task 3 in List 2',
        createdAt: DateTime.utc(2026, 11, 26),
        attachments: [
          TaskAttachment(
            id: 'att-a3',
            displayName: 'a3.txt',
            localPath: stagedA3.localPath,
          ),
        ],
      );

      final todoNotifier = container.read(todoProvider.notifier);
      todoNotifier.commit(
        TodoState(
          groups: const [],
          lists: [list1, list2],
          tasks: [task1, task2, task2Copy, task3],
          selectedListId: 'l-1',
        ),
      );

      // 1. batchDeleteTasks deletes unreferenced t-1 file, keeps shared t-2 file.
      container.read(tasksActionPresenterProvider).batchDeleteTasks({
        't-1',
        't-2',
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await File(stagedA1.localPath).exists(), isFalse);
      expect(await File(stagedA2.localPath).exists(), isTrue);

      // 2. deleteList removes t-3's attachment file.
      container.read(tasksViewPresenterProvider).deleteList('l-2');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await File(stagedA3.localPath).exists(), isFalse);

      // 3. signOut deletes acctA's entire attachment directory without touching acctB.
      await accountNotifier.signOut(acctA.id);
      expect(
        await Directory(p.join(tempDir.path, 'attachments', acctA.id)).exists(),
        isFalse,
      );
      expect(await File(stagedB1.localPath).exists(), isTrue);
    });

    test('cleanupPickedSource removes temp cache copies without touching originals outside tempDir', () async {
      final rootDir = await Directory.systemTemp.createTemp('yata_clean_');
      addTearDown(() => rootDir.delete(recursive: true));

      final tempDir = Directory(p.join(rootDir.path, 'cache'))..createSync();
      final userDir = Directory(p.join(rootDir.path, 'docs'))..createSync();

      final pickedSubDir = Directory(p.join(tempDir.path, 'file_picker', '1'))
        ..createSync(recursive: true);
      final pickedTempFile = File(p.join(pickedSubDir.path, 'doc.pdf'))
        ..writeAsBytesSync([1, 2, 3]);
      final cameraTempFile = File(p.join(tempDir.path, 'cam_123.jpg'))
        ..writeAsBytesSync([4, 5, 6]);
      final userOriginal = File(p.join(userDir.path, 'original.pdf'))
        ..writeAsBytesSync([7, 8, 9]);

      final container = ProviderContainer(
        overrides: [
          attachmentServiceProvider.overrideWith(
            (ref) => AttachmentService(
              ref,
              storageRootProvider: () async => rootDir,
              tempDirProvider: () async => tempDir,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final service = container.read(attachmentServiceProvider);

      await service.cleanupPickedSource(pickedTempFile.path);
      expect(await pickedTempFile.exists(), isFalse);
      expect(await pickedSubDir.exists(), isFalse);
      expect(await tempDir.exists(), isTrue);

      await service.cleanupPickedSource(cameraTempFile.path);
      expect(await cameraTempFile.exists(), isFalse);
      expect(await tempDir.exists(), isTrue);

      // Must never delete a user file outside tempDir (e.g. desktop picker).
      await service.cleanupPickedSource(userOriginal.path);
      expect(await userOriginal.exists(), isTrue);
    });
  });
}
