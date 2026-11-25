import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../account/account_provider.dart';
import '../data/todo_provider.dart';
import 'home_widget_service.dart';

export 'home_widget_service.dart';

final homeWidgetSyncProvider = Provider<HomeWidgetSyncController>((ref) {
  final controller = HomeWidgetSyncController(
    ref,
    ref.watch(homeWidgetServiceProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// Keeps the home widget aligned with active account and task mutations.
final homeWidgetAutoSyncProvider = Provider<void>((ref) {
  final controller = ref.watch(homeWidgetSyncProvider);
  final account = ref.watch(
    accountProvider.select(
      (s) => (id: s.activeAccount?.id, name: s.activeAccount?.displayName),
    ),
  );
  if (account.id == null) {
    controller.handleSignedOut();
    return;
  }
  ref.listen<TodoState>(todoProvider, (_, next) {
    controller.syncState(next);
  });
  controller.handleSignedIn(account.id!, account.name ?? '');
});

/// Coordinates app-side home widget synchronization, lifecycle, and click URIs.
class HomeWidgetSyncController with WidgetsBindingObserver {
  HomeWidgetSyncController(this._ref, this._service)
    : _lastKnownMutationMs =
          _ref
              .read(sharedPreferencesProvider)
              .getInt(kWidgetLastMutationMsKey) ??
          0,
      _isAppForeground =
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused,
      _strings = HomeWidgetStrings.fromLocales(
        PlatformDispatcher.instance.locales,
      ) {
    WidgetsBinding.instance.addObserver(this);
    _syncRequestSub = _service.widgetSyncRequests.listen((reason) {
      unawaited(syncFromWidget(reason: reason));
    });
    _clickSub = _service.widgetClicked.listen((uri) {
      if (uri != null) {
        unawaited(_handleClickedUri(uri));
      }
    });
  }

  final Ref _ref;
  final HomeWidgetService _service;
  final StreamController<HomeWidgetAction> _actionsController =
      StreamController<HomeWidgetAction>.broadcast();

  StreamSubscription<String>? _syncRequestSub;
  StreamSubscription<Uri?>? _clickSub;
  Future<void> _syncChain = Future<void>.value();
  int _lastKnownMutationMs;
  bool _isAppForeground;
  HomeWidgetStrings _strings;
  String? _activeAccountId;
  String? _activeAccountName;
  bool _disposed = false;

  Stream<HomeWidgetAction> get actions => _actionsController.stream;

  void handleSignedOut() {
    _activeAccountId = null;
    _activeAccountName = null;
    unawaited(_service.clearWidgetData());
  }

  void handleSignedIn(String accountId, String accountName) {
    final wasSignedIn = _activeAccountId != null;
    final changed =
        _activeAccountId != accountId || _activeAccountName != accountName;
    _activeAccountId = accountId;
    _activeAccountName = accountName;
    if (wasSignedIn && changed) {
      pushCurrentState(force: true);
    }
  }

  Future<HomeWidgetAction?> bootstrap() async {
    _strings = await HomeWidgetService.resolveSystemStrings();
    if (_disposed) return null;
    await syncFromWidget(reason: 'startup');
    if (_disposed) return null;
    pushCurrentState(force: true);
    final uri = await _service.consumeInitialLaunchUri();
    if (_disposed) return null;
    return HomeWidgetAction.fromUri(uri);
  }

  Future<void> syncFromWidget({required String reason}) {
    return _enqueue(() async {
      if (_disposed) return;
      final prefs = _ref.read(sharedPreferencesProvider);
      await prefs.reload();
      if (_disposed) return;

      final latestMs = prefs.getInt(kWidgetLastMutationMsKey) ?? 0;
      if (latestMs > _lastKnownMutationMs) {
        _lastKnownMutationMs = latestMs;
        _ref.invalidate(accountProvider);
        if (_ref.read(accountProvider).activeAccount != null) {
          await _ref.read(todoRepositoryProvider).preload();
          if (_disposed) return;
          _ref.invalidate(todoProvider);
        }
      }

      await WidgetEventProcessor(
        widgetService: _service,
        read: _ref.read,
        strings: _strings,
        isBackground: false,
        isAppForeground: _isAppForeground,
        isActive: () => !_disposed,
      ).process(reason: reason);
      if (_disposed) return;

      if (reason == 'resume') {
        pushCurrentState();
      }
    });
  }

  void syncState(TodoState state, {bool force = false}) {
    if (_disposed) return;
    final account = _ref.read(accountProvider).activeAccount;
    if (account == null) {
      unawaited(_service.clearWidgetData());
      return;
    }
    unawaited(
      _service.syncWithState(
        state,
        accountId: account.id,
        accountName: account.displayName,
        strings: _strings,
        force: force,
      ),
    );
  }

  void pushCurrentState({bool force = false}) {
    if (_disposed) return;
    if (_ref.read(accountProvider).activeAccount == null) {
      unawaited(_service.clearWidgetData());
      return;
    }
    syncState(_ref.read(todoProvider), force: force);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
    } else if (state == AppLifecycleState.paused) {
      _isAppForeground = false;
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    unawaited(_refreshStringsAndPush(locales));
  }

  Future<void> _refreshStringsAndPush(List<Locale>? locales) async {
    _strings = await HomeWidgetService.resolveSystemStrings(locales: locales);
    if (_disposed) return;
    pushCurrentState();
  }

  Future<void> _handleClickedUri(Uri uri) async {
    await syncFromWidget(reason: 'click');
    if (_disposed) return;
    final action = HomeWidgetAction.fromUri(uri);
    if (action != null && !_actionsController.isClosed) {
      _actionsController.add(action);
    }
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _syncChain.then((_) => task(), onError: (_) => task());
    _syncChain = next.then((_) {}, onError: (_, _) {});
    return next;
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_syncRequestSub?.cancel());
    unawaited(_clickSub?.cancel());
    unawaited(_actionsController.close());
  }
}
