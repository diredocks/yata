import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'cloud_sync_service.dart';
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

class SyncNotifier extends Notifier<SyncState> {
  /// Coalescing window for local edits.
  static const _mutationDebounceDuration = Duration(milliseconds: 300);

  /// Cap on how long continued activity may postpone a pending pass.
  static const _maxCoalesceDelay = Duration(seconds: 1);
  static const _debounceDuration = Duration(milliseconds: 1500);
  static const _foregroundDebounceDuration = Duration(milliseconds: 500);
  static const _periodicSyncInterval = Duration(seconds: 120);

  Timer? _debounceTimer;
  DateTime? _debounceStartedAt;
  DateTime? _debounceDeadline;
  SyncKind? _pendingKind;
  String _pendingReason = 'debounced';
  Timer? _periodicTimer;
  RealtimeSyncController? _realtimeController;

  bool _disposed = false;
  bool _isForeground = true;
  Future<void>? _activeSync;
  bool _syncQueued = false;
  SyncKind? _queuedKind;
  String _queuedReason = 'queued';

  RealtimeSyncController _ensureRealtimeController() {
    return _realtimeController ??= RealtimeSyncController(
      ref: ref,
      isSyncInFlight: () => _activeSync != null,
      onScheduleFallbackSync:
          ({required delay, required forceFullSync, required reason}) {
            scheduleDebouncedSync(
              delay: delay,
              forceFullSync: forceFullSync,
              reason: reason,
            );
          },
      onOverflowResync: (reason) {
        _syncQueued = true;
        _queuedKind = _mergeSyncKind(_queuedKind, SyncKind.full);
        _queuedReason = reason;
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
      _cancelDebounce();
      _queuedKind = null;
      _queuedReason = 'queued';
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
    _cancelDebounce();
    _queuedKind = null;
    _queuedReason = 'queued';
    _stopPeriodicSync();
    _realtimeController?.dispose();
    _realtimeController = null;
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _debounceStartedAt = null;
    _debounceDeadline = null;
    _pendingKind = null;
    _pendingReason = 'debounced';
  }

  void _startPeriodicSync() {
    if (_disposed || !_isForeground || _periodicTimer != null) return;
    _periodicTimer = Timer.periodic(_periodicSyncInterval, (_) {
      if (!_disposed && _isForeground) {
        unawaited(syncNow(reason: 'periodic'));
      }
    });
  }

  void _stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Pauses foreground-only sync channels (realtime long-polling and periodic
  /// timer) when the app moves to the background.
  void onAppPaused() {
    if (_disposed || !_isForeground) return;
    _isForeground = false;
    _log.info('onAppPaused: stopping realtime & periodic sync');
    _stopPeriodicSync();
    _realtimeController?.onAppPaused();
    final pending = _pendingKind;
    if (pending != null && _debounceTimer != null && _debounceTimer!.isActive) {
      final reason = _pendingReason;
      _cancelDebounce();
      _log.info(
        'onAppPaused: flushing pending debounced sync reason=$reason '
        'kind=${pending.name}',
      );
      unawaited(_syncNowForKind(pending, reason: reason));
    }
  }

  /// Resumes foreground sync channels and triggers a debounced sync when the
  /// app returns to the foreground.
  void onAppResumed() {
    if (_disposed) return;
    _isForeground = true;
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return;

    _log.info('onAppResumed: restarting realtime & scheduling full sync');
    if (ref.read(realtimeSyncEnabledProvider)) {
      _ensureRealtimeController().ensureStartedFor(active);
    }
    if (ref.read(periodicSyncEnabledProvider)) {
      _startPeriodicSync();
    }
    scheduleDebouncedSync(
      delay: _foregroundDebounceDuration,
      forceFullSync: true,
      reason: 'app_resumed',
    );
  }

  /// Triggers an immediate full sync for manual user refreshes (header, settings, pull-to-refresh).
  Future<void> refresh({String reason = 'manual'}) =>
      syncNow(forceFullSync: true, reason: reason);

  /// Starts an incremental sync on cold start (when enabled) or full sync on account switch.
  void syncOnSessionStart({bool accountChanged = false}) {
    if (!accountChanged && !ref.read(startupSyncEnabledProvider)) return;
    final account = ref.read(accountProvider).activeAccount;
    if (account is! MicrosoftAccount) return;
    unawaited(
      syncNow(
        forceFullSync: accountChanged,
        reason: accountChanged ? 'account_changed' : 'startup',
      ),
    );
  }

  /// Schedules a delta/full pass, coalescing pending requests into one.
  void scheduleDebouncedSync({
    Duration delay = _debounceDuration,
    bool forceFullSync = false,
    String reason = 'debounced',
  }) {
    _scheduleSync(
      kind: forceFullSync ? SyncKind.full : SyncKind.delta,
      delay: delay,
      reason: reason,
    );
  }

  void schedulePushOnlySync({
    Duration delay = _mutationDebounceDuration,
    String reason = 'local_mutation',
  }) {
    _scheduleSync(kind: SyncKind.pushOnly, delay: delay, reason: reason);
  }

  void _scheduleSync({
    required SyncKind kind,
    required Duration delay,
    required String reason,
  }) {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    final previous = _pendingKind;
    final merged = _mergeSyncKind(previous, kind);
    _pendingKind = merged;
    if (previous == null || merged != previous) {
      _pendingReason = reason;
    }

    final now = DateTime.now();
    final startedAt = _debounceStartedAt;
    final deadline = _debounceDeadline;
    final isPending = deadline != null && deadline.isAfter(now);
    final DateTime fireAt;
    if (isPending && startedAt != null) {
      final cap = startedAt.add(
        delay > _maxCoalesceDelay ? delay : _maxCoalesceDelay,
      );
      final extended = now.add(delay);
      fireAt = extended.isAfter(cap) ? cap : extended;
    } else {
      _debounceStartedAt = now;
      fireAt = now.add(delay);
    }
    _log.info(
      'scheduleDebouncedSync reason=$_pendingReason kind=${merged.name} '
      'delay=${delay.inMilliseconds}ms '
      'fireIn=${fireAt.difference(now).inMilliseconds}ms',
    );

    _debounceTimer?.cancel();
    _debounceDeadline = fireAt;
    _debounceTimer = Timer(fireAt.difference(now), () {
      if (_disposed) return;
      final pendingKind = _pendingKind ?? SyncKind.delta;
      final pendingReason = _pendingReason;
      _cancelDebounce();
      unawaited(_syncNowForKind(pendingKind, reason: pendingReason));
    });
  }

  Future<void> syncNow({
    bool forceFullSync = false,
    String reason = 'manual',
  }) => _syncNowForKind(
    forceFullSync ? SyncKind.full : SyncKind.delta,
    reason: reason,
  );

  /// Runs [kind] now, or queues it behind the in-flight pass.
  Future<void> _syncNowForKind(SyncKind kind, {String reason = 'manual'}) {
    if (_disposed) return Future<void>.value();
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return Future<void>.value();

    final inFlight = _activeSync;
    if (inFlight != null) {
      _syncQueued = true;
      final merged = _mergeSyncKind(_queuedKind, kind);
      if (merged != _queuedKind) {
        _queuedReason = reason;
      }
      _queuedKind = merged;
      _log.info(
        'syncNow coalesced into in-flight sync: reason=$reason '
        'kind=${kind.name} (queuedKind=${merged.name})',
      );
      return inFlight;
    }

    final completer = Completer<void>();
    _activeSync = completer.future;
    unawaited(() async {
      try {
        await _runSyncLoop(initialKind: kind, initialReason: reason);
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _runSyncLoop({
    required SyncKind initialKind,
    required String initialReason,
  }) async {
    state = state.copyWith(status: SyncStatus.syncing, error: null);
    var nextKind = initialKind;
    var nextReason = initialReason;
    try {
      do {
        _syncQueued = false;
        final runKind = nextKind;
        final runReason = nextReason;
        nextReason = 'queued';
        await _syncOnce(kind: runKind, reason: runReason);
        if (_syncQueued && !_disposed) {
          nextKind = _queuedKind ?? SyncKind.delta;
          nextReason = _queuedReason;
          _queuedKind = null;
          _queuedReason = 'queued';
        }
      } while (_syncQueued && !_disposed);
    } finally {
      _syncQueued = false;
      _queuedKind = null;
      _queuedReason = 'queued';
      _activeSync = null;
    }
    final realtime = _realtimeController;
    if (!_disposed && realtime != null && realtime.hasPendingEvents) {
      await realtime.drainPendingIfReady();
    }
  }

  Future<void> _syncOnce({
    required SyncKind kind,
    required String reason,
  }) async {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    final forceFullSync = kind == SyncKind.full;

    _log.info(
      'sync start account=${active.id} reason=$reason '
      'kind=${kind.name} forceFullSync=$forceFullSync',
    );

    final service = ref.read(cloudSyncServiceProvider);
    final todoNotifier = ref.read(todoProvider.notifier);
    final snapshotState = ref.read(todoProvider);

    final result = await service.syncAccount(
      account: active,
      currentState: snapshotState,
      repository: todoNotifier.repository,
      settings: todoNotifier.settings,
      idGenerator: todoNotifier.nextId,
      readLatestState: () => ref.read(todoProvider),
      kind: kind,
      reason: reason,
    );

    if (_disposed) return;

    await result.fold(
      (outcome) async {
        _log.info(
          'sync success reason=$reason forceFullSync=$forceFullSync '
          'lists=${outcome.lists.length} tasks=${outcome.tasks.length} '
          'pushedTasks=${outcome.syncedTaskIds.length}',
        );
        if (ref.read(accountProvider).activeAccount?.id == active.id) {
          final effectiveSnapshot = outcome.snapshotState ?? snapshotState;
          await todoNotifier.applySyncResult(
            groups: outcome.groups,
            lists: outcome.lists,
            tasks: outcome.tasks,
            settingsPatch: outcome.settingsPatch,
            snapshotGroups: effectiveSnapshot.groups,
            snapshotLists: effectiveSnapshot.lists,
            snapshotTasks: effectiveSnapshot.tasks,
            snapshotState: effectiveSnapshot,
            processedDeletedGroupRemoteIds:
                outcome.processedDeletedGroupRemoteIds,
            processedDeletedListRemoteIds:
                outcome.processedDeletedListRemoteIds,
            processedDeletedTaskRemoteIds:
                outcome.processedDeletedTaskRemoteIds,
            processedDeletedSteps: outcome.processedDeletedSteps,
            syncedGroupIds: outcome.syncedGroupIds,
            syncedListIds: outcome.syncedListIds,
            syncedTaskIds: outcome.syncedTaskIds,
            syncedSettingKeys: outcome.syncedSettingKeys,
            syncedDirtyFields: outcome.syncedDirtyFields,
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
        if (!_disposed) {
          state = state.copyWith(
            status: SyncStatus.success,
            lastSyncedAt: outcome.syncedAt,
            error: null,
          );
        }
      },
      (error) async {
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
      },
    );
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
