import 'package:flutter_test/flutter_test.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/data/state/todo_state.dart';
import 'package:yata/data/sync/sync_dirty_fields.dart';
import 'package:yata/data/sync/sync_outbox.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_models.dart';
import 'package:yata/sync/microsoft/push_task_handler.dart';
import 'package:yata/sync/microsoft/substrate_push_context.dart';
import 'package:yata/sync/microsoft/substrate_sync_mappers.dart';
import 'package:yata/sync/microsoft/todo_wire_codecs.dart';

import '../helpers/microsoft_sync_fakes.dart';

void main() {
  group('HTML note codecs & mappers', () {
    test(
      'isHtmlBodyEmpty treats empty paragraphs as empty unless img present',
      () {
        expect(isHtmlBodyEmpty(''), isTrue);
        expect(isHtmlBodyEmpty('<p><br></p>'), isTrue);
        expect(isHtmlBodyEmpty('<div>&nbsp;</div>'), isTrue);
        expect(isHtmlBodyEmpty('<p>Hello</p>'), isFalse);
        expect(
          isHtmlBodyEmpty('<p><img src="https://example.com/a.png"></p>'),
          isFalse,
        );
      },
    );

    test('normalizeHtmlBodyDocument wraps fragments and clears empty HTML', () {
      expect(normalizeHtmlBodyDocument('<p><br></p>'), '');
      final wrapped = normalizeHtmlBodyDocument('<p><strong>Hi</strong></p>');
      expect(
        wrapped,
        '<html><head>'
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'
        '</head><body><p><strong>Hi</strong></p></body></html>',
      );
      expect(normalizeHtmlBodyDocument(wrapped), wrapped);
    });

    test(
      'TaskItem.fromJson remains compatible with legacy JSON without noteHtml',
      () {
        final item = TaskItem.fromJson({
          'id': 't1',
          'listId': 'l1',
          'title': 'Legacy task',
          'createdAt': '2026-11-01T00:00:00.000Z',
          'note': 'Plain note',
        });
        expect(item.note, 'Plain note');
        expect(item.noteHtml, '');
        expect(item.noteContentType, isNull);
        expect(item.isHtmlNote, isFalse);
        expect(item.hasNote, isTrue);
      },
    );

    test('taskFromRemote and buildTaskWritePayload round-trip HTML notes', () {
      const rawHtml =
          '<html><head><meta charset="utf-8"></head><body><p><b>Bold</b> note</p></body></html>';
      final remote = RemoteTodoTask(
        id: 'rt-1',
        subject: 'Task',
        bodyContent: rawHtml,
        bodyContentType: 'HTML',
        bodyLastModifiedTime: DateTime.utc(2026, 11, 28, 1, 0),
      );
      final local = taskFromRemote(
        remote,
        localId: 'lt-1',
        listId: 'l1',
        existingSteps: const [],
        idGenerator: (p) => '$p-1',
      );
      expect(local.note, 'Bold note');
      expect(local.noteHtml, rawHtml);
      expect(local.noteContentType, 'HTML');
      expect(local.isHtmlNote, isTrue);

      final payload = buildTaskWritePayload(
        local,
        parentFolderRemoteId: 'rf-1',
        isCreate: false,
        firstDayOfWeek: WeekStart.sunday,
        dirtyFields: {TaskDirtyField.body},
      );
      expect(payload['Body'], {'Content': rawHtml, 'ContentType': 'HTML'});
    });
  });

  group('TaskPushHandler HTML LWW conflict resolution', () {
    test(
      'uses remote HTML when remote bodyLastModifiedTime is newer',
      () async {
        final fakeApi = FakeSubstrateApi();
        Map<String, dynamic>? retriedPatch;
        TaskItem? committedTask;

        final localList = TodoList(
          id: 'l1',
          title: 'Tasks',
          remoteId: 'rf-1',
        );
        final localTask = TaskItem(
          id: 't1',
          listId: 'l1',
          remoteId: 'rt-1',
          remoteParentFolderId: 'rf-1',
          changeKey: 'ck-1',
          title: 'Task',
          createdAt: DateTime.utc(2026, 11, 28, 0, 0),
          note: 'Local note',
          noteHtml: '<p>Local note</p>',
          noteContentType: 'HTML',
          noteUpdatedAt: DateTime.utc(2026, 11, 28, 1, 0),
        );

        fakeApi.onPatchTask = (id, patch, ck) async {
          if (ck == 'ck-1') {
            throw const AppError.network(
              statusCode: 409,
              code: 'ErrorIrresolvableConflict',
              message: 'conflict',
            );
          }
          retriedPatch = Map<String, dynamic>.from(patch);
          return const RemoteTodoTask(
            id: 'rt-1',
            changeKey: 'ck-3',
            parentFolderId: 'rf-1',
            subject: 'Task',
          );
        };

        fakeApi.onGetTask = (id) async => RemoteTodoTask(
          id: 'rt-1',
          changeKey: 'ck-2',
          parentFolderId: 'rf-1',
          subject: 'Task',
          bodyContent: '<html><body><p>Remote newer</p></body></html>',
          bodyContentType: 'HTML',
          bodyLastModifiedTime: DateTime.utc(2026, 11, 28, 2, 0),
        );

        final ctx = PushContext(
          todoApi: fakeApi,
          readState: () => TodoState(
            groups: const [],
            lists: [localList],
            tasks: [localTask],
            selectedListId: 'l1',
          ),
          startOfWeek: WeekStart.sunday,
          outbox: SyncOutboxQueue(),
          nowUtc: DateTime.utc(2026, 11, 28, 3, 0),
          onItemCommitted: (outcome) async {
            committedTask = outcome.pushedTasks['t1'];
          },
        );

        final handler = TaskPushHandler(ctx);
        final res = await handler.pushTaskOp(
          SyncOutboxOp(
            seq: 1,
            entityType: SyncEntityType.task,
            kind: SyncOpKind.upsert,
            localId: 't1',
            fields: {TaskDirtyField.body.name},
          ),
        );

        expect(res.isSuccess(), isTrue);
        expect(retriedPatch?['Body'], {
          'Content': '<html><body><p>Remote newer</p></body></html>',
          'ContentType': 'HTML',
        });
        expect(committedTask?.note, 'Remote newer');
        expect(
          committedTask?.noteHtml,
          '<html><body><p>Remote newer</p></body></html>',
        );
      },
    );
  });
}
