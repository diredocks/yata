import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../core/logging/app_logger.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'microsoft_todo_api.dart';
import 'realtime_event_merger.dart';
import 'sync_log_format.dart';
import 'sync_provider.dart';

/// Manages the foreground Substrate `/realtime` long-polling connection,
/// reconnect backoff, mid-sync event buffering, and direct state merging.
class RealtimeSyncController {
  RealtimeSyncController({
    required this.ref,
    required this.isSyncInFlight,
    required this.onScheduleFallbackSync,
    required this.onOverflowResync,
  });

  static const _reconnectDebounceDuration = Duration(milliseconds: 500);
  static const _initialBackoff = Duration(seconds: 2);
  static const _maxBackoff = Duration(seconds: 60);
  static const _maxPendingEvents = 200;

  final Ref ref;
  final bool Function() isSyncInFlight;
  final void Function({
    required Duration delay,
    required bool forceFullSync,
    required String reason,
  })
  onScheduleFallbackSync;
  final void Function(String reason) onOverflowResync;

  Timer? _reconnectTimer;
  StreamSubscription<RealtimeEvent>? _sub;
  final List<RealtimeEvent> _pendingEvents = [];
  bool _needsFullSyncOnConnect = false;
  Duration _backoff = _initialBackoff;
  String? _accountId;
  bool _disposed = false;

  bool get hasPendingEvents => _pendingEvents.isNotEmpty;

  static bool _shouldForceFullSyncForEvent(RealtimeEvent event) {
    final typeLower = event.type.trim().toLowerCase();
    return typeLower == 'task' ||
        typeLower == 'taskfolder' ||
        typeLower == 'foldergroup';
  }

  void ensureStartedFor(MicrosoftAccount account) {
    if (_disposed || _accountId == account.id) return;
    startFor(account);
  }

  void startFor(MicrosoftAccount account) {
    if (_disposed) return;
    final accountChanged = _accountId != null && _accountId != account.id;
    stop(clearPending: accountChanged);
    _accountId = account.id;
    _backoff = _initialBackoff;
    unawaited(_connect(account));
  }

  void stop({bool clearPending = false}) {
    _accountId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    if (clearPending) {
      _pendingEvents.clear();
      _needsFullSyncOnConnect = false;
    }
  }

  void onAppPaused() {
    _needsFullSyncOnConnect = false;
    stop();
  }

  void dispose() {
    _disposed = true;
    stop(clearPending: true);
  }

