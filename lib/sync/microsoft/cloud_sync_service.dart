import 'package:result_dart/result_dart.dart';

import '../../auth/microsoft_auth_service.dart';
import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_repository.dart';
import '../../data/todo_state.dart';
import '../../models/account.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../sync_guard.dart';
import 'microsoft_todo_api.dart';
import 'substrate_pull_engine.dart';
import 'substrate_push_engine.dart';

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
    required this.syncedAt,
    this.remoteSettings,
    this.cancelled = false,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;

  /// Null when the pass did not fetch remote settings (push-only syncs).
  final Map<String, String>? remoteSettings;
  final DateTime syncedAt;
  final bool cancelled;
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
    TodoRepository repository, {
    bool forceRefreshToken = false,
  }) => _resolveTokens(account, forceRefreshToken: forceRefreshToken).flatMap((
    tokens,
  ) {
    final cid = tokens.userId.isNotEmpty
        ? tokens.userId
        : account.microsoftUserId;
    return _resolveBaseUrl(repository, cid).map(
      (baseUrl) => SubstrateRequestContext(
        baseUrl: baseUrl,
        accessToken: tokens.accessToken,
        cid: cid,
      ),
    );
  });

  AsyncAppResult<MicrosoftAuthTokens> _resolveTokens(
    MicrosoftAccount account, {
    required bool forceRefreshToken,
  }) async {
    if (!forceRefreshToken) {
      return authClient.ensureValidTokens(
        accountId: account.id,
        storage: tokenStorage,
        fallbackCid: account.microsoftUserId,
      );
    }
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
    final refreshed = await authClient.refreshTokens(
      refreshToken: stored.refreshToken,
      fallbackUserId: stored.userId.isNotEmpty
          ? stored.userId
          : account.microsoftUserId,
    );
    if (refreshed.isSuccess()) {
      await tokenStorage.saveTokens(account.id, refreshed.getOrNull()!);
    }
    return refreshed;
  }

  AsyncAppResult<String> _resolveBaseUrl(
    TodoRepository repository,
    String cid,
  ) async {
    final cached = repository.loadCachedEndpointUrl();
    if (cached != null) return Success(cached);
    final discovered = await guardApiCall(
      () => authClient.discoverTodoEndpoint(cid),
      operation: 'discoverEndpoint',
    );
    if (discovered.isSuccess()) {
      await repository.saveCachedEndpointUrl(discovered.getOrNull()!);
    }
    return discovered;
  }

  AsyncAppResult<T> _runWithAuthRetry<T extends Object>({
    required MicrosoftAccount account,
    required TodoRepository repository,
    required AsyncAppResult<T> Function(SubstrateRequestContext ctx) run,
  }) async {
    AsyncAppResult<T> runAttempt({required bool forceRefreshToken}) =>
        resolveContext(
          account,
          repository,
          forceRefreshToken: forceRefreshToken,
        ).flatMap(run);

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

  /// Pushes pending Outbox mutations without running a Pull pass.
  AsyncAppResult<OutboxPushOutcome> pushAccount({
    required MicrosoftAccount account,
    required TodoState currentState,
    required TodoRepository repository,
    TodoState Function()? readLatestState,
    Future<void> Function(OutboxPushOutcome pushOutcome)? onPushCommitted,
    String reason = 'push',
    PushLaneFilter laneFilter = PushLaneFilter.all,
  }) => _runWithAuthRetry<OutboxPushOutcome>(
    account: account,
    repository: repository,
    run: (ctx) => _executePush(
      ctx: ctx,
      currentState: readLatestState?.call() ?? currentState,
      repository: repository,
      readLatestState: readLatestState,
      onPushCommitted: onPushCommitted,
      reason: reason,
      laneFilter: laneFilter,
    ),
  );

  /// Pulls remote changes as a stateless patch and applies them against the
  /// latest live local state using monotonic outbox sequence numbers.
  AsyncAppResult<SyncOutcome> pullAccount({
    required MicrosoftAccount account,
    required TodoState currentState,
    required TodoRepository repository,
    required String Function(String prefix) idGenerator,
    TodoState Function()? readLatestState,
    SyncKind kind = SyncKind.delta,
    String reason = 'pull',
    bool Function()? isCancelled,
    int? pruneProtectSinceSeq,
  }) => _runWithAuthRetry<SyncOutcome>(
    account: account,
    repository: repository,
    run: (ctx) => _executePull(
      ctx: ctx,
      fallbackState: currentState,
      readLatestState: readLatestState,
      repository: repository,
      idGenerator: idGenerator,
      kind: kind,
      reason: reason,
      isCancelled: isCancelled,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    ),
  );

  AsyncAppResult<OutboxPushOutcome> _executePush({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required TodoRepository repository,
    TodoState Function()? readLatestState,
    Future<void> Function(OutboxPushOutcome pushOutcome)? onPushCommitted,
    required String reason,
    required PushLaneFilter laneFilter,
  }) {
    final nowUtc = DateTime.now().toUtc();
    final outbox = repository.outbox;

    _log.info(
      'push start reason=$reason '
      'localLists=${currentState.lists.length} localTasks=${currentState.tasks.length} '
      'outboxOps=${outbox.ops.length}',
    );

    return _pushEngine.pushOutbox(
      ctx: ctx,
      currentState: currentState,
      outbox: outbox,
      nowUtc: nowUtc,
      readLatestState: readLatestState,
      laneFilter: laneFilter,
      onItemCommitted: (itemOutcome) async {
        if (itemOutcome.followUpPullFolderRemoteIds.isNotEmpty) {
          await repository.savePendingTaskFolderPulls({
            ...repository.loadPendingTaskFolderPulls(),
            ...itemOutcome.followUpPullFolderRemoteIds,
          });
        }
        if (onPushCommitted != null) {
          await onPushCommitted(itemOutcome);
        } else {
          outbox.ackBatch(
            itemOutcome.ackedSeqs,
            itemOutcome.clearedRemoteIdKeys,
          );
          await repository.saveOutbox();
        }
      },
    );
  }

  AsyncAppResult<SyncOutcome> _executePull({
    required SubstrateRequestContext ctx,
    required TodoState fallbackState,
    required TodoState Function()? readLatestState,
    required TodoRepository repository,
    required String Function(String prefix) idGenerator,
    required SyncKind kind,
    required String reason,
    bool Function()? isCancelled,
    int? pruneProtectSinceSeq,
  }) {
    final outbox = repository.outbox;
    final pullStartSeq = outbox.lastSeq;
    final effectivePruneSeq = pruneProtectSinceSeq ?? pullStartSeq;
    final startState = readLatestState?.call() ?? fallbackState;

    _log.info(
      'pull start reason=$reason kind=${kind.name} '
      'localLists=${startState.lists.length} localTasks=${startState.tasks.length}',
    );

    final knownFolderRemoteIds = <String>{
      for (final l in startState.lists)
        if (l.remoteId != null) l.remoteId!,
    };

    return _pullEngine
        .fetchPatch(
          ctx: ctx,
          repository: repository,
          knownFolderRemoteIds: knownFolderRemoteIds,
          forceFullSync: kind == SyncKind.full,
          isSelective: kind == SyncKind.pushOnly,
          isCancelled: isCancelled,
        )
        .flatMap((fetched) {
          final liveState = readLatestState?.call() ?? fallbackState;
          return switch (fetched) {
            PullPatchCancelled() => Future.value(
              Success<SyncOutcome, AppError>(
                _cancelledOutcome(liveState, reason: reason, kind: kind),
              ),
            ),
            final RemotePullPatch patch => _applyFetchedPatch(
              patch: patch,
              liveState: liveState,
              repository: repository,
              outbox: outbox,
              idGenerator: idGenerator,
              pullStartSeq: pullStartSeq,
              pruneProtectSinceSeq: effectivePruneSeq,
            ),
          };
        });
  }

  SyncOutcome _cancelledOutcome(
    TodoState liveState, {
    required String reason,
    required SyncKind kind,
  }) {
    _log.info('pull cancelled reason=$reason kind=${kind.name}');
    return SyncOutcome(
      groups: liveState.groups,
      lists: liveState.lists,
      tasks: liveState.tasks,
      syncedAt: DateTime.now().toUtc(),
      cancelled: true,
    );
  }

  AsyncAppResult<SyncOutcome> _applyFetchedPatch({
    required RemotePullPatch patch,
    required TodoState liveState,
    required TodoRepository repository,
    required SyncOutboxQueue outbox,
    required String Function(String prefix) idGenerator,
    required int pullStartSeq,
    required int pruneProtectSinceSeq,
  }) => guardApiCall(() async {
    final applied = await _pullEngine.applyPatch(
      patch: patch,
      repository: repository,
      liveGroups: liveState.groups,
      liveLists: liveState.lists,
      liveTasks: liveState.tasks,
      outbox: outbox,
      idGenerator: idGenerator,
      pullStartSeq: pullStartSeq,
      pruneProtectSinceSeq: pruneProtectSinceSeq,
    );
    return SyncOutcome(
      groups: applied.groups,
      lists: applied.lists,
      tasks: applied.tasks,
      remoteSettings: applied.remoteSettings,
      syncedAt: DateTime.now().toUtc(),
    );
  }, operation: 'applyPullPatch');
}
