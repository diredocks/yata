import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';

import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../data/sync_outbox.dart';
import '../data/todo_repository.dart';
import '../data/todo_state.dart';
import '../models/account.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'background_sync_bridge.dart';
import 'microsoft/microsoft_todo_api.dart';
import 'microsoft/remote_change_reconciler.dart';
import 'microsoft/substrate_pull_engine.dart';
import 'microsoft/substrate_push_engine.dart';
import 'realtime_sync_controller.dart';
import 'sync_dispatcher.dart';
import '../core/network/http_guard.dart';

final _log = appLogFor('Sync');
final _realtimeLog = appLogFor('SyncRealtime');

enum SyncStatus { idle, syncing, success, error, requiresRelogin }

const _unset = Object();

class SyncState {
  const SyncState({
    this.status = SyncStatus.idle,
    this.lastSyncedAt,
    this.error,
  });

  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? error;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get requiresRelogin => status == SyncStatus.requiresRelogin;

  SyncState copyWith({
    SyncStatus? status,
    Object? lastSyncedAt = _unset,
    Object? error = _unset,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: identical(lastSyncedAt, _unset)
          ? this.lastSyncedAt
          : lastSyncedAt as DateTime?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncState &&
          status == other.status &&
          lastSyncedAt == other.lastSyncedAt &&
          error == other.error);

  @override
  int get hashCode => Object.hash(status, lastSyncedAt, error);

  @override
  String toString() =>
      'SyncState(status: $status, lastSyncedAt: $lastSyncedAt, error: $error)';
}

/// Host environment callbacks decouple [SyncCoordinator] from Riverpod so sync
/// orchestration, dual lanes, and realtime buffering stay pure Dart.
class SyncHost {
  const SyncHost({
    required this.readActiveAccount,
    required this.readTodoState,
    required this.readRepository,
    required this.nextId,
    required this.readTodoApi,
    required this.readBackgroundScheduler,
    required this.isRealtimeEnabled,
    required this.isPeriodicEnabled,
    required this.isStartupSyncEnabled,
    required this.commitPushBatch,
    required this.applyRemoteState,
    required this.persistAccountSyncStatus,
    required this.refreshProfileIfIncomplete,
    required this.onBackgroundDbReloaded,
    required this.onStateChanged,
  });

  final MicrosoftAccount? Function() readActiveAccount;
  final TodoState Function() readTodoState;
  final TodoRepository Function() readRepository;
  final String Function(String prefix) nextId;
  final MicrosoftTodoApi Function() readTodoApi;
  final BackgroundSyncScheduler Function() readBackgroundScheduler;
  final bool Function() isRealtimeEnabled;
  final bool Function() isPeriodicEnabled;
  final bool Function() isStartupSyncEnabled;
  final Future<void> Function(OutboxPushOutcome outcome) commitPushBatch;
  final Future<void> Function({
    List<ListGroup>? groups,
    List<TodoList>? lists,
    List<TaskItem>? tasks,
    Map<String, String>? remoteSettings,
  })
  applyRemoteState;
  final Future<void> Function(
    MicrosoftAccount active, {
    DateTime? lastSyncedAt,
    String? syncError,
    required bool clearSyncError,
  })
  persistAccountSyncStatus;
  final Future<void> Function(MicrosoftAccount active)
  refreshProfileIfIncomplete;
  final void Function() onBackgroundDbReloaded;
  final void Function(SyncState next) onStateChanged;
}

/// Pure-Dart sync coordinator owning the independent Push/Pull lanes,
/// foreground lifecycle, durable background handoff, and realtime intake.
class SyncCoordinator {
  SyncCoordinator({
    required this.host,
    SyncState initialState = const SyncState(),
  }) : _state = initialState;

  static const mutationDebounceDuration = Duration(milliseconds: 300);
  static const maxCoalesceDelay = Duration(seconds: 1);
  static const debounceDuration = Duration(milliseconds: 1500);
  static const foregroundDebounceDuration = Duration(milliseconds: 500);
  static const periodicSyncInterval = Duration(seconds: 120);
  static const _reconnectDebounceDuration = Duration(milliseconds: 500);
  static const _fallbackDebounceDuration = Duration(milliseconds: 200);
  static const _maxPendingRealtimeEvents = 200;

