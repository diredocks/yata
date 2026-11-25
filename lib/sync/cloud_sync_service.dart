import 'package:result_dart/result_dart.dart';

import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/logging/app_logger.dart';
import '../core/result/app_result.dart';
import '../data/sync_dirty_fields.dart';
import '../data/todo_repository.dart';
import '../data/todo_settings_store.dart';
import '../data/todo_settings_sync.dart';
import '../data/todo_state.dart';
import '../models/account.dart';
import '../models/pending_step_deletion.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'microsoft_todo_api.dart';
import 'substrate_pull_engine.dart';
import 'substrate_push_engine.dart';
import 'sync_guard.dart';

final _log = appLogFor('SyncEngine');

/// Result returned by a full 10-phase Substrate sync pass.
class SyncOutcome {
  const SyncOutcome({
    required this.groups,
    required this.lists,
    required this.tasks,
    required this.settingsPatch,
    required this.processedDeletedGroupRemoteIds,
    required this.processedDeletedListRemoteIds,
    required this.processedDeletedTaskRemoteIds,
    required this.processedDeletedSteps,
    required this.syncedGroupIds,
    required this.syncedListIds,
    required this.syncedTaskIds,
    required this.syncedSettingKeys,
    required this.syncedAt,
    this.syncedDirtyFields = const SyncedDirtyFields(),
    this.snapshotState,
  });

  final List<ListGroup> groups;
  final List<TodoList> lists;
  final List<TaskItem> tasks;
  final SyncedSettingsPatch settingsPatch;
  final List<String> processedDeletedGroupRemoteIds;
  final List<String> processedDeletedListRemoteIds;
  final List<String> processedDeletedTaskRemoteIds;
  final List<PendingStepDeletion> processedDeletedSteps;
  final Set<String> syncedGroupIds;
  final Set<String> syncedListIds;
  final Set<String> syncedTaskIds;
  final Set<String> syncedSettingKeys;
  final SyncedDirtyFields syncedDirtyFields;
  final DateTime syncedAt;
  final TodoState? snapshotState;
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

  /// Runs all 10 Substrate v1 sync phases for [account] and [currentState].
  AsyncAppResult<SyncOutcome> syncAccount({
    required MicrosoftAccount account,
    required TodoState currentState,
    required TodoRepository repository,
    required TodoSettingsStore settings,
    required String Function(String prefix) idGenerator,
    TodoState Function()? readLatestState,
    bool forceFullSync = false,
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
            () => _executeSyncPhases(
              ctx: ctx,
              currentState: readLatestState?.call() ?? currentState,
              repository: repository,
              settings: settings,
              idGenerator: idGenerator,
              forceFullSync: forceFullSync,
              reason: reason,
            ),
            operation: 'syncPhases',
          ),
        );

    final firstAttempt = await runAttempt(forceRefreshToken: false);
    if (firstAttempt.exceptionOrNull() is! AuthError) {
      return firstAttempt;
    }

    // 401: force a token refresh and retry once.
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

