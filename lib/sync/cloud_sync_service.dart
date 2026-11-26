import 'package:result_dart/result_dart.dart';

import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../data/todo_settings_sync.dart';
import '../data/todo_state.dart';
import '../models/account.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_api.dart';
import 'substrate_pull_engine.dart';
import 'substrate_push_engine.dart';
import 'sync_guard.dart';

final _log = appLogFor('SyncEngine');

/// How much work one sync pass does; ordered from lightest to heaviest.
enum SyncKind {
  /// Push Outbox, then pull only the folders the push flagged.
  pushOnly,

  /// Push Outbox, then pull everything by delta.
  delta,

  /// Push Outbox, then reset delta links and prune stale rows.
  full,
}

/// Result returned by a completed sync pass.
class SyncOutcome {
  const SyncOutcome({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.pushedTasksCount,
    required this.syncedAt,
    this.settingsPatch,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;

  /// Null when the pass did not fetch remote settings (push-only syncs).
  final SyncedSettingsPatch? settingsPatch;
  final int pushedTasksCount;
  final DateTime syncedAt;
}

class CloudSyncService {
  CloudSyncService({
    required this.authClient,
    required this.todoApi,
    required this.tokenStorage,
  }) : _pushEngine = SubstratePushEngine(todoApi),
       _pullEngine = SubstratePullEngine(todoApi);

  final MicrosoftAuthClient authClient;
  final MicrosoftTodoApi todoApi;
  final AuthTokenStorage tokenStorage;
  final SubstratePushEngine _pushEngine;
  final SubstratePullEngine _pullEngine;

  /// Resolves valid MSA bearer token, CID, and discovered Substrate base URL.
  AsyncAppResult<SubstrateRequestContext> resolveContext(
    MicrosoftAccount account,
    TodoSettingsStore settings, {
    bool forceRefreshToken = false,
  }) async {
    final AppResult<MicrosoftAuthTokens> tokensResult;
    if (forceRefreshToken) {
      final stored = await tokenStorage.loadTokens(account.id);
      if (stored == null || stored.refreshToken.isEmpty) {
        return const Failure(
          AppError.auth(
            message: 'Refresh token unavailable; please sign in again.',
            code: 'no_refresh_token',
            requiresReauth: true,
          ),
        );
      }
      tokensResult = await authClient.refreshTokens(
        refreshToken: stored.refreshToken,
        fallbackUserId: stored.userId.isNotEmpty
            ? stored.userId
            : account.microsoftUserId,
      );
      if (tokensResult.isSuccess()) {
        await tokenStorage.saveTokens(account.id, tokensResult.getOrThrow());
      }
    } else {
      tokensResult = await authClient.ensureValidTokens(
        accountId: account.id,
        storage: tokenStorage,
        fallbackCid: account.microsoftUserId,
      );
    }

    if (tokensResult.isError()) {
      return Failure(tokensResult.exceptionOrNull()!);
    }
    final tokens = tokensResult.getOrThrow();
    final cid = tokens.userId.isNotEmpty
        ? tokens.userId
        : account.microsoftUserId;
    var baseUrl = settings.loadCachedEndpointUrl();
    if (baseUrl == null) {
      baseUrl = await authClient.discoverTodoEndpoint(cid);
      await settings.saveCachedEndpointUrl(baseUrl);
    }
    return Success(
      SubstrateRequestContext(
        baseUrl: baseUrl,
        accessToken: tokens.accessToken,
        cid: cid,
      ),
    );
  }

  /// Runs a sync pass: Push Outbox -> commit pushed IDs -> Pull (selective/delta/full).
  AsyncAppResult<SyncOutcome> syncAccount({
    required MicrosoftAccount account,
    required TodoState currentState,
    required TodoRepository repository,
    required TodoSettingsStore settings,
    required String Function(String prefix) idGenerator,
    TodoState Function()? readLatestState,
    Future<void> Function(OutboxPushOutcome pushOutcome)? onPushCommitted,
    SyncKind kind = SyncKind.delta,
    String reason = 'sync',
  }) async {
    Future<AppResult<SyncOutcome>> runAttempt({
      required bool forceRefreshToken,
    }) =>
        resolveContext(
          account,
          settings,
          forceRefreshToken: forceRefreshToken,
        ).flatMap(
          (ctx) => guardApiCall(
            () => _executeSync(
              ctx: ctx,
              currentState: readLatestState?.call() ?? currentState,
              repository: repository,
              settings: settings,
              idGenerator: idGenerator,
              readLatestState: readLatestState,
              onPushCommitted: onPushCommitted,
              kind: kind,
              reason: reason,
            ),
            operation: 'syncPhases',
          ),
        );

    final firstAttempt = await runAttempt(forceRefreshToken: false);
    if (firstAttempt.exceptionOrNull() is! AuthError) {
      return firstAttempt;
    }

    final retried = await runAttempt(forceRefreshToken: true);
    return retried.mapError(
      (error) => error is AuthError
          ? AppError.auth(
              message: error.message,
              code: error.code,
              requiresReauth: true,
            )
          : error,
    );
  }

  Future<SyncOutcome> _executeSync({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required TodoRepository repository,
    required TodoSettingsStore settings,
    required String Function(String prefix) idGenerator,
    TodoState Function()? readLatestState,
    Future<void> Function(OutboxPushOutcome pushOutcome)? onPushCommitted,
    required SyncKind kind,
    required String reason,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final outbox = repository.outbox;

    _log.info(
      'start reason=$reason kind=${kind.name} '
      'localLists=${currentState.lists.length} localTasks=${currentState.tasks.length} '
      'outboxOps=${outbox.ops.length}',
    );

    // 1. Push Outbox
    final pushOutcome = (await _pushEngine.pushOutbox(
      ctx: ctx,
      currentState: currentState,
      outbox: outbox,
      nowUtc: nowUtc,
      onPartialCommit: (partial) async {
        if (partial.followUpPullFolderRemoteIds.isNotEmpty) {
          await settings.savePendingTaskFolderPulls({
            ...settings.loadPendingTaskFolderPulls(),
            ...partial.followUpPullFolderRemoteIds,
          });
        }
        if (onPushCommitted != null) {
          await onPushCommitted(partial);
        } else {
          for (final seq in partial.ackedSeqs) {
            outbox.ackOp(seq);
          }
          for (final entry in partial.clearedRemoteIdKeys) {
            outbox.clearRemoteId(entry.type, entry.localId);
          }
          await repository.saveOutbox();
        }
      },
    )).getOrThrow();

    if (pushOutcome.followUpPullFolderRemoteIds.isNotEmpty) {
      await settings.savePendingTaskFolderPulls({
        ...settings.loadPendingTaskFolderPulls(),
        ...pushOutcome.followUpPullFolderRemoteIds,
      });
    }

    // 2. Commit pushed IDs & ack Outbox immediately before Pull starts.
    late List<ListGroup> workingGroups;
    late List<TodoList> workingLists;
    late List<TaskItem> workingTasks;
    if (onPushCommitted != null) {
      await onPushCommitted(pushOutcome);
      final latest = readLatestState?.call() ?? currentState;
      workingGroups = latest.groups;
      workingLists = latest.lists;
      workingTasks = latest.tasks;
    } else {
      for (final seq in pushOutcome.ackedSeqs) {
        outbox.ackOp(seq);
      }
      for (final entry in pushOutcome.clearedRemoteIdKeys) {
        outbox.clearRemoteId(entry.type, entry.localId);
      }
      workingGroups = [
        for (final g in currentState.groups)
          pushOutcome.pushedGroups[g.id] ?? g,
      ];
      workingLists = [
        for (final l in currentState.lists) pushOutcome.pushedLists[l.id] ?? l,
      ];
      workingTasks = [
        for (final t in currentState.tasks) pushOutcome.pushedTasks[t.id] ?? t,
      ];
    }

    // 3. Pull according to SyncKind
    switch (kind) {
      case SyncKind.pushOnly:
        final mergedTasks = await _pullEngine.pullSelectiveFolders(
          ctx: ctx,
          settings: settings,
          workingLists: workingLists,
          workingTasks: workingTasks,
          outbox: outbox,
          idGenerator: idGenerator,
        );
        return SyncOutcome(
          groups: workingGroups,
          lists: workingLists,
          tasks: mergedTasks,
          pushedTasksCount: pushOutcome.pushedTasks.length,
          syncedAt: DateTime.now().toUtc(),
        );

      case SyncKind.delta:
        final pulled = await _pullEngine.pullDelta(
          ctx: ctx,
          settings: settings,
          workingGroups: workingGroups,
          workingLists: workingLists,
          workingTasks: workingTasks,
          outbox: outbox,
          idGenerator: idGenerator,
        );
        return SyncOutcome(
          groups: pulled.groups,
          lists: pulled.lists,
          tasks: pulled.tasks,
          settingsPatch: pulled.settingsPatch,
          pushedTasksCount: pushOutcome.pushedTasks.length,
          syncedAt: DateTime.now().toUtc(),
        );

      case SyncKind.full:
        final pulled = await _pullEngine.pullFull(
          ctx: ctx,
          settings: settings,
          workingGroups: workingGroups,
          workingLists: workingLists,
          workingTasks: workingTasks,
          outbox: outbox,
          idGenerator: idGenerator,
          justPushedGroupIds: pushOutcome.pushedGroups.keys.toSet(),
          justPushedListIds: pushOutcome.pushedLists.keys.toSet(),
          justPushedTaskIds: pushOutcome.pushedTasks.keys.toSet(),
        );
        return SyncOutcome(
          groups: pulled.groups,
          lists: pulled.lists,
          tasks: pulled.tasks,
          settingsPatch: pulled.settingsPatch,
          pushedTasksCount: pushOutcome.pushedTasks.length,
          syncedAt: DateTime.now().toUtc(),
        );
    }
  }
}
