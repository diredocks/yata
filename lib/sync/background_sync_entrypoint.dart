import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/sync_job.dart';
import '../data/sync_outbox.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../detailview/attachments/attachment_service.dart';
import '../models/account.dart';
import '../widget/home_widget_service.dart';
import 'background_sync_bridge.dart';
import 'microsoft/cloud_sync_service.dart';
import 'microsoft/microsoft_todo_api.dart';
import 'sync_provider.dart';
import 'sync_worker_engine.dart';

final _log = appLogFor('BackgroundEntrypoint');

/// Unified headless Dart entrypoint invoked by Android's `YataBackgroundEngineHost`
/// (shared across WorkManager sync jobs, attachment transfers, and home widget ops).
///
/// The host sends `runBackgroundSync` calls over `kBackgroundSyncChannelName`
/// and waits for `backgroundRunCompleted` so a single engine instance can serve
/// multiple sequential runs without tearing down and rebooting Dart each time.
@pragma('vm:entry-point')
Future<void> yataBackgroundSyncEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kBackgroundSyncChannelName);
  const scheduler = PlatformBackgroundSyncScheduler();

  channel.setMethodCallHandler((call) async {
    if (call.method != 'runBackgroundSync') return null;
    final args = call.arguments as Map<Object?, Object?>? ?? const {};
    final laneName = args['lane'] as String? ?? SyncJobLane.metadata.name;
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

    if (laneName == 'widget') {
      await _runWidgetPass(prefs: prefs, database: database, reason: reason);
    }

    if (active is! MicrosoftAccount) {
      return (shouldRetry: false, hasPendingTransfers: false);
    }

    final settings = TodoSettingsStore(prefs, accountId: active.id);
    final repo = TodoRepository.forSession(database, settings);
    await repo.preload();

    final authClient = HttpMicrosoftAuthClient();
    final todoApi = HttpMicrosoftTodoApi();
    final tokenStorage = AuthTokenStorage(prefs);
    final cloudSync = CloudSyncService(
      authClient: authClient,
      todoApi: todoApi,
      tokenStorage: tokenStorage,
    );
    var idSeq = 0;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoDatabaseProvider.overrideWithValue(database),
      ],
    );
    try {
      final attachmentService = container.read(attachmentServiceProvider);
      final engine = SyncWorkerEngine(
        account: active,
        repository: repo,
        settings: settings,
        cloudSync: cloudSync,
        idGenerator: (prefix) =>
            '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${++idSeq}',
        downloadAttachment: SyncWorkerEngine.defaultAttachmentDownloader(
          account: active,
          settings: settings,
          cloudSync: cloudSync,
          attachmentService: attachmentService,
        ),
      );

      final targetLane = laneName == SyncJobLane.transfer.name
          ? SyncJobLane.transfer
          : (laneName == SyncJobLane.metadata.name
                ? SyncJobLane.metadata
                : null);

      // If outbox has pending items but no explicit job row was enqueued yet,
      // ensure a push job is present so offline mutations always drain.
      if (repo.outbox.isNotEmpty) {
        final hasAttachmentOps = repo.outbox.ops.any(
          (op) =>
              op.entityType == SyncEntityType.attachment &&
              op.kind == SyncOpKind.upsert,
        );
        final hasMetadataOps = repo.outbox.ops.any(
          (op) =>
              !(op.entityType == SyncEntityType.attachment &&
                  op.kind == SyncOpKind.upsert),
        );
        if (hasMetadataOps && targetLane != SyncJobLane.transfer) {
          await engine.enqueueJob(
            jobId: 'outbox_metadata_${active.id}',
            lane: SyncJobLane.metadata,
            jobType: SyncJobType.pushMetadata,
            payload: {'reason': reason},
          );
        }
        if (hasAttachmentOps && targetLane != SyncJobLane.metadata) {
          await engine.enqueueJob(
            jobId: 'outbox_transfer_${active.id}',
            lane: SyncJobLane.transfer,
            jobType: SyncJobType.uploadAttachment,
            payload: {'reason': reason},
          );
        }
      }

      final drainResult = await engine.drain(lane: targetLane);
      drainResult.fold(
        (summary) {
          shouldRetry = summary.hasRetryableFailures;
          hasPendingTransfers = summary.hasPendingTransfers;
          _log.info(
            'Headless drain lane=$laneName reason=$reason '
            'processed=${summary.processedCount} failed=${summary.failedCount} '
            'pendingTransfers=${summary.hasPendingTransfers}',
          );
        },
        (error) {
          shouldRetry = error.isRetryable;
          _log.warning('Headless drain failed: ${error.describe()}');
        },
      );
    } finally {
      container.dispose();
    }
  } finally {
    await database.close();
  }
  return (shouldRetry: shouldRetry, hasPendingTransfers: hasPendingTransfers);
}

Future<void> _runWidgetPass({
  required SharedPreferences prefs,
  required TodoDatabase database,
  required String reason,
}) async {
  final strings = await HomeWidgetService.resolveSystemStrings();
  final activeId = AccountLocalStorage(prefs).load().activeAccountId;
  if (activeId != null) {
    await TodoRepository.forAccount(
      prefs,
      accountId: activeId,
      database: database,
    ).preload();
  }
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoDatabaseProvider.overrideWithValue(database),
      realtimeSyncEnabledProvider.overrideWithValue(false),
      periodicSyncEnabledProvider.overrideWithValue(false),
    ],
  );
  try {
    final result = await WidgetEventProcessor(
      widgetService: HomeWidgetService(const FlutterHomeWidgetTransport()),
      read: container.read,
      strings: strings,
      isBackground: true,
      isAppForeground: false,
    ).process(reason: reason);
    if (result.didMutate || result.didSync) {
      await prefs.setInt(
        kWidgetLastMutationMsKey,
        DateTime.now().millisecondsSinceEpoch,
      );
      BackgroundWorkerEventBus.emit(
        BackgroundWorkerEvent(
          kind: BackgroundWorkerEvent.kindDbChanged,
          accountKey: activeId ?? 'default',
          lane: SyncJobLane.metadata,
          reason: 'widget_$reason',
        ),
      );
    }
  } finally {
    container.dispose();
  }
}
