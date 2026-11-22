import 'dart:async';

import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/auth/msa_webview_launcher.dart';
import 'package:yata/sync/microsoft_todo_api.dart';

class FakeInteractiveMsaClient implements MsaInteractiveSignInClient {
  FakeInteractiveMsaClient(this.result);

  final MsaInteractiveSignInResult? result;
  String? lastAuthorizeUrl;

  @override
  Future<MsaInteractiveSignInResult?> signIn({
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
  String? extractAuthorizationCode(String rawInput) =>
      HttpMicrosoftAuthClient().extractAuthorizationCode(rawInput);

  @override
  Future<MicrosoftAuthTokens> exchangeAuthorizationCode({
    required String code,
    String? uaid,
  }) async {
    return MicrosoftAuthTokens(
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      userId: 'cid12345',
    );
  }

  @override
  Future<MicrosoftAuthTokens> refreshTokens({
    required String refreshToken,
    String? scope,
    String? fallbackUserId,
    String? uaid,
  }) async {
    if (onRefreshTokens != null) {
      return onRefreshTokens!(refreshToken);
    }
    return MicrosoftAuthTokens(
      accessToken: 'refreshed-access',
      refreshToken: 'refreshed-rt',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      userId: fallbackUserId ?? 'cid12345',
    );
  }

  @override
  Future<MicrosoftSignInResult> completeSignInWithCode({
    required String code,
    String? loginHint,
    String? uaid,
  }) async {
    final tokens = await exchangeAuthorizationCode(code: code, uaid: uaid);
    return MicrosoftSignInResult(
      profile: MicrosoftUserProfile(
        id: tokens.userId,
        displayName: 'Alice Lee',
        email: loginHint ?? 'alice@outlook.com',
      ),
      tokens: tokens,
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
  Future<MicrosoftAuthTokens> ensureValidTokens({
    required String accountId,
    required AuthTokenStorage storage,
    String? fallbackCid,
  }) async {
    final stored = await storage.loadTokens(accountId);
    if (stored == null) {
      throw const MicrosoftAuthException('Not signed in', requiresReauth: true);
    }
    if (!stored.isExpired && stored.accessToken.isNotEmpty) {
      return stored;
    }
    final refreshed = await refreshTokens(
      refreshToken: stored.refreshToken,
      fallbackUserId: stored.userId.isNotEmpty ? stored.userId : fallbackCid,
    );
    await storage.saveTokens(accountId, refreshed);
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

  int _idSeq = 0;

  @override
  bool isOwnRequestId(String? requestId) =>
      requestId != null && ownRequestIds.contains(requestId);

  @override
  Future<Map<String, String>> getSettings(SubstrateRequestContext ctx) async {
    callLog.add('GET settings');
    return Map<String, String>.from(remoteSettings);
  }

  @override
  Future<void> patchSetting(
    SubstrateRequestContext ctx,
    String key,
    String value,
  ) async {
    callLog.add('PATCH settings/$key=$value');
    remoteSettings[key] = value;
  }

  @override
  Future<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) async {
    callLog.add('GET foldergroups($deltaLink)');
    return onFetchGroupsDelta?.call(deltaLink) ??
        const DeltaPageResult(items: [], deltaLink: 'dl-groups-1');
  }

  @override
  Future<RemoteFolderGroup> createFolderGroup(
    SubstrateRequestContext ctx, {
    required String name,
    required DateTime orderDateTime,
  }) async {
    callLog.add('POST foldergroups $name');
    if (onCreateGroup != null) return onCreateGroup!(name, orderDateTime);
    _idSeq += 1;
    return RemoteFolderGroup(
      id: 'rg-$_idSeq',
      name: name,
      orderDateTime: orderDateTime,
    );
  }

  @override
  Future<RemoteFolderGroup> patchFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  ) async {
    callLog.add('PATCH foldergroups/$remoteId');
    if (onPatchGroup != null) return onPatchGroup!(remoteId, patch);
    return RemoteFolderGroup(
      id: remoteId,
      name: patch['Name'] as String? ?? 'Group',
      orderDateTime: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> deleteFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
  ) async {
    callLog.add('DELETE foldergroups/$remoteId');
    if (onDeleteGroup != null) await onDeleteGroup!(remoteId);
  }

  @override
  Future<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) async {
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
  }

  @override
  Future<RemoteTodoFolder> createFolder(
    SubstrateRequestContext ctx,
    Map<String, dynamic> payload,
  ) async {
    callLog.add('POST taskfolders ${payload['Name']}');
    if (onCreateFolder != null) return onCreateFolder!(payload);
    _idSeq += 1;
    return RemoteTodoFolder(
      id: 'rf-$_idSeq',
      name: payload['Name'] as String? ?? 'List',
    );
  }

  @override
  Future<RemoteTodoFolder> patchFolder(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  ) async {
    callLog.add('PATCH taskfolders/$remoteId $patch');
    if (onPatchFolder != null) return onPatchFolder!(remoteId, patch);
    return RemoteTodoFolder(
      id: remoteId,
      name: patch['Name'] as String? ?? 'List',
      parentFolderGroupId: patch['ParentFolderGroupId'] as String?,
    );
  }

  @override
  Future<void> deleteFolder(
    SubstrateRequestContext ctx,
    String remoteId,
  ) async {
    callLog.add('DELETE taskfolders/$remoteId');
    if (onDeleteFolder != null) await onDeleteFolder!(remoteId);
  }

  @override
  Future<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  }) async {
    callLog.add('GET tasks($folderRemoteId,$deltaLink)');
    return onFetchTasksDelta?.call(folderRemoteId, deltaLink) ??
        DeltaPageResult(items: const [], deltaLink: 'dl-tasks-$folderRemoteId');
  }

  @override
  Future<RemoteTodoTask> getTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  ) async {
    callLog.add('GET tasks/$taskRemoteId');
    if (onGetTask != null) return onGetTask!(taskRemoteId);
    return RemoteTodoTask(
      id: taskRemoteId,
      subject: 'Task',
      changeKey: 'ck-new',
    );
  }

