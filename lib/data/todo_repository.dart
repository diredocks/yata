import 'dart:convert';

import 'package:result_dart/result_dart.dart';

import '../core/result/app_result.dart';
import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'todo_database.dart';

class _AccountCache {
  List<TodoList>? lists;
  List<ListGroup> groups = const [];
  List<TaskItem> tasks = const [];
  final Map<String, List<String>> mutationKeys = {};
  List<PendingStepDeletion> pendingDeletedSteps = const [];
}

/// Drift <-> freezed mapping, in-memory cache and guarded DB access.
class TodoRepository {
  TodoRepository(this._db);

  static const _deletedStepKind = 'deleted_step';
  static const _preloadedMutationKinds = [
    'deleted_list',
    'deleted_task',
    'deleted_group',
    'dirty_list',
    'dirty_group',
    'dirty_task',
  ];

  final TodoDatabase _db;
  final Map<String, _AccountCache> _cacheByScope = {};

  bool get persistToSqlite => _db.persistToSqlite;

  _AccountCache _cacheFor(String scopeKey) =>
      _cacheByScope.putIfAbsent(scopeKey, _AccountCache.new);

  List<TodoList>? readCachedLists(String scopeKey) => _cacheFor(scopeKey).lists;

  List<ListGroup> readCachedGroups(String scopeKey) =>
      _cacheFor(scopeKey).groups;

  List<TaskItem> readCachedTasks(String scopeKey) => _cacheFor(scopeKey).tasks;

  List<String> readCachedMutationKeys(String scopeKey, String kind) =>
      _cacheFor(scopeKey).mutationKeys[kind] ?? const [];

  List<PendingStepDeletion> readCachedPendingDeletedSteps(String scopeKey) =>
      _cacheFor(scopeKey).pendingDeletedSteps;

  /// Loads an account's rows from SQLite into the in-memory cache.
  AsyncAppResult<Unit> preloadAccount(String accountKey, {String? scopeKey}) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        final listRows = await _db.selectTodoListRecords(accountKey);
        final groupRows = await _db.selectListGroupRecords(accountKey);
        final taskRows = await _db.selectTaskItemRecords(accountKey);
        final mutationRows = <String, List<String>>{};
        for (final kind in _preloadedMutationKinds) {
          final rows = await _db.selectSyncMutationRecords(
            accountKey,
            kind: kind,
          );
          mutationRows[kind] = [for (final row in rows) row.itemKey];
        }
        final stepRows = await _db.selectSyncMutationRecords(
          accountKey,
          kind: _deletedStepKind,
        );

        // Decode first: a corrupt payload must not clobber the cache.
        final lists = _decodeTodoLists(listRows);
        final groups = _decodeListGroups(groupRows);
        final tasks = _decodeTaskItems(taskRows);
        final steps = [
          for (final row in stepRows) _decodePendingStepDeletion(row),
        ];