  final SyncHost host;

  late final SyncLane<PushCommand> _pushLane = SyncLane(
    maxCoalesceDelay: maxCoalesceDelay,
    coalesce: (queued, _) => queued,
    onDebounced: (command) => unawaited(_dispatch(command)),
  );
  late final SyncLane<PullCommand> _pullLane = SyncLane(
    maxCoalesceDelay: maxCoalesceDelay,
    coalesce: (queued, incoming) => queued.merge(incoming),
    onDebounced: (command) => unawaited(_dispatch(command)),
  );
  late final RealtimeSyncStream _realtimeStream = RealtimeSyncStream(
    apiOf: host.readTodoApi,
    isEnabled: host.isRealtimeEnabled,
    onEvent: (account, event) =>
        unawaited(_handleRealtimeEvent(account, event)),
    onReconnected: (_) => schedulePull(
      const PullCommand(PullScope.delta, SyncReason.realtimeReconnected),
      delay: _reconnectDebounceDuration,
    ),
  );

  final Queue<RealtimeEvent> _pendingRealtimeEvents = Queue<RealtimeEvent>();
  Timer? _periodicTimer;
  StreamSubscription<BackgroundDbChangedEvent>? _workerEventSub;

  SyncState _state;
  bool _disposed = false;
  bool _isForeground = true;
  int _pullGeneration = 0;
  AppError? _pushError;
  AppError? _pullError;
  bool _hasCompletedSync = false;
  String? _activeAccountId;

  SyncState get state => _state;

  bool get _hasActiveSync => _pushLane.isRunning || _pullLane.isRunning;

  bool get _delegatesTransfersToBackground =>
      host.readBackgroundScheduler().handlesTransfersInBackground;

  bool get _hasPendingForegroundPushOps {
    final ops = host.readRepository().outbox.ops;
    return _delegatesTransfersToBackground
        ? ops.any((op) => !op.isAttachmentUpload)
        : ops.isNotEmpty;
  }

  AppError? get _effectiveError {
    if (_pushError != null &&
        _pushError is! AuthError &&
        !_hasPendingForegroundPushOps) {
      _pushError = null;
    }
    if (_pullError is AuthError) return _pullError;
    if (_pushError is AuthError) return _pushError;
    return _pullError ?? _pushError;
  }

  static SyncStatus _statusForError(AppError error) => switch (error) {
    AuthError(:final requiresReauth) when requiresReauth =>
      SyncStatus.requiresRelogin,
    _ => SyncStatus.error,
  };

  /// Re-syncs coordinator channels with the currently active account and
  /// returns the initial [SyncState] for the current session.
  SyncState configureSession({
    required MicrosoftAccount? activeAccount,
    required bool realtimeEnabled,
    required bool periodicEnabled,
  }) {
    _disposed = false;
    _realtimeStream.reactivate();
    _workerEventSub ??= BackgroundWorkerEventBus.events.listen(
      _handleBackgroundWorkerEvent,
    );

    final nextAccountId = activeAccount?.id;
    if (nextAccountId != _activeAccountId) {
      _pushError = null;
      _pullError = null;
      _hasCompletedSync = false;
      _pendingRealtimeEvents.clear();
      _activeAccountId = nextAccountId;
    }

    if (activeAccount == null) {
      _realtimeStream.stop(resetReconnectFlag: true);
      _pendingRealtimeEvents.clear();
      _stopPeriodicSync();
      _resetChannels();
      _pushError = null;
      _pullError = null;
      _hasCompletedSync = false;
      _state = const SyncState();
      return _state;
    }

    if (_isForeground) {
      if (realtimeEnabled) {
        _realtimeStream.ensureStartedFor(activeAccount);
      } else {
        _realtimeStream.stop(resetReconnectFlag: true);
      }
      if (periodicEnabled) {
        _startPeriodicSync();
      } else {
        _stopPeriodicSync();
      }
    }

    _state = SyncState(lastSyncedAt: activeAccount.lastSyncedAt);
    return _state;
  }

