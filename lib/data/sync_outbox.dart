enum SyncEntityType { group, list, task, step, attachment, setting }

enum SyncOpKind { upsert, delete }

typedef SyncEntityKey = ({SyncEntityType type, String localId});

/// A single ordered local mutation queued for push to Substrate.
class SyncOutboxOp {
  const SyncOutboxOp({
    required this.seq,
    required this.entityType,
    required this.kind,
    required this.localId,
    this.remoteId,
    this.parentLocalId,
    this.parentRemoteId,
    this.fields = const <String>{},
    this.stepIds = const <String>{},
    this.baseNote,
  });

  final int seq;
  final SyncEntityType entityType;
  final SyncOpKind kind;
  final String localId;
  final String? remoteId;
  final String? parentLocalId;
  final String? parentRemoteId;
  final Set<String> fields;
  final Set<String> stepIds;
  final String? baseNote;

  String get key => '${entityType.name}::$localId';

  bool get isAttachmentUpload =>
      entityType == SyncEntityType.attachment && kind == SyncOpKind.upsert;

  SyncOutboxOp copyWith({
    int? seq,
    String? remoteId,
    String? parentRemoteId,
    Set<String>? fields,
    Set<String>? stepIds,
    String? baseNote,
  }) {
    return SyncOutboxOp(
      seq: seq ?? this.seq,
      entityType: entityType,
      kind: kind,
      localId: localId,
      remoteId: remoteId ?? this.remoteId,
      parentLocalId: parentLocalId,
      parentRemoteId: parentRemoteId ?? this.parentRemoteId,
      fields: fields ?? this.fields,
      stepIds: stepIds ?? this.stepIds,
      baseNote: baseNote ?? this.baseNote,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'seq': seq,
    'entityType': entityType.name,
    'kind': kind.name,
    'localId': localId,
    if (remoteId != null) 'remoteId': remoteId,
    if (parentLocalId != null) 'parentLocalId': parentLocalId,
    if (parentRemoteId != null) 'parentRemoteId': parentRemoteId,
    if (fields.isNotEmpty) 'fields': fields.toList(),
    if (stepIds.isNotEmpty) 'stepIds': stepIds.toList(),
    if (baseNote != null) 'baseNote': baseNote,
  };

  factory SyncOutboxOp.fromJson(Map<String, dynamic> json) {
    return SyncOutboxOp(
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      entityType: SyncEntityType.values.byName(json['entityType'] as String),
      kind: SyncOpKind.values.byName(json['kind'] as String),
      localId: json['localId'] as String,
      remoteId: json['remoteId'] as String?,
      parentLocalId: json['parentLocalId'] as String?,
      parentRemoteId: json['parentRemoteId'] as String?,
      fields: {
        for (final f in (json['fields'] as List<dynamic>? ?? const []))
          f as String,
      },
      stepIds: {
        for (final s in (json['stepIds'] as List<dynamic>? ?? const []))
          s as String,
      },
      baseNote: json['baseNote'] as String?,
    );
  }
}

/// Row-level diff describing pending persistence work for [SyncOutboxQueue].
class OutboxPersistenceDelta {
  const OutboxPersistenceDelta({
    this.upsertOps = const [],
    this.deleteSeqs = const [],
  });

  final List<SyncOutboxOp> upsertOps;
  final List<int> deleteSeqs;

  bool get isEmpty => upsertOps.isEmpty && deleteSeqs.isEmpty;
}

/// In-memory ordered outbox with coalescing for non-in-flight ops.
class SyncOutboxQueue {
  SyncOutboxQueue([Iterable<SyncOutboxOp> initial = const []]) {
    _ops.addAll(initial);
    _ops.sort((a, b) => a.seq.compareTo(b.seq));
    for (final op in _ops) {
      if (op.seq > _lastSeq) _lastSeq = op.seq;
    }
  }

  final List<SyncOutboxOp> _ops = [];
  final Map<String, int> _ackedEntitySeq = {};
  final Map<String, int> _deletedRemoteSeq = {};
  final Set<int> _dirtyUpsertSeqs = <int>{};
  final Set<int> _dirtyDeleteSeqs = <int>{};
  int _lastSeq = 0;
  int _inFlightUpToSeq = 0;

  bool get isEmpty => _ops.isEmpty;
  bool get isNotEmpty => _ops.isNotEmpty;
  int get lastSeq => _lastSeq;
  List<SyncOutboxOp> get ops => List<SyncOutboxOp>.unmodifiable(_ops);