        final cache = _cacheFor(scopeKey ?? accountKey);
        cache.lists = lists.isEmpty ? null : List<TodoList>.unmodifiable(lists);
        cache.groups = List<ListGroup>.unmodifiable(groups);
        cache.tasks = List<TaskItem>.unmodifiable(tasks);
        cache.mutationKeys
          ..clear()
          ..addAll({
            for (final entry in mutationRows.entries)
              entry.key: List<String>.unmodifiable(entry.value),
          });
        cache.pendingDeletedSteps = List<PendingStepDeletion>.unmodifiable(
          steps,
        );
      }
      return unit;
    }, operation: 'preloadAccount');
  }

  AsyncAppResult<Unit> writeLists(
    String accountKey,
    List<TodoList> lists, {
    String? scopeKey,
  }) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.replaceTodoListRecords(
          accountKey,
          _encodeTodoLists(accountKey, lists),
        );
      }
      _cacheFor(scopeKey ?? accountKey).lists = List<TodoList>.unmodifiable(
        lists,
      );
      return unit;
    }, operation: 'writeLists');
  }

  AsyncAppResult<Unit> writeGroups(
    String accountKey,
    List<ListGroup> groups, {
    String? scopeKey,
  }) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.replaceListGroupRecords(
          accountKey,
          _encodeListGroups(accountKey, groups),
        );
      }
      _cacheFor(scopeKey ?? accountKey).groups = List<ListGroup>.unmodifiable(
        groups,
      );
      return unit;
    }, operation: 'writeGroups');
  }

  AsyncAppResult<Unit> writeTasks(
    String accountKey,
    List<TaskItem> tasks, {
    String? scopeKey,
  }) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.replaceTaskItemRecords(
          accountKey,
          _encodeTaskItems(accountKey, tasks),
        );
      }
      _cacheFor(scopeKey ?? accountKey).tasks = List<TaskItem>.unmodifiable(
        tasks,
      );
      return unit;
    }, operation: 'writeTasks');
  }

  AsyncAppResult<Unit> writeMutationKeys(
    String accountKey,
    String kind,
    Iterable<String> keys, {
    String? scopeKey,
  }) {
    return guardDbCall(() async {
      final list = List<String>.unmodifiable(keys);
      if (_db.persistToSqlite) {
        await _db.replaceSyncMutationRecords(
          accountKey,
          kind: kind,
          rows: [
            for (var i = 0; i < list.length; i++)
              SyncMutationRecordsCompanion.insert(
                accountKey: accountKey,
                kind: kind,
                itemKey: list[i],
                position: i,
                payloadJson: list[i],
              ),
          ],
        );
      }
      _cacheFor(scopeKey ?? accountKey).mutationKeys[kind] = list;
      return unit;
    }, operation: 'writeMutationKeys($kind)');
  }

  AsyncAppResult<Unit> writePendingDeletedSteps(
    String accountKey,
    List<PendingStepDeletion> items, {
    String? scopeKey,
  }) {
    return guardDbCall(() async {
      final list = List<PendingStepDeletion>.unmodifiable(items);
      if (_db.persistToSqlite) {
        await _db.replaceSyncMutationRecords(
          accountKey,
          kind: _deletedStepKind,
          rows: [
            for (var i = 0; i < list.length; i++)
              SyncMutationRecordsCompanion.insert(
                accountKey: accountKey,
                kind: _deletedStepKind,
                itemKey: '${list[i].taskRemoteId}::${list[i].stepRemoteId}',
                position: i,
                payloadJson: jsonEncode(list[i].toJson()),
              ),
          ],
        );
      }
      _cacheFor(scopeKey ?? accountKey).pendingDeletedSteps = list;
      return unit;
    }, operation: 'writePendingDeletedSteps');
  }

  AsyncAppResult<Unit> deleteAccountRecords(
    String accountKey, {
    String? scopeKey,
  }) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.deleteAllAccountRecords(accountKey);
      }
      _cacheByScope.remove(scopeKey ?? accountKey);
      return unit;
    }, operation: 'deleteAccountRecords');
  }

  List<TodoList> _decodeTodoLists(List<TodoListRecord> rows) => [
    for (final row in rows) _decodeTodoList(row),
  ];

  List<ListGroup> _decodeListGroups(List<ListGroupRecord> rows) => [
    for (final row in rows) _decodeListGroup(row),
  ];

  List<TaskItem> _decodeTaskItems(List<TaskItemRecord> rows) => [
    for (final row in rows) _decodeTaskItem(row),
  ];

  TodoList _decodeTodoList(TodoListRecord row) =>
      TodoList.fromJson(_decodePayload(row.payloadJson));

  ListGroup _decodeListGroup(ListGroupRecord row) =>
      ListGroup.fromJson(_decodePayload(row.payloadJson));

  TaskItem _decodeTaskItem(TaskItemRecord row) =>
      TaskItem.fromJson(_decodePayload(row.payloadJson));

  PendingStepDeletion _decodePendingStepDeletion(SyncMutationRecord row) =>
      PendingStepDeletion.fromJson(_decodePayload(row.payloadJson));

  Map<String, dynamic> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object payload.', payloadJson);
  }

  List<TodoListRecordsCompanion> _encodeTodoLists(
    String accountKey,
    List<TodoList> lists,
  ) => [
    for (var i = 0; i < lists.length; i++)
      TodoListRecordsCompanion.insert(
        accountKey: accountKey,
        id: lists[i].id,
        position: i,
        payloadJson: jsonEncode(lists[i].toJson()),
      ),
  ];

  List<ListGroupRecordsCompanion> _encodeListGroups(
    String accountKey,
    List<ListGroup> groups,
  ) => [
    for (var i = 0; i < groups.length; i++)
      ListGroupRecordsCompanion.insert(
        accountKey: accountKey,
        id: groups[i].id,
        position: i,
        payloadJson: jsonEncode(groups[i].toJson()),
      ),
  ];

  List<TaskItemRecordsCompanion> _encodeTaskItems(
    String accountKey,
    List<TaskItem> tasks,
  ) => [
    for (var i = 0; i < tasks.length; i++)
      TaskItemRecordsCompanion.insert(
        accountKey: accountKey,
        id: tasks[i].id,
        listId: tasks[i].listId,
        position: i,
        payloadJson: jsonEncode(tasks[i].toJson()),
      ),
  ];
}
