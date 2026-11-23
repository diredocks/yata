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
  Future<void> writeQueue = Future<void>.value();
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
    if (!_db.persistToSqlite) {
      return Future.value(const Success(unit));
    }
    return guardDbCall(() async {
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
      return unit;
    }, operation: 'preloadAccount');
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final cache = _cache;
    final next = cache.writeQueue.then((_) => action(), onError: (_) => action());
    cache.writeQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  AsyncAppResult<Unit> _persistWrite(
    String operation,
    Future<void> Function() write,
  ) {
    if (!_db.persistToSqlite) {
      return Future.value(const Success(unit));
    }
    return guardDbCall(() async {
      await _enqueueWrite(write);
      return unit;
    }, operation: operation);
  }

  AsyncAppResult<Unit> saveLists(List<TodoList> lists) {
    final snapshot = List<TodoList>.unmodifiable(lists);
    _cache.lists = snapshot;
    return _persistWrite(
      'saveLists',
      () => _db.replaceTodoListRecords(accountKey, [
        for (var i = 0; i < snapshot.length; i++)
          TodoListRecordsCompanion.insert(
            accountKey: accountKey,
            id: snapshot[i].id,
            position: i,
            payloadJson: jsonEncode(snapshot[i].toJson()),
          ),
      ]),
    );
  }

  AsyncAppResult<Unit> saveGroups(List<ListGroup> groups) {
    final snapshot = List<ListGroup>.unmodifiable(groups);
    _cache.groups = snapshot;
    return _persistWrite(
      'saveGroups',
      () => _db.replaceListGroupRecords(accountKey, [
        for (var i = 0; i < snapshot.length; i++)
          ListGroupRecordsCompanion.insert(
            accountKey: accountKey,
            id: snapshot[i].id,
            position: i,
            payloadJson: jsonEncode(snapshot[i].toJson()),
          ),
      ]),
    );
  }

  AsyncAppResult<Unit> saveTasks(List<TaskItem> tasks) {
    final snapshot = List<TaskItem>.unmodifiable(tasks);
    _cache.tasks = snapshot;
    return _persistWrite(
      'saveTasks',
      () => _db.replaceTaskItemRecords(accountKey, [
        for (var i = 0; i < snapshot.length; i++)
          TaskItemRecordsCompanion.insert(
            accountKey: accountKey,
            id: snapshot[i].id,
            listId: snapshot[i].listId,
            position: i,
            payloadJson: jsonEncode(snapshot[i].toJson()),
          ),
      ]),
    );
  }

  AsyncAppResult<Unit> saveMutationKeys(String kind, Iterable<String> keys) {
    final list = List<String>.unmodifiable(keys);
    _cache.mutationKeys[kind] = list;
    return _persistWrite(
      'saveMutationKeys($kind)',
      () => _db.replaceSyncMutationRecords(
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
      ),
    );
  }

  AsyncAppResult<Unit> savePendingDeletedSteps(
    List<PendingStepDeletion> items,
  ) {
    final list = List<PendingStepDeletion>.unmodifiable(items);
    _cache.pendingDeletedSteps = list;
    return _persistWrite(
      'savePendingDeletedSteps',
      () => _db.replaceSyncMutationRecords(
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
      ),
    );
  }

  AsyncAppResult<Unit> deleteAccountRecords() {
    final cache = _caches[_db]?.remove(scopeKey);
    if (!_db.persistToSqlite) {
      return Future.value(const Success(unit));
    }
    return guardDbCall(() async {
      final prior = cache?.writeQueue ?? Future<void>.value();
      await prior.then(
        (_) => _db.deleteAllAccountRecords(accountKey),
        onError: (_) => _db.deleteAllAccountRecords(accountKey),
      );
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
