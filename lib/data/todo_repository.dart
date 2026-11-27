import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'sync_outbox.dart';
import 'todo_database.dart';
import 'todo_settings_store.dart';

final _log = appLogFor('TodoRepository');

/// Database used when none is registered (widget tests / web bootstrapping).
final TodoDatabase sharedFallbackTodoDatabase = TodoDatabase();

class _AccountCache {
  List<TodoList>? lists;
  List<ListGroup> groups = const [];
  List<TaskItem> tasks = const [];
  SyncOutboxQueue outbox = SyncOutboxQueue();
  String? groupsDeltaLink;
  String? foldersDeltaLink;
  Map<String, String> taskDeltaLinks = const {};
  String? cachedEndpointUrl;
  DateTime? cachedEndpointFetchedAt;
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
  static const _syncMetaKind = 'sync_meta';

  static const _groupsDeltaLinkKey = 'groups_delta_link';
  static const _foldersDeltaLinkKey = 'folders_delta_link';
  static const _taskDeltaLinksKey = 'task_delta_links';
  static const _cachedEndpointKey = 'cached_endpoint';

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

  String? loadGroupsDeltaLink() => _cache.groupsDeltaLink;

  String? loadFoldersDeltaLink() => _cache.foldersDeltaLink;

  Map<String, String> loadTaskDeltaLinks() =>
      Map<String, String>.unmodifiable(_cache.taskDeltaLinks);

  String? loadCachedEndpointUrl({
    Duration maxAge = const Duration(hours: 12),
  }) {
    final url = _cache.cachedEndpointUrl;
    final fetchedAt = _cache.cachedEndpointFetchedAt;
    if (url == null || url.isEmpty || fetchedAt == null) return null;
    if (DateTime.now().toUtc().difference(fetchedAt.toUtc()) > maxAge) {
      return null;
    }
    return url;
  }

  AsyncAppResult<Unit> saveCachedEndpointUrl(String url) {
    final nowUtc = DateTime.now().toUtc();
    _cache.cachedEndpointUrl = url;
    _cache.cachedEndpointFetchedAt = nowUtc;
    return _persistWrite(
      'saveCachedEndpointUrl',
      () => _db.upsertSyncMutationRecord(
        SyncMutationRecordsCompanion.insert(
          accountKey: accountKey,
          kind: _syncMetaKind,
          itemKey: _cachedEndpointKey,
          position: 0,
          payloadJson: jsonEncode({
            'url': url,
            'fetchedAt': nowUtc.toIso8601String(),
          }),
        ),
      ),
    );
  }