  static String remoteKey(SyncEntityType type, String id) =>
      '${type.name}::$id';

  void _markUpsert(int seq) {
    _dirtyUpsertSeqs.add(seq);
    _dirtyDeleteSeqs.remove(seq);
  }

  void _markDelete(int seq) {
    _dirtyDeleteSeqs.add(seq);
    _dirtyUpsertSeqs.remove(seq);
  }

  OutboxPersistenceDelta takePendingPersistenceDelta() {
    if (_dirtyUpsertSeqs.isEmpty && _dirtyDeleteSeqs.isEmpty) {
      return const OutboxPersistenceDelta();
    }
    final upsertOps = [
      for (final op in _ops)
        if (_dirtyUpsertSeqs.contains(op.seq)) op,
    ];
    final deleteSeqs = _dirtyDeleteSeqs.toList(growable: false);
    _dirtyUpsertSeqs.clear();
    _dirtyDeleteSeqs.clear();
    return OutboxPersistenceDelta(upsertOps: upsertOps, deleteSeqs: deleteSeqs);
  }

  /// Stamps a newly assigned [remoteId] onto any pending outbox ops that
  /// reference [localId] directly or as their parent task (e.g., a delete or
  /// attachment op queued while the entity's create POST was still in flight).
  bool backfillRemoteId(SyncEntityType type, String localId, String remoteId) {
    var changed = false;
    for (var i = 0; i < _ops.length; i++) {
      final op = _ops[i];
      final needsSelf =
          op.entityType == type && op.localId == localId && op.remoteId == null;
      final needsParent =
          type == SyncEntityType.task &&
          op.parentLocalId == localId &&
          op.parentRemoteId == null;
      if (!needsSelf && !needsParent) continue;
      _ops[i] = op.copyWith(
        remoteId: needsSelf ? remoteId : op.remoteId,
        parentRemoteId: needsParent ? remoteId : op.parentRemoteId,
      );
      _markUpsert(op.seq);
      changed = true;
    }
    return changed;
  }

  int _nextSeq() => ++_lastSeq;

  /// Marks ops up to [maxSeq] as currently being pushed so new mutations
  /// during an in-flight push are never merged into the active batch.
  List<SyncOutboxOp> beginBatch() {
    if (_ops.isEmpty) {
      _inFlightUpToSeq = _lastSeq;
      return const [];
    }
    _inFlightUpToSeq = _ops.last.seq;
    return List<SyncOutboxOp>.unmodifiable(_ops);
  }

  void endBatch() {
    _inFlightUpToSeq = 0;
  }

  /// Acknowledges completed operation [ackedSeqs], recording monotonic commit
  /// sequences for concurrent pull reconciliation and delete tombstones.
  void ackBatch(Iterable<int> ackedSeqs) {
    for (final seq in ackedSeqs) {
      ackOp(seq);
    }
  }

  void ackOp(int seq) {
    final idx = _ops.indexWhere((op) => op.seq == seq);
    if (idx < 0) return;
    final op = _ops.removeAt(idx);
    _markDelete(seq);
    final commitSeq = _nextSeq();
    _ackedEntitySeq[op.key] = commitSeq;
    if (op.kind == SyncOpKind.delete && op.remoteId != null) {
      _deletedRemoteSeq[remoteKey(op.entityType, op.remoteId!)] = commitSeq;
    }
  }

  /// Enqueues an upsert, coalescing with any pending (non-in-flight) upsert
  /// for the same entity.
  void enqueueUpsert({
    required SyncEntityType entityType,
    required String localId,
    String? parentLocalId,
    String? parentRemoteId,
    Set<String> fields = const <String>{},
    Set<String> stepIds = const <String>{},
    String? baseNote,
  }) {
    final idx = _ops.lastIndexWhere(
      (op) =>
          op.seq > _inFlightUpToSeq &&
          op.entityType == entityType &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert,
    );
    if (idx >= 0) {
      final existing = _ops[idx];
      _ops[idx] = existing.copyWith(
        parentRemoteId: parentRemoteId ?? existing.parentRemoteId,
        fields: {...existing.fields, ...fields},
        stepIds: {...existing.stepIds, ...stepIds},
        baseNote: existing.baseNote ?? baseNote,
      );
      _markUpsert(existing.seq);
      return;
    }
    final newOp = SyncOutboxOp(
      seq: _nextSeq(),
      entityType: entityType,
      kind: SyncOpKind.upsert,
      localId: localId,
      parentLocalId: parentLocalId,
      parentRemoteId: parentRemoteId,
      fields: Set<String>.from(fields),
      stepIds: Set<String>.from(stepIds),
      baseNote: baseNote,
    );
    _ops.add(newOp);
    _markUpsert(newOp.seq);
  }