  Future<SyncOutcome> _executeSyncPhases({
    required SubstrateRequestContext ctx,
    required TodoState currentState,
    required TodoRepository repository,
    required TodoSettingsStore settings,
    required String Function(String prefix) idGenerator,
    bool forceFullSync = false,
    String reason = 'sync',
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final dirtySettingKeys = settings.loadDirtySettingKeys().toSet();
    final dirtyGroupIds = repository.loadDirtyGroupIds().toSet();
    final dirtyGroupFields = repository.loadDirtyGroupFields();
    final dirtyListIds = repository.loadDirtyListIds().toSet();
    final dirtyListFields = repository.loadDirtyListFields();
    final dirtyTaskIds = repository.loadDirtyTaskIds().toSet();
    final dirtyTaskFields = repository.loadDirtyTaskFields();
    final dirtyStepIdsByTask = repository.loadDirtyStepIds();
    final taskBaseNotes = repository.loadTaskBaseNotes();

    _log.info(
      'start reason=$reason forceFullSync=$forceFullSync '
      'localLists=${currentState.lists.length} localTasks=${currentState.tasks.length} '
      'dirtyTasks=${dirtyTaskIds.length}',
    );

    final metaPush = await _pushEngine.pushMetadataAndDeletions(
      ctx: ctx,
      currentState: currentState,
      repository: repository,
      dirtySettingKeys: dirtySettingKeys,
      dirtyGroupIds: dirtyGroupIds,
      dirtyGroupFields: dirtyGroupFields,
      dirtyListIds: dirtyListIds,
      dirtyListFields: dirtyListFields,
      nowUtc: nowUtc,
    );

    final metaPull = await _pullEngine.pullSettingsGroupsAndFolders(
      ctx: ctx,
      settings: settings,
      workingGroups: metaPush.groups,
      workingLists: metaPush.lists,
      remainingDirtySettings: dirtySettingKeys.difference(
        metaPush.syncedSettingKeys,
      ),
      remainingDirtyGroups: dirtyGroupIds.difference(metaPush.syncedGroupIds),
      remainingDirtyLists: dirtyListIds.difference(metaPush.syncedListIds),
      syncedGroupIds: metaPush.syncedGroupIds,
      syncedListIds: metaPush.syncedListIds,
      forceFullSync: forceFullSync,
      idGenerator: idGenerator,
    );

    // Remove tasks orphaned by a deleted remote folder.
    final validListIds = {for (final l in metaPull.lists) l.id};
    final liveTasks = currentState.tasks
        .where((t) => validListIds.contains(t.listId))
        .toList();

    final taskPush = await _pushEngine.pushTasksAndSteps(
      ctx: ctx,
      workingLists: metaPull.lists,
      workingTasks: liveTasks,
      processedDeletedTaskRemoteIds: metaPush.processedDeletedTaskRemoteIds,
      dirtyTaskIds: dirtyTaskIds,
      dirtyTaskFields: dirtyTaskFields,
      dirtyStepIdsByTask: dirtyStepIdsByTask,
      taskBaseNotes: taskBaseNotes,
      firstDayOfWeek: currentState.startOfWeek,
      nowUtc: nowUtc,
    );

    final mergedTasks = await _pullEngine.pullAndMergeTasksDelta(
      ctx: ctx,
      settings: settings,
      workingLists: metaPull.lists,
      workingTasks: taskPush.tasks,
      remainingDirtyTasks: dirtyTaskIds.difference(taskPush.syncedTaskIds),
      syncedTaskIds: taskPush.syncedTaskIds,
      forceFullSync: forceFullSync,
      idGenerator: idGenerator,
    );

    return SyncOutcome(
      groups: metaPull.groups,
      lists: metaPull.lists,
      tasks: mergedTasks,
      settingsPatch: metaPull.settingsPatch,
      processedDeletedGroupRemoteIds: metaPush.processedDeletedGroupRemoteIds,
      processedDeletedListRemoteIds: metaPush.processedDeletedListRemoteIds,
      processedDeletedTaskRemoteIds: metaPush.processedDeletedTaskRemoteIds,
      processedDeletedSteps: metaPush.processedDeletedSteps,
      syncedGroupIds: metaPush.syncedGroupIds,
      syncedListIds: metaPush.syncedListIds,
      syncedTaskIds: taskPush.syncedTaskIds,
      syncedSettingKeys: metaPush.syncedSettingKeys,
      syncedDirtyFields: SyncedDirtyFields(
        groupFields: metaPush.syncedGroupFields,
        listFields: metaPush.syncedListFields,
        taskFields: taskPush.syncedTaskFields,
        stepIds: taskPush.syncedStepIds,
      ),
      syncedAt: DateTime.now().toUtc(),
      snapshotState: currentState,
    );
  }
}
