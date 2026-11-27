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

/// Drift table storing sync dirty entity IDs, pending remote deletions, and
/// durable background sync jobs (`kind = 'sync_job'`).
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

  Future<List<TodoListRecord>> selectTodoListRecords(String accountKey) {
    return (select(todoListRecords)
          ..where((t) => t.accountKey.equals(accountKey))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Stream<List<TodoListRecord>> watchTodoListRecords(String accountKey) {
    return (select(todoListRecords)
          ..where((t) => t.accountKey.equals(accountKey))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  /// Row-level diff upsert: updates/inserts present rows and prunes only
  /// removed IDs without wiping the table.
  Future<void> replaceTodoListRecords(
    String accountKey,
    List<TodoListRecordsCompanion> rows,
  ) {
    return transaction(() async {
      final keepIds = <String>[
        for (final row in rows)
          if (row.id.present) row.id.value,
      ];
      if (keepIds.isEmpty) {
        await (delete(
          todoListRecords,
        )..where((t) => t.accountKey.equals(accountKey))).go();
        return;
      }
      await (delete(todoListRecords)..where(
            (t) => t.accountKey.equals(accountKey) & t.id.isNotIn(keepIds),
          ))
          .go();
      await batch(
        (b) => b.insertAll(
          todoListRecords,
          rows,
          mode: InsertMode.insertOrReplace,
        ),
      );
    });
  }

  Future<List<ListGroupRecord>> selectListGroupRecords(String accountKey) {
    return (select(listGroupRecords)
          ..where((t) => t.accountKey.equals(accountKey))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Stream<List<ListGroupRecord>> watchListGroupRecords(String accountKey) {
    return (select(listGroupRecords)
          ..where((t) => t.accountKey.equals(accountKey))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  /// Row-level diff upsert for list groups.
  Future<void> replaceListGroupRecords(
    String accountKey,
    List<ListGroupRecordsCompanion> rows,
  ) {
    return transaction(() async {
      final keepIds = <String>[
        for (final row in rows)
          if (row.id.present) row.id.value,
      ];
      if (keepIds.isEmpty) {
        await (delete(
          listGroupRecords,
        )..where((t) => t.accountKey.equals(accountKey))).go();
        return;
      }
      await (delete(listGroupRecords)..where(
            (t) => t.accountKey.equals(accountKey) & t.id.isNotIn(keepIds),
          ))
          .go();
      await batch(
        (b) => b.insertAll(
          listGroupRecords,
          rows,
          mode: InsertMode.insertOrReplace,
        ),
      );
    });
  }

  Future<List<TaskItemRecord>> selectTaskItemRecords(String accountKey) {
    return (select(taskItemRecords)
          ..where((t) => t.accountKey.equals(accountKey))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
  }

  Stream<List<TaskItemRecord>> watchTaskItemRecords(String accountKey) {
    return (select(taskItemRecords)
          ..where((t) => t.accountKey.equals(accountKey))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .watch();
  }

  Future<void> upsertTaskItemRecord(TaskItemRecordsCompanion row) {
    return into(taskItemRecords).insertOnConflictUpdate(row);
  }

  Future<void> deleteTaskItemRecord(String accountKey, String id) {
    return (delete(taskItemRecords)
          ..where((t) => t.accountKey.equals(accountKey) & t.id.equals(id)))
        .go();
  }

  /// Row-level diff upsert for tasks.
  Future<void> replaceTaskItemRecords(
    String accountKey,
    List<TaskItemRecordsCompanion> rows,
  ) {
    return transaction(() async {
      final keepIds = <String>[
        for (final row in rows)
          if (row.id.present) row.id.value,
      ];
      if (keepIds.isEmpty) {
        await (delete(
          taskItemRecords,
        )..where((t) => t.accountKey.equals(accountKey))).go();
        return;
      }
      await (delete(taskItemRecords)..where(
            (t) => t.accountKey.equals(accountKey) & t.id.isNotIn(keepIds),
          ))
          .go();
      await batch(
        (b) => b.insertAll(
          taskItemRecords,
          rows,
          mode: InsertMode.insertOrReplace,
        ),
      );
    });
  }

  Future<List<SyncMutationRecord>> selectSyncMutationRecords(
    String accountKey, {
    String? kind,
  }) {
    final query = select(syncMutationRecords)
      ..where((t) => t.accountKey.equals(accountKey))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    if (kind != null) {
      query.where((t) => t.kind.equals(kind));
    }
    return query.get();
  }

  Stream<List<SyncMutationRecord>> watchSyncMutationRecords(
    String accountKey, {
    String? kind,
  }) {
    final query = select(syncMutationRecords)
      ..where((t) => t.accountKey.equals(accountKey))
      ..orderBy([(t) => OrderingTerm.asc(t.position)]);
    if (kind != null) {
      query.where((t) => t.kind.equals(kind));
    }
    return query.watch();
  }

  Future<void> upsertSyncMutationRecord(SyncMutationRecordsCompanion row) {
    return into(syncMutationRecords).insertOnConflictUpdate(row);
  }

  Future<void> deleteSyncMutationRecord(
    String accountKey, {
    required String kind,
    required String itemKey,
  }) {
    return (delete(syncMutationRecords)..where(
          (t) =>
              t.accountKey.equals(accountKey) &
              t.kind.equals(kind) &
              t.itemKey.equals(itemKey),
        ))
        .go();
  }

  /// Row-level diff upsert for outbox / remote-id records.
  Future<void> replaceSyncMutationRecords(
    String accountKey, {
    required String kind,
    required List<SyncMutationRecordsCompanion> rows,
  }) {
    return transaction(() async {
      final keepKeys = <String>[
        for (final row in rows)
          if (row.itemKey.present) row.itemKey.value,
      ];
      if (keepKeys.isEmpty) {
        await (delete(syncMutationRecords)..where(
              (t) => t.accountKey.equals(accountKey) & t.kind.equals(kind),
            ))
            .go();
        return;
      }
      await (delete(syncMutationRecords)..where(
            (t) =>
                t.accountKey.equals(accountKey) &
                t.kind.equals(kind) &
                t.itemKey.isNotIn(keepKeys),
          ))
          .go();
      await batch(
        (b) => b.insertAll(
          syncMutationRecords,
          rows,
          mode: InsertMode.insertOrReplace,
        ),
      );
    });
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
