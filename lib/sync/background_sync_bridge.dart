import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer, PluginUtilities;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final _log = appLogFor('BackgroundSync');

const String kBackgroundSyncChannelName = 'top.clickfling.yata/background_sync';
const String kBackgroundUiEventPortName = 'top.clickfling.yata.ui_events';

/// Execution lane for background sync work so slow binary transfers never
/// block fast metadata mutations.
enum BackgroundSyncLane { metadata, transfer }

/// Lightweight notification emitted by the background worker over
/// `IsolateNameServer` or an in-process stream when SQLite state changes.
class BackgroundDbChangedEvent {
  const BackgroundDbChangedEvent({
    required this.accountKey,
    this.lane,
    this.reason,
  });

  final String accountKey;
  final BackgroundSyncLane? lane;
  final String? reason;

  Map<String, Object?> toWireMap() => <String, Object?>{
    'accountKey': accountKey,
    if (lane != null) 'lane': lane!.name,
    if (reason != null) 'reason': reason,
  };

  static BackgroundDbChangedEvent? fromWireMap(Object? raw) {
    if (raw is! Map) return null;
    final accountKey = raw['accountKey'];
    if (accountKey is! String || accountKey.isEmpty) return null;
    final laneName = raw['lane'];
    final lane = laneName is String
        ? BackgroundSyncLane.values.firstWhereOrNull((l) => l.name == laneName)
        : null;
    final reason = raw['reason'];
    return BackgroundDbChangedEvent(
      accountKey: accountKey,
      lane: lane,
      reason: reason is String ? reason : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BackgroundDbChangedEvent &&
          accountKey == other.accountKey &&
          lane == other.lane &&
          reason == other.reason);

  @override
  int get hashCode => Object.hash(accountKey, lane, reason);
}

/// Schedules durable background execution on the current platform's OS host
/// (Android `WorkManager` / `YataSyncWorker`, or in-process/isolate on desktop).
abstract class BackgroundSyncScheduler {
  /// Whether this platform runs long-lived attachment transfers exclusively in
  /// a dedicated OS background worker (e.g. Android WorkManager) rather than
  /// inside the foreground UI isolate.
  bool get handlesTransfersInBackground => false;

  Future<void> registerBackgroundEntrypoint(Function entrypoint);

  Future<void> enqueueSync({
    required BackgroundSyncLane lane,
    required String reason,
    bool requiresNetwork = true,
    bool expedited = false,
  });

  Future<void> notifyBackgroundRunCompleted({
    required String lane,
    required bool shouldRetry,
    required bool hasPendingTransfers,
  });
}

class PlatformBackgroundSyncScheduler implements BackgroundSyncScheduler {
  const PlatformBackgroundSyncScheduler();

  static const MethodChannel _channel = MethodChannel(
    kBackgroundSyncChannelName,
  );

  static bool get isAndroidHost {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid;
  }

  @override
  bool get handlesTransfersInBackground => isAndroidHost;

  Future<void> _invokeGuarded(String method, Object? arguments) async {
    if (!isAndroidHost) return;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException catch (e) {
      _log.warning('$method plugin unavailable: $e');
    } on PlatformException catch (e) {
      _log.warning('$method platform error: $e');
    }
  }

  @override
  Future<void> registerBackgroundEntrypoint(Function entrypoint) async {
    if (!isAndroidHost) return;
    final handle = PluginUtilities.getCallbackHandle(entrypoint);
    if (handle == null) {
      _log.warning('Failed to resolve callback handle for background sync');
      return;
    }
    await _invokeGuarded('registerBackgroundEntrypoint', {
      'callbackHandle': handle.toRawHandle(),
    });
  }

  @override
  Future<void> enqueueSync({
    required BackgroundSyncLane lane,
    required String reason,
    bool requiresNetwork = true,
    bool expedited = false,
  }) => _invokeGuarded('enqueueSync', {
    'lane': lane.name,
    'reason': reason,
    'requiresNetwork': requiresNetwork,
    'expedited': expedited,
  });

  @override
  Future<void> notifyBackgroundRunCompleted({
    required String lane,
    required bool shouldRetry,
    required bool hasPendingTransfers,
  }) => _invokeGuarded('backgroundRunCompleted', {
    'lane': lane,
    'shouldRetry': shouldRetry,
    'hasPendingTransfers': hasPendingTransfers,
  });
}

/// Same-process IPC event bus between the headless background worker isolate
/// and an optionally attached UI isolate using `IsolateNameServer`.
///
/// When the UI is detached or backgrounded, emitting events is a cheap no-op.
class BackgroundWorkerEventBus {
  BackgroundWorkerEventBus._();

  static final StreamController<BackgroundDbChangedEvent> _localController =
      StreamController<BackgroundDbChangedEvent>.broadcast();
  static ReceivePort? _uiReceivePort;

  static Stream<BackgroundDbChangedEvent> get events => _localController.stream;

  /// Registers the UI isolate's `ReceivePort` so background worker isolates
  /// can push DB-change signals without polling.
  static void attachUiListener() {
    if (_uiReceivePort != null) return;
    final port = ReceivePort();
    _uiReceivePort = port;
    IsolateNameServer.removePortNameMapping(kBackgroundUiEventPortName);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      kBackgroundUiEventPortName,
    );
    port.listen((raw) {
      final event = BackgroundDbChangedEvent.fromWireMap(raw);
      if (event != null && !_localController.isClosed) {
        _localController.add(event);
      }
    });
  }

  /// Sends [event] to the attached UI isolate (if any) and local listeners.
  static void emit(BackgroundDbChangedEvent event) {
    final remotePort = IsolateNameServer.lookupPortByName(
      kBackgroundUiEventPortName,
    );
    if (remotePort != null) {
      remotePort.send(event.toWireMap());
      return;
    }
    if (!_localController.isClosed) {
      _localController.add(event);
    }
  }
}

final backgroundSyncSchedulerProvider = Provider<BackgroundSyncScheduler>((
  ref,
) {
  return const PlatformBackgroundSyncScheduler();
});