  /// Atomically persists sync cursors in SQLite.
  AsyncAppResult<Unit> saveSyncMetaBatch({
    String? groupsDeltaLink,
    bool updateGroupsDeltaLink = false,
    String? foldersDeltaLink,
    bool updateFoldersDeltaLink = false,
    Map<String, String>? taskDeltaLinks,
  }) {
    final writes = <({String key, Map<String, dynamic>? payload})>[];
    if (updateGroupsDeltaLink) {
      final normalized =
          (groupsDeltaLink == null || groupsDeltaLink.isEmpty)
          ? null
          : groupsDeltaLink;
      _cache.groupsDeltaLink = normalized;
      writes.add((
        key: _groupsDeltaLinkKey,
        payload: normalized == null ? null : {'value': normalized},
      ));
    }
    if (updateFoldersDeltaLink) {
      final normalized =
          (foldersDeltaLink == null || foldersDeltaLink.isEmpty)
          ? null
          : foldersDeltaLink;
      _cache.foldersDeltaLink = normalized;
      writes.add((
        key: _foldersDeltaLinkKey,
        payload: normalized == null ? null : {'value': normalized},
      ));
    }
    if (taskDeltaLinks != null) {
      final normalized = Map<String, String>.unmodifiable({
        for (final entry in taskDeltaLinks.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      });
      _cache.taskDeltaLinks = normalized;
      writes.add((
        key: _taskDeltaLinksKey,
        payload: normalized.isEmpty ? null : {'links': normalized},
      ));
    }
    if (writes.isEmpty) {
      return Future.value(const Success(unit));
    }
    return _persistWrite(
      'saveSyncMetaBatch',
      () => _db.transaction(() async {
        for (final entry in writes) {
          if (entry.payload == null) {
            await _db.deleteSyncMutationRecords(
              accountKey,
              kind: _syncMetaKind,
              itemKeys: [entry.key],
            );
          } else {
            await _db.upsertSyncMutationRecord(
              SyncMutationRecordsCompanion.insert(
                accountKey: accountKey,
                kind: _syncMetaKind,
                itemKey: entry.key,
                position: 0,
                payloadJson: jsonEncode(entry.payload),
              ),
            );
          }
        }
      }),
    );
  }

  /// Waits for all previously enqueued SQLite writes for this account to finish.
  Future<void> flushPendingWrites() => _cache.writeQueue;

  Future<({List<TodoList> lists, List<ListGroup> groups, List<TaskItem> tasks})>
  _loadEntityTables() async {
    final listRows = await _db.selectTodoListRecords(accountKey);
    final groupRows = await _db.selectListGroupRecords(accountKey);
    final taskRows = await _db.selectTaskItemRecords(accountKey);
    return (
      lists: _decodeRows(listRows, (r) => r.payloadJson, TodoList.fromJson),
      groups: _decodeRows(groupRows, (r) => r.payloadJson, ListGroup.fromJson),
      tasks: _decodeRows(taskRows, (r) => r.payloadJson, TaskItem.fromJson),
    );
  }

  /// Loads this account's rows from SQLite into the in-memory cache.
  AsyncAppResult<Unit> preload() {
    if (!_db.persistToSqlite) {
      return Future.value(const Success(unit));
    }
    return guardDbCall(() async {
      await _cache.writeQueue;
      final entities = await _loadEntityTables();
      final allMutations = await _db.selectSyncMutationRecords(accountKey);

      final groupedMutations = allMutations.groupListsBy((row) => row.kind);
      final outboxOps = _decodeRows(
        groupedMutations[_outboxKind] ?? const [],
        (r) => r.payloadJson,
        SyncOutboxOp.fromJson,
      );
      final remoteIdMap = <String, String>{
        for (final row in groupedMutations[_remoteIdMapKind] ?? const [])
          if (_decodePayload(row.payloadJson)['remoteId'] case final String id)
            row.itemKey: id,
      };

      final cache = _cache;
      cache.lists = entities.lists.isEmpty ? null : entities.lists;
      cache.groups = entities.groups;
      cache.tasks = entities.tasks;
      cache.outbox = SyncOutboxQueue(outboxOps, remoteIdMap);
      _applyLoadedSyncMeta(cache, groupedMutations[_syncMetaKind] ?? const []);
      return unit;
    }, operation: 'preloadAccount');
  }

  /// Reloads entity tables (lists, groups, tasks) from SQLite into the
  /// in-memory cache without resetting [outbox] or sync metadata.
  AsyncAppResult<Unit> reloadEntities() {
    if (!_db.persistToSqlite) {
      return Future.value(const Success(unit));
    }
    return guardDbCall(() async {
      await _cache.writeQueue;
      final entities = await _loadEntityTables();

      final cache = _cache;
      cache.lists = entities.lists.isEmpty ? null : entities.lists;
      cache.groups = entities.groups;
      cache.tasks = entities.tasks;
      return unit;
    }, operation: 'reloadEntities');
  }

  void _applyLoadedSyncMeta(
    _AccountCache cache,
    List<SyncMutationRecord> rows,
  ) {
    cache.groupsDeltaLink = null;
    cache.foldersDeltaLink = null;
    cache.taskDeltaLinks = const {};
    cache.cachedEndpointUrl = null;
    cache.cachedEndpointFetchedAt = null;

    for (final row in rows) {
      try {
        final payload = _decodePayload(row.payloadJson);
        switch (row.itemKey) {
          case _groupsDeltaLinkKey:
            if (payload['value'] case final String v when v.isNotEmpty) {
              cache.groupsDeltaLink = v;
            }
          case _foldersDeltaLinkKey:
            if (payload['value'] case final String v when v.isNotEmpty) {
              cache.foldersDeltaLink = v;
            }
          case _taskDeltaLinksKey:
            if (payload['links'] case final Map links) {
              cache.taskDeltaLinks = Map<String, String>.unmodifiable({
                for (final entry in links.entries)
                  if (entry.key is String &&
                      entry.value is String &&
                      (entry.value as String).isNotEmpty)
                    entry.key as String: entry.value as String,
              });
            }
          case _cachedEndpointKey:
            final url = payload['url'];
            final fetchedRaw = payload['fetchedAt'];
            if (url is String && url.isNotEmpty && fetchedRaw is String) {
              final fetchedAt = DateTime.tryParse(fetchedRaw);
              if (fetchedAt != null) {
                cache.cachedEndpointUrl = url;
                cache.cachedEndpointFetchedAt = fetchedAt.toUtc();
              }
            }
        }
      } on Object catch (error) {
        _log.warning('discarding unreadable sync_meta ${row.itemKey}', error);
      }
    }
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

  /// Row-level upsert of a single task without rewriting unrelated rows.
  AsyncAppResult<Unit> upsertTask(TaskItem task, {int? position}) {
    final current = _cache.tasks;
    final existingIdx = current.indexWhere((t) => t.id == task.id);
    final resolvedPosition =
        position ?? (existingIdx >= 0 ? existingIdx : current.length);
    final nextTasks = [
      for (final item in current)
        if (item.id == task.id) task else item,
      if (existingIdx < 0) task,
    ];
    _cache.tasks = List<TaskItem>.unmodifiable(nextTasks);
    return _persistWrite(
      'upsertTask',
      () => _db.upsertTaskItemRecord(
        TaskItemRecordsCompanion.insert(
          accountKey: accountKey,
          id: task.id,
          listId: task.listId,
          position: resolvedPosition,
          payloadJson: jsonEncode(task.toJson()),
        ),
      ),
    );
  }

  /// Row-level batch upsert of [tasks] without rewriting unrelated rows.
  AsyncAppResult<Unit> upsertTasks(Iterable<TaskItem> tasks) {
    final taskList = tasks.toList(growable: false);
    if (taskList.isEmpty) {
      return Future.value(const Success(unit));
    }
    final uniqueById = {for (final t in taskList) t.id: t};
    final pendingById = Map<String, TaskItem>.of(uniqueById);
    final nextTasks = <TaskItem>[];
    final positions = <String, int>{};
    for (final existing in _cache.tasks) {
      final replacement = pendingById.remove(existing.id);
      if (replacement != null) {
        positions[replacement.id] = nextTasks.length;
        nextTasks.add(replacement);
      } else {
        nextTasks.add(existing);
      }
    }
    for (final added in pendingById.values) {
      positions[added.id] = nextTasks.length;
      nextTasks.add(added);
    }
    _cache.tasks = List<TaskItem>.unmodifiable(nextTasks);
    final toPersist = uniqueById.values.toList(growable: false);
    return _persistWrite(
      'upsertTasks',
      () => _db.transaction(() async {
        for (final task in toPersist) {
          await _db.upsertTaskItemRecord(
            TaskItemRecordsCompanion.insert(
              accountKey: accountKey,
              id: task.id,
              listId: task.listId,
              position: positions[task.id]!,
              payloadJson: jsonEncode(task.toJson()),
            ),
          );
        }
      }),
    );
  }

  /// Row-level deletion of a single task without rewriting unrelated rows.
  AsyncAppResult<Unit> deleteTask(String taskId) {
    _cache.tasks = List<TaskItem>.unmodifiable(
      _cache.tasks.where((t) => t.id != taskId),
    );
    return _persistWrite(
      'deleteTask',
      () => _db.deleteTaskItemRecord(accountKey, taskId),
    );
  }

  AsyncAppResult<Unit> saveLists(List<TodoList> lists) {
    final snapshot = List<TodoList>.unmodifiable(lists);
    _cache.lists = snapshot;
    return _persistWrite(
      'saveLists',
      () => _db.replaceTodoListRecords(
        accountKey,
        snapshot
            .mapIndexed(
              (i, item) => TodoListRecordsCompanion.insert(
                accountKey: accountKey,
                id: item.id,
                position: i,
                payloadJson: jsonEncode(item.toJson()),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  AsyncAppResult<Unit> saveGroups(List<ListGroup> groups) {
    final snapshot = List<ListGroup>.unmodifiable(groups);
    _cache.groups = snapshot;
    return _persistWrite(
      'saveGroups',
      () => _db.replaceListGroupRecords(
        accountKey,
        snapshot
            .mapIndexed(
              (i, item) => ListGroupRecordsCompanion.insert(
                accountKey: accountKey,
                id: item.id,
                position: i,
                payloadJson: jsonEncode(item.toJson()),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  AsyncAppResult<Unit> saveTasks(List<TaskItem> tasks) {
    final snapshot = List<TaskItem>.unmodifiable(tasks);
    _cache.tasks = snapshot;
    return _persistWrite(
      'saveTasks',
      () => _db.replaceTaskItemRecords(
        accountKey,
        snapshot
            .mapIndexed(
              (i, item) => TaskItemRecordsCompanion.insert(
                accountKey: accountKey,
                id: item.id,
                listId: item.listId,
                position: i,
                payloadJson: jsonEncode(item.toJson()),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  AsyncAppResult<Unit> saveOutbox() {
    final delta = _cache.outbox.takePendingPersistenceDelta();
    if (delta.isEmpty) {
      return Future.value(const Success(unit));
    }

    return _persistWrite(
      'saveOutbox',
      () => _db.transaction(() async {
        if (delta.deleteSeqs.isNotEmpty) {
          await _db.deleteSyncMutationRecords(
            accountKey,
            kind: _outboxKind,
            itemKeys: [for (final s in delta.deleteSeqs) s.toString()],
          );
        }
        for (final op in delta.upsertOps) {
          await _db.upsertSyncMutationRecord(
            SyncMutationRecordsCompanion.insert(
              accountKey: accountKey,
              kind: _outboxKind,
              itemKey: op.seq.toString(),
              position: op.seq,
              payloadJson: jsonEncode(op.toJson()),
            ),
          );
        }
        if (delta.deleteRemoteIdKeys.isNotEmpty) {
          await _db.deleteSyncMutationRecords(
            accountKey,
            kind: _remoteIdMapKind,
            itemKeys: delta.deleteRemoteIdKeys,
          );
        }
        for (final entry in delta.upsertRemoteIds.entries) {
          await _db.upsertSyncMutationRecord(
            SyncMutationRecordsCompanion.insert(
              accountKey: accountKey,
              kind: _remoteIdMapKind,
              itemKey: entry.key,
              position: 0,
              payloadJson: jsonEncode({'remoteId': entry.value}),
            ),
          );
        }
      }),
    );
  }

  List<T> _decodeRows<R, T>(
    Iterable<R> rows,
    String Function(R row) payloadOf,
    T Function(Map<String, dynamic> json) fromJson,
  ) => List<T>.unmodifiable(
    rows.map((row) => fromJson(_decodePayload(payloadOf(row)))),
  );

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
