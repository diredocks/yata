import 'dart:convert';

import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/app_result.dart';
import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'todo_database.dart';
import 'todo_settings_store.dart';

/// Database used when none is registered (widget tests / web bootstrapping).
final TodoDatabase sharedFallbackTodoDatabase = TodoDatabase();

class _AccountCache {
  List<TodoList>? lists;
  List<ListGroup> groups = const [];
  List<TaskItem> tasks = const [];
  final Map<String, List<String>> mutationKeys = {};
  List<PendingStepDeletion> pendingDeletedSteps = const [];
}

/// Drift <-> freezed mapping, in-memory cache and guarded DB access.
///
/// A repository instance is bound to one account/prefs session, so callers
/// never pass account or scope keys around.
class TodoRepository {
  TodoRepository(
    this._db, {
    this.accountKey = 'default',
    this.scopeKey = 'default',
  });

  factory TodoRepository.forSession(
    TodoDatabase database,
    TodoSettingsStore settings,
  ) => TodoRepository(
    database,
    accountKey: settings.accountKey,
    scopeKey: settings.scopeKey,
  );

  factory TodoRepository.forAccount(
    SharedPreferences prefs, {
    String? accountId,
    TodoDatabase? database,
  }) => TodoRepository.forSession(
    database ?? sharedFallbackTodoDatabase,
    TodoSettingsStore(prefs, accountId: accountId),
  );

  static const _deletedStepKind = 'deleted_step';

  /// Cache buckets are shared by every repository over the same database, so a
  /// second instance for the same session sees the same data.
  static final Expando<Map<String, _AccountCache>> _caches = Expando();

  final TodoDatabase _db;
  final String accountKey;
  final String scopeKey;

  _AccountCache get _cache {
    final perDb = _caches[_db] ??= <String, _AccountCache>{};
    return perDb.putIfAbsent(scopeKey, _AccountCache.new);
  }

  bool get persistToSqlite => _db.persistToSqlite;

  List<TodoList>? readCachedLists() => _cache.lists;

  List<ListGroup> readCachedGroups() => _cache.groups;

  List<TaskItem> readCachedTasks() => _cache.tasks;

  List<PendingStepDeletion> readCachedPendingDeletedSteps() =>
      _cache.pendingDeletedSteps;

