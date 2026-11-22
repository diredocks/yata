import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'todo_local_storage.dart';

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

/// Drift table storing sync dirty entity IDs and pending remote deletions.
class SyncMutationRecords extends Table {
  TextColumn get accountKey => text()();
  TextColumn get kind => text()();
  TextColumn get itemKey => text()();
  IntColumn get position => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {accountKey, kind, itemKey};
}

class _AccountDbCache {
  List<TodoList>? lists;
  List<ListGroup> groups = const [];
  List<TaskItem> tasks = const [];
  final Map<String, List<String>> mutationKeys = {};
  List<PendingStepDeletion> pendingDeletedSteps = const [];
}

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
  final Map<String, _AccountDbCache> _cacheByScope = {};

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return NativeDatabase.memory();
    }
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'yata.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }

  _AccountDbCache _cacheFor(String scopeKey) =>
      _cacheByScope.putIfAbsent(scopeKey, _AccountDbCache.new);

  /// Preloads an account's rows from the Drift SQLite tables into memory so
  /// synchronous Riverpod providers can read without async loading flicker.
  Future<void> preloadAccount(String accountKey, {String? scopeKey}) async {
    if (!_persistToSqlite) return;
    final cache = _cacheFor(scopeKey ?? accountKey);
    final lists = await fetchLists(accountKey);
    cache.lists = lists.isEmpty ? null : lists;
    cache.groups = await fetchGroups(accountKey);
    cache.tasks = await fetchTasks(accountKey);
    for (final kind in const [
      'deleted_list',
      'deleted_task',
      'deleted_group',
      'dirty_list',
      'dirty_group',
      'dirty_task',
    ]) {
      cache.mutationKeys[kind] = await fetchMutationKeys(accountKey, kind);
    }
    cache.pendingDeletedSteps = await fetchPendingDeletedSteps(accountKey);
  }

  List<TodoList>? readCachedLists(String scopeKey) => _cacheFor(scopeKey).lists;

  List<ListGroup> readCachedGroups(String scopeKey) =>
      _cacheFor(scopeKey).groups;

  List<TaskItem> readCachedTasks(String scopeKey) => _cacheFor(scopeKey).tasks;

  List<String> readCachedMutationKeys(String scopeKey, String kind) =>
      _cacheFor(scopeKey).mutationKeys[kind] ?? const [];

  List<PendingStepDeletion> readCachedPendingDeletedSteps(String scopeKey) =>
      _cacheFor(scopeKey).pendingDeletedSteps;

  Future<void> writeLists(
    String accountKey,
    List<TodoList> lists, {
    String? scopeKey,
  }) async {
    _cacheFor(scopeKey ?? accountKey).lists = List<TodoList>.unmodifiable(
      lists,
    );
    if (_persistToSqlite) {
      await replaceLists(accountKey, lists);
    }
  }

  Future<void> writeGroups(
    String accountKey,
    List<ListGroup> groups, {
    String? scopeKey,
  }) async {
    _cacheFor(scopeKey ?? accountKey).groups = List<ListGroup>.unmodifiable(
      groups,
    );
    if (_persistToSqlite) {
      await replaceGroups(accountKey, groups);
    }
  }

  Future<void> writeTasks(
    String accountKey,
    List<TaskItem> tasks, {
    String? scopeKey,
  }) async {
    _cacheFor(scopeKey ?? accountKey).tasks = List<TaskItem>.unmodifiable(
      tasks,
    );
    if (_persistToSqlite) {
      await replaceTasks(accountKey, tasks);
    }
  }

  Future<void> writeMutationKeys(
    String accountKey,
    String kind,
    Iterable<String> keys, {
    String? scopeKey,
  }) async {
    final list = List<String>.unmodifiable(keys);
    _cacheFor(scopeKey ?? accountKey).mutationKeys[kind] = list;
    if (_persistToSqlite) {
      await replaceMutationKeys(accountKey, kind, list);
    }
  }

  Future<void> writePendingDeletedSteps(
    String accountKey,
    List<PendingStepDeletion> items, {
    String? scopeKey,
  }) async {
    final list = List<PendingStepDeletion>.unmodifiable(items);
    _cacheFor(scopeKey ?? accountKey).pendingDeletedSteps = list;
    if (_persistToSqlite) {
      await replacePendingDeletedSteps(accountKey, list);
    }
  }

  Future<List<TodoList>> fetchLists(String accountKey) async {
    final rows =
        await (select(todoListRecords)
              ..where((t) => t.accountKey.equals(accountKey))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return [
      for (final row in rows)
        TodoList.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>),
    ];
  }

  Future<void> replaceLists(String accountKey, List<TodoList> lists) async {
    await transaction(() async {
      await (delete(
        todoListRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
      if (lists.isEmpty) return;
      await batch((b) {
        b.insertAll(todoListRecords, [
          for (var i = 0; i < lists.length; i++)
            TodoListRecordsCompanion.insert(
              accountKey: accountKey,
              id: lists[i].id,
              position: i,
              payloadJson: jsonEncode(lists[i].toJson()),
            ),
        ]);
      });
    });
  }

  Future<List<ListGroup>> fetchGroups(String accountKey) async {
    final rows =
        await (select(listGroupRecords)
              ..where((t) => t.accountKey.equals(accountKey))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return [
      for (final row in rows)
        ListGroup.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>),
    ];
  }

  Future<void> replaceGroups(String accountKey, List<ListGroup> groups) async {
    await transaction(() async {
      await (delete(
        listGroupRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
      if (groups.isEmpty) return;
      await batch((b) {
        b.insertAll(listGroupRecords, [
          for (var i = 0; i < groups.length; i++)
            ListGroupRecordsCompanion.insert(
              accountKey: accountKey,
              id: groups[i].id,
              position: i,
              payloadJson: jsonEncode(groups[i].toJson()),
            ),
        ]);
      });
    });
  }

  Future<List<TaskItem>> fetchTasks(String accountKey) async {
    final rows =
        await (select(taskItemRecords)
              ..where((t) => t.accountKey.equals(accountKey))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return [
      for (final row in rows)
        TaskItem.fromJson(jsonDecode(row.payloadJson) as Map<String, dynamic>),
    ];
  }

  Future<void> replaceTasks(String accountKey, List<TaskItem> tasks) async {
    await transaction(() async {
      await (delete(
        taskItemRecords,
      )..where((t) => t.accountKey.equals(accountKey))).go();
      if (tasks.isEmpty) return;
      await batch((b) {
        b.insertAll(taskItemRecords, [
          for (var i = 0; i < tasks.length; i++)
            TaskItemRecordsCompanion.insert(
              accountKey: accountKey,
              id: tasks[i].id,
              listId: tasks[i].listId,
              position: i,
              payloadJson: jsonEncode(tasks[i].toJson()),
            ),
        ]);
      });
    });
  }

  Future<List<String>> fetchMutationKeys(String accountKey, String kind) async {
    final rows =
        await (select(syncMutationRecords)
              ..where(
                (t) => t.accountKey.equals(accountKey) & t.kind.equals(kind),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return [for (final row in rows) row.itemKey];
  }

  Future<void> replaceMutationKeys(
    String accountKey,
    String kind,
    Iterable<String> keys,
  ) async {
    final list = keys.toList();
    await transaction(() async {
      await (delete(syncMutationRecords)..where(
            (t) => t.accountKey.equals(accountKey) & t.kind.equals(kind),
          ))
          .go();
      if (list.isEmpty) return;
      await batch((b) {
        b.insertAll(syncMutationRecords, [
          for (var i = 0; i < list.length; i++)
            SyncMutationRecordsCompanion.insert(
              accountKey: accountKey,
              kind: kind,
              itemKey: list[i],
              position: i,
              payloadJson: list[i],
            ),
        ]);
      });
    });
  }

  Future<List<PendingStepDeletion>> fetchPendingDeletedSteps(
    String accountKey,
  ) async {
    final rows =
        await (select(syncMutationRecords)
              ..where(
                (t) =>
                    t.accountKey.equals(accountKey) &
                    t.kind.equals('deleted_step'),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return [
      for (final row in rows)
        PendingStepDeletion.fromJson(
          jsonDecode(row.payloadJson) as Map<String, dynamic>,
        ),
    ];
  }

  Future<void> replacePendingDeletedSteps(
    String accountKey,
    List<PendingStepDeletion> items,
  ) async {
    await transaction(() async {
      await (delete(syncMutationRecords)..where(
            (t) =>
                t.accountKey.equals(accountKey) & t.kind.equals('deleted_step'),
          ))
          .go();
      if (items.isEmpty) return;
      await batch((b) {
        b.insertAll(syncMutationRecords, [
          for (var i = 0; i < items.length; i++)
            SyncMutationRecordsCompanion.insert(
              accountKey: accountKey,
              kind: 'deleted_step',
              itemKey: '${items[i].taskRemoteId}::${items[i].stepRemoteId}',
              position: i,
              payloadJson: jsonEncode(items[i].toJson()),
            ),
        ]);
      });
    });
  }

  Future<void> deleteAccountRecords(
    String accountKey, {
    String? scopeKey,
  }) async {
    _cacheByScope.remove(scopeKey ?? accountKey);
    if (_persistToSqlite) {
      await transaction(() async {
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
}