  void dispose() {
    _disposed = true;
    _resetChannels();
    _stopPeriodicSync();
    _realtimeStream.dispose();
    _pendingRealtimeEvents.clear();
    unawaited(_workerEventSub?.cancel());
    _workerEventSub = null;
  }

  void _emit(SyncState next) {
    _state = next;
    if (!_disposed) {
      host.onStateChanged(next);
    }
  }

  void _publishState({DateTime? lastSyncedAt, bool preferIdle = false}) {
    if (_disposed) return;
    if (_hasActiveSync) {
      _emit(
        _state.copyWith(
          status: SyncStatus.syncing,
          lastSyncedAt: lastSyncedAt ?? _state.lastSyncedAt,
          error: null,
        ),
      );
      return;
    }
    final error = _effectiveError;
    final nextStatus = error != null
        ? _statusForError(error)
        : (preferIdle
              ? SyncStatus.idle
              : (_hasCompletedSync ? SyncStatus.success : SyncStatus.idle));
    _emit(
      _state.copyWith(
        status: nextStatus,
        lastSyncedAt: lastSyncedAt ?? _state.lastSyncedAt,
        error: error?.userMessage,
      ),
    );
  }

  Future<void> _persistAccountSyncStatus(
    MicrosoftAccount active, {
    DateTime? lastSyncedAt,
  }) {
    final error = _effectiveError;
    return host.persistAccountSyncStatus(
      active,
      lastSyncedAt: lastSyncedAt,
      syncError: error?.userMessage,
      clearSyncError: error == null,
    );
  }

  void _resetChannels() {
    _pushLane.reset();
    _pullLane.reset();
    _pullGeneration += 1;
  }

  void _startPeriodicSync() {
    if (_disposed || !_isForeground || _periodicTimer != null) return;
    _periodicTimer = Timer.periodic(periodicSyncInterval, (_) {
      if (!_disposed && _isForeground) {
        unawaited(syncNow(reason: SyncReason.periodic));
      }
    });
  }

  void _stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void onAppPaused() {
    if (_disposed || !_isForeground) return;
    _isForeground = false;
    _log.info('onAppPaused: stopping realtime & periodic sync');
    _stopPeriodicSync();
    _realtimeStream.stop(resetReconnectFlag: true);

    if (_pullLane.isRunning) {
      _log.info('onAppPaused: cancelling in-flight pull to prioritize push');
    }
    _pullLane.reset();
    _pullGeneration += 1;

    final pendingPush = _pushLane.pending;
    if (pendingPush != null && _pushLane.isDebouncing) {
      _pushLane.cancelPending();
      if (!_delegatesTransfersToBackground) {
        _log.info(
          'onAppPaused: flushing pending push reason=${pendingPush.reason.label}',
        );
        unawaited(_pushNow(reason: pendingPush.reason));
      }
    }
    _scheduleDurableBackgroundHandoff(
      reason: pendingPush?.reason ?? SyncReason.appPaused,
    );
  }

  void onAppResumed() {
    if (_disposed) return;
    _isForeground = true;
    final active = host.readActiveAccount();
    if (active == null) return;

    _log.info('onAppResumed: restarting realtime & scheduling delta sync');
    if (host.isRealtimeEnabled()) {
      _realtimeStream.ensureStartedFor(active);
    }
    if (host.isPeriodicEnabled()) {
      _startPeriodicSync();
    }
    scheduleDebouncedSync(
      delay: foregroundDebounceDuration,
      forceFullSync: false,
      reason: SyncReason.appResumed,
    );
  }

  Future<void> refresh({SyncReason reason = SyncReason.manual}) =>
      syncNow(forceFullSync: true, reason: reason);

  void syncOnSessionStart({bool accountChanged = false}) {
    if (!accountChanged && !host.isStartupSyncEnabled()) return;
    final account = host.readActiveAccount();
    if (account == null) return;

    if (accountChanged) {
      unawaited(
        syncNow(forceFullSync: true, reason: SyncReason.accountChanged),
      );
      return;
    }

    final needsFollowUpFull = account.lastSyncedAt != null;
    unawaited(() async {
      await syncNow(forceFullSync: false, reason: SyncReason.startup);
      if (!_disposed &&
          _isForeground &&
          needsFollowUpFull &&
          _pullError == null &&
          !_state.requiresRelogin) {
        await syncNow(forceFullSync: true, reason: SyncReason.startup);
      }
    }());
  }

