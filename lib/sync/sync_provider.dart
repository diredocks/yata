import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_profile_refresher.dart';
import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../data/sync_outbox.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'background_sync_bridge.dart';
import 'microsoft/substrate_pull_engine.dart';
import 'microsoft/substrate_push_engine.dart';
import 'realtime_sync_controller.dart';
import 'sync_dispatcher.dart';

final _log = appLogFor('Sync');

/// Allows tests to disable background realtime long-polling streams.
final realtimeSyncEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to disable foreground periodic sync timers.
final periodicSyncEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to disable automatic cold-start sync on shell mount.
final startupSyncEnabledProvider = Provider<bool>((ref) => true);

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

class SyncNotifier extends Notifier<SyncState> {
  /// Coalescing window for local edits.
  static const _mutationDebounceDuration = Duration(milliseconds: 300);

  /// Cap on how long continued activity may postpone a pending pass.
  static const _maxCoalesceDelay = Duration(seconds: 1);
  static const _debounceDuration = Duration(milliseconds: 1500);
  static const _foregroundDebounceDuration = Duration(milliseconds: 500);
  static const _periodicSyncInterval = Duration(seconds: 120);

  late final SyncLane<PushCommand> _pushLane = SyncLane(
    maxCoalesceDelay: _maxCoalesceDelay,
    coalesce: (queued, _) => queued,
    onDebounced: (command) => unawaited(_dispatch(command)),
  );
  late final SyncLane<PullCommand> _pullLane = SyncLane(
    maxCoalesceDelay: _maxCoalesceDelay,
    coalesce: (queued, incoming) => queued.merge(incoming),
    onDebounced: (command) => unawaited(_dispatch(command)),
  );

  Timer? _periodicTimer;
  RealtimeSyncController? _realtimeController;
  StreamSubscription<BackgroundDbChangedEvent>? _workerEventSub;

  bool _disposed = false;
  bool _isForeground = true;
  int _pullGeneration = 0;
  AppError? _pushError;
  AppError? _pullError;
  bool _hasCompletedSync = false;
  String? _activeAccountId;

  bool get _hasActiveSync => _pushLane.isRunning || _pullLane.isRunning;

  bool get _delegatesTransfersToBackground =>
      ref.read(backgroundSyncSchedulerProvider).handlesTransfersInBackground;

