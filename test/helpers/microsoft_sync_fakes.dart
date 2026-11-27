import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_local_storage.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/auth/msa_webview_launcher.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/core/result/app_result.dart';
import 'package:yata/data/sync_outbox.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/data/todo_settings_store.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_guard.dart';
import 'package:yata/sync/sync_provider.dart';

class FakeInteractiveMsaClient implements MsaInteractiveSignInClient {
  FakeInteractiveMsaClient(this.result);

  final MsaInteractiveSignInResult? result;
  String? lastAuthorizeUrl;

  @override
  Future<MsaInteractiveSignInResult?> signIn({
    BuildContext? context,
    required String authorizeUrl,
    required String redirectUri,
    bool clearCookies = true,
  }) async {
    lastAuthorizeUrl = authorizeUrl;
    return result;
  }
}

class FakeAuthClient implements MicrosoftAuthClient {
  FakeAuthClient({this.onRefreshTokens, this.onFetchUserProfile});

  final Future<MicrosoftAuthTokens> Function(String refreshToken)?
  onRefreshTokens;
  final Future<MicrosoftUserProfile> Function(
    String cid,
    String refreshToken,
    String? fallbackEmail,
  )?
  onFetchUserProfile;
  int discoverCalls = 0;

  @override
  String buildAuthorizeUrl({String? loginHint, String? uaid}) =>
      'https://login.live.com/oauth20_authorize.srf?client_id=000000004C18365E';

  @override
  AppResult<String> extractAuthorizationCode(String rawInput) =>
      HttpMicrosoftAuthClient().extractAuthorizationCode(rawInput);

  @override
  AsyncAppResult<MicrosoftAuthTokens> exchangeAuthorizationCode({
    required String code,
    String? uaid,
  }) async {
    return Success(
      MicrosoftAuthTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        userId: 'cid12345',
      ),
    );
  }

  @override
  AsyncAppResult<MicrosoftAuthTokens> refreshTokens({
    required String refreshToken,
    String? scope,
    String? fallbackUserId,
    String? uaid,
  }) {
    return guardApiCall(() async {
      if (onRefreshTokens != null) {
        return onRefreshTokens!(refreshToken);
      }
      return MicrosoftAuthTokens(
        accessToken: 'refreshed-access',
        refreshToken: 'refreshed-rt',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        userId: fallbackUserId ?? 'cid12345',
      );
    });
  }

  @override
  AsyncAppResult<MicrosoftSignInResult> completeSignInWithCode({
    required String code,
    String? loginHint,
    String? uaid,
  }) {
    return exchangeAuthorizationCode(code: code, uaid: uaid).map(
      (tokens) => MicrosoftSignInResult(
        profile: MicrosoftUserProfile(
          id: tokens.userId,
          displayName: 'Alice Lee',
          email: loginHint ?? 'alice@outlook.com',
        ),
        tokens: tokens,
      ),
    );
  }

  @override
  Future<MicrosoftUserProfile> fetchUserProfile({
    required String cid,
    required String refreshToken,
    String? fallbackEmail,
  }) async {
    if (onFetchUserProfile != null) {
      return onFetchUserProfile!(cid, refreshToken, fallbackEmail);
    }
    return MicrosoftUserProfile(
      id: cid,
      displayName: 'Alice Lee',
      email: fallbackEmail ?? 'alice@outlook.com',
    );
  }

  @override
  Future<String> discoverTodoEndpoint(String cid) async {
    discoverCalls += 1;
    return 'https://substrate.office.com/todob2/api/v1/';
  }

  @override
  AsyncAppResult<MicrosoftAuthTokens> ensureValidTokens({
    required String accountId,
    required AuthTokenStorage storage,
    String? fallbackCid,
  }) async {
    final stored = await storage.loadTokens(accountId);
    if (stored == null) {
      return const Failure(
        AppError.auth(message: 'Not signed in', requiresReauth: true),
      );
    }
    if (!stored.isExpired && stored.accessToken.isNotEmpty) {
      return Success(stored);
    }
    final refreshed = await refreshTokens(
      refreshToken: stored.refreshToken,
      fallbackUserId: stored.userId.isNotEmpty ? stored.userId : fallbackCid,
    );
    if (refreshed.isSuccess()) {
      await storage.saveTokens(accountId, refreshed.getOrThrow());
    }
    return refreshed;
  }
}

