import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/sync_job.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../detailview/attachments/attachment_service.dart';
import '../models/account.dart';
import '../widget/home_widget_service.dart';
import 'background_sync_bridge.dart';
import 'sync_provider.dart';
import 'sync_worker_engine.dart';

final _log = appLogFor('BackgroundEntrypoint');

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

    final settings = TodoSettingsStore(prefs, accountId: active.id);
    final repo = TodoRepository.forSession(database, settings);
    await repo.preload();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoDatabaseProvider.overrideWithValue(database),
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
      }

      if (active is! MicrosoftAccount) {
        return (shouldRetry: false, hasPendingTransfers: false);
      }

      final cloudSync = container.read(cloudSyncServiceProvider);
      final attachmentService = container.read(attachmentServiceProvider);
      var idSeq = 0;
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

      final targetLane = SyncJobLane.values.firstWhereOrNull(
        (lane) => lane.name == laneName,
      );
      await _enqueuePendingOutboxJobs(
        engine: engine,
        repo: repo,
        accountId: active.id,
        targetLane: targetLane,
        reason: reason,
      );

      final drainResult = await engine.drain(lane: targetLane);
      drainResult.fold(
        (summary) {
          shouldRetry = summary.hasRetryableFailures;
          hasPendingTransfers =
              summary.hasPendingTransfers ||
              (targetLane != SyncJobLane.transfer &&
                  repo.outbox.ops.any((op) => op.isAttachmentUpload));
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

Future<void> _enqueuePendingOutboxJobs({
  required SyncWorkerEngine engine,
  required TodoRepository repo,
  required String accountId,
  required SyncJobLane? targetLane,
  required String reason,
}) async {
  if (repo.outbox.isEmpty) return;
  final hasAttachmentOps = repo.outbox.ops.any((op) => op.isAttachmentUpload);
  final hasMetadataOps = repo.outbox.ops.any((op) => !op.isAttachmentUpload);
  if (hasMetadataOps && targetLane != SyncJobLane.transfer) {
    await engine.enqueueJob(
      jobId: 'outbox_metadata_$accountId',
      lane: SyncJobLane.metadata,
      jobType: SyncJobType.pushMetadata,
      payload: {'reason': reason},
    );
  }
  if (hasAttachmentOps && targetLane != SyncJobLane.metadata) {
    await engine.enqueueJob(
      jobId: 'outbox_transfer_$accountId',
      lane: SyncJobLane.transfer,
      jobType: SyncJobType.uploadAttachment,
      payload: {'reason': reason},
    );
  }
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
    BackgroundWorkerEvent.dbChanged(
      accountKey: accountId,
      lane: SyncJobLane.metadata,
      reason: 'widget_$reason',
    ),
  );
}
