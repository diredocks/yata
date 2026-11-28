import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:result_dart/result_dart.dart';

import '../core/result/app_result.dart';

/// App-icon quick actions supported by Yata.
enum QuickActionType {
  search('search'),
  newTask('new_task');

  const QuickActionType(this.id);

  final String id;

  static QuickActionType? fromId(String id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return null;
  }
}

/// Abstract transport so tests can verify quick actions without OS channels.
abstract class QuickActionsTransport {
  bool get isSupported;

  Future<void> initialize(void Function(String type) onAction);

  Future<void> setShortcutItems(List<ShortcutItem> items);

  Future<void> clearShortcutItems();
}

class PlatformQuickActionsTransport implements QuickActionsTransport {
  const PlatformQuickActionsTransport([
    QuickActions quickActions = const QuickActions(),
  ]) : _quickActions = quickActions;

  final QuickActions _quickActions;

  @override
  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Future<void> initialize(void Function(String type) onAction) =>
      _quickActions.initialize(onAction);

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) =>
      _quickActions.setShortcutItems(items);

  @override
  Future<void> clearShortcutItems() => _quickActions.clearShortcutItems();
}

final quickActionsTransportProvider = Provider<QuickActionsTransport>(
  (_) => const PlatformQuickActionsTransport(),
);

final quickActionsServiceProvider = Provider<QuickActionsService>((ref) {
  final service = QuickActionsService(ref.watch(quickActionsTransportProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Registers and dispatches launcher quick actions for searching and adding tasks.
class QuickActionsService {
  QuickActionsService(this._transport);

  final QuickActionsTransport _transport;
  final StreamController<QuickActionType> _actionsController =
      StreamController<QuickActionType>.broadcast();

  bool _initialized = false;
  bool _disposed = false;
  QuickActionType? _pendingAction;
  String? _lastSearchLabel;
  String? _lastNewTaskLabel;

  Stream<QuickActionType> get actions => _actionsController.stream;

  Future<AppResult<Unit>> initialize({
    required String searchLabel,
    required String newTaskLabel,
  }) async {
    if (_disposed || !_transport.isSupported) return const Success(unit);

    if (!_initialized) {
      final initResult = await guardAsyncUnit(
        () => _transport.initialize(_handleActionId),
        operation: 'quickActionsInitialize',
      );
      if (initResult.isError()) return initResult;
      _initialized = true;
    }

    return updateShortcuts(
      searchLabel: searchLabel,
      newTaskLabel: newTaskLabel,
    );
  }

  Future<AppResult<Unit>> updateShortcuts({
    required String searchLabel,
    required String newTaskLabel,
  }) async {
    if (_disposed || !_transport.isSupported) return const Success(unit);
    if (_lastSearchLabel == searchLabel && _lastNewTaskLabel == newTaskLabel) {
      return const Success(unit);
    }

    final result = await guardAsyncUnit(
      () => _transport.setShortcutItems(<ShortcutItem>[
        ShortcutItem(
          type: QuickActionType.newTask.id,
          localizedTitle: newTaskLabel,
          icon: 'ic_shortcut_add',
        ),
        ShortcutItem(
          type: QuickActionType.search.id,
          localizedTitle: searchLabel,
          icon: 'ic_shortcut_search',
        ),
      ]),
      operation: 'quickActionsSetShortcuts',
    );
    if (result.isSuccess()) {
      _lastSearchLabel = searchLabel;
      _lastNewTaskLabel = newTaskLabel;
    }
    return result;
  }

  QuickActionType? consumePendingAction() {
    final pending = _pendingAction;
    _pendingAction = null;
    return pending;
  }

  Future<AppResult<Unit>> clearShortcuts() {
    if (_disposed || !_transport.isSupported) {
      return Future.value(const Success(unit));
    }
    _lastSearchLabel = null;
    _lastNewTaskLabel = null;
    return guardAsyncUnit(
      _transport.clearShortcutItems,
      operation: 'quickActionsClearShortcuts',
    );
  }

  void _handleActionId(String type) {
    if (_disposed) return;
    final action = QuickActionType.fromId(type);
    if (action == null) return;
    if (!_actionsController.hasListener) {
      _pendingAction = action;
      return;
    }
    _actionsController.add(action);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_actionsController.close());
  }
}