class FakeSubstrateApi implements MicrosoftTodoApi {
  final List<String> callLog = [];
  final Set<String> ownRequestIds = {};
  final Map<String, String> remoteSettings = {};
  final StreamController<RealtimeEvent> realtimeController =
      StreamController<RealtimeEvent>.broadcast();

  DeltaPageResult<RemoteFolderGroup> Function(String? deltaLink)?
  onFetchGroupsDelta;
  DeltaPageResult<RemoteTodoFolder> Function(String? deltaLink)?
  onFetchFoldersDelta;
  DeltaPageResult<RemoteTodoTask> Function(
    String folderRemoteId,
    String? deltaLink,
  )?
  onFetchTasksDelta;

  Future<RemoteFolderGroup> Function(String name, DateTime order)?
  onCreateGroup;
  Future<RemoteFolderGroup> Function(
    String remoteId,
    Map<String, dynamic> patch,
  )?
  onPatchGroup;
  Future<void> Function(String remoteId)? onDeleteGroup;

  Future<RemoteTodoFolder> Function(Map<String, dynamic> payload)?
  onCreateFolder;
  Future<RemoteTodoFolder> Function(
    String remoteId,
    Map<String, dynamic> patch,
  )?
  onPatchFolder;
  Future<void> Function(String remoteId)? onDeleteFolder;

  Future<RemoteTodoTask> Function(
    String folderRemoteId,
    Map<String, dynamic> payload,
  )?
  onCreateTask;
  Future<RemoteTodoTask> Function(
    String taskRemoteId,
    Map<String, dynamic> patch,
    String? changeKey,
  )?
  onPatchTask;
  Future<RemoteTodoTask> Function(String taskRemoteId)? onGetTask;
  Future<void> Function(String taskRemoteId)? onDeleteTask;

  Future<RemoteTaskStep> Function(
    String taskRemoteId,
    String subject,
    DateTime order,
  )?
  onCreateStep;
  Future<RemoteTaskStep> Function(
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  )?
  onPatchStep;
  Future<void> Function(String taskRemoteId, String stepRemoteId)? onDeleteStep;

  Future<RemoteFileUpload> Function(
    String taskRemoteId,
    String fileName,
    List<int> bytes,
    String? contentType,
  )?
  onUploadAttachment;
  Future<Uint8List> Function(String webLink)? onDownloadAttachment;
  Future<void> Function(String taskRemoteId, String entityRemoteId)?
  onDeleteLinkedEntity;

  int _idSeq = 0;

  @override
  bool isOwnRequestId(String? requestId) =>
      requestId != null && ownRequestIds.contains(requestId);

  @override
  AsyncAppResult<Map<String, String>> getSettings(SubstrateRequestContext ctx) {
    return guardApiCall(() async {
      callLog.add('GET settings');
      return Map<String, String>.from(remoteSettings);
    });
  }

  @override
  AsyncAppResult<Unit> patchSetting(
    SubstrateRequestContext ctx,
    String key,
    String value,
  ) {
    return guardApiCall(() async {
      callLog.add('PATCH settings/$key=$value');
      remoteSettings[key] = value;
      return unit;
    });
  }

