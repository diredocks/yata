import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../core/logging/app_logger.dart';
import '../data/sync_outbox.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'microsoft/microsoft_todo_api.dart';
import 'microsoft/realtime_event_merger.dart';
import 'sync_log_format.dart';
import 'sync_provider.dart';

final _log = appLogFor('SyncRealtime');

/// Manages the foreground Substrate `/realtime` long-polling connection,
/// reconnect backoff, mid-sync event buffering, and direct state merging.
class RealtimeSyncController {
  RealtimeSyncController({
    required this.ref,
    required this.isSyncInFlight,
    required this.onScheduleFallbackSync,
    required this.onOverflowResync,
    required this.onCatchupDeltaSync,
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
  final Future<void> Function(String reason) onCatchupDeltaSync;

  Timer? _reconnectTimer;
  StreamSubscription<RealtimeEvent>? _sub;
  final Queue<RealtimeEvent> _pendingEvents = Queue<RealtimeEvent>();
  bool _needsSyncOnConnect = false;
  Duration _backoff = _initialBackoff;
  String? _accountId;
  bool _disposed = false;

  bool get hasPendingEvents => _pendingEvents.isNotEmpty;

  static bool _shouldForceFullSyncForEvent(RealtimeEvent event) =>
      switch (event.entityType) {
        RealtimeEventEntityType.task ||
        RealtimeEventEntityType.taskFolder ||
        RealtimeEventEntityType.folderGroup => true,
        RealtimeEventEntityType.setting ||
        RealtimeEventEntityType.keepAlive ||
        RealtimeEventEntityType.unknown => false,
      };

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
    final sub = _sub;
    _sub = null;
    if (sub != null) {
      unawaited(sub.cancel().catchError((_) {}));
    }
    if (clearPending) {
      _pendingEvents.clear();
      _needsSyncOnConnect = false;
    }
  }

  void onAppPaused() {
    _needsSyncOnConnect = false;
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
        if (_needsSyncOnConnect) {
          _needsSyncOnConnect = false;
          _log.info('reconnected; scheduling delta sync');
          onScheduleFallbackSync(
            delay: _reconnectDebounceDuration,
            forceFullSync: false,
            reason: 'realtime_reconnected',
          );
        }
        if (event.isKeepAlive) return;
        if (service.todoApi.isOwnRequestId(event.requestId)) {
          _log.fine(
            'ignore own event type=${event.type} op=${event.operation} '
            'id=${shortSyncId(event.id)} req=${event.requestId}',
          );
          return;
        }
        unawaited(_handleRemoteEvent(account, event));
      },
      onError: (Object error) {
        _log.info('stream error=$error');
        _needsSyncOnConnect = true;
        _scheduleReconnect(account, reason: 'error');
      },
      onDone: () {
        _log.info('stream done');
        _needsSyncOnConnect = true;
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
        _log.info(
          'deferred queue overflow ($_maxPendingEvents); '
          'scheduling full resync',
        );
        return;
      }
      _pendingEvents.add(event);
      _log.fine(
        'deferred event while syncing: type=${event.type} '
        'op=${event.operation} id=${shortSyncId(event.id)} '
        'queued=${_pendingEvents.length}',
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

    _log.info('draining ${_pendingEvents.length} deferred realtime event(s)');

    var needsFallbackSync = false;
    var fallbackReason = 'realtime_deferred';

    while (!_disposed && !isSyncInFlight() && _pendingEvents.isNotEmpty) {
      final currentActive = ref.read(accountProvider).activeAccount;
      if (currentActive is! MicrosoftAccount ||
          _accountId != currentActive.id) {
        _pendingEvents.clear();
        return;
      }
      final event = _pendingEvents.removeFirst();
      final handled = await _applyRealtimeEventNow(
        currentActive,
        event,
        fromQueue: true,
      );
      if (!handled) {
        needsFallbackSync = true;
        fallbackReason =
            'realtime_${event.type}_${event.operation ?? 'unknown'}';
      }
    }

    if (needsFallbackSync && !_disposed) {
      await onCatchupDeltaSync(fallbackReason);
    }
  }

  Future<bool> _commitMerge<T>(
    RealtimeMergeResult<T> result, {
    required String prefix,
    required bool fallbackForceFull,
    required Future<void> Function(T value) apply,
  }) async {
    if (result.handled) {
      _log.info('$prefix${result.summary}');
      final value = result.value;
      if (result.changed && value != null) {
        await apply(value);
      }
      return true;
    }
    _log.info(
      '$prefix${result.summary}; fallback to sync (forceFullSync=$fallbackForceFull)',
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
    final prefix = fromQueue ? '(drained) ' : '';

    final outbox = todoNotifier.repository.outbox;
    switch (event.entityType) {
      case RealtimeEventEntityType.task:
        return _commitMerge(
          mergeRealtimeTaskEvent(
            event: event,
            lists: currentState.lists,
            currentTasks: currentState.tasks,
            dirtyTaskIds: outbox.pendingLocalIds(SyncEntityType.task),
            pendingDeletedTaskRemoteIds: outbox.pendingDeletedRemoteIds(
              SyncEntityType.task,
            ),
            idGenerator: todoNotifier.nextId,
          ),
          prefix: prefix,
          fallbackForceFull: !fromQueue,
          apply: todoNotifier.applyRemoteTasksSnapshot,
        );

      case RealtimeEventEntityType.taskFolder:
        return _commitMerge(
          mergeRealtimeFolderEvent(
            event: event,
            groups: currentState.groups,
            currentLists: currentState.lists,
            currentTasks: currentState.tasks,
            dirtyListIds: outbox.pendingLocalIds(SyncEntityType.list),
            pendingDeletedListRemoteIds: outbox.pendingDeletedRemoteIds(
              SyncEntityType.list,
            ),
            idGenerator: todoNotifier.nextId,
          ),
          prefix: prefix,
          fallbackForceFull: !fromQueue,
          apply: (update) => todoNotifier.applyRemoteListsSnapshot(
            nextLists: update.lists,
            nextTasks: update.tasks,
          ),
        );

      case RealtimeEventEntityType.folderGroup:
        return _commitMerge(
          mergeRealtimeFolderGroupEvent(
            event: event,
            currentGroups: currentState.groups,
            dirtyGroupIds: outbox.pendingLocalIds(SyncEntityType.group),
            pendingDeletedGroupRemoteIds: outbox.pendingDeletedRemoteIds(
              SyncEntityType.group,
            ),
            idGenerator: todoNotifier.nextId,
          ),
          prefix: prefix,
          fallbackForceFull: !fromQueue,
          apply: todoNotifier.applyRemoteGroupsSnapshot,
        );

      case RealtimeEventEntityType.setting:
        return _commitMerge(
          mergeRealtimeSettingEvent(
            event: event,
            dirtySettingKeys: outbox.pendingLocalIds(SyncEntityType.setting),
          ),
          prefix: prefix,
          fallbackForceFull: false,
          apply: todoNotifier.applyRemoteSettingsPatch,
        );

      case RealtimeEventEntityType.keepAlive:
      case RealtimeEventEntityType.unknown:
        _log.info(
          '${prefix}non-direct event type=${event.type} op=${event.operation}; '
          'fallback to sync (forceFullSync=false)',
        );
        return false;
    }
  }

  void _scheduleReconnect(MicrosoftAccount account, {required String reason}) {
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
    _log.info('scheduling reconnect reason=$reason wait=${wait.inSeconds}s');
    _reconnectTimer = Timer(wait, () {
      if (!_disposed && _accountId == account.id) {
        unawaited(_connect(account));
      }
    });
  }
}
