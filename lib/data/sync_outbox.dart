import 'sync_dirty_fields.dart';

enum SyncEntityType { group, list, task, step, setting }

enum SyncOpKind { upsert, delete }

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

/// In-memory ordered outbox with coalescing for non-in-flight ops.
class SyncOutboxQueue {
  SyncOutboxQueue([
    Iterable<SyncOutboxOp> initial = const [],
    Map<String, String> initialRemoteIds = const {},
  ]) {
    _ops.addAll(initial);
    _ops.sort((a, b) => a.seq.compareTo(b.seq));
    for (final op in _ops) {
      if (op.seq > _lastSeq) _lastSeq = op.seq;
    }
    _remoteIdByKey.addAll(initialRemoteIds);
  }

  final List<SyncOutboxOp> _ops = [];
  final Map<String, String> _remoteIdByKey = {};
  int _lastSeq = 0;
  int _inFlightUpToSeq = 0;

  bool get isEmpty => _ops.isEmpty;
  bool get isNotEmpty => _ops.isNotEmpty;
  List<SyncOutboxOp> get ops => List<SyncOutboxOp>.unmodifiable(_ops);
  Map<String, String> get remoteIdMap =>
      Map<String, String>.unmodifiable(_remoteIdByKey);

  static String remoteKey(SyncEntityType type, String localId) =>
      '${type.name}::$localId';

  void recordRemoteId(SyncEntityType type, String localId, String remoteId) {
    _remoteIdByKey[remoteKey(type, localId)] = remoteId;
  }

  String? resolveRemoteId(SyncEntityType type, String localId) =>
      _remoteIdByKey[remoteKey(type, localId)];

  void clearRemoteId(SyncEntityType type, String localId) {
    _remoteIdByKey.remove(remoteKey(type, localId));
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

  /// Acknowledges a single completed operation [seq].
  void ackOp(int seq) {
    _ops.removeWhere((op) => op.seq == seq);
  }

  /// Enqueues an upsert, coalescing with any pending (non-in-flight) upsert
  /// for the same entity.
  void enqueueUpsert({
    required SyncEntityType entityType,
    required String localId,
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
        fields: {...existing.fields, ...fields},
        stepIds: {...existing.stepIds, ...stepIds},
        baseNote: existing.baseNote ?? baseNote,
      );
      return;
    }
    _ops.add(
      SyncOutboxOp(
        seq: _nextSeq(),
        entityType: entityType,
        kind: SyncOpKind.upsert,
        localId: localId,
        fields: Set<String>.from(fields),
        stepIds: Set<String>.from(stepIds),
        baseNote: baseNote,
      ),
    );
  }

  /// Enqueues a deletion. If an un-pushed (non-in-flight) upsert exists for a
  /// never-synced item (`remoteId == null` and no resolved remoteId), both cancel out.
  void enqueueDelete({
    required SyncEntityType entityType,
    required String localId,
    String? remoteId,
    String? parentLocalId,
    String? parentRemoteId,
  }) {
    final effectiveRemoteId = remoteId ?? resolveRemoteId(entityType, localId);
    // Cancel any non-in-flight pending upsert for this item.
    var cancelledUncreatedUpsert = false;
    _ops.removeWhere((op) {
      if (op.seq > _inFlightUpToSeq &&
          op.entityType == entityType &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert) {
        if (effectiveRemoteId == null) {
          cancelledUncreatedUpsert = true;
        }
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
      // Never reached the server and no create is in flight.
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
    _ops.add(
      SyncOutboxOp(
        seq: _nextSeq(),
        entityType: entityType,
        kind: SyncOpKind.delete,
        localId: localId,
        remoteId: effectiveRemoteId,
        parentLocalId: parentLocalId,
        parentRemoteId: parentRemoteId,
      ),
    );
  }

  void enqueueSetting(String key) {
    final exists = _ops.any(
      (op) =>
          op.seq > _inFlightUpToSeq &&
          op.entityType == SyncEntityType.setting &&
          op.localId == key,
    );
    if (exists) return;
    _ops.add(
      SyncOutboxOp(
        seq: _nextSeq(),
        entityType: SyncEntityType.setting,
        kind: SyncOpKind.upsert,
        localId: key,
      ),
    );
  }

  bool hasPending(SyncEntityType type, String localId) =>
      _ops.any((op) => op.entityType == type && op.localId == localId);

  bool hasPendingAfter(SyncEntityType type, String localId, int seq) =>
      _ops.any(
        (op) => op.entityType == type && op.localId == localId && op.seq > seq,
      );

  Set<String> pendingLocalIds(SyncEntityType type) => {
    for (final op in _ops)
      if (op.entityType == type) op.localId,
  };

  Set<String> pendingDeletedRemoteIds(SyncEntityType type) => {
    for (final op in _ops)
      if (op.entityType == type &&
          op.kind == SyncOpKind.delete &&
          (op.remoteId ?? resolveRemoteId(type, op.localId)) != null)
        (op.remoteId ?? resolveRemoteId(type, op.localId))!,
  };

  Set<GroupDirtyField>? pendingGroupFields(String localId) {
    final fields = <GroupDirtyField>{};
    for (final op in _ops) {
      if (op.entityType == SyncEntityType.group &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert) {
        if (op.fields.isEmpty) return null;
        for (final name in op.fields) {
          final f = GroupDirtyField.values.where((e) => e.name == name);
          fields.addAll(f);
        }
      }
    }
    return fields.isEmpty ? null : fields;
  }

  Set<ListDirtyField>? pendingListFields(String localId) {
    final fields = <ListDirtyField>{};
    for (final op in _ops) {
      if (op.entityType == SyncEntityType.list &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert) {
        if (op.fields.isEmpty) return null;
        for (final name in op.fields) {
          final f = ListDirtyField.values.where((e) => e.name == name);
          fields.addAll(f);
        }
      }
    }
    return fields.isEmpty ? null : fields;
  }

  Set<TaskDirtyField>? pendingTaskFields(String localId) {
    final fields = <TaskDirtyField>{};
    for (final op in _ops) {
      if (op.entityType == SyncEntityType.task &&
          op.localId == localId &&
          op.kind == SyncOpKind.upsert) {
        if (op.fields.isEmpty) return null;
        for (final name in op.fields) {
          final f = TaskDirtyField.values.where((e) => e.name == name);
          fields.addAll(f);
        }
      }
    }
    return fields.isEmpty ? null : fields;
  }

  /// Drops any pending non-delete ops for items whose parent list no longer exists.
  void pruneOrphanedEntities({
    required Set<String> validGroupIds,
    required Set<String> validListIds,
    required Set<String> validTaskIds,
  }) {
    _ops.removeWhere((op) {
      if (op.kind == SyncOpKind.delete) return false;
      return switch (op.entityType) {
        SyncEntityType.group => !validGroupIds.contains(op.localId),
        SyncEntityType.list => !validListIds.contains(op.localId),
        SyncEntityType.task => !validTaskIds.contains(op.localId),
        SyncEntityType.step || SyncEntityType.setting => false,
      };
    });
  }

  void clear() {
    _ops.clear();
    _remoteIdByKey.clear();
    _lastSeq = 0;
    _inFlightUpToSeq = 0;
  }
}