  bool get _hasPendingForegroundPushOps {
    final ops = ref.read(todoProvider.notifier).repository.outbox.ops;
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

  void _publishState({DateTime? lastSyncedAt, bool preferIdle = false}) {
    if (_disposed) return;
    if (_hasActiveSync) {
      state = state.copyWith(
        status: SyncStatus.syncing,
        lastSyncedAt: lastSyncedAt ?? state.lastSyncedAt,
        error: null,
      );
      return;
    }
    final error = _effectiveError;
    final nextStatus = error != null
        ? _statusForError(error)
        : (preferIdle
              ? SyncStatus.idle
              : (_hasCompletedSync ? SyncStatus.success : SyncStatus.idle));
    state = state.copyWith(
      status: nextStatus,
      lastSyncedAt: lastSyncedAt ?? state.lastSyncedAt,
      error: error?.userMessage,
    );
  }

  Future<void> _persistAccountSyncStatus(
    MicrosoftAccount active, {
    DateTime? lastSyncedAt,
  }) {
    final error = _effectiveError;
    return ref
        .read(accountProvider.notifier)
        .updateSyncStatus(
          active.id,
          lastSyncedAt: lastSyncedAt,
          syncError: error?.userMessage,
          clearSyncError: error == null,
        );
  }

  MicrosoftAccount? get _activeMicrosoftAccount {
    final active = ref.read(accountProvider).activeAccount;
    return active is MicrosoftAccount ? active : null;
  }

  RealtimeSyncController _ensureRealtimeController() {
    return _realtimeController ??= RealtimeSyncController(
      ref: ref,
      isSyncInFlight: () => _hasActiveSync,
      onScheduleFallbackPull: (command, delay) =>
          schedulePull(command, delay: delay),
      onOverflowResync: (reason) {
        _pullLane.enqueue(PullCommand(PullScope.full, reason));
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
    if (accountIdentity.id != _activeAccountId) {
      _pushError = null;
      _pullError = null;
      _hasCompletedSync = false;
      _activeAccountId = accountIdentity.id;
    }
    final activeAccount = ref.read(accountProvider).activeAccount;

    ref.listen<int>(todoProvider.select((s) => s.mutationVersion), (
      prev,
      next,
    ) {
      if (prev != null && next > prev) {
        schedulePush();
      }
    });

    if (!accountIdentity.isMicrosoft || activeAccount is! MicrosoftAccount) {
      realtime.stop(clearPending: true);
      _stopPeriodicSync();
      _resetChannels();
      _pushError = null;
      _pullError = null;
      _hasCompletedSync = false;
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
    _resetChannels();
    _stopPeriodicSync();
    _realtimeController?.dispose();
    _realtimeController = null;
    unawaited(_workerEventSub?.cancel());
    _workerEventSub = null;
  }

  /// Drops every pending and queued command and invalidates in-flight pulls.
  void _resetChannels() {
    _pushLane.reset();
    _pullLane.reset();
    _pullGeneration += 1;
  }

  void _startPeriodicSync() {
    if (_disposed || !_isForeground || _periodicTimer != null) return;
    _periodicTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (!_disposed && _isForeground) {
        unawaited(syncNow(reason: SyncReason.periodic));
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

  void _scheduleDurableBackgroundHandoff({required SyncReason reason}) {
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
    final repo = ref.read(todoProvider.notifier).repository;
    if (!repo.outbox.ops.any((op) => op.isAttachmentUpload)) return;
    await repo.flushPendingWrites();
    if (_disposed) return;
    await ref
        .read(backgroundSyncSchedulerProvider)
        .enqueueSync(
          lane: BackgroundSyncLane.transfer,
          reason: reason.label,
          requiresNetwork: true,
          expedited: false,
        );
  }

  void _handleBackgroundWorkerEvent(BackgroundDbChangedEvent event) {
    if (_disposed || _activeMicrosoftAccount == null) return;
    final repo = ref.read(todoProvider.notifier).repository;
    if (event.accountKey != repo.accountKey) return;
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
      reason: SyncReason.appResumed,
    );
  }

  /// Triggers an immediate full sync for manual user refreshes (header, settings, pull-to-refresh).
  Future<void> refresh({SyncReason reason = SyncReason.manual}) =>
      syncNow(forceFullSync: true, reason: reason);

  /// Starts an incremental sync followed by a full sync on cold start for
  /// previously synced accounts, or a single full sync on account switch.
  void syncOnSessionStart({bool accountChanged = false}) {
    if (!accountChanged && !ref.read(startupSyncEnabledProvider)) return;
    final account = _activeMicrosoftAccount;
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
          !state.requiresRelogin) {
        await syncNow(forceFullSync: true, reason: SyncReason.startup);
      }
    }());
  }

  /// Schedules a delta/full pull pass, coalescing pending requests into one.
  void scheduleDebouncedSync({
    Duration delay = _debounceDuration,
    bool forceFullSync = false,
    SyncReason reason = SyncReason.debounced,
  }) => schedulePull(
    PullCommand(forceFullSync ? PullScope.full : PullScope.delta, reason),
    delay: delay,
  );

  /// Schedules a pull pass, coalescing pending commands into one.
  void schedulePull(PullCommand command, {Duration delay = _debounceDuration}) {
    if (_disposed || _activeMicrosoftAccount == null) return;

    final fireIn = _pullLane.submit(command, delay);
    _log.info(
      'schedulePull reason=${command.reason.label} '
      'scope=${command.scope.name} '
      'folders=${command.folderRemoteIds?.length ?? 0} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  /// Schedules an independent local Outbox push pass (never blocked by pulls).
  void schedulePush({
    Duration delay = _mutationDebounceDuration,
    SyncReason reason = SyncReason.localMutation,
  }) {
    if (_disposed || _activeMicrosoftAccount == null) return;

    final fireIn = _pushLane.submit(PushCommand(reason), delay);
    _log.info(
      'schedulePush reason=${reason.label} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  /// Runs a push (if any outbox ops are pending) followed by a delta or full pull,
  /// or runs push concurrently if a pull is already in flight.
  Future<void> syncNow({
    bool forceFullSync = false,
    SyncReason reason = SyncReason.manual,
  }) => _dispatch(
    PullCommand(forceFullSync ? PullScope.full : PullScope.delta, reason),
  );

  Future<void> _dispatch(SyncCommand command) {
    if (_disposed || _activeMicrosoftAccount == null) {
      return Future<void>.value();
    }
    return switch (command) {
      PushCommand() => _pushNow(reason: command.reason),
      PullCommand() => _dispatchPull(command),
    };
  }

  Future<void> _dispatchPull(PullCommand command) async {
    final outbox = ref.read(todoProvider.notifier).repository.outbox;
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

    if (!_pushLane.isRunning) {
      state = state.copyWith(status: SyncStatus.syncing, error: null);
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
            ref
                .read(todoProvider.notifier)
                .repository
                .outbox
                .ops
                .any((op) => op.kind == SyncOpKind.delete);
        if (hasPendingDeletes) {
          _pushLane.enqueue(const PushCommand(SyncReason.outboxPending));
        }
      },
      onCycleComplete: () async {
        if (lastSucceeded && !_hasActiveSync) {
          final active = _activeMicrosoftAccount;
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
          await _drainRealtimeIfReady();
        }
      },
    );
  }

  Future<void> _pullNow(PullCommand command) {
    if (_disposed || _activeMicrosoftAccount == null) {
      return Future<void>.value();
    }

    DateTime? lastSyncedAt;
    var lastCancelled = false;

    if (!_pullLane.isRunning) {
      state = state.copyWith(status: SyncStatus.syncing, error: null);
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
          await _drainRealtimeIfReady();
        }
      },
    );
  }

  Future<OutboxPushOutcome?> _pushOnce({required SyncReason reason}) async {
    final active = _activeMicrosoftAccount;
    if (_disposed || active == null) return null;

    _log.info('push start account=${active.id} reason=${reason.label}');

    final todoNotifier = ref.read(todoProvider.notifier);
    final result = await SubstratePushEngine(ref.read(microsoftTodoApiProvider))
        .pushOutbox(
          readState: () => ref.read(todoProvider),
          outbox: todoNotifier.repository.outbox,
          nowUtc: DateTime.now().toUtc(),
          onItemCommitted: (pushOutcome) async {
            if (_disposed ||
                ref.read(accountProvider).activeAccount?.id != active.id) {
              return;
            }
            await todoNotifier.commitPushBatch(pushOutcome);
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
    final active = _activeMicrosoftAccount;
    if (_disposed || active == null) {
      return (ok: false, syncedAt: null, cancelled: false);
    }

    final gen = ++_pullGeneration;
    final forceFullSync = command.scope == PullScope.full;

    _log.info(
      'sync start account=${active.id} reason=${command.reason.label} '
      'scope=${command.scope.name} forceFullSync=$forceFullSync',
    );

    final todoNotifier = ref.read(todoProvider.notifier);
    final result = await SubstratePullEngine(ref.read(microsoftTodoApiProvider))
        .pull(
          repository: todoNotifier.repository,
          readState: () => ref.read(todoProvider),
          idGenerator: todoNotifier.nextId,
          onReconciled: (outcome) async {
            if (_disposed ||
                ref.read(accountProvider).activeAccount?.id != active.id) {
              return;
            }
            await todoNotifier.applyRemoteState(
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
        await refreshMicrosoftProfileIfIncomplete(
          authClient: ref.read(microsoftAuthClientProvider),
          tokenStorage: ref.read(authTokenStorageProvider),
          account: active,
          isDisposed: () => _disposed,
          onProfileUpdated: ref
              .read(accountProvider.notifier)
              .updateMicrosoftProfile,
        );
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
