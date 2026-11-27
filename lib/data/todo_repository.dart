import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final Set<String> pendingOrphanedAttachments = <String>{};
  Future<void>? attachmentCleanup;
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

  String? loadCachedEndpointUrl({Duration maxAge = const Duration(hours: 12)}) {
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
      final normalized = (groupsDeltaLink == null || groupsDeltaLink.isEmpty)
          ? null
          : groupsDeltaLink;
      _cache.groupsDeltaLink = normalized;
      writes.add((
        key: _groupsDeltaLinkKey,
        payload: normalized == null ? null : {'value': normalized},
      ));
    }
    if (updateFoldersDeltaLink) {
      final normalized = (foldersDeltaLink == null || foldersDeltaLink.isEmpty)
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

  /// Waits for all previously enqueued SQLite writes and pending attachment
  /// cleanups for this account to finish.
  Future<void> flushPendingWrites() async {
    await _cache.writeQueue;
    await _cache.attachmentCleanup;
  }

  static Future<
    ({List<TodoList> lists, List<ListGroup> groups, List<TaskItem> tasks})
  >
  _loadEntityTables(TodoDatabase db, String accountKey) async {
    final listRows = await db.selectTodoListRecords(accountKey);
    final groupRows = await db.selectListGroupRecords(accountKey);
    final taskRows = await db.selectTaskItemRecords(accountKey);
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
      final entities = await _loadEntityTables(_db, accountKey);
      final allMutations = await _db.selectSyncMutationRecords(accountKey);

      final groupedMutations = allMutations.groupListsBy((row) => row.kind);
      final outboxOps = _decodeRows(
        groupedMutations[_outboxKind] ?? const [],
        (r) => r.payloadJson,
        SyncOutboxOp.fromJson,
      );

      final cache = _cache;
      cache.lists = entities.lists.isEmpty ? null : entities.lists;
      cache.groups = entities.groups;
      cache.tasks = entities.tasks;
      cache.outbox = SyncOutboxQueue(outboxOps);
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
      final entities = await _loadEntityTables(_db, accountKey);

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
                for (final e in links.entries)
                  if ((e.key, e.value) case (final String k, final String v)
                      when v.isNotEmpty)
                    k: v,
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

  static Iterable<String> _attachmentLocalPaths(Iterable<TaskItem> tasks) =>
      tasks
          .expand((t) => t.attachments)
          .map((a) => a.localPath)
          .nonNulls
          .where((p) => p.isNotEmpty);

  static List<String> _unreferencedAttachmentPaths(
    List<TaskItem> previousTasks,
    List<TaskItem> nextTasks,
  ) {
    final orphaned = _attachmentLocalPaths(previousTasks).toSet();
    if (orphaned.isEmpty) return const [];
    orphaned.removeAll(_attachmentLocalPaths(nextTasks));
    return orphaned.toList(growable: false);
  }

  static Future<void> _deleteAttachmentFiles(List<String> paths) async {
    for (final localPath in paths) {
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
        final parent = file.parent;
        if (await parent.exists() && await parent.list().isEmpty) {
          await parent.delete();
        }
      } on Object catch (e) {
        _log.warning('Failed to delete local attachment cache: $e');
      }
    }
  }

  void _scheduleAttachmentCleanup(List<String> orphanedPaths) {
    if (orphanedPaths.isEmpty) return;
    final cache = _cache;
    cache.pendingOrphanedAttachments.addAll(orphanedPaths);
    if (cache.attachmentCleanup != null) return;
    late final Future<void> job;
    job =
        Future<void>.delayed(Duration.zero, () async {
          while (cache.pendingOrphanedAttachments.isNotEmpty) {
            final batch = cache.pendingOrphanedAttachments.toList(
              growable: false,
            );
            cache.pendingOrphanedAttachments.clear();
            final stillReferenced = _attachmentLocalPaths(cache.tasks).toSet();
            final toDelete = [
              for (final path in batch)
                if (!stillReferenced.contains(path)) path,
            ];
            if (toDelete.isNotEmpty) {
              await _deleteAttachmentFiles(toDelete);
            }
          }
        }).whenComplete(() {
          if (identical(cache.attachmentCleanup, job)) {
            cache.attachmentCleanup = null;
          }
        });
    cache.attachmentCleanup = job;
    unawaited(job);
  }

  TodoListRecordsCompanion _listCompanion(TodoList list, int position) =>
      TodoListRecordsCompanion.insert(
        accountKey: accountKey,
        id: list.id,
        position: position,
        payloadJson: jsonEncode(list.toJson()),
      );

  ListGroupRecordsCompanion _groupCompanion(ListGroup group, int position) =>
      ListGroupRecordsCompanion.insert(
        accountKey: accountKey,
        id: group.id,
        position: position,
        payloadJson: jsonEncode(group.toJson()),
      );

  TaskItemRecordsCompanion _taskCompanion(TaskItem task, int position) =>
      TaskItemRecordsCompanion.insert(
        accountKey: accountKey,
        id: task.id,
        listId: task.listId,
        position: position,
        payloadJson: jsonEncode(task.toJson()),
      );

  ({
    List<TaskItem> snapshot,
    List<TaskItemRecordsCompanion> upserts,
    List<String> deleteIds,
  })
  _diffTasks(List<TaskItem> previous, List<TaskItem> next) {
    final snapshot = List<TaskItem>.unmodifiable(next);
    final prevById = <String, ({TaskItem task, int position})>{
      for (final (i, item) in previous.indexed)
        item.id: (task: item, position: i),
    };
    final nextIds = <String>{};
    final upserts = <TaskItemRecordsCompanion>[];
    for (final (i, item) in snapshot.indexed) {
      nextIds.add(item.id);
      final prev = prevById[item.id];
      if (prev == null || prev.position != i || prev.task != item) {
        upserts.add(_taskCompanion(item, i));
      }
    }
    final deleteIds = [
      for (final item in previous)
        if (!nextIds.contains(item.id)) item.id,
    ];
    return (snapshot: snapshot, upserts: upserts, deleteIds: deleteIds);
  }

  ({List<TaskItem> nextTasks, List<TaskItemRecordsCompanion> upserts})
  _mergeTasks(
    List<TaskItem> previous,
    Iterable<TaskItem> upsertTasks, {
    Set<String> deleteIds = const {},
  }) {
    final uniqueById = {
      for (final t in upsertTasks)
        if (!deleteIds.contains(t.id)) t.id: t,
    };
    final pendingById = Map<String, TaskItem>.of(uniqueById);
    final built = <TaskItem>[];
    final positions = <String, int>{};
    for (final existing in previous) {
      if (deleteIds.contains(existing.id)) continue;
      final replacement = pendingById.remove(existing.id);
      if (replacement != null) {
        positions[replacement.id] = built.length;
        built.add(replacement);
      } else {
        built.add(existing);
      }
    }
    for (final added in pendingById.values) {
      positions[added.id] = built.length;
      built.add(added);
    }
    final upserts = [
      for (final task in uniqueById.values)
        _taskCompanion(task, positions[task.id]!),
    ];
    return (nextTasks: List<TaskItem>.unmodifiable(built), upserts: upserts);
  }

  Future<void> _applyOutboxDelta(OutboxPersistenceDelta delta) async {
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
  }

  AsyncAppResult<Unit> _persistTasksChange(
    String operation,
    List<TaskItem> previousTasks,
    List<TaskItem> nextTasks,
    Future<void> Function() write,
  ) {
    final snapshot = List<TaskItem>.unmodifiable(nextTasks);
    _cache.tasks = snapshot;
    _scheduleAttachmentCleanup(
      _unreferencedAttachmentPaths(previousTasks, snapshot),
    );
    return _persistWrite(operation, write);
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
    return _persistTasksChange(
      'upsertTask',
      current,
      nextTasks,
      () => _db.upsertTaskItemRecord(_taskCompanion(task, resolvedPosition)),
    );
  }

  /// Row-level batch upsert of [tasks] without rewriting unrelated rows.
  AsyncAppResult<Unit> upsertTasks(Iterable<TaskItem> tasks) {
    final taskList = tasks.toList(growable: false);
    if (taskList.isEmpty) {
      return Future.value(const Success(unit));
    }
    final current = _cache.tasks;
    final merged = _mergeTasks(current, taskList);
    return _persistTasksChange(
      'upsertTasks',
      current,
      merged.nextTasks,
      () => _db.transaction(() async {
        for (final companion in merged.upserts) {
          await _db.upsertTaskItemRecord(companion);
        }
      }),
    );
  }

  /// Row-level deletion of a single task without rewriting unrelated rows.
  AsyncAppResult<Unit> deleteTask(String taskId) {
    final current = _cache.tasks;
    final nextTasks = current
        .where((t) => t.id != taskId)
        .toList(growable: false);
    return _persistTasksChange(
      'deleteTask',
      current,
      nextTasks,
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
            .mapIndexed((i, item) => _listCompanion(item, i))
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
            .mapIndexed((i, item) => _groupCompanion(item, i))
            .toList(growable: false),
      ),
    );
  }

  /// Persists [tasks] using a row-level diff against the cached snapshot so
  /// pull and realtime merges only touch added, modified, repositioned, or
  /// removed rows.
  AsyncAppResult<Unit> saveTasks(List<TaskItem> tasks) {
    final current = _cache.tasks;
    final diff = _diffTasks(current, tasks);
    return _persistTasksChange(
      'saveTasks',
      current,
      diff.snapshot,
      () => _db.applyTaskItemDiff(
        accountKey,
        upserts: diff.upserts,
        deleteIds: diff.deleteIds,
      ),
    );
  }

  /// Atomically persists touched entity tables (groups, lists, row-level task
  /// upserts/deletes or full task diff) together with pending outbox deltas in
  /// a single SQLite transaction, while scheduling orphaned local attachment
  /// cleanup asynchronously outside the write queue.
  AsyncAppResult<Unit> persistSyncBatch({
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? fullTasks,
    Iterable<TaskItem> upsertTasks = const [],
    Iterable<String> deleteTaskIds = const [],
    bool saveOutbox = false,
  }) {
    final prevTasks = _cache.tasks;
    final groupSnapshot = groups != null
        ? List<ListGroup>.unmodifiable(groups)
        : null;
    final listSnapshot = lists != null
        ? List<TodoList>.unmodifiable(lists)
        : null;
    if (groupSnapshot != null) _cache.groups = groupSnapshot;
    if (listSnapshot != null) _cache.lists = listSnapshot;

    final taskUpserts = <TaskItemRecordsCompanion>[];
    final taskDeleteIds = <String>[];
    List<TaskItem>? nextTasks;

    if (fullTasks != null) {
      final diff = _diffTasks(prevTasks, fullTasks);
      taskUpserts.addAll(diff.upserts);
      taskDeleteIds.addAll(diff.deleteIds);
      nextTasks = diff.snapshot;
    } else {
      final upsertList = upsertTasks.toList(growable: false);
      final deleteSet = deleteTaskIds.toSet();
      if (upsertList.isNotEmpty || deleteSet.isNotEmpty) {
        final merged = _mergeTasks(prevTasks, upsertList, deleteIds: deleteSet);
        taskUpserts.addAll(merged.upserts);
        taskDeleteIds.addAll(deleteSet);
        nextTasks = merged.nextTasks;
      }
    }

    final outboxDelta = saveOutbox
        ? _cache.outbox.takePendingPersistenceDelta()
        : const OutboxPersistenceDelta();

    final orphanedPaths = nextTasks != null
        ? _unreferencedAttachmentPaths(prevTasks, nextTasks)
        : const <String>[];
    if (nextTasks != null) {
      _cache.tasks = nextTasks;
    }
    _scheduleAttachmentCleanup(orphanedPaths);

    final hasDbWork =
        groupSnapshot != null ||
        listSnapshot != null ||
        taskUpserts.isNotEmpty ||
        taskDeleteIds.isNotEmpty ||
        !outboxDelta.isEmpty;

    if (!_db.persistToSqlite || !hasDbWork) {
      return Future.value(const Success(unit));
    }

    return _persistWrite(
      'persistSyncBatch',
      () => _db.transaction(() async {
        if (groupSnapshot != null) {
          await _db.replaceListGroupRecords(
            accountKey,
            groupSnapshot
                .mapIndexed((i, item) => _groupCompanion(item, i))
                .toList(growable: false),
          );
        }
        if (listSnapshot != null) {
          await _db.replaceTodoListRecords(
            accountKey,
            listSnapshot
                .mapIndexed((i, item) => _listCompanion(item, i))
                .toList(growable: false),
          );
        }
        if (taskUpserts.isNotEmpty || taskDeleteIds.isNotEmpty) {
          await _db.applyTaskItemDiff(
            accountKey,
            upserts: taskUpserts,
            deleteIds: taskDeleteIds,
          );
        }
        if (!outboxDelta.isEmpty) {
          await _applyOutboxDelta(outboxDelta);
        }
      }),
    );
  }

  AsyncAppResult<Unit> saveOutbox() {
    final delta = _cache.outbox.takePendingPersistenceDelta();
    if (delta.isEmpty) {
      return Future.value(const Success(unit));
    }

    return _persistWrite(
      'saveOutbox',
      () => _db.transaction(() => _applyOutboxDelta(delta)),
    );
  }

  static List<T> _decodeRows<R, T>(
    Iterable<R> rows,
    String Function(R row) payloadOf,
    T Function(Map<String, dynamic> json) fromJson,
  ) => List<T>.unmodifiable(
    rows.map((row) => fromJson(_decodePayload(payloadOf(row)))),
  );

  AsyncAppResult<Unit> deleteAccountRecords() {
    final cache = _caches[_db]?.remove(scopeKey);
    cache?.pendingOrphanedAttachments.clear();
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

  static Map<String, dynamic> _decodePayload(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('Expected a JSON object payload.', payloadJson);
  }
}
