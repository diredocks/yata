import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/result/app_result.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'sync_job.dart';
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
  final Map<String, SyncJob> jobs = <String, SyncJob>{};
  final StreamController<List<SyncJob>> jobsController =
      StreamController<List<SyncJob>>.broadcast();
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
  static const _syncJobKind = 'sync_job';

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

  /// Reactive task stream backed by Drift when SQLite persistence is active.
  Stream<List<TaskItem>> watchTasks() {
    if (!_db.persistToSqlite) {
      return Stream<List<TaskItem>>.value(_cache.tasks);
    }
    return _db
        .watchTaskItemRecords(accountKey)
        .map(
          (rows) => List<TaskItem>.unmodifiable(
            rows.map(
              (row) => TaskItem.fromJson(_decodePayload(row.payloadJson)),
            ),
          ),
        );
  }

  /// Reactive list stream backed by Drift when SQLite persistence is active.
  Stream<List<TodoList>> watchLists() {
    if (!_db.persistToSqlite) {
      return Stream<List<TodoList>>.value(_cache.lists ?? const []);
    }
    return _db
        .watchTodoListRecords(accountKey)
        .map(
          (rows) => List<TodoList>.unmodifiable(
            rows.map(
              (row) => TodoList.fromJson(_decodePayload(row.payloadJson)),
            ),
          ),
        );
  }

  /// Reactive group stream backed by Drift when SQLite persistence is active.
  Stream<List<ListGroup>> watchGroups() {
    if (!_db.persistToSqlite) {
      return Stream<List<ListGroup>>.value(_cache.groups);
    }
    return _db
        .watchListGroupRecords(accountKey)
        .map(
          (rows) => List<ListGroup>.unmodifiable(
            rows.map(
              (row) => ListGroup.fromJson(_decodePayload(row.payloadJson)),
            ),
          ),
        );
  }

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
      final lists = listRows
          .map((row) => TodoList.fromJson(_decodePayload(row.payloadJson)))
          .toList(growable: false);
      final groups = groupRows
          .map((row) => ListGroup.fromJson(_decodePayload(row.payloadJson)))
          .toList(growable: false);
      final tasks = taskRows
          .map((row) => TaskItem.fromJson(_decodePayload(row.payloadJson)))
          .toList(growable: false);
      final groupedMutations = allMutations.groupListsBy((row) => row.kind);
      final outboxOps = (groupedMutations[_outboxKind] ?? const [])
          .map((row) => SyncOutboxOp.fromJson(_decodePayload(row.payloadJson)))
          .toList(growable: false);
      final remoteIdMap = <String, String>{
        for (final row in groupedMutations[_remoteIdMapKind] ?? const [])
          if (_decodePayload(row.payloadJson)['remoteId'] case final String id)
            row.itemKey: id,
      };
      final jobs = (groupedMutations[_syncJobKind] ?? const [])
          .map((row) => SyncJob.fromJson(_decodePayload(row.payloadJson)))
          .toList(growable: false);

      final cache = _cache;
      cache.lists = lists.isEmpty ? null : List<TodoList>.unmodifiable(lists);
      cache.groups = List<ListGroup>.unmodifiable(groups);
      cache.tasks = List<TaskItem>.unmodifiable(tasks);
      cache.outbox = SyncOutboxQueue(outboxOps, remoteIdMap);
      cache.jobs
        ..clear()
        ..addEntries(jobs.map((job) => MapEntry(job.jobId, job)));
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
    final opsSnapshot = _cache.outbox.ops;
    final remoteMapEntries = _cache.outbox.remoteIdMap.entries.toList(
      growable: false,
    );
    return _persistWrite('saveOutbox', () async {
      await _db.replaceSyncMutationRecords(
        accountKey,
        kind: _outboxKind,
        rows: opsSnapshot
            .mapIndexed(
              (i, op) => SyncMutationRecordsCompanion.insert(
                accountKey: accountKey,
                kind: _outboxKind,
                itemKey: op.seq.toString(),
                position: i,
                payloadJson: jsonEncode(op.toJson()),
              ),
            )
            .toList(growable: false),
      );
      await _db.replaceSyncMutationRecords(
        accountKey,
        kind: _remoteIdMapKind,
        rows: remoteMapEntries
            .mapIndexed(
              (i, entry) => SyncMutationRecordsCompanion.insert(
                accountKey: accountKey,
                kind: _remoteIdMapKind,
                itemKey: entry.key,
                position: i,
                payloadJson: jsonEncode({'remoteId': entry.value}),
              ),
            )
            .toList(growable: false),
      );
    });
  }

  /// Inserts or updates a durable background [SyncJob].
  AsyncAppResult<Unit> upsertSyncJob(SyncJob job) {
    _cache.jobs[job.jobId] = job;
    _emitCachedJobs();
    return _persistWrite(
      'upsertSyncJob',
      () => _db.upsertSyncMutationRecord(
        SyncMutationRecordsCompanion.insert(
          accountKey: accountKey,
          kind: _syncJobKind,
          itemKey: job.jobId,
          position: job.createdAt.toUtc().millisecondsSinceEpoch,
          payloadJson: jsonEncode(job.toJson()),
        ),
      ),
    );
  }

  /// Deletes a single durable background [SyncJob] by [jobId].
  AsyncAppResult<Unit> deleteSyncJob(String jobId) {
    _cache.jobs.remove(jobId);
    _emitCachedJobs();
    return _persistWrite(
      'deleteSyncJob',
      () => _db.deleteSyncMutationRecord(
        accountKey,
        kind: _syncJobKind,
        itemKey: jobId,
      ),
    );
  }

  /// Clears completed [SyncJob] rows for this account.
  AsyncAppResult<Unit> clearCompletedSyncJobs() {
    _cache.jobs.removeWhere((_, job) => job.isTerminal);
    _emitCachedJobs();
    return _persistWrite('clearCompletedSyncJobs', () async {
      final rows = await _db.selectSyncMutationRecords(
        accountKey,
        kind: _syncJobKind,
      );
      final completedKeys = rows
          .where(
            (row) =>
                SyncJob.fromJson(_decodePayload(row.payloadJson)).isTerminal,
          )
          .map((row) => row.itemKey)
          .toList(growable: false);
      await _db.deleteSyncMutationRecords(
        accountKey,
        kind: _syncJobKind,
        itemKeys: completedKeys,
      );
    });
  }

  /// Loads persisted [SyncJob] rows (optionally filtered by [lane] or readiness).
  AsyncAppResult<List<SyncJob>> loadSyncJobs({
    SyncJobLane? lane,
    bool onlyRunnable = false,
    DateTime? nowUtc,
  }) {
    final effectiveNow = nowUtc ?? DateTime.now().toUtc();
    if (!_db.persistToSqlite) {
      return Future.value(
        Success(
          _filterJobs(
            _cache.jobs.values,
            lane: lane,
            onlyRunnable: onlyRunnable,
            nowUtc: effectiveNow,
          ),
        ),
      );
    }
    return guardDbCall(() async {
      await _cache.writeQueue;
      final rows = await _db.selectSyncMutationRecords(
        accountKey,
        kind: _syncJobKind,
      );
      return _filterJobs(
        rows.map((row) => SyncJob.fromJson(_decodePayload(row.payloadJson))),
        lane: lane,
        onlyRunnable: onlyRunnable,
        nowUtc: effectiveNow,
      );
    }, operation: 'loadSyncJobs');
  }

  /// Watches persisted [SyncJob] rows reactively.
  Stream<List<SyncJob>> watchSyncJobs({SyncJobLane? lane}) {
    if (!_db.persistToSqlite) {
      return _cache.jobsController.stream.map(
        (jobs) => _filterJobs(jobs, lane: lane),
      );
    }
    return _db
        .watchSyncMutationRecords(accountKey, kind: _syncJobKind)
        .map(
          (rows) => _filterJobs(
            rows.map(
              (row) => SyncJob.fromJson(_decodePayload(row.payloadJson)),
            ),
            lane: lane,
          ),
        );
  }

  List<SyncJob> _filterJobs(
    Iterable<SyncJob> jobs, {
    SyncJobLane? lane,
    bool onlyRunnable = false,
    DateTime? nowUtc,
  }) {
    final checkTime = nowUtc ?? DateTime.now().toUtc();
    return List<SyncJob>.unmodifiable(
      jobs
          .where(
            (job) =>
                (lane == null || job.lane == lane) &&
                (!onlyRunnable || job.isReadyAt(checkTime)),
          )
          .sortedBy((job) => job.createdAt),
    );
  }

  void _emitCachedJobs() {
    if (!_cache.jobsController.isClosed) {
      _cache.jobsController.add(List<SyncJob>.unmodifiable(_cache.jobs.values));
    }
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
