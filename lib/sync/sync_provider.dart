import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../data/sync_outbox.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'background_sync_bridge.dart';
import 'microsoft/account_profile_refresher.dart';
import 'microsoft/cloud_sync_service.dart';
import 'microsoft/substrate_push_engine.dart';
import 'realtime_sync_controller.dart';

final _log = appLogFor('Sync');

/// Allows tests to disable background realtime long-polling streams.
final realtimeSyncEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to disable foreground periodic sync timers.
final periodicSyncEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to disable automatic cold-start sync on shell mount.
final startupSyncEnabledProvider = Provider<bool>((ref) => true);

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService(
    authClient: ref.watch(microsoftAuthClientProvider),
    todoApi: ref.watch(microsoftTodoApiProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

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

enum SyncReason {
  manual('manual'),
  debounced('debounced'),
  localMutation('local_mutation'),
  startup('startup'),
  accountChanged('account_changed'),
  appResumed('app_resumed'),
  periodic('periodic'),
  realtimeReconnected('realtime_reconnected'),
  realtimeOverflow('realtime_overflow'),
  outboxPending('outbox_pending'),
  queued('queued');

  const SyncReason(this.label);
  final String label;
}

class _SyncCommand {
  const _SyncCommand(this.kind, this.reason, {this.pruneProtectSinceSeq});

  final SyncKind kind;
  final String reason;
  final int? pruneProtectSinceSeq;

  _SyncCommand merge(_SyncCommand other) {
    final earliestPruneSeq = switch ((
      pruneProtectSinceSeq,
      other.pruneProtectSinceSeq,
    )) {
      (final a?, final b?) => a < b ? a : b,
      (final a?, null) => a,
      (null, final b?) => b,
      (null, null) => null,
    };
    final winner = other.kind.index > kind.index ? other : this;
    return _SyncCommand(
      winner.kind,
      winner.reason,
      pruneProtectSinceSeq: earliestPruneSeq,
    );
  }
}

class _CancelFlag {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Coalescing timer with a bounded maximum postponement cap.
class _CoalescingDebouncer {
  _CoalescingDebouncer(this.maxCoalesceDelay);

  final Duration maxCoalesceDelay;
  Timer? _timer;
  DateTime? _startedAt;
  DateTime? _deadline;

  bool get isActive => _timer != null && _timer!.isActive;

  Duration schedule(Duration delay, void Function() onFire) {
    final now = DateTime.now();
    final isPending = _deadline != null && _deadline!.isAfter(now);
    final DateTime fireAt;
    if (isPending && _startedAt != null) {
      final cap = _startedAt!.add(
        delay > maxCoalesceDelay ? delay : maxCoalesceDelay,
      );
      final extended = now.add(delay);
      fireAt = extended.isAfter(cap) ? cap : extended;
    } else {
      _startedAt = now;
      fireAt = now.add(delay);
    }

    _timer?.cancel();
    _deadline = fireAt;
    final fireIn = fireAt.difference(now);
    _timer = Timer(fireIn, () {
      cancel();
      onFire();
    });
    return fireIn;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    _deadline = null;
  }
}

/// Single-lane async runner that coalesces overlapping triggers into a single
/// queued follow-up command while an execution cycle is in flight.
class _CoalescingRunner<T> {
  _CoalescingRunner({required this.coalesce});

  final T Function(T queued, T incoming) coalesce;

  Future<void>? _inFlight;
  T? _queued;

  bool get isRunning => _inFlight != null;
  bool get hasQueued => _queued != null;

  void enqueue(T command) {
    _queued = _queued == null ? command : coalesce(_queued as T, command);
  }

  void clearQueued() {
    _queued = null;
  }

  Future<void> run(
    T command, {
    required bool Function() isCancelled,
    required Future<void> Function(T item) execute,
    void Function(T merged)? onCoalesced,
    Future<void> Function()? onCycleComplete,
  }) {
    final active = _inFlight;
    if (active != null) {
      enqueue(command);
      onCoalesced?.call(_queued as T);
      return active;
    }

    final completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(() async {
      T? next = command;
      try {
        while (next != null && !isCancelled()) {
          final current = next;
          next = null;
          await execute(current);
          if (!isCancelled()) {
            next = _queued;
            _queued = null;
          }
        }
      } finally {
        _queued = null;
        _inFlight = null;
      }
      try {
        if (!isCancelled() && onCycleComplete != null) {
          await onCycleComplete();
        }
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }
}

class SyncNotifier extends Notifier<SyncState> {
  /// Coalescing window for local edits.
  static const _mutationDebounceDuration = Duration(milliseconds: 300);

  /// Cap on how long continued activity may postpone a pending pass.
  static const _maxCoalesceDelay = Duration(seconds: 1);
  static const _debounceDuration = Duration(milliseconds: 1500);
  static const _foregroundDebounceDuration = Duration(milliseconds: 500);
  static const _periodicSyncInterval = Duration(seconds: 120);

  final _pushDebouncer = _CoalescingDebouncer(_maxCoalesceDelay);
  String? _pendingPushReason;

  final _pullDebouncer = _CoalescingDebouncer(_maxCoalesceDelay);
  _SyncCommand? _pendingPullCommand;

  final _pushRunner = _CoalescingRunner<String>(
    coalesce: (queued, _) => queued,
  );
  final _pullRunner = _CoalescingRunner<_SyncCommand>(
    coalesce: (queued, incoming) => queued.merge(incoming),
  );

  Timer? _periodicTimer;
  RealtimeSyncController? _realtimeController;
  StreamSubscription<BackgroundDbChangedEvent>? _workerEventSub;

  bool _disposed = false;
  bool _isForeground = true;
  _CancelFlag? _activePullCancel;

  bool get _hasActiveSync => _pushRunner.isRunning || _pullRunner.isRunning;

  bool get _delegatesTransfersToBackground =>
      ref.read(backgroundSyncSchedulerProvider).handlesTransfersInBackground;

  MicrosoftAccount? get _activeMicrosoftAccount {
    final active = ref.read(accountProvider).activeAccount;
    return active is MicrosoftAccount ? active : null;
  }

  RealtimeSyncController _ensureRealtimeController() {
    return _realtimeController ??= RealtimeSyncController(
      ref: ref,
      isSyncInFlight: () => _hasActiveSync,
      onScheduleFallbackSync:
          ({required delay, required forceFullSync, required reason}) {
            scheduleDebouncedSync(
              delay: delay,
              forceFullSync: forceFullSync,
              reason: reason,
            );
          },
      onOverflowResync: (reason) {
        _pullRunner.enqueue(_SyncCommand(SyncKind.full, reason));
      },
      onCatchupDeltaSync: (reason) =>
          syncNow(forceFullSync: false, reason: reason),
    );
  }

  @override
  SyncState build() {
    _disposed = false;
    ref.onDispose(_disposeResources);
    _workerEventSub ??= BackgroundWorkerEventBus.events.listen(
      _handleBackgroundWorkerEvent,
    );
    final realtime = _ensureRealtimeController();

    final accountIdentity = ref.watch(
      accountProvider.select(
        (s) => (
          id: s.activeAccount?.id,
          isMicrosoft: s.activeAccount is MicrosoftAccount,
        ),
      ),
    );
    final activeAccount = ref.read(accountProvider).activeAccount;

    ref.listen<int>(todoProvider.select((s) => s.mutationVersion), (
      prev,
      next,
    ) {
      if (prev != null && next > prev) {
        schedulePushOnlySync();
      }
    });

    if (!accountIdentity.isMicrosoft || activeAccount is! MicrosoftAccount) {
      realtime.stop(clearPending: true);
      _stopPeriodicSync();
      _cancelPushDebounce();
      _cancelPullDebounce();
      _pushRunner.clearQueued();
      _pullRunner.clearQueued();
      _activePullCancel?.cancel();
      return const SyncState();
    }

    if (_isForeground) {
      if (ref.watch(realtimeSyncEnabledProvider)) {
        realtime.ensureStartedFor(activeAccount);
      }
      if (ref.watch(periodicSyncEnabledProvider)) {
        _startPeriodicSync();
      } else {
        _stopPeriodicSync();
      }
    }

    return SyncState(lastSyncedAt: activeAccount.lastSyncedAt);
  }

  void _disposeResources() {
    _disposed = true;
    _cancelPushDebounce();
    _cancelPullDebounce();
    _pushRunner.clearQueued();
    _pullRunner.clearQueued();
    _activePullCancel?.cancel();
    _stopPeriodicSync();
    _realtimeController?.dispose();
    _realtimeController = null;
    unawaited(_workerEventSub?.cancel());
    _workerEventSub = null;
  }

  void _cancelPushDebounce() {
    _pushDebouncer.cancel();
    _pendingPushReason = null;
  }

  void _cancelPullDebounce() {
    _pullDebouncer.cancel();
    _pendingPullCommand = null;
  }

  void _startPeriodicSync() {
    if (_disposed || !_isForeground || _periodicTimer != null) return;
    _periodicTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (!_disposed && _isForeground) {
        unawaited(syncNow(reason: SyncReason.periodic.label));
      }
    });
  }

  void _stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Pauses foreground-only sync channels when backgrounded, cancels any
  /// in-flight pull so bandwidth/time go to pushes, and flushes pending pushes.
  void onAppPaused() {
    if (_disposed || !_isForeground) return;
    _isForeground = false;
    _log.info('onAppPaused: stopping realtime & periodic sync');
    _stopPeriodicSync();
    _realtimeController?.onAppPaused();

    if (_pullRunner.isRunning) {
      _log.info('onAppPaused: cancelling in-flight pull to prioritize push');
      _activePullCancel?.cancel();
      _pullRunner.clearQueued();
    }
    _cancelPullDebounce();

    final pendingPushReason = _pendingPushReason;
    if (pendingPushReason != null && _pushDebouncer.isActive) {
      _cancelPushDebounce();
      if (!_delegatesTransfersToBackground) {
        _log.info(
          'onAppPaused: flushing pending push reason=$pendingPushReason',
        );
        unawaited(_pushNow(reason: pendingPushReason));
      }
    }
    _scheduleDurableBackgroundHandoff(
      reason: pendingPushReason ?? 'app_paused',
    );
  }

  void _scheduleDurableBackgroundHandoff({required String reason}) {
    final active = _activeMicrosoftAccount;
    if (_disposed || active == null) return;
    final repo = ref.read(todoProvider.notifier).repository;
    final outbox = repo.outbox;
    if (outbox.isEmpty) return;

    final hasMetadata = outbox.ops.any((op) => !op.isAttachmentUpload);
    final hasAttachments = outbox.ops.any((op) => op.isAttachmentUpload);
    final scheduler = ref.read(backgroundSyncSchedulerProvider);
    unawaited(() async {
      await repo.flushPendingWrites();
      if (_disposed) return;
      if (hasMetadata) {
        await scheduler.enqueueSync(
          lane: BackgroundSyncLane.metadata,
          reason: reason,
          requiresNetwork: true,
          expedited: true,
        );
      }
      if (hasAttachments) {
        await scheduler.enqueueSync(
          lane: BackgroundSyncLane.transfer,
          reason: reason,
          requiresNetwork: true,
          expedited: false,
        );
      }
    }());
  }

  Future<void> _enqueueBackgroundTransferIfPending(String reason) async {
    if (_disposed || !_delegatesTransfersToBackground) return;
    final repo = ref.read(todoProvider.notifier).repository;
    if (!repo.outbox.ops.any((op) => op.isAttachmentUpload)) return;
    await repo.flushPendingWrites();
    if (_disposed) return;
    await ref
        .read(backgroundSyncSchedulerProvider)
        .enqueueSync(
          lane: BackgroundSyncLane.transfer,
          reason: reason,
          requiresNetwork: true,
          expedited: false,
        );
  }

  void _handleBackgroundWorkerEvent(BackgroundDbChangedEvent event) {
    if (_disposed) return;
    final active = _activeMicrosoftAccount;
    if (active == null) return;
    final repo = ref.read(todoProvider.notifier).repository;
    if (event.accountKey != repo.accountKey && event.accountKey != active.id) {
      return;
    }
    unawaited(() async {
      await repo.preload();
      if (!_disposed) {
        ref.invalidate(todoProvider);
      }
    }());
  }

  /// Resumes foreground sync channels and triggers a debounced sync when the
  /// app returns to the foreground.
  void onAppResumed() {
    if (_disposed) return;
    _isForeground = true;
    final active = _activeMicrosoftAccount;
    if (active == null) return;

    _log.info('onAppResumed: restarting realtime & scheduling delta sync');
    if (ref.read(realtimeSyncEnabledProvider)) {
      _ensureRealtimeController().ensureStartedFor(active);
    }
    if (ref.read(periodicSyncEnabledProvider)) {
      _startPeriodicSync();
    }
    scheduleDebouncedSync(
      delay: _foregroundDebounceDuration,
      forceFullSync: false,
      reason: SyncReason.appResumed.label,
    );
  }

  /// Triggers an immediate full sync for manual user refreshes (header, settings, pull-to-refresh).
  Future<void> refresh({String reason = 'manual'}) =>
      syncNow(forceFullSync: true, reason: reason);

  /// Starts an incremental sync followed by a full sync on cold start for
  /// previously synced accounts, or a single full sync on account switch.
  void syncOnSessionStart({bool accountChanged = false}) {
    if (!accountChanged && !ref.read(startupSyncEnabledProvider)) return;
    final account = _activeMicrosoftAccount;
    if (account == null) return;

    if (accountChanged) {
      unawaited(
        syncNow(forceFullSync: true, reason: SyncReason.accountChanged.label),
      );
      return;
    }

    final needsFollowUpFull = account.lastSyncedAt != null;
    unawaited(() async {
      await syncNow(forceFullSync: false, reason: SyncReason.startup.label);
      if (!_disposed &&
          _isForeground &&
          needsFollowUpFull &&
          state.status == SyncStatus.success) {
        await syncNow(forceFullSync: true, reason: SyncReason.startup.label);
      }
    }());
  }

  /// Schedules a delta/full pull pass, coalescing pending requests into one.
  void scheduleDebouncedSync({
    Duration delay = _debounceDuration,
    bool forceFullSync = false,
    String reason = 'debounced',
  }) {
    if (_disposed || _activeMicrosoftAccount == null) return;

    final incoming = _SyncCommand(
      forceFullSync ? SyncKind.full : SyncKind.delta,
      reason,
    );
    final merged = _pendingPullCommand?.merge(incoming) ?? incoming;
    _pendingPullCommand = merged;

    final fireIn = _pullDebouncer.schedule(delay, () {
      if (_disposed) return;
      final pending =
          _pendingPullCommand ??
          _SyncCommand(SyncKind.delta, SyncReason.debounced.label);
      _pendingPullCommand = null;
      unawaited(
        syncNow(
          forceFullSync: pending.kind == SyncKind.full,
          reason: pending.reason,
        ),
      );
    });
    _log.info(
      'scheduleDebouncedSync reason=${merged.reason} kind=${merged.kind.name} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  /// Schedules an independent local Outbox push pass (never blocked by pulls).
  void schedulePushOnlySync({
    Duration delay = _mutationDebounceDuration,
    String reason = 'local_mutation',
  }) {
    if (_disposed || _activeMicrosoftAccount == null) return;

    _pendingPushReason ??= reason;
    final fireIn = _pushDebouncer.schedule(delay, () {
      if (_disposed) return;
      final pendingReason =
          _pendingPushReason ?? SyncReason.localMutation.label;
      _pendingPushReason = null;
      unawaited(_pushNow(reason: pendingReason));
    });
    _log.info(
      'schedulePushOnlySync reason=$reason kind=${SyncKind.pushOnly.name} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  /// Runs a push (if any outbox ops are pending) followed by a pull of [kind],
  /// or runs push concurrently if a pull is already in flight.
  Future<void> syncNow({
    bool forceFullSync = false,
    String reason = 'manual',
  }) async {
    if (_disposed || _activeMicrosoftAccount == null) return;

    final kind = forceFullSync ? SyncKind.full : SyncKind.delta;
    final outbox = ref.read(todoProvider.notifier).repository.outbox;
    int? pruneProtectSinceSeq;

    if (outbox.isNotEmpty && !_pullRunner.isRunning) {
      pruneProtectSinceSeq = outbox.lastSeq;
      await _pushNow(reason: reason, enqueueFollowUpPull: false);
      if (_disposed) return;
    } else if (outbox.isNotEmpty) {
      unawaited(_pushNow(reason: reason));
    }

    await _pullNow(
      kind,
      reason: reason,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    );
  }

  Future<void> _pushNow({
    String reason = 'local_mutation',
    bool enqueueFollowUpPull = true,
  }) {
    if (_disposed || _activeMicrosoftAccount == null) {
      return Future<void>.value();
    }

    if (_delegatesTransfersToBackground) {
      final ops = ref.read(todoProvider.notifier).repository.outbox.ops;
      final hasMetadata = ops.any((op) => !op.isAttachmentUpload);
      if (!hasMetadata) {
        return _enqueueBackgroundTransferIfPending(reason);
      }
    }

    final followUpFolders = <String>{};
    var lastSucceeded = false;

    if (!_pushRunner.isRunning) {
      state = state.copyWith(status: SyncStatus.syncing, error: null);
    }

    return _pushRunner.run(
      reason,
      isCancelled: () => _disposed,
      onCoalesced: (_) =>
          _log.info('push coalesced into in-flight push: reason=$reason'),
      execute: (currentReason) async {
        final outcome = await _pushOnce(reason: currentReason);
        if (outcome == null) {
          lastSucceeded = false;
          return;
        }
        lastSucceeded = true;
        followUpFolders.addAll(outcome.followUpPullFolderRemoteIds);
        final hasPendingDeletes =
            !_disposed &&
            !_pushRunner.hasQueued &&
            ref
                .read(todoProvider.notifier)
                .repository
                .outbox
                .ops
                .any((op) => op.kind == SyncOpKind.delete);
        if (hasPendingDeletes) {
          _pushRunner.enqueue(SyncReason.outboxPending.label);
        }
      },
      onCycleComplete: () async {
        if (lastSucceeded && !_hasActiveSync) {
          state = state.copyWith(status: SyncStatus.success, error: null);
        }
        await _enqueueBackgroundTransferIfPending(reason);
        if (enqueueFollowUpPull &&
            followUpFolders.isNotEmpty &&
            _isForeground) {
          unawaited(_pullNow(SyncKind.pushOnly, reason: reason));
        } else if (!_hasActiveSync) {
          await _drainRealtimeIfReady();
        }
      },
    );
  }

  Future<void> _pullNow(
    SyncKind kind, {
    String reason = 'manual',
    int? pruneProtectSinceSeq,
  }) {
    if (_disposed || _activeMicrosoftAccount == null) {
      return Future<void>.value();
    }

    final command = _SyncCommand(
      kind,
      reason,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    );
    if (!_pullRunner.isRunning) {
      state = state.copyWith(status: SyncStatus.syncing, error: null);
    }

    return _pullRunner.run(
      command,
      isCancelled: () => _disposed,
      onCoalesced: (merged) => _log.info(
        'syncNow coalesced into in-flight sync: reason=$reason '
        'kind=${kind.name} (queuedKind=${merged.kind.name})',
      ),
      execute: (current) async {
        try {
          await _pullOnce(
            kind: current.kind,
            reason: current.reason,
            pruneProtectSinceSeq: current.pruneProtectSinceSeq,
          );
        } finally {
          _activePullCancel = null;
        }
      },
      onCycleComplete: () async {
        if (!_hasActiveSync) {
          await _drainRealtimeIfReady();
        }
      },
    );
  }

  Future<OutboxPushOutcome?> _pushOnce({required String reason}) async {
    final active = _activeMicrosoftAccount;
    if (_disposed || active == null) return null;

    _log.info('push start account=${active.id} reason=$reason');

    final service = ref.read(cloudSyncServiceProvider);
    final todoNotifier = ref.read(todoProvider.notifier);
    final snapshotState = ref.read(todoProvider);

    final result = await service.pushAccount(
      account: active,
      currentState: snapshotState,
      repository: todoNotifier.repository,
      readLatestState: () => ref.read(todoProvider),
      onPushCommitted: (pushOutcome) async {
        if (_disposed ||
            ref.read(accountProvider).activeAccount?.id != active.id) {
          return;
        }
        await todoNotifier.commitPushBatch(pushOutcome);
      },
      reason: reason,
      laneFilter: _delegatesTransfersToBackground
          ? PushLaneFilter.metadataOnly
          : PushLaneFilter.all,
    );

    if (_disposed) return null;

    return result.fold(
      (outcome) async {
        _log.info(
          'push success reason=$reason '
          'pushedTasks=${outcome.pushedTasks.length}',
        );
        return outcome;
      },
      (error) async {
        await _handleSyncError(active, reason, error);
        return null;
      },
    );
  }

  Future<bool> _pullOnce({
    required SyncKind kind,
    required String reason,
    int? pruneProtectSinceSeq,
  }) async {
    final active = _activeMicrosoftAccount;
    if (_disposed || active == null) return false;

    final forceFullSync = kind == SyncKind.full;
    final cancelFlag = _CancelFlag();
    _activePullCancel = cancelFlag;

    _log.info(
      'sync start account=${active.id} reason=$reason '
      'kind=${kind.name} forceFullSync=$forceFullSync',
    );

    final service = ref.read(cloudSyncServiceProvider);
    final todoNotifier = ref.read(todoProvider.notifier);
    final snapshotState = ref.read(todoProvider);

    final result = await service.pullAccount(
      account: active,
      currentState: snapshotState,
      repository: todoNotifier.repository,
      idGenerator: todoNotifier.nextId,
      readLatestState: () => ref.read(todoProvider),
      kind: kind,
      reason: reason,
      isCancelled: () => _disposed || cancelFlag.cancelled,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    );

    if (_disposed) return false;

    return result.fold(
      (outcome) async {
        if (outcome.cancelled) {
          _log.info(
            'sync cancelled reason=$reason forceFullSync=$forceFullSync',
          );
          if (!_disposed && !_pushRunner.isRunning) {
            state = state.copyWith(status: SyncStatus.idle);
          }
          return false;
        }
        _log.info(
          'sync success reason=$reason forceFullSync=$forceFullSync '
          'lists=${outcome.lists.length} tasks=${outcome.tasks.length}',
        );
        if (ref.read(accountProvider).activeAccount?.id == active.id) {
          await todoNotifier.applyRemoteState(
            groups: kind == SyncKind.pushOnly ? null : outcome.groups,
            lists: kind == SyncKind.pushOnly ? null : outcome.lists,
            tasks: outcome.tasks,
            remoteSettings: outcome.remoteSettings,
            protectPendingOutbox: true,
          );
        }
        await ref
            .read(accountProvider.notifier)
            .updateSyncStatus(
              active.id,
              lastSyncedAt: outcome.syncedAt,
              clearSyncError: true,
            );
        await refreshMicrosoftProfileIfIncomplete(
          service: service,
          account: active,
          isDisposed: () => _disposed,
          onProfileUpdated: ref
              .read(accountProvider.notifier)
              .updateMicrosoftProfile,
        );
        if (!_disposed && !_pushRunner.isRunning) {
          state = state.copyWith(
            status: SyncStatus.success,
            lastSyncedAt: outcome.syncedAt,
            error: null,
          );
        } else if (!_disposed) {
          state = state.copyWith(lastSyncedAt: outcome.syncedAt, error: null);
        }
        return true;
      },
      (error) async {
        await _handleSyncError(active, reason, error);
        return false;
      },
    );
  }

  Future<void> _handleSyncError(
    MicrosoftAccount active,
    String reason,
    AppError error,
  ) async {
    final status = switch (error) {
      AuthError(:final requiresReauth) when requiresReauth =>
        SyncStatus.requiresRelogin,
      _ => SyncStatus.error,
    };
    _log.info(
      'sync error reason=$reason status=$status error=${error.describe()}',
    );
    final message = error.userMessage;
    await ref
        .read(accountProvider.notifier)
        .updateSyncStatus(active.id, syncError: message);
    if (!_disposed) {
      state = state.copyWith(status: status, error: message);
    }
  }

  Future<void> _drainRealtimeIfReady() async {
    final realtime = _realtimeController;
    if (!_disposed && realtime != null && realtime.hasPendingEvents) {
      await realtime.drainPendingIfReady();
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