  void scheduleDebouncedSync({
    Duration delay = debounceDuration,
    bool forceFullSync = false,
    SyncReason reason = SyncReason.debounced,
  }) => schedulePull(
    PullCommand(forceFullSync ? PullScope.full : PullScope.delta, reason),
    delay: delay,
  );

  void schedulePull(PullCommand command, {Duration delay = debounceDuration}) {
    if (_disposed || host.readActiveAccount() == null) return;

    final fireIn = _pullLane.submit(command, delay);
    _log.info(
      'schedulePull reason=${command.reason.label} '
      'scope=${command.scope.name} '
      'folders=${command.folderRemoteIds?.length ?? 0} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  void schedulePush({
    Duration delay = mutationDebounceDuration,
    SyncReason reason = SyncReason.localMutation,
  }) {
    if (_disposed || host.readActiveAccount() == null) return;

    final fireIn = _pushLane.submit(PushCommand(reason), delay);
    _log.info(
      'schedulePush reason=${reason.label} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  Future<void> syncNow({
    bool forceFullSync = false,
    SyncReason reason = SyncReason.manual,
  }) => _dispatch(
    PullCommand(forceFullSync ? PullScope.full : PullScope.delta, reason),
  );

  Future<void> _dispatch(SyncCommand command) {
    if (_disposed || host.readActiveAccount() == null) {
      return Future<void>.value();
    }
    return switch (command) {
      PushCommand() => _pushNow(reason: command.reason),
      PullCommand() => _dispatchPull(command),
    };
  }

  Future<void> _dispatchPull(PullCommand command) async {
    final outbox = host.readRepository().outbox;
    var effective = command;
    if (outbox.isNotEmpty) {
      effective = command.protectSince(outbox.lastSeq);
      if (_pullLane.isRunning) {
        unawaited(_pushNow(reason: command.reason));
      } else {
        await _pushNow(reason: command.reason, enqueueFollowUpPull: false);
        if (_disposed) return;
      }
    }
    await _pullNow(effective);
  }

  Future<void> _pushNow({
    SyncReason reason = SyncReason.localMutation,
    bool enqueueFollowUpPull = true,
  }) {
    if (_disposed || host.readActiveAccount() == null) {
      return Future<void>.value();
    }

    if (_delegatesTransfersToBackground) {
      final ops = host.readRepository().outbox.ops;
      if (!ops.any((op) => !op.isAttachmentUpload)) {
        return _enqueueBackgroundTransferIfPending(reason);
      }
    }

    final followUpFolders = <String>{};
    var lastSucceeded = false;

    if (!_pushLane.isRunning) {
      _emit(_state.copyWith(status: SyncStatus.syncing, error: null));
    }

    return _pushLane.run(
      PushCommand(reason),
      isCancelled: () => _disposed,
      onCoalesced: (merged) => _log.info(
        'push coalesced into in-flight push: reason=${merged.reason.label}',
      ),
      execute: (command) async {
        final outcome = await _pushOnce(reason: command.reason);
        if (outcome == null) {
          lastSucceeded = false;
          return;
        }
        lastSucceeded = true;
        followUpFolders.addAll(outcome.followUpPullFolderRemoteIds);
        final hasPendingDeletes =
            !_disposed &&
            !_pushLane.hasQueued &&
            host.readRepository().outbox.ops.any(
              (op) => op.kind == SyncOpKind.delete,
            );
        if (hasPendingDeletes) {
          _pushLane.enqueue(const PushCommand(SyncReason.outboxPending));
        }
      },
      onCycleComplete: () async {
        if (lastSucceeded && !_hasActiveSync) {
          final active = host.readActiveAccount();
          if (active != null) {
            await _persistAccountSyncStatus(active);
          }
        }
        _publishState();
        await _enqueueBackgroundTransferIfPending(reason);
        if (enqueueFollowUpPull &&
            followUpFolders.isNotEmpty &&
            _isForeground) {
          unawaited(
            _pullNow(
              PullCommand(
                PullScope.selective,
                reason,
                folderRemoteIds: Set<String>.of(followUpFolders),
              ),
            ),
          );
        } else if (!_hasActiveSync) {
          await _drainPendingRealtimeIfReady();
        }
      },
    );
  }

