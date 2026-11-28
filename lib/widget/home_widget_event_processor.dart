import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../data/account_provider.dart';
import '../core/result/app_result.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import '../sync/sync_dispatcher.dart';
import '../sync/sync_provider.dart';
import '../data/task_mutations.dart';
import 'home_widget_service.dart';

typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

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

  WidgetEventProcessResult get _result =>
      WidgetEventProcessResult(didMutate: _didMutate, didSync: _didSync);

  Future<WidgetEventProcessResult> process({String reason = ''}) async {
    if (!_active) return const WidgetEventProcessResult();

    final prevAckedOpId = await _widgetService.readAckedOpId() ?? 0;
    final pendingOps = await _readUnackedOps(prevAckedOpId);
    final refreshRequested = await _widgetService.readRefreshRequested();
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
    final raw = await _widgetService.readPendingOpsRaw();
    if (raw == null || raw.isEmpty) return const [];
    final decoded = guardSync<List<WidgetPendingOp>>(() {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<Object?, Object?>>()
          .map(WidgetPendingOp.fromMap)
          .nonNulls
          .where((op) => op.opId > ackedOpId)
          .sortedBy((op) => op.opId);
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
        .firstWhereOrNull((t) => t.id == op.taskId);
    if (target == null) return;

    final presenter = _read(taskMutationsProvider);
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
    await _widgetService.clearRefreshRequested();
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
        _runCloudSync ??
        () =>
            _read(syncProvider.notifier).syncNow(reason: SyncReason.homeWidget);
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
    _read(syncProvider.notifier)
        .scheduleDebouncedSync(delay: const Duration(milliseconds: 400));
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
