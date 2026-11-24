import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'cloud_sync_service.dart';
import 'microsoft_todo_api.dart';
import 'substrate_sync_mappers.dart';
import 'sync_guard.dart';
import 'sync_log_format.dart';

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
  static const _realtimeInitialBackoff = Duration(seconds: 2);
  static const _realtimeMaxBackoff = Duration(seconds: 60);
  static const _maxPendingRealtimeEvents = 200;

  Timer? _debounceTimer;
  Timer? _periodicTimer;
  Timer? _realtimeReconnectTimer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  bool _disposed = false;
  bool _isForeground = true;
  Future<void>? _activeSync;
  bool _syncQueued = false;
  bool _pendingDebouncedForceFullSync = false;
  String _pendingDebouncedReason = 'debounced';
  bool _queuedForceFullSync = false;
  String _queuedReason = 'queued';
  final List<RealtimeEvent> _pendingRealtimeEvents = [];
  bool _realtimeNeedsFullSyncOnConnect = false;
  Duration _realtimeBackoff = _realtimeInitialBackoff;
  String? _realtimeAccountId;

  static bool _shouldForceFullSyncForEvent(RealtimeEvent event) {
    final typeLower = event.type.trim().toLowerCase();
    return typeLower == 'task' ||
        typeLower == 'taskfolder' ||
        typeLower == 'foldergroup';
  }

  @override
  SyncState build() {
    _disposed = false;
    ref.onDispose(_disposeResources);

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
      _stopRealtime();
      _stopPeriodicSync();
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _pendingDebouncedForceFullSync = false;
      _pendingDebouncedReason = 'debounced';
      _queuedForceFullSync = false;
      _queuedReason = 'queued';
      _pendingRealtimeEvents.clear();
      _realtimeNeedsFullSyncOnConnect = false;
      return const SyncState();
    }

    if (_isForeground) {
      if (ref.watch(realtimeSyncEnabledProvider) &&
          _realtimeAccountId != activeAccount.id) {
        _startRealtimeFor(activeAccount);
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
    _pendingRealtimeEvents.clear();
    _realtimeNeedsFullSyncOnConnect = false;
    _stopPeriodicSync();
    _stopRealtime();
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
    _realtimeNeedsFullSyncOnConnect = false;
    appLog('onAppPaused: stopping realtime & periodic sync', label: 'Sync');
    _stopPeriodicSync();
    _stopRealtime();
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
    if (ref.read(realtimeSyncEnabledProvider) &&
        _realtimeAccountId != active.id) {
      _startRealtimeFor(active);
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

  void _stopRealtime() {
    _realtimeAccountId = null;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    unawaited(_realtimeSub?.cancel());
    _realtimeSub = null;
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
    if (!_disposed && _pendingRealtimeEvents.isNotEmpty) {
      await _drainPendingRealtimeEvents();
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
            syncedGroupFields: outcome.syncedGroupFields,
            syncedListFields: outcome.syncedListFields,
            syncedTaskFields: outcome.syncedTaskFields,
            syncedStepIds: outcome.syncedStepIds,
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

    // Best-effort; failures are logged by the guard.
  }

  void _startRealtimeFor(MicrosoftAccount account) {
    final accountChanged =
        _realtimeAccountId != null && _realtimeAccountId != account.id;
    _stopRealtime();
    if (accountChanged) {
      _pendingRealtimeEvents.clear();
      _realtimeNeedsFullSyncOnConnect = false;
    }
    _realtimeAccountId = account.id;
    _realtimeBackoff = _realtimeInitialBackoff;
    unawaited(_connectRealtime(account));
  }

  Future<void> _connectRealtime(MicrosoftAccount account) async {
    if (_disposed || _realtimeAccountId != account.id) return;
    if (!ref.read(realtimeSyncEnabledProvider)) return;

    final service = ref.read(cloudSyncServiceProvider);
    final settings = ref.read(todoProvider.notifier).settings;
    final ctxResult = await service.resolveContext(account, settings);

    if (_disposed || _realtimeAccountId != account.id) return;

    final ctx = ctxResult.fold((ctx) => ctx, (_) => null);
    if (ctx == null) {
      _scheduleRealtimeReconnect(account, reason: 'no_context');
      return;
    }

    final stream = service.todoApi.connectRealtime(ctx);
    _realtimeSub = stream.listen(
      (event) {
        if (_disposed || _realtimeAccountId != account.id) return;
        _realtimeBackoff = _realtimeInitialBackoff;
        if (_realtimeNeedsFullSyncOnConnect) {
          _realtimeNeedsFullSyncOnConnect = false;
          appLog('reconnected; scheduling full sync', label: 'SyncRealtime');
          scheduleDebouncedSync(
            delay: _foregroundDebounceDuration,
            forceFullSync: true,
            reason: 'realtime_reconnected',
          );
        }
        if (event.isKeepAlive) return;
        if (service.todoApi.isOwnRequestId(event.requestId)) {
          appLog(
            'ignore own event type=${event.type} op=${event.operation} '
            'id=${shortSyncId(event.id)} req=${event.requestId}',
            label: 'SyncRealtime',
          );
          return;
        }
        unawaited(_handleRemoteRealtimeEvent(account, event));
      },
      onError: (Object error) {
        appLog('stream error=$error', label: 'SyncRealtime');
        _realtimeNeedsFullSyncOnConnect = true;
        _scheduleRealtimeReconnect(account, reason: 'error');
      },
      onDone: () {
        appLog('stream done', label: 'SyncRealtime');
        _realtimeNeedsFullSyncOnConnect = true;
        _scheduleRealtimeReconnect(account, reason: 'done');
      },
      cancelOnError: true,
    );
  }

  Future<void> _handleRemoteRealtimeEvent(
    MicrosoftAccount account,
    RealtimeEvent event,
  ) async {
    if (_disposed ||
        _realtimeAccountId != account.id ||
        ref.read(accountProvider).activeAccount?.id != account.id) {
      return;
    }

    if (_activeSync != null) {
      if (_pendingRealtimeEvents.length >= _maxPendingRealtimeEvents) {
        _pendingRealtimeEvents.clear();
        _syncQueued = true;
        _queuedForceFullSync = true;
        _queuedReason = 'realtime_overflow';
        appLog(
          'deferred queue overflow ($_maxPendingRealtimeEvents); '
          'scheduling full resync',
          label: 'SyncRealtime',
        );
        return;
      }
      _pendingRealtimeEvents.add(event);
      appLog(
        'deferred event while syncing: type=${event.type} '
        'op=${event.operation} id=${shortSyncId(event.id)} '
        'queued=${_pendingRealtimeEvents.length}',
        label: 'SyncRealtime',
      );
      return;
    }

    final handled = await _applyRealtimeEventNow(account, event);
    if (!handled && !_disposed) {
      scheduleDebouncedSync(
        delay: const Duration(milliseconds: 200),
        forceFullSync: _shouldForceFullSyncForEvent(event),
        reason: 'realtime_${event.type}_${event.operation ?? 'unknown'}',
      );
    }
  }

  Future<void> _drainPendingRealtimeEvents() async {
    if (_disposed || _pendingRealtimeEvents.isEmpty) return;
    final initialActive = ref.read(accountProvider).activeAccount;
    if (initialActive is! MicrosoftAccount ||
        _realtimeAccountId != initialActive.id) {
      _pendingRealtimeEvents.clear();
      return;
    }

    appLog(
      'draining ${_pendingRealtimeEvents.length} deferred realtime event(s)',
      label: 'SyncRealtime',
    );

    var needsFallbackSync = false;
    var fallbackForceFullSync = false;
    var fallbackReason = 'realtime_deferred';

    while (!_disposed &&
        _activeSync == null &&
        _pendingRealtimeEvents.isNotEmpty) {
      final currentActive = ref.read(accountProvider).activeAccount;
      if (currentActive is! MicrosoftAccount ||
          _realtimeAccountId != currentActive.id) {
        _pendingRealtimeEvents.clear();
        return;
      }
      final event = _pendingRealtimeEvents.removeAt(0);
      final handled = await _applyRealtimeEventNow(
        currentActive,
        event,
        fromQueue: true,
      );
      if (!handled) {
        needsFallbackSync = true;
        if (_shouldForceFullSyncForEvent(event)) {
          fallbackForceFullSync = true;
        }
        fallbackReason =
            'realtime_${event.type}_${event.operation ?? 'unknown'}';
      }
    }

    if (needsFallbackSync && !_disposed) {
      scheduleDebouncedSync(
        delay: const Duration(milliseconds: 200),
        forceFullSync: fallbackForceFullSync,
        reason: fallbackReason,
      );
    }
  }

  Future<bool> _applyRealtimeEventNow(
    MicrosoftAccount account,
    RealtimeEvent event, {
    bool fromQueue = false,
  }) async {
    if (_disposed ||
        _realtimeAccountId != account.id ||
        ref.read(accountProvider).activeAccount?.id != account.id) {
      return true;
    }

    final todoNotifier = ref.read(todoProvider.notifier);
    final currentState = ref.read(todoProvider);
    final typeLower = event.type.trim().toLowerCase();
    final prefix = fromQueue ? '(drained) ' : '';

    switch (typeLower) {
      case 'task':
        final result = mergeRealtimeTaskEvent(
          event: event,
          lists: currentState.lists,
          currentTasks: currentState.tasks,
          dirtyTaskIds: todoNotifier.repository.loadDirtyTaskIds().toSet(),
          pendingDeletedTaskRemoteIds: todoNotifier.repository
              .loadPendingDeletedTaskRemoteIds()
              .toSet(),
          idGenerator: todoNotifier.nextId,
        );
        if (result.handled) {
          appLog('$prefix${result.summary}', label: 'SyncRealtime');
          if (result.changed && result.tasks != null) {
            await todoNotifier.applyRemoteTasksSnapshot(result.tasks!);
          }
          return true;
        }
        appLog(
          '$prefix${result.summary}; fallback to sync (forceFullSync=true)',
          label: 'SyncRealtime',
        );
        return false;

      case 'taskfolder':
        final result = mergeRealtimeFolderEvent(
          event: event,
          groups: currentState.groups,
          currentLists: currentState.lists,
          currentTasks: currentState.tasks,
          dirtyListIds: todoNotifier.repository.loadDirtyListIds().toSet(),
          pendingDeletedListRemoteIds: todoNotifier.repository
              .loadPendingDeletedListRemoteIds()
              .toSet(),
          idGenerator: todoNotifier.nextId,
        );
        if (result.handled) {
          appLog('$prefix${result.summary}', label: 'SyncRealtime');
          if (result.changed && result.lists != null) {
            await todoNotifier.applyRemoteListsSnapshot(
              nextLists: result.lists!,
              nextTasks: result.tasks,
            );
          }
          return true;
        }
        appLog(
          '$prefix${result.summary}; fallback to sync (forceFullSync=true)',
          label: 'SyncRealtime',
        );
        return false;

      case 'foldergroup':
        final result = mergeRealtimeFolderGroupEvent(
          event: event,
          currentGroups: currentState.groups,
          dirtyGroupIds: todoNotifier.repository.loadDirtyGroupIds().toSet(),
          pendingDeletedGroupRemoteIds: todoNotifier.repository
              .loadPendingDeletedGroupRemoteIds()
              .toSet(),
          idGenerator: todoNotifier.nextId,
        );
        if (result.handled) {
          appLog('$prefix${result.summary}', label: 'SyncRealtime');
          if (result.changed && result.groups != null) {
            await todoNotifier.applyRemoteGroupsSnapshot(result.groups!);
          }
          return true;
        }
        appLog(
          '$prefix${result.summary}; fallback to sync (forceFullSync=true)',
          label: 'SyncRealtime',
        );
        return false;

      case 'setting':
        final result = mergeRealtimeSettingEvent(
          event: event,
          dirtySettingKeys: todoNotifier.settings
              .loadDirtySettingKeys()
              .toSet(),
        );
        if (result.handled) {
          appLog('$prefix${result.summary}', label: 'SyncRealtime');
          if (result.changed && result.patch != null) {
            await todoNotifier.applyRemoteSettingsPatch(result.patch!);
          }
          return true;
        }
        appLog(
          '$prefix${result.summary}; fallback to sync (forceFullSync=false)',
          label: 'SyncRealtime',
        );
        return false;

      default:
        appLog(
          '${prefix}non-direct event type=${event.type} op=${event.operation}; '
          'fallback to sync (forceFullSync=false)',
          label: 'SyncRealtime',
        );
        return false;
    }
  }

  void _scheduleRealtimeReconnect(
    MicrosoftAccount account, {
    required String reason,
  }) {
    if (_disposed || _realtimeAccountId != account.id) return;
    if (!ref.read(realtimeSyncEnabledProvider)) return;
    _realtimeSub = null;
    _realtimeReconnectTimer?.cancel();
    final wait = _realtimeBackoff;
    final nextSecs = (wait.inSeconds * 2).clamp(
      _realtimeInitialBackoff.inSeconds,
      _realtimeMaxBackoff.inSeconds,
    );
    _realtimeBackoff = Duration(seconds: nextSecs);
    appLog(
      'scheduling reconnect reason=$reason wait=${wait.inSeconds}s',
      label: 'SyncRealtime',
    );
    _realtimeReconnectTimer = Timer(wait, () {
      if (!_disposed && _realtimeAccountId == account.id) {
        unawaited(_connectRealtime(account));
      }
    });
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
