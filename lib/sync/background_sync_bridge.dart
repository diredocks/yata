import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer, PluginUtilities;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../data/sync_job.dart';

final _log = appLogFor('BackgroundSync');

const String kBackgroundSyncChannelName = 'top.clickfling.yata/background_sync';
const String kBackgroundUiEventPortName = 'top.clickfling.yata.ui_events';

/// Schedules durable background execution on the current platform's OS host
/// (Android `WorkManager` / `YataSyncWorker`, or in-process/isolate on desktop).
abstract class BackgroundSyncScheduler {
  Future<void> registerBackgroundEntrypoint(Function entrypoint);

  Future<void> enqueueSync({
    required SyncJobLane lane,
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
    required SyncJobLane lane,
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

  static final StreamController<BackgroundWorkerEvent> _localController =
      StreamController<BackgroundWorkerEvent>.broadcast();
  static ReceivePort? _uiReceivePort;

  static Stream<BackgroundWorkerEvent> get events => _localController.stream;

  /// Registers the UI isolate's `ReceivePort` so background worker isolates
  /// can push real-time progress and DB-change signals without polling.
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
      final event = BackgroundWorkerEvent.fromWireMap(raw);
      if (event != null && !_localController.isClosed) {
        _localController.add(event);
      }
    });
  }

  static void detachUiListener() {
    final port = _uiReceivePort;
    if (port == null) return;
    _uiReceivePort = null;
    IsolateNameServer.removePortNameMapping(kBackgroundUiEventPortName);
    port.close();
  }

  /// Sends [event] to the attached UI isolate (if any) and local listeners.
  static void emit(BackgroundWorkerEvent event) {
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

final backgroundWorkerEventsProvider = StreamProvider<BackgroundWorkerEvent>((
  ref,
) {
  return BackgroundWorkerEventBus.events;
});