  @override
  AsyncAppResult<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) {
    return guardApiCall(() async {
      callLog.add('GET foldergroups($deltaLink)');
      return onFetchGroupsDelta?.call(deltaLink) ??
          const DeltaPageResult(items: [], deltaLink: 'dl-groups-1');
    });
  }

  @override
  AsyncAppResult<RemoteFolderGroup> createFolderGroup(
    SubstrateRequestContext ctx, {
    required String name,
    required DateTime orderDateTime,
  }) {
    return guardApiCall(() async {
      callLog.add('POST foldergroups $name');
      if (onCreateGroup != null) return onCreateGroup!(name, orderDateTime);
      _idSeq += 1;
      return RemoteFolderGroup(
        id: 'rg-$_idSeq',
        name: name,
        orderDateTime: orderDateTime,
      );
    });
  }

  @override
  AsyncAppResult<RemoteFolderGroup> patchFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  ) {
    return guardApiCall(() async {
      callLog.add('PATCH foldergroups/$remoteId');
      if (onPatchGroup != null) return onPatchGroup!(remoteId, patch);
      return RemoteFolderGroup(
        id: remoteId,
        name: patch['Name'] as String? ?? 'Group',
        orderDateTime: DateTime.now().toUtc(),
      );
    });
  }

  @override
  AsyncAppResult<Unit> deleteFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
  ) {
    return guardApiCall(() async {
      callLog.add('DELETE foldergroups/$remoteId');
      if (onDeleteGroup != null) await onDeleteGroup!(remoteId);
      return unit;
    });
  }

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) {
    return guardApiCall(() async {
      callLog.add('GET taskfolders($deltaLink)');
      return onFetchFoldersDelta?.call(deltaLink) ??
          const DeltaPageResult(
            items: [
              RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
              ),
            ],
            deltaLink: 'dl-folders-1',
          );
    });
  }

  @override
  AsyncAppResult<RemoteTodoFolder> createFolder(
    SubstrateRequestContext ctx,
    Map<String, dynamic> payload,
  ) {
    return guardApiCall(() async {
      callLog.add('POST taskfolders ${payload['Name']}');
      if (onCreateFolder != null) return onCreateFolder!(payload);
      _idSeq += 1;
      return RemoteTodoFolder(
        id: 'rf-$_idSeq',
        name: payload['Name'] as String? ?? 'List',
      );
    });
  }

  @override
  AsyncAppResult<RemoteTodoFolder> patchFolder(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  ) {
    return guardApiCall(() async {
      callLog.add('PATCH taskfolders/$remoteId $patch');
      if (onPatchFolder != null) return onPatchFolder!(remoteId, patch);
      return RemoteTodoFolder(
        id: remoteId,
        name: patch['Name'] as String? ?? 'List',
        parentFolderGroupId: patch['ParentFolderGroupId'] as String?,
      );
    });
  }

  @override
  AsyncAppResult<Unit> deleteFolder(
    SubstrateRequestContext ctx,
    String remoteId,
  ) {
    return guardApiCall(() async {
      callLog.add('DELETE taskfolders/$remoteId');
      if (onDeleteFolder != null) await onDeleteFolder!(remoteId);
      return unit;
    });
  }

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  }) {
    return guardApiCall(() async {
      callLog.add('GET tasks($folderRemoteId,$deltaLink)');
      return onFetchTasksDelta?.call(folderRemoteId, deltaLink) ??
          DeltaPageResult(
            items: const [],
            deltaLink: 'dl-tasks-$folderRemoteId',
          );
    });
  }

  @override
  AsyncAppResult<RemoteTodoTask> getTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  ) {
    return guardApiCall(() async {
      callLog.add('GET tasks/$taskRemoteId');
      if (onGetTask != null) return onGetTask!(taskRemoteId);
      return RemoteTodoTask(
        id: taskRemoteId,
        subject: 'Task',
        changeKey: 'ck-new',
      );
    });
  }

  @override
  AsyncAppResult<RemoteTodoTask> createTask(
    SubstrateRequestContext ctx,
    String folderRemoteId,
    Map<String, dynamic> payload,
  ) {
    return guardApiCall(() async {
      callLog.add(
        'POST taskfolders/$folderRemoteId/tasks ${payload['Subject']}',
      );
      if (onCreateTask != null) return onCreateTask!(folderRemoteId, payload);
      _idSeq += 1;
      return RemoteTodoTask(
        id: 'rt-$_idSeq',
        changeKey: 'ck-$_idSeq',
        parentFolderId: folderRemoteId,
        subject: payload['Subject'] as String? ?? 'Task',
      );
    });
  }

  @override
  AsyncAppResult<RemoteTodoTask> patchTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  }) {
    return guardApiCall(() async {
      callLog.add('PATCH tasks/$taskRemoteId(ifMatch=$changeKey)');
      if (onPatchTask != null) {
        return onPatchTask!(taskRemoteId, patch, changeKey);
      }
      return RemoteTodoTask(
        id: taskRemoteId,
        changeKey: 'ck-updated',
        subject: patch['Subject'] as String? ?? 'Task',
      );
    });
  }

  @override
  AsyncAppResult<Unit> deleteTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  ) {
    return guardApiCall(() async {
      callLog.add('DELETE tasks/$taskRemoteId');
      if (onDeleteTask != null) await onDeleteTask!(taskRemoteId);
      return unit;
    });
  }

  @override
  AsyncAppResult<RemoteTaskStep> createStep(
    SubstrateRequestContext ctx,
    String taskRemoteId, {
    required String subject,
    required DateTime orderDateTime,
  }) {
    return guardApiCall(() async {
      callLog.add('POST tasks/$taskRemoteId/subtasks $subject');
      if (onCreateStep != null) {
        return onCreateStep!(taskRemoteId, subject, orderDateTime);
      }
      _idSeq += 1;
      return RemoteTaskStep(
        id: 'rs-$_idSeq',
        subject: subject,
        orderDateTime: orderDateTime,
      );
    });
  }

  @override
  AsyncAppResult<RemoteTaskStep> patchStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  ) {
    return guardApiCall(() async {
      callLog.add('PATCH tasks/$taskRemoteId/subtasks/$stepRemoteId');
      if (onPatchStep != null) {
        return onPatchStep!(taskRemoteId, stepRemoteId, patch);
      }
      return RemoteTaskStep(id: stepRemoteId, subject: 'Step');
    });
  }

  @override
  AsyncAppResult<Unit> deleteStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
  ) {
    return guardApiCall(() async {
      callLog.add('DELETE tasks/$taskRemoteId/subtasks/$stepRemoteId');
      if (onDeleteStep != null) await onDeleteStep!(taskRemoteId, stepRemoteId);
      return unit;
    });
  }

  @override
  AsyncAppResult<RemoteFileUpload> uploadAttachment(
    SubstrateRequestContext ctx,
    String taskRemoteId, {
    required String fileName,
    required List<int> bytes,
    String? contentType,
  }) {
    return guardApiCall(() async {
      callLog.add('POST tasks/$taskRemoteId/attachments ($fileName)');
      if (onUploadAttachment != null) {
        return onUploadAttachment!(taskRemoteId, fileName, bytes, contentType);
      }
      return RemoteFileUpload(
        id: 'remote-att-${callLog.length}',
        size: bytes.length,
        contentType: contentType ?? 'application/octet-stream',
        lastModifiedDateTime: DateTime.now().toUtc(),
      );
    });
  }

  @override
  AsyncAppResult<Uint8List> downloadAttachment(
    SubstrateRequestContext ctx,
    String webLink,
  ) {
    return guardApiCall(() async {
      callLog.add('GET $webLink');
      if (onDownloadAttachment != null) {
        return onDownloadAttachment!(webLink);
      }
      return Uint8List(0);
    });
  }

  @override
  AsyncAppResult<Unit> deleteLinkedEntity(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String entityRemoteId,
  ) {
    return guardApiCall(() async {
      callLog.add('DELETE tasks/$taskRemoteId/linkedentities/$entityRemoteId');
      if (onDeleteLinkedEntity != null) {
        await onDeleteLinkedEntity!(taskRemoteId, entityRemoteId);
      }
      return unit;
    });
  }

  @override
  Stream<RealtimeEvent> connectRealtime(SubstrateRequestContext ctx) {
    callLog.add('GET realtime');
    return realtimeController.stream;
  }
}

