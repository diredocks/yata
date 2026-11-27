import 'dart:async';

import '../core/logging/app_logger.dart';
import '../models/account.dart';
import 'microsoft/microsoft_todo_api.dart';
import 'sync_guard.dart';

final _log = appLogFor('SyncRealtime');

/// Pure transport manager for the foreground Substrate `/realtime` long-polling
/// stream: handles connection lifecycle, own-request filtering, and exponential
/// reconnect backoff without coupling to Riverpod or sync scheduling lanes.
class RealtimeSyncStream {
  RealtimeSyncStream({
    required this.apiOf,
    required this.isEnabled,
    required this.onEvent,
    required this.onReconnected,
  });

  static const _initialBackoff = Duration(seconds: 2);
  static const _maxBackoff = Duration(seconds: 60);

  final MicrosoftTodoApi Function() apiOf;
  final bool Function() isEnabled;
  final void Function(MicrosoftAccount account, RealtimeEvent event) onEvent;
  final void Function(MicrosoftAccount account) onReconnected;

  Timer? _reconnectTimer;
  StreamSubscription<RealtimeEvent>? _sub;
  bool _needsSyncOnConnect = false;
  Duration _backoff = _initialBackoff;
  String? _accountId;
  bool _disposed = false;

  String? get activeAccountId => _accountId;

  void ensureStartedFor(MicrosoftAccount account) {
    if (_disposed || _accountId == account.id) return;
    startFor(account);
  }

  void startFor(MicrosoftAccount account) {
    if (_disposed) return;
    stop(resetReconnectFlag: _accountId != null && _accountId != account.id);
    _accountId = account.id;
    _backoff = _initialBackoff;
    unawaited(_connect(account));
  }

  void stop({bool resetReconnectFlag = false}) {
    _accountId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final sub = _sub;
    _sub = null;
    if (sub != null) {
      unawaited(sub.cancel().catchError((_) {}));
    }
    if (resetReconnectFlag) {
      _needsSyncOnConnect = false;
    }
  }

  void reactivate() {
    _disposed = false;
  }

  void dispose() {
    _disposed = true;
    stop(resetReconnectFlag: true);
  }

  Future<void> _connect(MicrosoftAccount account) async {
    await Future<void>.microtask(() {});
    if (_disposed || _accountId != account.id || !isEnabled()) return;

    final api = apiOf();
    _sub = api.connectRealtime().listen(
      (event) {
        if (_disposed || _accountId != account.id) return;
        _backoff = _initialBackoff;
        if (_needsSyncOnConnect) {
          _needsSyncOnConnect = false;
          _log.info('reconnected; scheduling delta sync');
          onReconnected(account);
        }
        if (event.isKeepAlive) return;
        if (api.isOwnRequestId(event.requestId)) {
          _log.fine(
            'ignore own event type=${event.type} op=${event.operation} '
            'id=${shortSyncId(event.id)} req=${event.requestId}',
          );
          return;
        }
        onEvent(account, event);
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

  void _scheduleReconnect(MicrosoftAccount account, {required String reason}) {
    if (_disposed || _accountId != account.id || !isEnabled()) return;
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
