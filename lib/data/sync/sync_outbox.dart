enum SyncEntityType { group, list, task, step, attachment, setting }

enum SyncOpKind { upsert, delete }

typedef SyncEntityKey = ({SyncEntityType type, String localId});
typedef SyncRemoteKey = ({SyncEntityType type, String remoteId});

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

  SyncEntityKey get entityKey => (type: entityType, localId: localId);

  SyncRemoteKey? get remoteKey =>
      remoteId == null ? null : (type: entityType, remoteId: remoteId!);

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

  static const _dirtyProtectionTypes = [
    SyncEntityType.setting,
    SyncEntityType.group,
    SyncEntityType.list,
    SyncEntityType.task,
  ];

  static const _entityProtectionTypes = [
    SyncEntityType.group,
    SyncEntityType.list,
    SyncEntityType.task,
  ];

  final List<SyncOutboxOp> _ops = [];
  final Map<SyncEntityKey, int> _ackedEntitySeq = {};
  final Map<SyncRemoteKey, int> _deletedRemoteSeq = {};
  final Set<int> _dirtyUpsertSeqs = <int>{};
  final Set<int> _dirtyDeleteSeqs = <int>{};
  int _lastSeq = 0;
  int _inFlightUpToSeq = 0;

  bool get isEmpty => _ops.isEmpty;
  bool get isNotEmpty => _ops.isNotEmpty;
  int get lastSeq => _lastSeq;
  List<SyncOutboxOp> get ops => List<SyncOutboxOp>.unmodifiable(_ops);

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
    final targetKey = (type: type, localId: localId);
    var changed = false;
    for (var i = 0; i < _ops.length; i++) {
      final op = _ops[i];
      final needsSelf = op.entityKey == targetKey && op.remoteId == null;
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
    _ackedEntitySeq[op.entityKey] = commitSeq;
    if (op.remoteKey case final rKey? when op.kind == SyncOpKind.delete) {
      _deletedRemoteSeq[rKey] = commitSeq;
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
    final targetKey = (type: entityType, localId: localId);
    final idx = _ops.lastIndexWhere(
      (op) =>
          op.seq > _inFlightUpToSeq &&
          op.entityKey == targetKey &&
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
  bool cancelPendingUpserts(SyncEntityType entityType, String localId) =>
      _cancelPending((type: entityType, localId: localId), SyncOpKind.upsert);

  /// Cancels any non-in-flight pending delete ops for [entityType]/[localId].
  /// Returns true if at least one op was removed.
  bool cancelPendingDeletes(SyncEntityType entityType, String localId) =>
      _cancelPending((type: entityType, localId: localId), SyncOpKind.delete);

  bool _cancelPending(SyncEntityKey targetKey, SyncOpKind kind) {
    final before = _ops.length;
    _ops.removeWhere((op) {
      final match =
          op.seq > _inFlightUpToSeq &&
          op.entityKey == targetKey &&
          op.kind == kind;
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
    final targetKey = (type: entityType, localId: localId);
    var cancelledUncreatedUpsert = false;
    _ops.removeWhere((op) {
      if (op.seq > _inFlightUpToSeq &&
          op.entityKey == targetKey &&
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
          (op) => op.entityKey == targetKey && op.kind == SyncOpKind.upsert,
        )) {
      return;
    }
    final alreadyQueued = _ops.any(
      (op) =>
          op.seq > _inFlightUpToSeq &&
          op.entityKey == targetKey &&
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
    final targetKey = (type: SyncEntityType.setting, localId: key);
    final exists = _ops.any(
      (op) => op.seq > _inFlightUpToSeq && op.entityKey == targetKey,
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

  bool hasPending(SyncEntityType type, String localId) {
    final targetKey = (type: type, localId: localId);
    return _ops.any((op) => op.entityKey == targetKey);
  }

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
  }) => {
    for (final op in _ops)
      if (op.entityType == type && (includePriorPending || op.seq > sinceSeq))
        op.localId,
    for (final entry in _ackedEntitySeq.entries)
      if (entry.value > sinceSeq && entry.key.type == type) entry.key.localId,
  };

  /// Remote IDs with pending deletes or acknowledged deletes strictly after [sinceSeq].
  Set<String> deletedRemoteIdsSince(SyncEntityType type, int sinceSeq) => {
    ...pendingDeletedRemoteIds(type),
    for (final entry in _deletedRemoteSeq.entries)
      if (entry.value > sinceSeq && entry.key.type == type) entry.key.remoteId,
  };

  /// Drops pending non-delete ops for entities that no longer exist in local
  /// state. Returns `true` if any op was removed.
  bool pruneOrphanedEntities({
    required Set<String> validGroupIds,
    required Set<String>? validListIds,
    required Set<String> validTaskIds,
  }) {
    final validIdsByType = <SyncEntityType, Set<String>?>{
      SyncEntityType.group: validGroupIds,
      SyncEntityType.list: validListIds,
      SyncEntityType.task: validTaskIds,
      SyncEntityType.attachment: validTaskIds,
    };
    var changed = false;
    _ops.removeWhere((op) {
      if (op.kind == SyncOpKind.delete) return false;
      final validIds = validIdsByType[op.entityType];
      final targetId = op.entityType == SyncEntityType.attachment
          ? op.parentLocalId
          : op.localId;
      final orphaned =
          validIds != null && targetId != null && !validIds.contains(targetId);
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
    dirtyIdsByType: {
      for (final type in _dirtyProtectionTypes)
        type: modifiedLocalIdsSince(type, pullStartSeq),
    },
    pruneKeepIdsByType: {
      for (final type in _entityProtectionTypes)
        type: modifiedLocalIdsSince(
          type,
          pruneProtectSinceSeq,
          includePriorPending: false,
        ),
    },
    deletedRemotesByType: {
      for (final type in _entityProtectionTypes)
        type: deletedRemoteIdsSince(type, pullStartSeq),
    },
  );

  /// Captures current pending local IDs and pending delete tombstones without
  /// prune-protection sets (used for immediate realtime event reconciliation).
  OutboxPullProtection captureCurrentProtection() => OutboxPullProtection(
    dirtyIdsByType: {
      for (final type in _dirtyProtectionTypes) type: pendingLocalIds(type),
    },
    deletedRemotesByType: {
      for (final type in _entityProtectionTypes)
        type: pendingDeletedRemoteIds(type),
    },
  );
}

/// Snapshot of dirty local IDs and deleted remote IDs used by pull
/// reconciliation to protect concurrent local edits and delete tombstones.
class OutboxPullProtection {
  const OutboxPullProtection({
    this.dirtyIdsByType = const {},
    this.pruneKeepIdsByType = const {},
    this.deletedRemotesByType = const {},
  });

  final Map<SyncEntityType, Set<String>> dirtyIdsByType;
  final Map<SyncEntityType, Set<String>> pruneKeepIdsByType;
  final Map<SyncEntityType, Set<String>> deletedRemotesByType;

  Set<String> dirtyIds(SyncEntityType type) => dirtyIdsByType[type] ?? const {};

  Set<String> pruneKeepIds(SyncEntityType type) =>
      pruneKeepIdsByType[type] ?? const {};

  Set<String> deletedRemotes(SyncEntityType type) =>
      deletedRemotesByType[type] ?? const {};
}
