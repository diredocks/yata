import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/todo_state.dart';
import 'home_widget_event_processor.dart';
import 'home_widget_models.dart';

export 'home_widget_event_processor.dart';
export 'home_widget_models.dart';

final _log = appLogFor('HomeWidgetTransport');

const String kWidgetLastMutationMsKey = 'yata.widget_last_mutation_ms';
const String kAndroidWidgetProviderName =
    'top.clickfling.yata.widget.TodoWidgetProvider';
const String kWidgetSyncChannelName = 'top.clickfling.yata/widget_sync';

const String kWidgetSnapshotKey = 'widget_snapshot_json';
const String kWidgetPendingOpsKey = 'widget_pending_ops_json';
const String kWidgetAckedOpIdKey = 'widget_acked_op_id';
const String kWidgetRefreshRequestedKey = 'widget_refresh_requested';
const String kWidgetIsRefreshingKey = 'widget_is_refreshing';
const String kWidgetRefreshStartedMsKey = 'widget_refresh_started_ms';

abstract class HomeWidgetTransport {
  Future<T?> getData<T>(String key);
  Future<void> saveData(String key, Object? value);
  Future<void> updateWidget();
  Future<Uri?> initiallyLaunchedFromHomeWidget();
  Stream<Uri?> get widgetClicked;
  Stream<String> get widgetSyncRequests;
}

class FlutterHomeWidgetTransport implements HomeWidgetTransport {
  const FlutterHomeWidgetTransport();

  static const MethodChannel _channel = MethodChannel(kWidgetSyncChannelName);
  static final StreamController<String> _syncRequestsController =
      StreamController<String>.broadcast();
  static bool _handlerInstalled = false;

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid;
  }

  static void _ensureSyncHandlerInstalled() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'syncWidget') {
        _syncRequestsController.add(call.arguments as String? ?? '');
      }
      return null;
    });
  }

  Future<T?> _guardPlatform<T>(
    String operation,
    Future<T?> Function() action,
  ) async {
    if (!isSupportedPlatform) return null;
    try {
      return await action();
    } on MissingPluginException catch (e) {
      _log.warning('$operation plugin unavailable: $e');
      return null;
    } on PlatformException catch (e) {
      _log.warning('$operation platform error: $e');
      return null;
    }
  }

  @override
  Future<T?> getData<T>(String key) =>
      _guardPlatform('getData($key)', () => HomeWidget.getWidgetData<T>(key));

  @override
  Future<void> saveData(String key, Object? value) => _guardPlatform(
    'saveData($key)',
    () => HomeWidget.saveWidgetData<Object?>(key, value),
  );

  @override
  Future<void> updateWidget() => _guardPlatform(
    'updateWidget',
    () => HomeWidget.updateWidget(
      qualifiedAndroidName: kAndroidWidgetProviderName,
    ),
  );

  @override
  Future<Uri?> initiallyLaunchedFromHomeWidget() => _guardPlatform(
    'initiallyLaunchedFromHomeWidget',
    HomeWidget.initiallyLaunchedFromHomeWidget,
  );

  @override
  Stream<Uri?> get widgetClicked => isSupportedPlatform
      ? HomeWidget.widgetClicked
      : const Stream<Uri?>.empty();

  @override
  Stream<String> get widgetSyncRequests {
    if (!isSupportedPlatform) return const Stream<String>.empty();
    _ensureSyncHandlerInstalled();
    return _syncRequestsController.stream;
  }
}

final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  return HomeWidgetService(const FlutterHomeWidgetTransport());
});

class _PendingCommit {
  _PendingCommit({
    required this.canonicalJson,
    required this.wireJson,
    required this.ackedOpId,
    required this.clearRefreshing,
    required this.force,
    required this.notifyWidget,
  });

  String canonicalJson;
  String wireJson;
  int ackedOpId;
  bool clearRefreshing;
  bool force;
  bool notifyWidget;
  final Completer<void> done = Completer<void>();

  void coalesce({
    required String canonicalJson,
    required String wireJson,
    required int ackedOpId,
    required bool clearRefreshing,
    required bool force,
    required bool notifyWidget,
  }) {
    this.canonicalJson = canonicalJson;
    this.wireJson = wireJson;
    this.ackedOpId = max(this.ackedOpId, ackedOpId);
    this.clearRefreshing = this.clearRefreshing || clearRefreshing;
    this.force = this.force || force;
    this.notifyWidget = this.notifyWidget || notifyWidget;
  }
}

class HomeWidgetService {
  HomeWidgetService(this._transport);

  final HomeWidgetTransport _transport;

  String? _lastCommittedCanonicalJson;
  String? _lastConsumedInitialUri;

  Future<void>? _flushTask;
  _PendingCommit? _pendingCommit;
  Completer<void>? _pendingClear;

  Stream<Uri?> get widgetClicked => _transport.widgetClicked;

  Stream<String> get widgetSyncRequests => _transport.widgetSyncRequests;

  Future<int?> readAckedOpId() => _transport.getData<int>(kWidgetAckedOpIdKey);

  Future<String?> readPendingOpsRaw() =>
      _transport.getData<String>(kWidgetPendingOpsKey);