  /// Cancels any non-in-flight pending upsert ops for [entityType]/[localId].
  /// Returns true if at least one op was removed.
  bool cancelPendingUpserts(SyncEntityType entityType, String localId) {
    final before = _ops.length;
    _ops.removeWhere((op) {
      final match =
          op.seq > _inFlightUpToSeq &&
          op.entityType == entityType &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert;
      if (match) _markDelete(op.seq);
      return match;
    });
    return _ops.length != before;
  }

  /// Enqueues a deletion. If an un-pushed (non-in-flight) upsert exists for a
  /// never-synced item (`remoteId == null`), both cancel out.
  void enqueueDelete({
    required SyncEntityType entityType,
    required String localId,
    String? remoteId,
    String? parentLocalId,
    String? parentRemoteId,
  }) {
    var cancelledUncreatedUpsert = false;
    _ops.removeWhere((op) {
      if (op.seq > _inFlightUpToSeq &&
          op.entityType == entityType &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert) {
        if (remoteId == null) {
          cancelledUncreatedUpsert = true;
        }
        _markDelete(op.seq);
        return true;
      }
      return false;
    });
    if (cancelledUncreatedUpsert &&
        !_ops.any(
          (op) =>
              op.entityType == entityType &&
              op.localId == localId &&
              op.kind == SyncOpKind.upsert,
        )) {
      return;
    }
    final alreadyQueued = _ops.any(
      (op) =>
          op.seq > _inFlightUpToSeq &&
          op.entityType == entityType &&
          op.localId == localId &&
          op.kind == SyncOpKind.delete,
    );
    if (alreadyQueued) return;
    final newOp = SyncOutboxOp(
      seq: _nextSeq(),
      entityType: entityType,
      kind: SyncOpKind.delete,
      localId: localId,
      remoteId: remoteId,
      parentLocalId: parentLocalId,
      parentRemoteId: parentRemoteId,
    );
    _ops.add(newOp);
    _markUpsert(newOp.seq);
  }

  void enqueueSetting(String key) {
    final exists = _ops.any(
      (op) =>
          op.seq > _inFlightUpToSeq &&
          op.entityType == SyncEntityType.setting &&
          op.localId == key,
    );
    if (exists) return;
    final newOp = SyncOutboxOp(
      seq: _nextSeq(),
      entityType: SyncEntityType.setting,
      kind: SyncOpKind.upsert,
      localId: key,
    );
    _ops.add(newOp);
    _markUpsert(newOp.seq);
  }

  bool hasPending(SyncEntityType type, String localId) =>
      _ops.any((op) => op.entityType == type && op.localId == localId);

  Set<String> pendingLocalIds(SyncEntityType type) => {
    for (final op in _ops)
      if (op.entityType == type) op.localId,
  };

  Set<String> pendingDeletedRemoteIds(SyncEntityType type) => {
    for (final op in _ops)
      if (op.entityType == type &&
          op.kind == SyncOpKind.delete &&
          op.remoteId != null)
        op.remoteId!,
  };

  /// Local IDs with pending ops (optionally restricted to `seq > sinceSeq`)
  /// or acknowledged commits strictly after [sinceSeq].
  Set<String> modifiedLocalIdsSince(
    SyncEntityType type,
    int sinceSeq, {
    bool includePriorPending = true,
  }) {
    final prefix = '${type.name}::';
    return {
      for (final op in _ops)
        if (op.entityType == type && (includePriorPending || op.seq > sinceSeq))
          op.localId,
      for (final entry in _ackedEntitySeq.entries)
        if (entry.value > sinceSeq && entry.key.startsWith(prefix))
          entry.key.substring(prefix.length),
    };
  }

  /// Remote IDs with pending deletes or acknowledged deletes strictly after [sinceSeq].
  Set<String> deletedRemoteIdsSince(SyncEntityType type, int sinceSeq) {
    final prefix = '${type.name}::';
    return {
      ...pendingDeletedRemoteIds(type),
      for (final entry in _deletedRemoteSeq.entries)
        if (entry.value > sinceSeq && entry.key.startsWith(prefix))
          entry.key.substring(prefix.length),
    };
  }