  /// Loads this account's rows from SQLite into the in-memory cache.
  AsyncAppResult<Unit> preload() {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        final listRows = await _db.selectTodoListRecords(accountKey);
        final groupRows = await _db.selectListGroupRecords(accountKey);
        final taskRows = await _db.selectTaskItemRecords(accountKey);
        final allMutations = await _db.selectSyncMutationRecords(accountKey);

        // Decode first: a corrupt payload must not clobber the cache.
        final lists = [
          for (final row in listRows)
            TodoList.fromJson(_decodePayload(row.payloadJson)),
        ];
        final groups = [
          for (final row in groupRows)
            ListGroup.fromJson(_decodePayload(row.payloadJson)),
        ];
        final tasks = [
          for (final row in taskRows)
            TaskItem.fromJson(_decodePayload(row.payloadJson)),
        ];
        final mutationRows = <String, List<String>>{};
        final steps = <PendingStepDeletion>[];
        for (final row in allMutations) {
          if (row.kind == _deletedStepKind) {
            steps.add(
              PendingStepDeletion.fromJson(_decodePayload(row.payloadJson)),
            );
          } else {
            (mutationRows[row.kind] ??= <String>[]).add(row.itemKey);
          }
        }

        final cache = _cache;
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

  AsyncAppResult<Unit> saveLists(List<TodoList> lists) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.replaceTodoListRecords(accountKey, [
          for (var i = 0; i < lists.length; i++)
            TodoListRecordsCompanion.insert(
              accountKey: accountKey,
              id: lists[i].id,
              position: i,
              payloadJson: jsonEncode(lists[i].toJson()),
            ),
        ]);
      }
      _cache.lists = List<TodoList>.unmodifiable(lists);
      return unit;
    }, operation: 'saveLists');
  }

  AsyncAppResult<Unit> saveGroups(List<ListGroup> groups) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.replaceListGroupRecords(accountKey, [
          for (var i = 0; i < groups.length; i++)
            ListGroupRecordsCompanion.insert(
              accountKey: accountKey,
              id: groups[i].id,
              position: i,
              payloadJson: jsonEncode(groups[i].toJson()),
            ),
        ]);
      }
      _cache.groups = List<ListGroup>.unmodifiable(groups);
      return unit;
    }, operation: 'saveGroups');
  }

  AsyncAppResult<Unit> saveTasks(List<TaskItem> tasks) {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.replaceTaskItemRecords(accountKey, [
          for (var i = 0; i < tasks.length; i++)
            TaskItemRecordsCompanion.insert(
              accountKey: accountKey,
              id: tasks[i].id,
              listId: tasks[i].listId,
              position: i,
              payloadJson: jsonEncode(tasks[i].toJson()),
            ),
        ]);
      }
      _cache.tasks = List<TaskItem>.unmodifiable(tasks);
      return unit;
    }, operation: 'saveTasks');
  }

  AsyncAppResult<Unit> saveMutationKeys(String kind, Iterable<String> keys) {
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
      _cache.mutationKeys[kind] = list;
      return unit;
    }, operation: 'saveMutationKeys($kind)');
  }

  AsyncAppResult<Unit> savePendingDeletedSteps(
    List<PendingStepDeletion> items,
  ) {
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
      _cache.pendingDeletedSteps = list;
      return unit;
    }, operation: 'savePendingDeletedSteps');
  }

  AsyncAppResult<Unit> deleteAccountRecords() {
    return guardDbCall(() async {
      if (_db.persistToSqlite) {
        await _db.deleteAllAccountRecords(accountKey);
      }
      _caches[_db]?.remove(scopeKey);
      return unit;
    }, operation: 'deleteAccountRecords');
  }

  List<String> _readMutationKeys(String kind) =>
      _cache.mutationKeys[kind] ?? const [];

  List<String> loadPendingDeletedListRemoteIds() =>
      _readMutationKeys('deleted_list');

  AsyncAppResult<Unit> savePendingDeletedListRemoteIds(List<String> ids) =>
      saveMutationKeys('deleted_list', ids);

  List<String> loadPendingDeletedTaskRemoteIds() =>
      _readMutationKeys('deleted_task');

  AsyncAppResult<Unit> savePendingDeletedTaskRemoteIds(List<String> ids) =>
      saveMutationKeys('deleted_task', ids);

  List<String> loadPendingDeletedGroupRemoteIds() =>
      _readMutationKeys('deleted_group');

  AsyncAppResult<Unit> savePendingDeletedGroupRemoteIds(List<String> ids) =>
      saveMutationKeys('deleted_group', ids);

  List<PendingStepDeletion> loadPendingDeletedSteps() =>
      readCachedPendingDeletedSteps();

  Set<String> loadDirtyListIds() => _readMutationKeys('dirty_list').toSet();

  AsyncAppResult<Unit> saveDirtyListIds(Set<String> ids) =>
      saveMutationKeys('dirty_list', ids);

  Set<String> loadDirtyGroupIds() => _readMutationKeys('dirty_group').toSet();

  AsyncAppResult<Unit> saveDirtyGroupIds(Set<String> ids) =>
      saveMutationKeys('dirty_group', ids);

  Set<String> loadDirtyTaskIds() => _readMutationKeys('dirty_task').toSet();

  AsyncAppResult<Unit> saveDirtyTaskIds(Set<String> ids) =>
      saveMutationKeys('dirty_task', ids);

  Map<String, dynamic> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object payload.', payloadJson);
  }
}