  Future<void> _pullNow(PullCommand command) {
    if (_disposed || host.readActiveAccount() == null) {
      return Future<void>.value();
    }

    DateTime? lastSyncedAt;
    var lastCancelled = false;

    if (!_pullLane.isRunning) {
      _emit(_state.copyWith(status: SyncStatus.syncing, error: null));
    }

    return _pullLane.run(
      command,
      isCancelled: () => _disposed,
      onCoalesced: (merged) => _log.info(
        'syncNow coalesced into in-flight sync: reason=${command.reason.label} '
        'scope=${command.scope.name} (queuedScope=${merged.scope.name})',
      ),
      execute: (cmd) async {
        final res = await _pullOnce(cmd);
        lastCancelled = res.cancelled;
        if (res.syncedAt != null) lastSyncedAt = res.syncedAt;
      },
      onCycleComplete: () async {
        _publishState(lastSyncedAt: lastSyncedAt, preferIdle: lastCancelled);
        if (!_hasActiveSync) {
          await _drainPendingRealtimeIfReady();
        }
      },
    );
  }

  Future<OutboxPushOutcome?> _pushOnce({required SyncReason reason}) async {
    final active = host.readActiveAccount();
    if (_disposed || active == null) return null;

    _log.info('push start account=${active.id} reason=${reason.label}');

    final result = await SubstratePushEngine(host.readTodoApi()).pushOutbox(
      readState: host.readTodoState,
      outbox: host.readRepository().outbox,
      nowUtc: DateTime.now().toUtc(),
      onItemCommitted: (pushOutcome) async {
        if (_disposed || host.readActiveAccount()?.id != active.id) return;
        await host.commitPushBatch(pushOutcome);
      },
      laneFilter: _delegatesTransfersToBackground
          ? PushLaneFilter.metadataOnly
          : PushLaneFilter.all,
      reason: reason.label,
    );

    if (_disposed) return null;

    return result.fold(
      (outcome) {
        _pushError = null;
        _hasCompletedSync = true;
        _log.info(
          'push success reason=${reason.label} '
          'pushedTasks=${outcome.pushedTasks.length}',
        );
        return outcome;
      },
      (error) async {
        _pushError = error;
        _log.info(
          'sync error reason=${reason.label} status=${_statusForError(error)} '
          'error=${error.describe()}',
        );
        await _persistAccountSyncStatus(active);
        return null;
      },
    );
  }

  Future<({bool ok, DateTime? syncedAt, bool cancelled})> _pullOnce(
    PullCommand command,
  ) async {
    final active = host.readActiveAccount();
    if (_disposed || active == null) {
      return (ok: false, syncedAt: null, cancelled: false);
    }

    final gen = ++_pullGeneration;
    final forceFullSync = command.scope == PullScope.full;

    _log.info(
      'sync start account=${active.id} reason=${command.reason.label} '
      'scope=${command.scope.name} forceFullSync=$forceFullSync',
    );

    final result = await SubstratePullEngine(host.readTodoApi()).pull(
      repository: host.readRepository(),
      readState: host.readTodoState,
      idGenerator: host.nextId,
      onReconciled: (outcome) async {
        if (_disposed || host.readActiveAccount()?.id != active.id) return;
        await host.applyRemoteState(
          groups: outcome.isSelective ? null : outcome.groups,
          lists: outcome.isSelective ? null : outcome.lists,
          tasks: outcome.tasks,
          remoteSettings: outcome.remoteSettings,
        );
      },
      forceFullSync: forceFullSync,
      onlyFolderRemoteIds: command.folderRemoteIds,
      isCancelled: () => _disposed || _pullGeneration != gen,
      pruneProtectSinceSeq: command.pruneProtectSinceSeq,
      reason: command.reason.label,
    );

    if (_disposed) {
      return (ok: false, syncedAt: null, cancelled: false);
    }

    return result.fold(
      (outcome) async {
        if (outcome.cancelled) {
          _log.info(
            'sync cancelled reason=${command.reason.label} '
            'forceFullSync=$forceFullSync',
          );
          return (ok: false, syncedAt: null, cancelled: true);
        }
        _pullError = null;
        _hasCompletedSync = true;
        _log.info(
          'sync success reason=${command.reason.label} '
          'forceFullSync=$forceFullSync '
          'lists=${outcome.lists.length} tasks=${outcome.tasks.length}',
        );
        await _persistAccountSyncStatus(active, lastSyncedAt: outcome.syncedAt);
        await host.refreshProfileIfIncomplete(active);
        return (ok: true, syncedAt: outcome.syncedAt, cancelled: false);
      },
      (error) async {
        _pullError = error;
        _log.info(
          'sync error reason=${command.reason.label} '
          'status=${_statusForError(error)} error=${error.describe()}',
        );
        await _persistAccountSyncStatus(active);
        return (ok: false, syncedAt: null, cancelled: false);
      },
    );
  }