  /// Drops pending non-delete ops for entities that no longer exist in local
  /// state. Returns `true` if any op was removed.
  bool pruneOrphanedEntities({
    required Set<String> validGroupIds,
    required Set<String>? validListIds,
    required Set<String> validTaskIds,
  }) {
    var changed = false;
    _ops.removeWhere((op) {
      if (op.kind == SyncOpKind.delete) return false;
      final orphaned = switch (op.entityType) {
        SyncEntityType.group => !validGroupIds.contains(op.localId),
        SyncEntityType.list =>
          validListIds != null && !validListIds.contains(op.localId),
        SyncEntityType.task => !validTaskIds.contains(op.localId),
        SyncEntityType.attachment =>
          op.parentLocalId != null && !validTaskIds.contains(op.parentLocalId!),
        SyncEntityType.step || SyncEntityType.setting => false,
      };
      if (orphaned) {
        _markDelete(op.seq);
        changed = true;
      }
      return orphaned;
    });
    return changed;
  }

  /// Captures dirty-entity and delete-tombstone protection sets for applying a
  /// pull patch started at [pullStartSeq] with full-sync prune protection from
  /// [pruneProtectSinceSeq].
  OutboxPullProtection capturePullProtection({
    required int pullStartSeq,
    required int pruneProtectSinceSeq,
  }) => OutboxPullProtection(
    dirtySettings: modifiedLocalIdsSince(SyncEntityType.setting, pullStartSeq),
    dirtyGroups: modifiedLocalIdsSince(SyncEntityType.group, pullStartSeq),
    dirtyLists: modifiedLocalIdsSince(SyncEntityType.list, pullStartSeq),
    dirtyTasks: modifiedLocalIdsSince(SyncEntityType.task, pullStartSeq),
    pruneKeepGroups: modifiedLocalIdsSince(
      SyncEntityType.group,
      pruneProtectSinceSeq,
      includePriorPending: false,
    ),
    pruneKeepLists: modifiedLocalIdsSince(
      SyncEntityType.list,
      pruneProtectSinceSeq,
      includePriorPending: false,
    ),
    pruneKeepTasks: modifiedLocalIdsSince(
      SyncEntityType.task,
      pruneProtectSinceSeq,
      includePriorPending: false,
    ),
    deletedGroupRemotes: deletedRemoteIdsSince(
      SyncEntityType.group,
      pullStartSeq,
    ),
    deletedListRemotes: deletedRemoteIdsSince(
      SyncEntityType.list,
      pullStartSeq,
    ),
    deletedTaskRemotes: deletedRemoteIdsSince(
      SyncEntityType.task,
      pullStartSeq,
    ),
  );

  /// Captures current pending local IDs and pending delete tombstones without
  /// prune-protection sets (used for immediate realtime event reconciliation).
  OutboxPullProtection captureCurrentProtection() => OutboxPullProtection(
    dirtySettings: pendingLocalIds(SyncEntityType.setting),
    dirtyGroups: pendingLocalIds(SyncEntityType.group),
    dirtyLists: pendingLocalIds(SyncEntityType.list),
    dirtyTasks: pendingLocalIds(SyncEntityType.task),
    pruneKeepGroups: const {},
    pruneKeepLists: const {},
    pruneKeepTasks: const {},
    deletedGroupRemotes: pendingDeletedRemoteIds(SyncEntityType.group),
    deletedListRemotes: pendingDeletedRemoteIds(SyncEntityType.list),
    deletedTaskRemotes: pendingDeletedRemoteIds(SyncEntityType.task),
  );
}

/// Snapshot of dirty local IDs and deleted remote IDs used by pull
/// reconciliation to protect concurrent local edits and delete tombstones.
class OutboxPullProtection {
  const OutboxPullProtection({
    required this.dirtySettings,
    required this.dirtyGroups,
    required this.dirtyLists,
    required this.dirtyTasks,
    required this.pruneKeepGroups,
    required this.pruneKeepLists,
    required this.pruneKeepTasks,
    required this.deletedGroupRemotes,
    required this.deletedListRemotes,
    required this.deletedTaskRemotes,
  });

  final Set<String> dirtySettings;
  final Set<String> dirtyGroups;
  final Set<String> dirtyLists;
  final Set<String> dirtyTasks;
  final Set<String> pruneKeepGroups;
  final Set<String> pruneKeepLists;
  final Set<String> pruneKeepTasks;
  final Set<String> deletedGroupRemotes;
  final Set<String> deletedListRemotes;
  final Set<String> deletedTaskRemotes;
}
