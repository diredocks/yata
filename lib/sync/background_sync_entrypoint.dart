import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../models/account.dart';
import '../models/default_lists.dart';
import '../widget/home_widget_service.dart';
import 'background_sync_bridge.dart';
import 'microsoft/microsoft_todo_api.dart';
import 'microsoft/substrate_push_engine.dart';
import 'sync_provider.dart';
import 'sync_store.dart';

final _log = appLogFor('BackgroundEntrypoint');

typedef BackgroundPassOutcome = ({
  bool shouldRetry,
  bool hasPendingTransfers,
  bool didMutateDb,
});

/// Unified headless Dart entrypoint invoked by Android's `YataBackgroundEngineHost`
/// (shared across WorkManager sync jobs, attachment transfers, and home widget ops).
@pragma('vm:entry-point')
Future<void> yataBackgroundSyncEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kBackgroundSyncChannelName);
  const scheduler = PlatformBackgroundSyncScheduler();

  channel.setMethodCallHandler((call) async {
    if (call.method != 'runBackgroundSync') return null;
    final args = call.arguments as Map<Object?, Object?>? ?? const {};
    final laneName = args['lane'] as String? ?? BackgroundSyncLane.metadata.name;
    final reason = args['reason'] as String? ?? 'background';
    final outcome = await _runHeadlessSyncPass(
      laneName: laneName,
      reason: reason,
    );
    await scheduler.notifyBackgroundRunCompleted(
      lane: laneName,
      shouldRetry: outcome.shouldRetry,
      hasPendingTransfers: outcome.hasPendingTransfers,
    );
    return null;
  });

  await guardAsyncUnit(
    () => channel.invokeMethod<void>('backgroundEngineReady'),
    operation: 'backgroundEngineReady',
  );
}

/// Pushes pending outbox operations directly for the requested [lane] and
/// persists committed results to SQLite without intermediate SyncJob records.
Future<BackgroundPassOutcome> runBackgroundOutboxPass({
  required TodoRepository repository,
  required TodoSettingsStore settings,
  required MicrosoftTodoApi todoApi,
  required BackgroundSyncLane? lane,
  required String reason,
  void Function(BackgroundDbChangedEvent event)? onDbChanged,
}) async {
  final laneFilter = lane == BackgroundSyncLane.transfer
      ? PushLaneFilter.attachmentsOnly
      : PushLaneFilter.metadataOnly;
  final wantAttachments = laneFilter == PushLaneFilter.attachmentsOnly;
  final hasMatchingOps = repository.outbox.ops.any(
    (op) => op.isAttachmentUpload == wantAttachments,
  );
  if (!hasMatchingOps) {
    final hasPendingTransfers =
        lane != BackgroundSyncLane.transfer &&
        repository.outbox.ops.any((op) => op.isAttachmentUpload);
    return (
      shouldRetry: false,
      hasPendingTransfers: hasPendingTransfers,
      didMutateDb: false,
    );
  }

  final store = SyncStore(repository: repository, settings: settings);
  final snapshot = _buildSnapshotState(repository, settings);
  final result = await SubstratePushEngine(todoApi).pushOutbox(
    currentState: snapshot,
    outbox: repository.outbox,
    nowUtc: DateTime.now().toUtc(),
    readLatestState: () => _buildSnapshotState(repository, settings),
    onItemCommitted: store.commitPushHeadless,
    laneFilter: laneFilter,
    reason: reason,
  );

  return result.fold(
    (outcome) {
      if (outcome.didWork) {
        (onDbChanged ?? BackgroundWorkerEventBus.emit)(
          BackgroundDbChangedEvent(
            accountKey: repository.accountKey,
            lane: lane,
            reason: reason,
          ),
        );
      }
      final hasPendingTransfers = repository.outbox.ops.any(
        (op) => op.isAttachmentUpload,
      );
      _log.info(
        'Headless outbox push lane=${lane?.name ?? 'all'} reason=$reason '
        'didWork=${outcome.didWork} pendingTransfers=$hasPendingTransfers',
      );
      return (
        shouldRetry: false,
        hasPendingTransfers: hasPendingTransfers,
        didMutateDb: outcome.didWork,
      );
    },
    (error) {
      _log.warning(
        'Headless outbox push failed lane=${lane?.name ?? 'all'} '
        'reason=$reason: ${error.describe()}',
      );
      final hasPendingTransfers =
          lane != BackgroundSyncLane.transfer &&
          repository.outbox.ops.any((op) => op.isAttachmentUpload);
      return (
        shouldRetry: error.isRetryable,
        hasPendingTransfers: hasPendingTransfers,
        didMutateDb: false,
      );
    },
  );
}