  Future<void> _handleRealtimeEvent(
    MicrosoftAccount account,
    RealtimeEvent event,
  ) async {
    if (_disposed ||
        _realtimeStream.activeAccountId != account.id ||
        host.readActiveAccount()?.id != account.id) {
      return;
    }

    if (_hasActiveSync) {
      if (_pendingRealtimeEvents.length >= _maxPendingRealtimeEvents) {
        _pendingRealtimeEvents.clear();
        _pullLane.enqueue(
          const PullCommand(PullScope.full, SyncReason.realtimeOverflow),
        );
        _realtimeLog.info(
          'deferred queue overflow ($_maxPendingRealtimeEvents); '
          'scheduling full resync',
        );
        return;
      }
      _pendingRealtimeEvents.add(event);
      _realtimeLog.fine(
        'deferred event while syncing: type=${event.type} '
        'op=${event.operation} id=${shortSyncId(event.id)} '
        'queued=${_pendingRealtimeEvents.length}',
      );
      return;
    }

    final unhandled = await _applyRealtimeBatch(account, [event]);
    if (unhandled != null && !_disposed) {
      schedulePull(
        _fallbackCommandForRealtime(unhandled),
        delay: _fallbackDebounceDuration,
      );
    }
  }

  Future<void> _drainPendingRealtimeIfReady() async {
    if (_disposed || _pendingRealtimeEvents.isEmpty || _hasActiveSync) return;
    final active = host.readActiveAccount();
    if (active == null || _realtimeStream.activeAccountId != active.id) {
      _pendingRealtimeEvents.clear();
      return;
    }

    final batch = _pendingRealtimeEvents.toList(growable: false);
    _pendingRealtimeEvents.clear();
    _realtimeLog.info('draining ${batch.length} deferred realtime event(s)');

    final unhandled = await _applyRealtimeBatch(active, batch, fromQueue: true);
    if (unhandled != null && !_disposed) {
      await syncNow(forceFullSync: false, reason: SyncReason.realtimeEvent);
    }
  }

  Future<RealtimeEvent?> _applyRealtimeBatch(
    MicrosoftAccount account,
    List<RealtimeEvent> events, {
    bool fromQueue = false,
  }) async {
    if (_disposed ||
        _realtimeStream.activeAccountId != account.id ||
        host.readActiveAccount()?.id != account.id) {
      return null;
    }

    final parsed = parseRealtimeEventsBatch(events);
    final currentState = host.readTodoState();
    final protection = host.readRepository().outbox.captureCurrentProtection();

    final reconciled = reconcileRemoteDelta(
      delta: parsed.delta,
      liveGroups: currentState.groups,
      liveLists: currentState.lists,
      liveTasks: currentState.tasks,
      protection: protection,
      idGenerator: host.nextId,
      strictParentResolution: true,
      returnOnlyChanged: true,
    );

    final prefix = fromQueue ? '(drained) ' : '';
    if (reconciled.hasChanges) {
      _realtimeLog.info(
        '${prefix}applied realtime batch events=${events.length} '
        'groups=${reconciled.groups != null} lists=${reconciled.lists != null} '
        'tasks=${reconciled.tasks != null} '
        'settings=${reconciled.remoteSettings?.length ?? 0}',
      );
      await host.applyRemoteState(
        groups: reconciled.groups,
        lists: reconciled.lists,
        tasks: reconciled.tasks,
        remoteSettings: reconciled.remoteSettings,
      );
    }

    final unhandled =
        parsed.firstUnhandled ??
        (reconciled.hasUnhandledEntity
            ? (events.lastWhereOrNull(
                    (e) =>
                        e.entityType == RealtimeEventEntityType.task ||
                        e.entityType == RealtimeEventEntityType.taskFolder,
                  ) ??
                  events.last)
            : null);
    if (unhandled != null) {
      _realtimeLog.info(
        '${prefix}non-direct event type=${unhandled.type} op=${unhandled.operation} '
        'id=${shortSyncId(unhandled.id)}; fallback to sync',
      );
    }
    return unhandled;
  }