  Future<void> _connect(MicrosoftAccount account) async {
    if (_disposed || _accountId != account.id) return;
    if (!ref.read(realtimeSyncEnabledProvider)) return;

    final service = ref.read(cloudSyncServiceProvider);
    final settings = ref.read(todoProvider.notifier).settings;
    final ctxResult = await service.resolveContext(account, settings);

    if (_disposed || _accountId != account.id) return;

    final ctx = ctxResult.fold((ctx) => ctx, (_) => null);
    if (ctx == null) {
      _scheduleReconnect(account, reason: 'no_context');
      return;
    }

    final stream = service.todoApi.connectRealtime(ctx);
    _sub = stream.listen(
      (event) {
        if (_disposed || _accountId != account.id) return;
        _backoff = _initialBackoff;
        if (_needsFullSyncOnConnect) {
          _needsFullSyncOnConnect = false;
          appLog('reconnected; scheduling full sync', label: 'SyncRealtime');
          onScheduleFallbackSync(
            delay: _reconnectDebounceDuration,
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
        unawaited(_handleRemoteEvent(account, event));
      },
      onError: (Object error) {
        appLog('stream error=$error', label: 'SyncRealtime');
        _needsFullSyncOnConnect = true;
        _scheduleReconnect(account, reason: 'error');
      },
      onDone: () {
        appLog('stream done', label: 'SyncRealtime');
        _needsFullSyncOnConnect = true;
        _scheduleReconnect(account, reason: 'done');
      },
      cancelOnError: true,
    );
  }

  Future<void> _handleRemoteEvent(
    MicrosoftAccount account,
    RealtimeEvent event,
  ) async {
    if (_disposed ||
        _accountId != account.id ||
        ref.read(accountProvider).activeAccount?.id != account.id) {
      return;
    }

    if (isSyncInFlight()) {
      if (_pendingEvents.length >= _maxPendingEvents) {
        _pendingEvents.clear();
        onOverflowResync('realtime_overflow');
        appLog(
          'deferred queue overflow ($_maxPendingEvents); '
          'scheduling full resync',
          label: 'SyncRealtime',
        );
        return;
      }
      _pendingEvents.add(event);
      appLog(
        'deferred event while syncing: type=${event.type} '
        'op=${event.operation} id=${shortSyncId(event.id)} '
        'queued=${_pendingEvents.length}',
        label: 'SyncRealtime',
      );
      return;
    }

    final handled = await _applyRealtimeEventNow(account, event);
    if (!handled && !_disposed) {
      onScheduleFallbackSync(
        delay: const Duration(milliseconds: 200),
        forceFullSync: _shouldForceFullSyncForEvent(event),
        reason: 'realtime_${event.type}_${event.operation ?? 'unknown'}',
      );
    }
  }

  Future<void> drainPendingIfReady() async {
    if (_disposed || _pendingEvents.isEmpty) return;
    final initialActive = ref.read(accountProvider).activeAccount;
    if (initialActive is! MicrosoftAccount || _accountId != initialActive.id) {
      _pendingEvents.clear();
      return;
    }

    appLog(
      'draining ${_pendingEvents.length} deferred realtime event(s)',
      label: 'SyncRealtime',
    );

    var needsFallbackSync = false;
    var fallbackForceFullSync = false;
    var fallbackReason = 'realtime_deferred';

    while (!_disposed && !isSyncInFlight() && _pendingEvents.isNotEmpty) {
      final currentActive = ref.read(accountProvider).activeAccount;
      if (currentActive is! MicrosoftAccount ||
          _accountId != currentActive.id) {
        _pendingEvents.clear();
        return;
      }
      final event = _pendingEvents.removeAt(0);
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
      onScheduleFallbackSync(
        delay: const Duration(milliseconds: 200),
        forceFullSync: fallbackForceFullSync,
        reason: fallbackReason,
      );
    }
  }

  Future<bool> _commitMerge<T>(
    RealtimeMergeResult<T> result, {
    required String prefix,
    required bool fallbackForceFull,
    required Future<void> Function(T value) apply,
  }) async {
    if (result.handled) {
      appLog('$prefix${result.summary}', label: 'SyncRealtime');
      final value = result.value;
      if (result.changed && value != null) {
        await apply(value);
      }
      return true;
    }
    appLog(
      '$prefix${result.summary}; fallback to sync (forceFullSync=$fallbackForceFull)',
      label: 'SyncRealtime',
    );
    return false;
  }

  Future<bool> _applyRealtimeEventNow(
    MicrosoftAccount account,
    RealtimeEvent event, {
    bool fromQueue = false,
  }) async {
    if (_disposed ||
        _accountId != account.id ||
        ref.read(accountProvider).activeAccount?.id != account.id) {
      return true;
    }

    final todoNotifier = ref.read(todoProvider.notifier);
    final currentState = ref.read(todoProvider);
    final typeLower = event.type.trim().toLowerCase();
    final prefix = fromQueue ? '(drained) ' : '';

    switch (typeLower) {
      case 'task':
        return _commitMerge(
          mergeRealtimeTaskEvent(
            event: event,
            lists: currentState.lists,
            currentTasks: currentState.tasks,
            dirtyTaskIds: todoNotifier.repository.loadDirtyTaskIds().toSet(),
            pendingDeletedTaskRemoteIds: todoNotifier.repository
                .loadPendingDeletedTaskRemoteIds()
                .toSet(),
            idGenerator: todoNotifier.nextId,
          ),
          prefix: prefix,
          fallbackForceFull: true,
          apply: todoNotifier.applyRemoteTasksSnapshot,
        );

      case 'taskfolder':
        return _commitMerge(
          mergeRealtimeFolderEvent(
            event: event,
            groups: currentState.groups,
            currentLists: currentState.lists,
            currentTasks: currentState.tasks,
            dirtyListIds: todoNotifier.repository.loadDirtyListIds().toSet(),
            pendingDeletedListRemoteIds: todoNotifier.repository
                .loadPendingDeletedListRemoteIds()
                .toSet(),
            idGenerator: todoNotifier.nextId,
          ),
          prefix: prefix,
          fallbackForceFull: true,
          apply: (update) => todoNotifier.applyRemoteListsSnapshot(
            nextLists: update.lists,
            nextTasks: update.tasks,
          ),
        );

      case 'foldergroup':
        return _commitMerge(
          mergeRealtimeFolderGroupEvent(
            event: event,
            currentGroups: currentState.groups,
            dirtyGroupIds: todoNotifier.repository.loadDirtyGroupIds().toSet(),
            pendingDeletedGroupRemoteIds: todoNotifier.repository
                .loadPendingDeletedGroupRemoteIds()
                .toSet(),
            idGenerator: todoNotifier.nextId,
          ),
          prefix: prefix,
          fallbackForceFull: true,
          apply: todoNotifier.applyRemoteGroupsSnapshot,
        );

      case 'setting':
        return _commitMerge(
          mergeRealtimeSettingEvent(
            event: event,
            dirtySettingKeys: todoNotifier.settings
                .loadDirtySettingKeys()
                .toSet(),
          ),
          prefix: prefix,
          fallbackForceFull: false,
          apply: todoNotifier.applyRemoteSettingsPatch,
        );

      default:
        appLog(
          '${prefix}non-direct event type=${event.type} op=${event.operation}; '
          'fallback to sync (forceFullSync=false)',
          label: 'SyncRealtime',
        );
        return false;
    }
  }

  void _scheduleReconnect(
    MicrosoftAccount account, {
    required String reason,
  }) {
    if (_disposed || _accountId != account.id) return;
    if (!ref.read(realtimeSyncEnabledProvider)) return;
    _sub = null;
    _reconnectTimer?.cancel();
    final wait = _backoff;
    final nextSecs = (wait.inSeconds * 2).clamp(
      _initialBackoff.inSeconds,
      _maxBackoff.inSeconds,
    );
    _backoff = Duration(seconds: nextSecs);
    appLog(
      'scheduling reconnect reason=$reason wait=${wait.inSeconds}s',
      label: 'SyncRealtime',
    );
    _reconnectTimer = Timer(wait, () {
      if (!_disposed && _accountId == account.id) {
        unawaited(_connect(account));
      }
    });
  }
}