class BlockingFoldersApi extends FakeSubstrateApi {
  BlockingFoldersApi(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;
  int folderFetchCount = 0;

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) async {
    folderFetchCount += 1;
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.fetchFoldersDelta(ctx, deltaLink: deltaLink);
  }
}

class BlockingTasksDeltaApi extends FakeSubstrateApi {
  BlockingTasksDeltaApi(this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.fetchTasksDelta(
      ctx,
      folderRemoteId: folderRemoteId,
      deltaLink: deltaLink,
    );
  }
}

class SeededSyncSession {
  const SeededSyncSession({
    required this.prefs,
    required this.account,
    required this.repository,
    required this.settings,
  });

  final SharedPreferences prefs;
  final MicrosoftAccount account;
  final TodoRepository repository;
  final TodoSettingsStore settings;
}

class SyncTestHarness {
  const SyncTestHarness({
    required this.prefs,
    required this.account,
    required this.repository,
    required this.settings,
    required this.api,
    required this.authClient,
    required this.container,
  });

  final SharedPreferences prefs;
  final MicrosoftAccount account;
  final TodoRepository repository;
  final TodoSettingsStore settings;
  final FakeSubstrateApi api;
  final FakeAuthClient authClient;
  final ProviderContainer container;
}

Future<SeededSyncSession> seedMicrosoftSyncSession({
  SharedPreferences? prefs,
  String accountId = 'acct_1',
  String displayName = 'Alice',
  String email = 'alice@outlook.com',
  String microsoftUserId = 'cid1',
  DateTime? lastSyncedAt,
  bool saveTokens = true,
  MicrosoftAuthTokens? tokens,
  String? defaultTasksFolderRemoteId,
  List<TodoList>? lists,
  List<TodoList> extraLists = const [],
  List<ListGroup> groups = const [],
  List<TaskItem> tasks = const [],
  String? groupsDeltaLink,
  String? foldersDeltaLink,
  Map<String, String>? taskDeltaLinks,
  Set<String>? dirtyListIds,
  Set<String>? dirtyTaskIds,
  List<String>? pendingDeletedTaskRemoteIds,
}) async {
  late final SharedPreferences resolvedPrefs;
  if (prefs != null) {
    resolvedPrefs = prefs;
  } else {
    SharedPreferences.setMockInitialValues({});
    resolvedPrefs = await SharedPreferences.getInstance();
  }

  final account = MicrosoftAccount(
    id: accountId,
    displayName: displayName,
    email: email,
    createdAt: DateTime(2026, 11, 22),
    lastSyncedAt: lastSyncedAt,
    microsoftUserId: microsoftUserId,
  );
  await AccountLocalStorage(resolvedPrefs).saveAccounts([account]);
  await AccountLocalStorage(resolvedPrefs).saveActiveAccountId(accountId);

  if (saveTokens) {
    await AuthTokenStorage(resolvedPrefs).saveTokens(
      accountId,
      tokens ??
          MicrosoftAuthTokens(
            accessToken: 'tok-1',
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            userId: microsoftUserId,
          ),
    );
  }

  final settings = TodoSettingsStore(resolvedPrefs, accountId: accountId);
  final repository = TodoRepository.forSession(
    sharedFallbackTodoDatabase,
    settings,
  );

  if (groups.isNotEmpty) {
    await repository.saveGroups(groups);
  }
  if (lists != null) {
    await repository.saveLists(lists);
  } else if (defaultTasksFolderRemoteId != null || extraLists.isNotEmpty) {
    await repository.saveLists([
      ...defaultSmartLists().map(
        (l) =>
            defaultTasksFolderRemoteId != null &&
                l.smartType == SmartListType.tasks
            ? l.copyWith(remoteId: defaultTasksFolderRemoteId)
            : l,
      ),
      ...extraLists,
    ]);
  }
  if (tasks.isNotEmpty) {
    await repository.saveTasks(tasks);
  }
  if (groupsDeltaLink != null) {
    await repository.saveGroupsDeltaLink(groupsDeltaLink);
  }
  if (foldersDeltaLink != null) {
    await repository.saveFoldersDeltaLink(foldersDeltaLink);
  }
  if (taskDeltaLinks != null) {
    await repository.saveTaskDeltaLinks(taskDeltaLinks);
  }
  if (dirtyListIds != null) {
    for (final id in dirtyListIds) {
      repository.outbox.enqueueUpsert(
        entityType: SyncEntityType.list,
        localId: id,
      );
    }
  }
  if (dirtyTaskIds != null) {
    for (final id in dirtyTaskIds) {
      repository.outbox.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: id,
      );
    }
  }
  if (pendingDeletedTaskRemoteIds != null) {
    for (final remoteId in pendingDeletedTaskRemoteIds) {
      repository.outbox.enqueueDelete(
        entityType: SyncEntityType.task,
        localId: 'deleted_$remoteId',
        remoteId: remoteId,
      );
    }
  }
  await repository.saveOutbox();

  return SeededSyncSession(
    prefs: resolvedPrefs,
    account: account,
    repository: repository,
    settings: settings,
  );
}