Future<({bool shouldRetry, bool hasPendingTransfers})> _runHeadlessSyncPass({
  required String laneName,
  required String reason,
}) async {
  final database = TodoDatabase();
  var shouldRetry = false;
  var hasPendingTransfers = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final snapshot = AccountLocalStorage(prefs).load();
    final active = snapshot.accounts.firstWhereOrNull(
      (a) => a.id == snapshot.activeAccountId,
    );
    if (active == null) {
      return (shouldRetry: false, hasPendingTransfers: false);
    }

    final settings = TodoSettingsStore(prefs, accountId: active.id);
    final repo = TodoRepository.forSession(database, settings);
    await repo.preload();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoDatabaseProvider.overrideWithValue(database),
        todoRepositoryProvider.overrideWithValue(repo),
        realtimeSyncEnabledProvider.overrideWithValue(false),
        periodicSyncEnabledProvider.overrideWithValue(false),
        startupSyncEnabledProvider.overrideWithValue(false),
      ],
    );
    try {
      if (laneName == 'widget') {
        await _runWidgetPass(
          container: container,
          prefs: prefs,
          accountId: active.id,
          reason: reason,
        );
        await repo.preload();
      }

      if (active is! MicrosoftAccount) {
        return (shouldRetry: false, hasPendingTransfers: false);
      }

      final targetLane = BackgroundSyncLane.values.firstWhereOrNull(
        (lane) => lane.name == laneName,
      );
      final outcome = await runBackgroundOutboxPass(
        repository: repo,
        settings: settings,
        todoApi: container.read(microsoftTodoApiProvider),
        lane: targetLane,
        reason: reason,
      );
      shouldRetry = outcome.shouldRetry;
      hasPendingTransfers = outcome.hasPendingTransfers;
    } finally {
      container.dispose();
    }
  } finally {
    await database.close();
  }
  return (shouldRetry: shouldRetry, hasPendingTransfers: hasPendingTransfers);
}

TodoState _buildSnapshotState(
  TodoRepository repository,
  TodoSettingsStore settings,
) {
  final loaded = settings.load();
  return TodoState(
    lists: normalizeSmartLists(repository.readCachedLists()),
    groups: [...repository.readCachedGroups()],
    tasks: [...repository.readCachedTasks()],
    selectedListId: loaded.selectedListId,
    startOfWeek: loaded.startOfWeek,
    showDueTodayInMyDay: loaded.showDueTodayInMyDay,
    addNewTasksOnTop: loaded.addNewTasksOnTop,
    moveStarredTasksToTop: loaded.moveStarredTasksToTop,
    confirmBeforeDeleting: loaded.confirmBeforeDeleting,
    completedExpandedByList: loaded.completedExpandedByList,
  );
}

Future<void> _runWidgetPass({
  required ProviderContainer container,
  required SharedPreferences prefs,
  required String accountId,
  required String reason,
}) async {
  final strings = await HomeWidgetService.resolveSystemStrings();
  final result = await WidgetEventProcessor(
    widgetService: HomeWidgetService(const FlutterHomeWidgetTransport()),
    read: container.read,
    strings: strings,
    isBackground: true,
    isAppForeground: false,
  ).process(reason: reason);
  if (!result.didMutate && !result.didSync) return;
  await prefs.setInt(
    kWidgetLastMutationMsKey,
    DateTime.now().millisecondsSinceEpoch,
  );
  BackgroundWorkerEventBus.emit(
    BackgroundDbChangedEvent(
      accountKey: accountId,
      lane: BackgroundSyncLane.metadata,
      reason: 'widget_$reason',
    ),
  );
}
