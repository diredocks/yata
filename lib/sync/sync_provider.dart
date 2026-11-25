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
  static const _debounceDuration = Duration(milliseconds: 1500);
  static const _foregroundDebounceDuration = Duration(milliseconds: 500);
  static const _periodicSyncInterval = Duration(seconds: 120);

  Timer? _debounceTimer;
  Timer? _periodicTimer;
  RealtimeSyncController? _realtimeController;

  bool _disposed = false;
  bool _isForeground = true;
  Future<void>? _activeSync;
  bool _syncQueued = false;
  bool _pendingDebouncedForceFullSync = false;
  String _pendingDebouncedReason = 'debounced';
  bool _queuedForceFullSync = false;
  String _queuedReason = 'queued';

  RealtimeSyncController _ensureRealtimeController() {
    return _realtimeController ??= RealtimeSyncController(
      ref: ref,
      isSyncInFlight: () => _activeSync != null,
      onScheduleFallbackSync: ({required delay, required forceFullSync, required reason}) {
        scheduleDebouncedSync(
          delay: delay,
          forceFullSync: forceFullSync,
          reason: reason,
        );
      },
      onOverflowResync: (reason) {
        _syncQueued = true;
        _queuedForceFullSync = true;
        _queuedReason = reason;
      },
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
        scheduleDebouncedSync(reason: 'local_mutation');
      }
    });

    if (!accountIdentity.isMicrosoft || activeAccount is! MicrosoftAccount) {
      realtime.stop(clearPending: true);
      _stopPeriodicSync();
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _pendingDebouncedForceFullSync = false;
      _pendingDebouncedReason = 'debounced';
      _queuedForceFullSync = false;
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
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingDebouncedForceFullSync = false;
    _pendingDebouncedReason = 'debounced';
    _queuedForceFullSync = false;
    _queuedReason = 'queued';
    _stopPeriodicSync();
    _realtimeController?.dispose();
    _realtimeController = null;
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
    appLog('onAppPaused: stopping realtime & periodic sync', label: 'Sync');
    _stopPeriodicSync();
    _realtimeController?.onAppPaused();
    if (_debounceTimer != null && _debounceTimer!.isActive) {
      _debounceTimer!.cancel();
      _debounceTimer = null;
      final full = _pendingDebouncedForceFullSync;
      final r = _pendingDebouncedReason;
      _pendingDebouncedForceFullSync = false;
      _pendingDebouncedReason = 'debounced';
      appLog(
        'onAppPaused: flushing pending debounced sync reason=$r forceFullSync=$full',
        label: 'Sync',
      );
      unawaited(syncNow(forceFullSync: full, reason: r));
    }
  }

  /// Resumes foreground sync channels and triggers a debounced sync when the
  /// app returns to the foreground.
  void onAppResumed() {
    if (_disposed) return;
    _isForeground = true;
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return;

    appLog(
      'onAppResumed: restarting realtime & scheduling full sync',
      label: 'Sync',
    );
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

  /// Starts an initial full sync on cold start (when enabled) or account switch.
  void syncOnSessionStart({bool accountChanged = false}) {
    if (!accountChanged && !ref.read(startupSyncEnabledProvider)) return;
    final account = ref.read(accountProvider).activeAccount;
    if (account is! MicrosoftAccount) return;
    unawaited(
      syncNow(
        forceFullSync: true,
        reason: accountChanged ? 'account_changed' : 'startup',
      ),
    );
  }

  void scheduleDebouncedSync({
    Duration delay = _debounceDuration,
    bool forceFullSync = false,
    String reason = 'debounced',
  }) {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    if (forceFullSync || !_pendingDebouncedForceFullSync) {
      _pendingDebouncedReason = reason;
    }
    _pendingDebouncedForceFullSync =
        _pendingDebouncedForceFullSync || forceFullSync;
    appLog(
      'scheduleDebouncedSync reason=$_pendingDebouncedReason '
      'delay=${delay.inMilliseconds}ms '
      'forceFullSync=$_pendingDebouncedForceFullSync',
      label: 'Sync',
    );

    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      if (_disposed) return;
      final full = _pendingDebouncedForceFullSync;
      final r = _pendingDebouncedReason;
      _pendingDebouncedForceFullSync = false;
      _pendingDebouncedReason = 'debounced';
      unawaited(syncNow(forceFullSync: full, reason: r));
    });
  }

  Future<void> syncNow({
    bool forceFullSync = false,
    String reason = 'manual',
  }) {
    if (_disposed) return Future<void>.value();
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return Future<void>.value();

    final inFlight = _activeSync;
    if (inFlight != null) {
      _syncQueued = true;
      if (forceFullSync) {
        _queuedForceFullSync = true;
        _queuedReason = reason;
      }
      appLog(
        'syncNow coalesced into in-flight sync: reason=$reason '
        'forceFullSync=$forceFullSync '
        '(queuedFull=$_queuedForceFullSync)',
        label: 'Sync',
      );
      return inFlight;
    }

    final completer = Completer<void>();
    _activeSync = completer.future;
    unawaited(() async {
      try {
        await _runSyncLoop(
          initialForceFullSync: forceFullSync,
          initialReason: reason,
        );
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _runSyncLoop({
    required bool initialForceFullSync,
    required String initialReason,
  }) async {
    state = state.copyWith(status: SyncStatus.syncing, error: null);
    var nextForceFullSync = initialForceFullSync;
    var nextReason = initialReason;
    try {
      do {
        _syncQueued = false;
        final runForceFull = nextForceFullSync;
        final runReason = nextReason;
        nextForceFullSync = false;
        nextReason = 'queued';
        await _syncOnce(forceFullSync: runForceFull, reason: runReason);
        if (_syncQueued && !_disposed) {
          nextForceFullSync = _queuedForceFullSync;
          nextReason = _queuedReason;
          _queuedForceFullSync = false;
          _queuedReason = 'queued';
        }
      } while (_syncQueued && !_disposed);
    } finally {
      _syncQueued = false;
      _queuedForceFullSync = false;
      _queuedReason = 'queued';
      _activeSync = null;
    }
    final realtime = _realtimeController;
    if (!_disposed && realtime != null && realtime.hasPendingEvents) {
      await realtime.drainPendingIfReady();
    }
  }

  Future<void> _syncOnce({
    required bool forceFullSync,
    required String reason,
  }) async {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    appLog(
      'sync start account=${active.id} reason=$reason '
      'forceFullSync=$forceFullSync',
      label: 'Sync',
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
      forceFullSync: forceFullSync,
      reason: reason,
    );

    if (_disposed) return;

    await result.fold(
      (outcome) async {
        appLog(
          'sync success reason=$reason forceFullSync=$forceFullSync '
          'lists=${outcome.lists.length} tasks=${outcome.tasks.length} '
          'pushedTasks=${outcome.syncedTaskIds.length}',
          label: 'Sync',
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
        appLog(
          'sync error reason=$reason status=$status error=${error.describe()}',
          label: 'Sync',
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