  Future<bool> readRefreshRequested() async =>
      (await _transport.getData<bool>(kWidgetRefreshRequestedKey)) ?? false;

  Future<void> clearRefreshRequested() =>
      _transport.saveData(kWidgetRefreshRequestedKey, false);

  Future<Uri?> consumeInitialLaunchUri() async {
    final uri = await _transport.initiallyLaunchedFromHomeWidget();
    if (uri == null) return null;
    final raw = uri.toString();
    if (raw == _lastConsumedInitialUri) return null;
    _lastConsumedInitialUri = raw;
    return uri;
  }

  Future<void> syncWithState(
    TodoState state, {
    String? accountId,
    String accountName = '',
    HomeWidgetStrings strings = const HomeWidgetStrings(),
    int ackedOpId = 0,
    bool clearRefreshing = false,
    bool force = false,
    bool notifyWidget = true,
    DateTime? now,
  }) {
    final canonicalPayload = HomeWidgetSnapshotSerializer.buildCanonicalPayload(
      state,
      accountId: accountId,
      accountName: accountName,
      strings: strings,
      now: now,
    );
    final encoded = HomeWidgetSnapshotSerializer.encodePayload(
      canonicalPayload,
      now: now,
    );

    final pending = _pendingCommit;
    if (pending != null) {
      pending.coalesce(
        canonicalJson: encoded.canonicalJson,
        wireJson: encoded.wireJson,
        ackedOpId: ackedOpId,
        clearRefreshing: clearRefreshing,
        force: force,
        notifyWidget: notifyWidget,
      );
      return pending.done.future;
    }

    final created = _PendingCommit(
      canonicalJson: encoded.canonicalJson,
      wireJson: encoded.wireJson,
      ackedOpId: ackedOpId,
      clearRefreshing: clearRefreshing,
      force: force,
      notifyWidget: notifyWidget,
    );
    _pendingCommit = created;
    _ensureFlushLoop();
    return created.done.future;
  }

  Future<void> clearWidgetData() {
    final discarded = _pendingCommit;
    if (discarded != null) {
      _pendingCommit = null;
      if (!discarded.done.isCompleted) discarded.done.complete();
    }
    final clear = _pendingClear ??= Completer<void>();
    _ensureFlushLoop();
    return clear.future;
  }

  void _ensureFlushLoop() {
    _flushTask ??= _runFlushLoop().whenComplete(() {
      _flushTask = null;
      if (_pendingClear != null || _pendingCommit != null) {
        _ensureFlushLoop();
      }
    });
  }

  Future<void> _runFlushLoop() async {
    while (_pendingClear != null || _pendingCommit != null) {
      final clear = _pendingClear;
      if (clear != null) {
        _pendingClear = null;
        await _executeClear(clear);
        continue;
      }
      final commit = _pendingCommit;
      if (commit != null) {
        _pendingCommit = null;
        await _executeCommit(commit);
      }
    }
  }

  Future<void> _executeCommit(_PendingCommit req) async {
    if (!req.force &&
        req.ackedOpId == 0 &&
        !req.clearRefreshing &&
        req.canonicalJson == _lastCommittedCanonicalJson) {
      req.done.complete();
      return;
    }

    final result = await guardAsyncUnit(() async {
      await _transport.saveData(kWidgetSnapshotKey, req.wireJson);
      if (req.ackedOpId > 0) {
        await _transport.saveData(kWidgetAckedOpIdKey, req.ackedOpId);
      }
      if (req.clearRefreshing) {
        await _transport.saveData(kWidgetIsRefreshingKey, false);
        await _transport.saveData(kWidgetRefreshStartedMsKey, null);
      }
      if (req.notifyWidget) {
        await _transport.updateWidget();
      }
    }, operation: 'syncWidgetSnapshot');

    if (result.isSuccess()) {
      _lastCommittedCanonicalJson = req.canonicalJson;
    }
    req.done.complete();
  }

  Future<void> _executeClear(Completer<void> clear) async {
    _lastCommittedCanonicalJson = null;
    await guardAsyncUnit(() async {
      for (final key in [
        kWidgetSnapshotKey,
        kWidgetPendingOpsKey,
        kWidgetRefreshRequestedKey,
        kWidgetIsRefreshingKey,
        kWidgetRefreshStartedMsKey,
      ]) {
        await _transport.saveData(key, null);
      }
      await _transport.updateWidget();
    }, operation: 'clearWidgetData');
    clear.complete();
  }

  static Future<void> registerBackgroundCallback() async {
    if (!FlutterHomeWidgetTransport.isSupportedPlatform) return;
    await HomeWidget.registerInteractivityCallback(
      homeWidgetBackgroundCallback,
    );
  }

  static Future<HomeWidgetStrings> resolveSystemStrings({
    List<Locale>? locales,
  }) async {
    final strings = HomeWidgetStrings.fromLocales(
      locales ?? PlatformDispatcher.instance.locales,
    );
    await guardAsyncUnit(
      () => initializeDateFormatting(strings.localeName),
      operation: 'initWidgetDateFormatting',
    );
    return strings;
  }
}
