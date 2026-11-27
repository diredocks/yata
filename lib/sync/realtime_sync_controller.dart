import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../account/account_provider.dart';
import '../core/logging/app_logger.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'microsoft/microsoft_todo_api.dart';
import 'microsoft/remote_change_reconciler.dart';
import 'sync_log_format.dart';
import 'sync_provider.dart';

final _log = appLogFor('SyncRealtime');

/// Manages the foreground Substrate `/realtime` long-polling connection,
/// reconnect backoff, mid-sync event buffering, and batched state merging.
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
    final repository = ref.read(todoProvider.notifier).repository;
    final ctxResult = await service.resolveContext(account, repository);

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

    final unhandled = await _applyRealtimeBatch(account, [event]);
    if (unhandled != null && !_disposed) {
      onScheduleFallbackSync(
        delay: const Duration(milliseconds: 200),
        forceFullSync: _shouldForceFullSyncForEvent(unhandled),
        reason: 'realtime_${unhandled.type}_${unhandled.operation ?? 'unknown'}',
      );
    }
  }

  Future<void> drainPendingIfReady() async {
    if (_disposed || _pendingEvents.isEmpty || isSyncInFlight()) return;
    final initialActive = ref.read(accountProvider).activeAccount;
    if (initialActive is! MicrosoftAccount || _accountId != initialActive.id) {
      _pendingEvents.clear();
      return;
    }

    final batch = _pendingEvents.toList(growable: false);
    _pendingEvents.clear();
    _log.info('draining ${batch.length} deferred realtime event(s)');

    final unhandled = await _applyRealtimeBatch(
      initialActive,
      batch,
      fromQueue: true,
    );
    if (unhandled != null && !_disposed) {
      await onCatchupDeltaSync(
        'realtime_${unhandled.type}_${unhandled.operation ?? 'unknown'}',
      );
    }
  }

  Future<RealtimeEvent?> _applyRealtimeBatch(
    MicrosoftAccount account,
    List<RealtimeEvent> events, {
    bool fromQueue = false,
  }) async {
    if (_disposed ||
        _accountId != account.id ||
        ref.read(accountProvider).activeAccount?.id != account.id) {
      return null;
    }

    final parsed = parseRealtimeEventsBatch(events);
    final todoNotifier = ref.read(todoProvider.notifier);
    final currentState = ref.read(todoProvider);
    final protection = todoNotifier.repository.outbox.captureCurrentProtection();

    final reconciled = reconcileRemoteDelta(
      delta: parsed.delta,
      liveGroups: currentState.groups,
      liveLists: currentState.lists,
      liveTasks: currentState.tasks,
      protection: protection,
      idGenerator: todoNotifier.nextId,
      strictParentResolution: true,
      returnOnlyChanged: true,
    );

    final prefix = fromQueue ? '(drained) ' : '';
    if (reconciled.hasChanges) {
      _log.info(
        '${prefix}applied realtime batch events=${events.length} '
        'groups=${reconciled.groups != null} lists=${reconciled.lists != null} '
        'tasks=${reconciled.tasks != null} '
        'settings=${reconciled.remoteSettings?.length ?? 0}',
      );
      await todoNotifier.applyRemoteState(
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
      _log.info(
        '${prefix}non-direct event type=${unhandled.type} op=${unhandled.operation} '
        'id=${shortSyncId(unhandled.id)}; fallback to sync',
      );
    }
    return unhandled;
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
