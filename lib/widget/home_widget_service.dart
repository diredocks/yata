import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../account/account_provider.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../models/account.dart';
import '../sync/sync_provider.dart';
import '../tasksview/tasks_view_presenter.dart';
import 'home_widget_models.dart';

export 'home_widget_models.dart';

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

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

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
      appLog('$operation plugin unavailable: $e', label: 'HomeWidgetTransport');
      return null;
    } on PlatformException catch (e) {
      appLog('$operation platform error: $e', label: 'HomeWidgetTransport');
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

@immutable
class WidgetEventProcessResult {
  const WidgetEventProcessResult({
    this.didMutate = false,
    this.didSync = false,
  });

  final bool didMutate;
  final bool didSync;
}

class WidgetEventProcessor {
  WidgetEventProcessor({
    required this._widgetService,
    required this._read,
    required this._strings,
    required this._isBackground,
    this._isAppForeground = true,
    this._isActive,
    this._runCloudSync,
    this._scheduleBackgroundedAppCloudSync,
  });

  static const Duration _refreshSyncTimeout = Duration(seconds: 20);
  static const Duration _bgMutationSyncTimeout = Duration(seconds: 15);

  final HomeWidgetService _widgetService;
  final ProviderReader _read;
  final HomeWidgetStrings _strings;
  final bool _isBackground;
  final bool _isAppForeground;
  final bool Function()? _isActive;
  final Future<void> Function()? _runCloudSync;
  final VoidCallback? _scheduleBackgroundedAppCloudSync;

  bool _didMutate = false;
  bool _didSync = false;
  int _highestAckedOpId = 0;

  bool get _active => _isActive == null || _isActive();

  WidgetEventProcessResult get _result => WidgetEventProcessResult(
    didMutate: _didMutate,
    didSync: _didSync,
  );

  Future<WidgetEventProcessResult> process({String reason = ''}) async {
    if (!_active) return const WidgetEventProcessResult();

    final prevAckedOpId =
        await _widgetService._transport.getData<int>(kWidgetAckedOpIdKey) ?? 0;
    final pendingOps = await _readUnackedOps(prevAckedOpId);
    final refreshRequested =
        await _widgetService._transport.getData<bool>(
          kWidgetRefreshRequestedKey,
        ) ??
        false;
    if (!_active) return _result;

    final activeAccountId = _read(accountProvider).activeAccount?.id;
    if (activeAccountId == null) {
      await _widgetService.clearWidgetData();
      return _result;
    }

    _highestAckedOpId = _applyOps(pendingOps, activeAccountId, prevAckedOpId);
    if (_didMutate) {
      await _read(todoRepositoryProvider).flushPendingWrites();
      if (!_active) return _result;
    }

    if (refreshRequested) {
      await _handleRefreshRequest();
    } else {
      if (_highestAckedOpId > prevAckedOpId || reason == 'date_rollover') {
        await _pushSnapshot(force: true);
      }
      await _handlePostMutationSync();
    }

    return _result;
  }

  Future<List<WidgetPendingOp>> _readUnackedOps(int ackedOpId) async {
    final raw = await _widgetService._transport.getData<String>(
      kWidgetPendingOpsKey,
    );
    if (raw == null || raw.isEmpty) return const [];
    final decoded = guardSync<List<WidgetPendingOp>>(() {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<Object?, Object?>>()
          .map(WidgetPendingOp.fromMap)
          .nonNulls
          .where((op) => op.opId > ackedOpId)
          .toList()
        ..sort((a, b) => a.opId.compareTo(b.opId));
    }, operation: 'decodeWidgetPendingOps');
    return decoded.getOrElse((_) => const []);
  }

  int _applyOps(
    List<WidgetPendingOp> ops,
    String activeAccountId,
    int prevAckedOpId,
  ) {
    var maxOpId = prevAckedOpId;
    for (final op in ops) {
      maxOpId = max(maxOpId, op.opId);
      if (op.accountId != null &&
          op.accountId!.isNotEmpty &&
          op.accountId != activeAccountId) {
        continue;
      }
      _applySingleOp(op);
    }
    return maxOpId;
  }

  void _applySingleOp(WidgetPendingOp op) {
    final target = _read(todoProvider).tasks
        .where((t) => t.id == op.taskId)
        .firstOrNull;
    if (target == null) return;

    final presenter = _read(tasksViewPresenterProvider);
    switch (op.type) {
      case WidgetPendingOpType.toggleComplete
          when target.isCompleted != op.value:
        presenter.setTaskCompleted(op.taskId, completed: op.value);
        _didMutate = true;
      case WidgetPendingOpType.toggleImportant
          when target.isImportant != op.value:
        presenter.toggleTaskImportant(op.taskId);
        _didMutate = true;
      case WidgetPendingOpType.toggleComplete ||
          WidgetPendingOpType.toggleImportant:
        break;
    }
  }

  Future<void> _handleRefreshRequest() async {
    await _widgetService._transport.saveData(kWidgetRefreshRequestedKey, false);
    if (!_active) return;
    try {
      _didSync = await _runBoundedSync(
        _refreshSyncTimeout,
        'widgetRefreshSync',
      );
    } finally {
      if (_active) {
        await _flushAndPushSnapshot(clearRefreshing: true);
      }
    }
  }

  Future<void> _handlePostMutationSync() async {
    if (!_didMutate || !_active) return;
    if (!_isBackground) {
      if (!_isAppForeground) {
        _scheduleBackgroundedSync();
      }
      return;
    }

    final activeAccount = _read(accountProvider).activeAccount;
    if (activeAccount is! MicrosoftAccount) return;

    _didSync = await _runBoundedSync(
      _bgMutationSyncTimeout,
      'widgetBackgroundSync',
    );
    if (_active) {
      await _flushAndPushSnapshot();
    }
  }

  Future<bool> _runBoundedSync(Duration timeout, String operation) async {
    final syncCall =
        _runCloudSync ?? () => _read(syncProvider.notifier).syncNow();
    var timedOut = false;
    final result = await guardAsyncUnit(
      () => syncCall().timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
        },
      ),
      operation: operation,
    );
    return result.isSuccess() && !timedOut;
  }

  void _scheduleBackgroundedSync() {
    if (_scheduleBackgroundedAppCloudSync != null) {
      _scheduleBackgroundedAppCloudSync();
      return;
    }
    _read(
      syncProvider.notifier,
    ).scheduleDebouncedSync(delay: const Duration(milliseconds: 400));
  }

  Future<void> _flushAndPushSnapshot({bool clearRefreshing = false}) async {
    await _read(todoRepositoryProvider).flushPendingWrites();
    if (!_active) return;
    if (_read(accountProvider).activeAccount?.id == null) {
      await _widgetService.clearWidgetData();
      return;
    }
    await _pushSnapshot(clearRefreshing: clearRefreshing, force: true);
  }

  Future<void> _pushSnapshot({
    bool clearRefreshing = false,
    bool force = false,
  }) {
    final account = _read(accountProvider).activeAccount;
    return _widgetService.syncWithState(
      _read(todoProvider),
      accountId: account?.id,
      accountName: account?.displayName ?? '',
      strings: _strings,
      ackedOpId: _highestAckedOpId,
      clearRefreshing: clearRefreshing,
      force: force,
    );
  }
}

/// Background entry point invoked by `home_widget` when `MainActivity` is not alive.
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  final reason = uri?.queryParameters['reason'] ?? '';
  WidgetsFlutterBinding.ensureInitialized();
  final database = TodoDatabase();
  ProviderContainer? container;
  try {
    await guardAsyncUnit(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final strings = await HomeWidgetService.resolveSystemStrings();
      final activeId = AccountLocalStorage(prefs).load().activeAccountId;
      if (activeId != null) {
        await TodoRepository.forAccount(
          prefs,
          accountId: activeId,
          database: database,
        ).preload();
      }
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          todoDatabaseProvider.overrideWithValue(database),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      final result = await WidgetEventProcessor(
        widgetService: HomeWidgetService(const FlutterHomeWidgetTransport()),
        read: container!.read,
        strings: strings,
        isBackground: true,
        isAppForeground: false,
      ).process(reason: reason);
      if (result.didMutate || result.didSync) {
        await prefs.setInt(
          kWidgetLastMutationMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    }, operation: 'widgetBackgroundCallback($reason)');
  } finally {
    container?.dispose();
    await database.close();
  }
}