Future<SyncTestHarness> createSyncTestHarness({
  SharedPreferences? prefs,
  String accountId = 'acct_1',
  String displayName = 'Alice',
  String email = 'alice@outlook.com',
  String microsoftUserId = 'cid1',
  DateTime? lastSyncedAt,
  bool saveTokens = true,
  MicrosoftAuthTokens? tokens,
  String? defaultTasksFolderRemoteId,
  List<TodoList>? lists,
  List<TodoList> extraLists = const [],
  List<ListGroup> groups = const [],
  List<TaskItem> tasks = const [],
  String? groupsDeltaLink,
  String? foldersDeltaLink,
  Map<String, String>? taskDeltaLinks,
  Set<String>? dirtyListIds,
  Set<String>? dirtyTaskIds,
  List<String>? pendingDeletedTaskRemoteIds,
  FakeSubstrateApi? api,
  FakeAuthClient? authClient,
  bool realtimeSyncEnabled = false,
  bool periodicSyncEnabled = false,
  bool startupSyncEnabled = false,
  List<Override> extraOverrides = const [],
}) async {
  final session = await seedMicrosoftSyncSession(
    prefs: prefs,
    accountId: accountId,
    displayName: displayName,
    email: email,
    microsoftUserId: microsoftUserId,
    lastSyncedAt: lastSyncedAt,
    saveTokens: saveTokens,
    tokens: tokens,
    defaultTasksFolderRemoteId: defaultTasksFolderRemoteId,
    lists: lists,
    extraLists: extraLists,
    groups: groups,
    tasks: tasks,
    groupsDeltaLink: groupsDeltaLink,
    foldersDeltaLink: foldersDeltaLink,
    taskDeltaLinks: taskDeltaLinks,
    dirtyListIds: dirtyListIds,
    dirtyTaskIds: dirtyTaskIds,
    pendingDeletedTaskRemoteIds: pendingDeletedTaskRemoteIds,
  );
  final effectiveApi = api ?? FakeSubstrateApi();
  final effectiveAuth = authClient ?? FakeAuthClient();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(session.prefs),
      microsoftAuthClientProvider.overrideWithValue(effectiveAuth),
      microsoftTodoApiProvider.overrideWithValue(effectiveApi),
      realtimeSyncEnabledProvider.overrideWithValue(realtimeSyncEnabled),
      periodicSyncEnabledProvider.overrideWithValue(periodicSyncEnabled),
      startupSyncEnabledProvider.overrideWithValue(startupSyncEnabled),
      ...extraOverrides,
    ],
  );
  addTearDown(() async {
    container.dispose();
    await effectiveApi.realtimeController.close();
  });

  return SyncTestHarness(
    prefs: session.prefs,
    account: session.account,
    repository: session.repository,
    settings: session.settings,
    api: effectiveApi,
    authClient: effectiveAuth,
    container: container,
  );
}