  PullCommand _fallbackCommandForRealtime(RealtimeEvent event) {
    final folderRemoteIds = _affectedFolderRemoteIds(event);
    if (folderRemoteIds.isEmpty) {
      return const PullCommand(PullScope.delta, SyncReason.realtimeEvent);
    }
    return PullCommand(
      PullScope.selective,
      SyncReason.realtimeEvent,
      folderRemoteIds: folderRemoteIds,
    );
  }

  Set<String> _affectedFolderRemoteIds(RealtimeEvent event) {
    if (event.entityType != RealtimeEventEntityType.task) return const {};

    final state = host.readTodoState();
    final knownFolderRemoteIds = {
      for (final list in state.lists)
        if (list.remoteId != null) list.remoteId!,
    };
    final localListId = event.id == null
        ? null
        : state.tasks.firstWhereOrNull((t) => t.remoteId == event.id)?.listId;
    final candidates = <String>{
      if (event.payload?['ParentFolderId'] case final String id
          when id.isNotEmpty)
        id,
      if (localListId != null)
        if (state.lists.firstWhereOrNull((l) => l.id == localListId)?.remoteId
            case final String id)
          id,
    };
    return candidates.intersection(knownFolderRemoteIds);
  }

  void _scheduleDurableBackgroundHandoff({required SyncReason reason}) {
    final active = host.readActiveAccount();
    if (_disposed || active == null) return;
    final repo = host.readRepository();
    final outbox = repo.outbox;
    if (outbox.isEmpty) return;

    final hasMetadata = outbox.ops.any((op) => !op.isAttachmentUpload);
    final hasAttachments = outbox.ops.any((op) => op.isAttachmentUpload);
    final scheduler = host.readBackgroundScheduler();
    unawaited(() async {
      await repo.flushPendingWrites();
      if (_disposed) return;
      if (hasMetadata) {
        await scheduler.enqueueSync(
          lane: BackgroundSyncLane.metadata,
          reason: reason.label,
          requiresNetwork: true,
          expedited: true,
        );
      }
      if (hasAttachments) {
        await scheduler.enqueueSync(
          lane: BackgroundSyncLane.transfer,
          reason: reason.label,
          requiresNetwork: true,
          expedited: false,
        );
      }
    }());
  }

  Future<void> _enqueueBackgroundTransferIfPending(SyncReason reason) async {
    if (_disposed || !_delegatesTransfersToBackground) return;
    final repo = host.readRepository();
    if (!repo.outbox.ops.any((op) => op.isAttachmentUpload)) return;
    await repo.flushPendingWrites();
    if (_disposed) return;
    await host.readBackgroundScheduler().enqueueSync(
      lane: BackgroundSyncLane.transfer,
      reason: reason.label,
      requiresNetwork: true,
      expedited: false,
    );
  }

  void _handleBackgroundWorkerEvent(BackgroundDbChangedEvent event) {
    if (_disposed || host.readActiveAccount() == null) return;
    final repo = host.readRepository();
    if (event.accountKey != repo.accountKey) return;
    unawaited(() async {
      await repo.preload();
      if (!_disposed) {
        host.onBackgroundDbReloaded();
      }
    }());
  }
}
