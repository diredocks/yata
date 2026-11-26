import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../data/sync_outbox.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'microsoft/cloud_sync_service.dart';
import 'microsoft/substrate_push_engine.dart';
import 'realtime_sync_controller.dart';
import 'sync_guard.dart';

part 'sync_provider.freezed.dart';

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

SyncKind _mergeSyncKind(SyncKind? current, SyncKind next) =>
    current == null || next.index > current.index ? next : current;

@freezed
abstract class SyncState with _$SyncState {
  const SyncState._();

  const factory SyncState({
    @Default(SyncStatus.idle) SyncStatus status,
    DateTime? lastSyncedAt,
    String? error,
  }) = _SyncState;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get requiresRelogin => status == SyncStatus.requiresRelogin;
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
  SyncKind? _pendingPullKind;
  String _pendingPullReason = SyncReason.debounced.label;

  Timer? _periodicTimer;
  RealtimeSyncController? _realtimeController;

  bool _disposed = false;
  bool _isForeground = true;

  Future<void>? _activePush;
  String? _queuedPushReason;

  Future<void>? _activePull;
  _SyncCommand? _queuedPullCommand;
  _CancelFlag? _activePullCancel;

  bool get _hasActiveSync => _activePush != null || _activePull != null;

  void _enqueuePullCommand(_SyncCommand command) {
    _queuedPullCommand = _queuedPullCommand?.merge(command) ?? command;
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
        _enqueuePullCommand(_SyncCommand(SyncKind.full, reason));
      },
      onCatchupDeltaSync: (reason) =>
          syncNow(forceFullSync: false, reason: reason),
    );
  }

  @override
  SyncState build() {
    _disposed = false;
    ref.onDispose(_disposeResources);
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
      _queuedPushReason = null;
      _queuedPullCommand = null;
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
    _queuedPushReason = null;
    _queuedPullCommand = null;
    _activePullCancel?.cancel();
    _stopPeriodicSync();
    _realtimeController?.dispose();
    _realtimeController = null;
  }

  void _cancelPushDebounce() {
    _pushDebouncer.cancel();
    _pendingPushReason = null;
  }

  void _cancelPullDebounce() {
    _pullDebouncer.cancel();
    _pendingPullKind = null;
    _pendingPullReason = SyncReason.debounced.label;
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

    if (_activePull != null) {
      _log.info('onAppPaused: cancelling in-flight pull to prioritize push');
      _activePullCancel?.cancel();
      _queuedPullCommand = null;
    }
    _cancelPullDebounce();

    final pendingPushReason = _pendingPushReason;
    if (pendingPushReason != null && _pushDebouncer.isActive) {
      _cancelPushDebounce();
      _log.info(
        'onAppPaused: flushing pending push reason=$pendingPushReason',
      );
      unawaited(_pushNow(reason: pendingPushReason));
    }
  }

  /// Resumes foreground sync channels and triggers a debounced sync when the
  /// app returns to the foreground.
  void onAppResumed() {
    if (_disposed) return;
    _isForeground = true;
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return;

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
    final account = ref.read(accountProvider).activeAccount;
    if (account is! MicrosoftAccount) return;

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
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    final kind = forceFullSync ? SyncKind.full : SyncKind.delta;
    final previous = _pendingPullKind;
    final merged = _mergeSyncKind(previous, kind);
    _pendingPullKind = merged;
    if (previous == null || merged != previous) {
      _pendingPullReason = reason;
    }

    final fireIn = _pullDebouncer.schedule(delay, () {
      if (_disposed) return;
      final pendingKind = _pendingPullKind ?? SyncKind.delta;
      final pendingReason = _pendingPullReason;
      _pendingPullKind = null;
      _pendingPullReason = SyncReason.debounced.label;
      unawaited(
        syncNow(
          forceFullSync: pendingKind == SyncKind.full,
          reason: pendingReason,
        ),
      );
    });
    _log.info(
      'scheduleDebouncedSync reason=$_pendingPullReason kind=${merged.name} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  /// Schedules an independent local Outbox push pass (never blocked by pulls).
  void schedulePushOnlySync({
    Duration delay = _mutationDebounceDuration,
    String reason = 'local_mutation',
  }) {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    _pendingPushReason ??= reason;
    final fireIn = _pushDebouncer.schedule(delay, () {
      if (_disposed) return;
      final pendingReason = _pendingPushReason ?? SyncReason.localMutation.label;
      _pendingPushReason = null;
      unawaited(_pushNow(reason: pendingReason));
    });
    _log.info(
      'scheduleDebouncedSync reason=$reason kind=${SyncKind.pushOnly.name} '
      'delay=${delay.inMilliseconds}ms fireIn=${fireIn.inMilliseconds}ms',
    );
  }

  /// Runs a push (if any outbox ops are pending) followed by a pull of [kind],
  /// or runs push concurrently if a pull is already in flight.
  Future<void> syncNow({
    bool forceFullSync = false,
    String reason = 'manual',
  }) async {
    if (_disposed) return;
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return;

    final kind = forceFullSync ? SyncKind.full : SyncKind.delta;
    final outbox = ref.read(todoProvider.notifier).repository.outbox;
    int? pruneProtectSinceSeq;

    if (outbox.isNotEmpty && _activePull == null) {
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
    if (_disposed) return Future<void>.value();
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return Future<void>.value();

    final inFlight = _activePush;
    if (inFlight != null) {
      _queuedPushReason ??= reason;
      _log.info('push coalesced into in-flight push: reason=$reason');
      return inFlight;
    }

    final completer = Completer<void>();
    _activePush = completer.future;
    unawaited(() async {
      try {
        await _runPushLoop(
          reason,
          enqueueFollowUpPull: enqueueFollowUpPull,
        );
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _pullNow(
    SyncKind kind, {
    String reason = 'manual',
    int? pruneProtectSinceSeq,
  }) {
    if (_disposed) return Future<void>.value();
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return Future<void>.value();

    final command = _SyncCommand(
      kind,
      reason,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    );
    final inFlight = _activePull;
    if (inFlight != null) {
      _enqueuePullCommand(command);
      _log.info(
        'syncNow coalesced into in-flight sync: reason=$reason '
        'kind=${kind.name} (queuedKind=${_queuedPullCommand!.kind.name})',
      );
      return inFlight;
    }

    final completer = Completer<void>();
    _activePull = completer.future;
    unawaited(() async {
      try {
        await _runPullLoop(command);
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _runPushLoop(
    String initialReason, {
    bool enqueueFollowUpPull = true,
  }) async {
    state = state.copyWith(status: SyncStatus.syncing, error: null);
    String? nextReason = initialReason;
    final followUpFolders = <String>{};
    var lastSucceeded = false;

    try {
      while (nextReason != null && !_disposed) {
        final currentReason = nextReason;
        nextReason = null;
        final outcome = await _pushOnce(reason: currentReason);
        if (outcome != null) {
          lastSucceeded = true;
          followUpFolders.addAll(outcome.followUpPullFolderRemoteIds);
          if (!_disposed &&
              _queuedPushReason == null &&
              ref
                  .read(todoProvider.notifier)
                  .repository
                  .outbox
                  .ops
                  .any((op) => op.kind == SyncOpKind.delete)) {
            _queuedPushReason = SyncReason.outboxPending.label;
          }
        } else {
          lastSucceeded = false;
        }
        if (!_disposed) {
          nextReason = _queuedPushReason;
          _queuedPushReason = null;
        }
      }
    } finally {
      _queuedPushReason = null;
      _activePush = null;
    }

    if (!_disposed && lastSucceeded && !_hasActiveSync) {
      state = state.copyWith(status: SyncStatus.success, error: null);
    }

    if (!_disposed &&
        enqueueFollowUpPull &&
        followUpFolders.isNotEmpty &&
        _isForeground) {
      unawaited(_pullNow(SyncKind.pushOnly, reason: initialReason));
    } else if (!_disposed && !_hasActiveSync) {
      await _drainRealtimeIfReady();
    }
  }

  Future<OutboxPushOutcome?> _pushOnce({required String reason}) async {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return null;

    _log.info('push start account=${active.id} reason=$reason');

    final service = ref.read(cloudSyncServiceProvider);
    final todoNotifier = ref.read(todoProvider.notifier);
    final snapshotState = ref.read(todoProvider);

    final result = await service.pushAccount(
      account: active,
      currentState: snapshotState,
      repository: todoNotifier.repository,
      settings: todoNotifier.settings,
      readLatestState: () => ref.read(todoProvider),
      onPushCommitted: (pushOutcome) async {
        if (_disposed ||
            ref.read(accountProvider).activeAccount?.id != active.id) {
          return;
        }
        await todoNotifier.commitPushBatch(
          ackedSeqs: pushOutcome.ackedSeqs,
          pushedGroups: pushOutcome.pushedGroups,
          pushedLists: pushOutcome.pushedLists,
          pushedTasks: pushOutcome.pushedTasks,
          clearedRemoteIdKeys: pushOutcome.clearedRemoteIdKeys,
        );
      },
      reason: reason,
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

  Future<void> _runPullLoop(_SyncCommand initialCommand) async {
    state = state.copyWith(status: SyncStatus.syncing, error: null);
    _SyncCommand? nextCommand = initialCommand;
    try {
      while (nextCommand != null && !_disposed) {
        final current = nextCommand;
        nextCommand = null;
        await _pullOnce(
          kind: current.kind,
          reason: current.reason,
          pruneProtectSinceSeq: current.pruneProtectSinceSeq,
        );
        if (!_disposed) {
          nextCommand = _queuedPullCommand;
          _queuedPullCommand = null;
        }
      }
    } finally {
      _queuedPullCommand = null;
      _activePullCancel = null;
      _activePull = null;
    }
    if (!_disposed && !_hasActiveSync) {
      await _drainRealtimeIfReady();
    }
  }

  Future<bool> _pullOnce({
    required SyncKind kind,
    required String reason,
    int? pruneProtectSinceSeq,
  }) async {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return false;

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
      settings: todoNotifier.settings,
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
          if (!_disposed && _activePush == null) {
            state = state.copyWith(status: SyncStatus.idle);
          }
          return false;
        }
        _log.info(
          'sync success reason=$reason forceFullSync=$forceFullSync '
          'lists=${outcome.lists.length} tasks=${outcome.tasks.length}',
        );
        if (ref.read(accountProvider).activeAccount?.id == active.id) {
          await todoNotifier.applyPulledState(
            groups: kind == SyncKind.pushOnly ? null : outcome.groups,
            lists: kind == SyncKind.pushOnly ? null : outcome.lists,
            tasks: outcome.tasks,
            settingsPatch: outcome.settingsPatch,
          );
        }
        await ref
            .read(accountProvider.notifier)
            .updateSyncStatus(
              active.id,
              lastSyncedAt: outcome.syncedAt,
              clearSyncError: true,
            );
        await _refreshProfileIfIncomplete(service, active);
        if (!_disposed && _activePush == null) {
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

  Future<void> _refreshProfileIfIncomplete(
    CloudSyncService service,
    MicrosoftAccount account,
  ) async {
    final needsName =
        account.displayName == 'Microsoft Account' ||
        account.displayName.trim().isEmpty ||
        (account.email.isNotEmpty && account.displayName == account.email);
    final needsEmail = account.email.trim().isEmpty;
    final needsAvatar =
        account.avatarBase64 == null || account.avatarBase64!.isEmpty;
    if (!needsName && !needsEmail && !needsAvatar) return;

    await guardApiCall(() async {
      final tokens = await service.tokenStorage.loadTokens(account.id);
      if (tokens == null || tokens.refreshToken.isEmpty) return;
      final cid = tokens.userId.isNotEmpty
          ? tokens.userId
          : account.microsoftUserId;
      final profile = await service.authClient.fetchUserProfile(
        cid: cid,
        refreshToken: tokens.refreshToken,
        fallbackEmail: account.email,
      );
      if (_disposed) return;

      final nextName =
          profile.displayName.trim().isNotEmpty &&
              profile.displayName != 'Microsoft Account' &&
              (needsName || profile.displayName != account.displayName)
          ? profile.displayName
          : null;
      final nextEmail =
          profile.email.trim().isNotEmpty &&
              (needsEmail || profile.email != account.email)
          ? profile.email
          : null;
      final nextAvatar =
          (profile.avatarBase64 != null &&
              profile.avatarBase64!.isNotEmpty &&
              needsAvatar)
          ? profile.avatarBase64
          : null;

      if (nextName == null && nextEmail == null && nextAvatar == null) {
        return;
      }
      await ref
          .read(accountProvider.notifier)
          .updateMicrosoftProfile(
            account.id,
            displayName: nextName,
            email: nextEmail,
            avatarBase64: nextAvatar,
          );
    }, operation: 'refreshProfile');
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
