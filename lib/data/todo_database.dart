import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'todo_database.g.dart';

/// Drift table storing todo lists per account.
class TodoListRecords extends Table {
  TextColumn get accountKey => text()();
  TextColumn get id => text()();
  IntColumn get position => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountKey, id};
}

/// Drift table storing list groups per account.
class ListGroupRecords extends Table {
  TextColumn get accountKey => text()();
  TextColumn get id => text()();
  IntColumn get position => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountKey, id};
}

/// Drift table storing tasks (including subtasks/steps) per account.
class TaskItemRecords extends Table {
  TextColumn get accountKey => text()();
  TextColumn get id => text()();
  TextColumn get listId => text()();
  IntColumn get position => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountKey, id};
}

/// Drift table storing sync outbox ops and sync metadata cursors.
class SyncMutationRecords extends Table {
  TextColumn get accountKey => text()();
  TextColumn get kind => text()();
  TextColumn get itemKey => text()();
  IntColumn get position => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountKey, kind, itemKey};
}

/// Row-level Drift DAO; no freezed models, so Drift codegen stays isolated.
@DriftDatabase(
  tables: [
    TodoListRecords,
    ListGroupRecords,
    TaskItemRecords,
    SyncMutationRecords,
  ],
)
class TodoDatabase extends _$TodoDatabase {
  TodoDatabase([QueryExecutor? executor])
    : _persistToSqlite =
          executor != null ||
          (kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST')),
      super(executor ?? _openConnection());

  final bool _persistToSqlite;

  /// In-memory sessions keep their data in the repository cache instead.
  bool get persistToSqlite => _persistToSqlite;

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return NativeDatabase.memory();
    }
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'yata.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        setup: (database) {
          database.execute('PRAGMA journal_mode=WAL;');
          database.execute('PRAGMA busy_timeout=5000;');
        },
      );
    });
  }

  /// Transactional row-level diff upsert: prunes only removed keys within
  /// [scope] and upserts present [rows] without wiping the table.
  Future<void> _replaceRecords<T extends Table, D>({
    required TableInfo<T, D> table,
    required List<Insertable<D>> rows,
    required List<String> keepKeys,
    required Expression<bool> Function(T t) scope,
    required GeneratedColumn<String> Function(T t) keyColumn,
  }) {
    return transaction(() async {
      if (keepKeys.isEmpty) {
        await (delete(table)..where(scope)).go();
        return;
      }
      await (delete(
        table,
      )..where((t) => scope(t) & keyColumn(t).isNotIn(keepKeys))).go();
      await batch(
        (b) => b.insertAll(table, rows, mode: InsertMode.insertOrReplace),
      );
    });
  }

  SimpleSelectStatement<$TodoListRecordsTable, TodoListRecord> _todoListQuery(
    String accountKey,
  ) => select(todoListRecords)
    ..where((t) => t.accountKey.equals(accountKey))
    ..orderBy([(t) => OrderingTerm.asc(t.position)]);

  Future<List<TodoListRecord>> selectTodoListRecords(String accountKey) =>
      _todoListQuery(accountKey).get();

  Future<void> replaceTodoListRecords(
    String accountKey,
    List<TodoListRecordsCompanion> rows,
  ) => _replaceRecords(
    table: todoListRecords,
    rows: rows,
    keepKeys: [
      for (final r in rows)
        if (r.id.present) r.id.value,
    ],
    scope: (t) => t.accountKey.equals(accountKey),
    keyColumn: (t) => t.id,
  );

  SimpleSelectStatement<$ListGroupRecordsTable, ListGroupRecord>
  _listGroupQuery(String accountKey) => select(listGroupRecords)
    ..where((t) => t.accountKey.equals(accountKey))
    ..orderBy([(t) => OrderingTerm.asc(t.position)]);

  Future<List<ListGroupRecord>> selectListGroupRecords(String accountKey) =>
      _listGroupQuery(accountKey).get();

  Future<void> replaceListGroupRecords(
    String accountKey,
    List<ListGroupRecordsCompanion> rows,
  ) => _replaceRecords(
    table: listGroupRecords,
    rows: rows,
    keepKeys: [
      for (final r in rows)
        if (r.id.present) r.id.value,
    ],
    scope: (t) => t.accountKey.equals(accountKey),
    keyColumn: (t) => t.id,
  );

  SimpleSelectStatement<$TaskItemRecordsTable, TaskItemRecord> _taskItemQuery(
    String accountKey,
  ) => select(taskItemRecords)
    ..where((t) => t.accountKey.equals(accountKey))
    ..orderBy([(t) => OrderingTerm.asc(t.position)]);

  Future<List<TaskItemRecord>> selectTaskItemRecords(String accountKey) =>
      _taskItemQuery(accountKey).get();

  Future<void> upsertTaskItemRecord(TaskItemRecordsCompanion row) =>
      into(taskItemRecords).insertOnConflictUpdate(row);

  Future<void> deleteTaskItemRecord(String accountKey, String id) => (delete(
    taskItemRecords,
  )..where((t) => t.accountKey.equals(accountKey) & t.id.equals(id))).go();

  /// Applies a minimal row-level diff for tasks (deletes removed IDs and
  /// upserts only created/changed/repositioned rows) in one transaction.
  Future<void> applyTaskItemDiff(
    String accountKey, {
    required List<TaskItemRecordsCompanion> upserts,
    required List<String> deleteIds,
  }) {
    if (upserts.isEmpty && deleteIds.isEmpty) return Future<void>.value();
    return transaction(() async {
      if (deleteIds.isNotEmpty) {
        await (delete(taskItemRecords)..where(
              (t) => t.accountKey.equals(accountKey) & t.id.isIn(deleteIds),
            ))
            .go();
      }
      if (upserts.isNotEmpty) {
        await batch(
          (b) => b.insertAll(
            taskItemRecords,
            upserts,
            mode: InsertMode.insertOrReplace,
          ),
        );
      }
    });
  }

  SimpleSelectStatement<$SyncMutationRecordsTable, SyncMutationRecord>
  _syncMutationQuery(String accountKey, {String? kind}) {
    final query = select(syncMutationRecords)
      ..where((t) => t.accountKey.equals(accountKey))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    if (kind != null) {
      query.where((t) => t.kind.equals(kind));
    }
    return query;
  }

  Future<List<SyncMutationRecord>> selectSyncMutationRecords(
    String accountKey, {
    String? kind,
  }) => _syncMutationQuery(accountKey, kind: kind).get();

  Future<void> upsertSyncMutationRecord(SyncMutationRecordsCompanion row) =>
      into(syncMutationRecords).insertOnConflictUpdate(row);

  Future<void> deleteSyncMutationRecords(
    String accountKey, {
    required String kind,
    required List<String> itemKeys,
  }) {
    if (itemKeys.isEmpty) return Future<void>.value();
    return (delete(syncMutationRecords)..where(
          (t) =>
              t.accountKey.equals(accountKey) &
              t.kind.equals(kind) &
              t.itemKey.isIn(itemKeys),
        ))
        .go();
  }

  Future<void> deleteAllAccountRecords(String accountKey) {
    return transaction(() async {
      await (delete(
        todoListRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
      await (delete(
        listGroupRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
      await (delete(
        taskItemRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
      await (delete(
        syncMutationRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
    });
  }
}
