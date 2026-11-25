import 'dart:convert';

import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/app_result.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'sync_outbox.dart';
import 'todo_database.dart';
import 'todo_settings_store.dart';

/// Database used when none is registered (widget tests / web bootstrapping).
final TodoDatabase sharedFallbackTodoDatabase = TodoDatabase();

class _AccountCache {
  List<TodoList>? lists;
  List<ListGroup> groups = const [];
  List<TaskItem> tasks = const [];
  SyncOutboxQueue outbox = SyncOutboxQueue();
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

  static const _outboxKind = 'outbox';
  static const _remoteIdMapKind = 'remote_id_map';

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

  SyncOutboxQueue get outbox => _cache.outbox;

  /// Waits for all previously enqueued SQLite writes for this account to finish.
  Future<void> flushPendingWrites() => _cache.writeQueue;

  /// Loads this account's rows from SQLite into the in-memory cache.
  AsyncAppResult<Unit> preload() {
    if (!_db.persistToSqlite) {
      return Future.value(const Success(unit));
    }
    return guardDbCall(() async {
      await _cache.writeQueue;
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
      final outboxOps = <SyncOutboxOp>[];
      final remoteIdMap = <String, String>{};
      for (final row in allMutations) {
        if (row.kind == _outboxKind) {
          outboxOps.add(SyncOutboxOp.fromJson(_decodePayload(row.payloadJson)));
        } else if (row.kind == _remoteIdMapKind) {
          final map = _decodePayload(row.payloadJson);
          final remoteId = map['remoteId'] as String?;
          if (remoteId != null) {
            remoteIdMap[row.itemKey] = remoteId;
          }
        }
      }

      final cache = _cache;
      cache.lists = lists.isEmpty ? null : List<TodoList>.unmodifiable(lists);
      cache.groups = List<ListGroup>.unmodifiable(groups);
      cache.tasks = List<TaskItem>.unmodifiable(tasks);
      cache.outbox = SyncOutboxQueue(outboxOps, remoteIdMap);
      return unit;
    }, operation: 'preloadAccount');
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() action) {
    final cache = _cache;
    final next = cache.writeQueue.then(
      (_) => action(),
      onError: (_) => action(),
    );
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

  AsyncAppResult<Unit> saveOutbox() {
    final opsSnapshot = _cache.outbox.ops;
    final remoteMapEntries = _cache.outbox.remoteIdMap.entries.toList(
      growable: false,
    );
    return _persistWrite('saveOutbox', () async {
      await _db.replaceSyncMutationRecords(
        accountKey,
        kind: _outboxKind,
        rows: [
          for (var i = 0; i < opsSnapshot.length; i++)
            SyncMutationRecordsCompanion.insert(
              accountKey: accountKey,
              kind: _outboxKind,
              itemKey: opsSnapshot[i].seq.toString(),
              position: i,
              payloadJson: jsonEncode(opsSnapshot[i].toJson()),
            ),
        ],
      );
      await _db.replaceSyncMutationRecords(
        accountKey,
        kind: _remoteIdMapKind,
        rows: [
          for (var i = 0; i < remoteMapEntries.length; i++)
            SyncMutationRecordsCompanion.insert(
              accountKey: accountKey,
              kind: _remoteIdMapKind,
              itemKey: remoteMapEntries[i].key,
              position: i,
              payloadJson: jsonEncode({'remoteId': remoteMapEntries[i].value}),
            ),
        ],
      );
    });
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

  Map<String, dynamic> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object payload.', payloadJson);
  }
}
