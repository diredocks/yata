import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/core/result/app_result.dart';
import 'package:yata/data/todo_database.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/models/todo_list.dart';

void main() {
  group('AppError', () {
    test('exposes branch specific messages and retry semantics', () {
      const errors = <AppError>[
        AppError.network(message: 'offline', statusCode: 503),
        AppError.network(message: 'bad request', statusCode: 400),
        AppError.database(message: 'disk full'),
        AppError.notFound(message: 'missing', entity: 'task'),
        AppError.validation(message: 'title required', field: 'title'),
        AppError.auth(message: 'expired', requiresReauth: true),
        AppError.unknown(message: 'boom'),
      ];

      expect(errors.map((error) => error.userMessage).toList(), [
        'offline',
        'bad request',
        'disk full',
        'missing',
        'title required',
        'expired',
        'boom',
      ]);
      expect(errors.map((error) => error.isRetryable).toList(), [
        true,
        false,
        false,
        false,
        false,
        false,
        false,
      ]);
      expect(errors.first.describe(), contains('NetworkError'));
      expect(errors.first.describe(), contains('status=503'));
    });
  });

  group('guardDbCall', () {
    test('returns Success for completed work', () async {
      final result = await guardDbCall(() async => 42);
      expect(result, const Success<int, AppError>(42));
    });

    test('maps StateError to NotFoundError', () async {
      final result = await guardDbCall<int>(
        () async => throw StateError('No element'),
        operation: 'selectTask',
      );
      expect(result.isError(), isTrue);
      final error = result.exceptionOrNull();
      expect(error, isA<NotFoundError>());
      expect((error! as NotFoundError).entity, 'selectTask');
    });

    test('maps SqliteException to DatabaseError', () async {
      final result = await guardDbCall<int>(
        () async => throw SqliteException(
          message: 'database disk image is malformed',
          extendedResultCode: 11,
        ),
        operation: 'writeTasks',
      );
      final error = result.exceptionOrNull();
      expect(error, isA<DatabaseError>());
      expect((error! as DatabaseError).operation, 'writeTasks');
    });

    test('maps unknown failures to UnknownError', () async {
      final result = await guardDbCall<int>(
        () async => throw Exception('boom'),
      );
      expect(result.exceptionOrNull(), isA<UnknownError>());
    });

    test('guardDbUnit returns Unit on success', () async {
      final result = await guardDbUnit(() async {});
      expect(result.getOrThrow(), unit);
    });

    test('logs the failure once at the guard boundary', () async {
      final messages = _captureLogs();
      await guardDbCall<int>(
        () async => throw StateError('No element'),
        operation: 'selectTask',
      );
      expect(messages, hasLength(1));
      expect(messages.single, contains('[selectTask]'));
      expect(messages.single, contains('NotFoundError'));
    });
  });

  group('TodoRepository', () {
    late TodoDatabase database;
    late TodoRepository repository;

    setUp(() {
      database = TodoDatabase(NativeDatabase.memory());
      repository = TodoRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('round-trips Drift DataClass rows to freezed models', () async {
      const list = TodoList(id: 'list_1', title: 'Work');
      final write = await repository.writeLists('acct', const [list]);
      expect(write.isSuccess(), isTrue);

      final rows = await database.selectTodoListRecords('acct');
      expect(rows.single.id, 'list_1');

      final reloaded = await repository.preloadAccount('acct');
      expect(reloaded.isSuccess(), isTrue);
      expect(repository.readCachedLists('acct')!.single.title, 'Work');
    });

    test('returns DatabaseError when a stored payload is corrupted', () async {
      await database
          .into(database.todoListRecords)
          .insert(
            TodoListRecordsCompanion.insert(
              accountKey: 'acct',
              id: 'broken',
              position: 0,
              payloadJson: '{"id":',
            ),
          );

      final result = await repository.preloadAccount('acct');
      final error = result.exceptionOrNull();
      expect(error, isA<DatabaseError>());
      expect(
        (error! as DatabaseError).message,
        'A stored record could not be decoded.',
      );
    });

    test('deleteAccountRecords clears rows and cache', () async {
      await repository.writeLists('acct', const [
        TodoList(id: 'list_1', title: 'Work'),
      ]);
      expect(repository.readCachedLists('acct'), isNotNull);

      final cleared = await repository.deleteAccountRecords('acct');
      expect(cleared.isSuccess(), isTrue);
      expect(await database.selectTodoListRecords('acct'), isEmpty);
      expect(repository.readCachedLists('acct'), isNull);
    });
  });
}

List<String> _captureLogs() {
  final messages = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    messages.add(message ?? '');
  };
  addTearDown(() => debugPrint = original);
  return messages;
}