  @override
  Future<RemoteTodoTask> createTask(
    SubstrateRequestContext ctx,
    String folderRemoteId,
    Map<String, dynamic> payload,
  ) async {
    callLog.add('POST taskfolders/$folderRemoteId/tasks ${payload['Subject']}');
    if (onCreateTask != null) return onCreateTask!(folderRemoteId, payload);
    _idSeq += 1;
    return RemoteTodoTask(
      id: 'rt-$_idSeq',
      changeKey: 'ck-$_idSeq',
      parentFolderId: folderRemoteId,
      subject: payload['Subject'] as String? ?? 'Task',
    );
  }

  @override
  Future<RemoteTodoTask> patchTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  }) async {
    callLog.add('PATCH tasks/$taskRemoteId(ifMatch=$changeKey)');
    if (onPatchTask != null) {
      return onPatchTask!(taskRemoteId, patch, changeKey);
    }
    return RemoteTodoTask(
      id: taskRemoteId,
      changeKey: 'ck-updated',
      subject: patch['Subject'] as String? ?? 'Task',
    );
  }

  @override
  Future<void> deleteTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  ) async {
    callLog.add('DELETE tasks/$taskRemoteId');
    if (onDeleteTask != null) await onDeleteTask!(taskRemoteId);
  }

  @override
  Future<RemoteTaskStep> createStep(
    SubstrateRequestContext ctx,
    String taskRemoteId, {
    required String subject,
    required DateTime orderDateTime,
  }) async {
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
  }

  @override
  Future<RemoteTaskStep> patchStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  ) async {
    callLog.add('PATCH tasks/$taskRemoteId/subtasks/$stepRemoteId');
    if (onPatchStep != null) {
      return onPatchStep!(taskRemoteId, stepRemoteId, patch);
    }
    return RemoteTaskStep(id: stepRemoteId, subject: 'Step');
  }

  @override
  Future<void> deleteStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
  ) async {
    callLog.add('DELETE tasks/$taskRemoteId/subtasks/$stepRemoteId');
    if (onDeleteStep != null) await onDeleteStep!(taskRemoteId, stepRemoteId);
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
  Future<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
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
