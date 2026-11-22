import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_local_storage.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/auth/msa_webview_launcher.dart';
import 'package:yata/data/todo_local_storage.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/homeview/home_view_ordering.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/main.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/onboarding/landing_screen.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/sync/cloud_sync_service.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/sync/todo_wire_codecs.dart';
import 'package:yata/tasksview/tasks_action_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

class _FakeInteractiveMsaClient implements MsaInteractiveSignInClient {
  _FakeInteractiveMsaClient(this.result);

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

class _FakeAuthClient implements MicrosoftAuthClient {
  _FakeAuthClient({
    this.onRefreshTokens,
    this.onFetchUserProfile,
  });

  final Future<MicrosoftAuthTokens> Function(String refreshToken)?
      onRefreshTokens;
  final Future<MicrosoftUserProfile> Function(
    String cid,
    String refreshToken,
    String? fallbackEmail,
  )? onFetchUserProfile;
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
      throw const MicrosoftAuthException(
        'Not signed in',
        requiresReauth: true,
      );
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

class _FakeSubstrateApi implements MicrosoftTodoApi {
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
  )? onFetchTasksDelta;

  Future<RemoteFolderGroup> Function(String name, DateTime order)?
      onCreateGroup;
  Future<RemoteFolderGroup> Function(
    String remoteId,
    Map<String, dynamic> patch,
  )? onPatchGroup;
  Future<void> Function(String remoteId)? onDeleteGroup;

  Future<RemoteTodoFolder> Function(Map<String, dynamic> payload)? onCreateFolder;
  Future<RemoteTodoFolder> Function(
    String remoteId,
    Map<String, dynamic> patch,
  )? onPatchFolder;
  Future<void> Function(String remoteId)? onDeleteFolder;

  Future<RemoteTodoTask> Function(
    String folderRemoteId,
    Map<String, dynamic> payload,
  )? onCreateTask;
  Future<RemoteTodoTask> Function(
    String taskRemoteId,
    Map<String, dynamic> patch,
    String? changeKey,
  )? onPatchTask;
  Future<RemoteTodoTask> Function(String taskRemoteId)? onGetTask;
  Future<void> Function(String taskRemoteId)? onDeleteTask;

  Future<RemoteTaskStep> Function(
    String taskRemoteId,
    String subject,
    DateTime order,
  )? onCreateStep;
  Future<RemoteTaskStep> Function(
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  )? onPatchStep;
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
    return RemoteTodoTask(id: taskRemoteId, subject: 'Task', changeKey: 'ck-new');
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
    if (onPatchTask != null) return onPatchTask!(taskRemoteId, patch, changeKey);
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HttpMicrosoftAuthClient', () {
    test('builds MSA authorize URL and extracts code from redirect or raw code',
        () {
      final client = HttpMicrosoftAuthClient();
      final url = Uri.parse(
        client.buildAuthorizeUrl(
          loginHint: 'user@outlook.com',
          uaid: 'uaid-fixed',
        ),
      );
      expect(url.host, 'login.live.com');
      expect(url.path, '/oauth20_authorize.srf');
      expect(url.queryParameters['client_id'], '000000004C18365E');
      expect(url.queryParameters['state'], 'ProjectCheshire');
      expect(url.queryParameters['redirect_uri'], MsaAuthConfig.redirectUri);
      expect(url.queryParameters['uaid'], 'uaid-fixed');
      expect(url.queryParameters['username'], 'user@outlook.com');

      expect(
        client.extractAuthorizationCode(
          'https://login.live.com/oauth20_desktop.srf?code=M.C509_ABC&state=ProjectCheshire&lc=1033',
        ),
        'M.C509_ABC',
      );
      expect(client.extractAuthorizationCode('M.RAW_CODE'), 'M.RAW_CODE');
      expect(
        () => client.extractAuthorizationCode(
          'https://login.live.com/oauth20_desktop.srf?code=X&state=WrongState',
        ),
        throwsA(isA<MicrosoftAuthException>()),
      );
      expect(
        () => client.extractAuthorizationCode(
          'https://login.live.com/oauth20_desktop.srf?error=access_denied&error_description=User+cancelled',
        ),
        throwsA(isA<MicrosoftAuthException>()),
      );
    });

    test(
        'exchanges code, fetches primary Graph /beta/me profile+photo, and discovers endpoint',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == MsaAuthConfig.tokenEndpoint) {
          final form = Uri.splitQueryString(request.body);
          if (form['grant_type'] == 'authorization_code') {
            expect(form['client_id'], MsaAuthConfig.clientId);
            expect(form['client_secret'], MsaAuthConfig.clientSecret);
            expect(form['code'], 'code-1');
            expect(form.containsKey('scope'), isFalse);
            expect(form['uaid'], 'uaid-1');
            return http.Response(
              jsonEncode({
                'access_token': 'todo-access',
                'refresh_token': 'rt-1',
                'user_id': 'abcdef123456',
                'expires_in': 3600,
              }),
              200,
            );
          }
          expect(form['grant_type'], 'refresh_token');
          expect(form['scope'], MsaAuthConfig.graphProfileScope);
          return http.Response(
            jsonEncode({
              'access_token': 'graph-access',
              'refresh_token': 'rt-graph-2',
              'user_id': 'abcdef123456',
              'expires_in': 3600,
            }),
            200,
          );
        }
        if (request.url.toString() == MsaAuthConfig.graphMeBetaEndpoint) {
          expect(request.headers['Authorization'], 'Bearer graph-access');
          expect(request.headers['X-AnchorMailbox'], 'CID:abcdef123456');
          return http.Response(
            jsonEncode({
              'displayName': 'Alice Lee',
              'givenName': 'Alice',
              'surname': 'Lee',
              'mail': 'alice@outlook.com',
            }),
            200,
          );
        }
        if (request.url.toString() == MsaAuthConfig.graphPhotoBetaEndpoint) {
          expect(request.headers['Authorization'], 'Bearer graph-access');
          return http.Response.bytes(
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        if (request.url.host == 'outlook.office365.com') {
          expect(request.url.path, contains('CID:abcdef123456'));
          expect(request.url.queryParameters['Protocol'], 'todo');
          return http.Response(
            jsonEncode({
              'Protocol': 'todo',
              'Url': 'https://eur.substrate.office.com/todob2',
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final client = HttpMicrosoftAuthClient(httpClient: mockClient);
      final signIn = await client.completeSignInWithCode(
        code: 'code-1',
        uaid: 'uaid-1',
      );
      expect(signIn.profile.id, 'abcdef123456');
      expect(signIn.profile.displayName, 'Alice Lee');
      expect(signIn.profile.email, 'alice@outlook.com');
      expect(signIn.profile.avatarBase64, base64Encode([0xFF, 0xD8, 0xFF, 0xE0]));
      expect(signIn.tokens.accessToken, 'todo-access');
      expect(signIn.tokens.refreshToken, 'rt-graph-2');

      final endpoint = await client.discoverTodoEndpoint('abcdef123456');
      expect(endpoint, 'https://eur.substrate.office.com/todob2/api/v1/');
    });

    test(
        'falls back to Substrate /profile/v1.0/me/profile and storage.live PNG octet-stream avatar when Graph fails',
        () async {
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      final mockClient = MockClient((request) async {
        if (request.url.toString() == MsaAuthConfig.tokenEndpoint) {
          final form = Uri.splitQueryString(request.body);
          if (form['grant_type'] == 'authorization_code') {
            return http.Response(
              jsonEncode({
                'access_token': 'todo-access',
                'refresh_token': 'rt-1',
                'user_id': 'abcdef123456',
                'expires_in': 3600,
              }),
              200,
            );
          }
          if (form['scope'] == MsaAuthConfig.graphProfileScope) {
            return http.Response('{"error":"invalid_scope"}', 400);
          }
          if (form['scope'] == MsaAuthConfig.profileScope) {
            return http.Response(
              jsonEncode({
                'access_token': 'substrate-profile-access',
                'refresh_token': 'rt-sub-2',
                'user_id': 'abcdef123456',
                'expires_in': 3600,
              }),
              200,
            );
          }
        }
        if (request.url.toString() == MsaAuthConfig.profileEndpoint) {
          expect(request.headers['X-AnchorMailbox'], 'CID:abcdef123456');
          expect(
            request.headers['Authorization'],
            'Bearer substrate-profile-access',
          );
          return http.Response(
            jsonEncode({
              'accounts': [
                {'passportMemberName': 'alice@outlook.com', 'ageGroup': 5},
              ],
              'names': [
                {'givenName': 'Alice', 'lastName': 'Lee'},
              ],
            }),
            200,
          );
        }
        if (request.url.host == 'storage.live.com') {
          return http.Response.bytes(
            pngBytes,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }
        return http.Response('not found', 404);
      });

      final client = HttpMicrosoftAuthClient(httpClient: mockClient);
      final signIn = await client.completeSignInWithCode(code: 'code-fallback');
      expect(signIn.profile.id, 'abcdef123456');
      expect(signIn.profile.displayName, 'Alice Lee');
      expect(signIn.profile.email, 'alice@outlook.com');
      expect(signIn.profile.avatarBase64, base64Encode(pngBytes));
      expect(signIn.tokens.refreshToken, 'rt-sub-2');
    });

    test('treats profile fetch failure as non-fatal and falls back autodiscover',
        () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == MsaAuthConfig.tokenEndpoint) {
          final form = Uri.splitQueryString(request.body);
          if (form['grant_type'] == 'authorization_code') {
            return http.Response(
              jsonEncode({
                'access_token': 'todo-access',
                'refresh_token': 'rt-1',
                'user_id': 'cid999',
                'expires_in': 3600,
              }),
              200,
            );
          }
          return http.Response('{"error":"server_error"}', 500);
        }
        return http.Response('err', 500);
      });

      final client = HttpMicrosoftAuthClient(httpClient: mockClient);
      final signIn = await client.completeSignInWithCode(
        code: 'code-x',
        loginHint: 'bob@hotmail.com',
      );
      expect(signIn.profile.id, 'cid999');
      expect(signIn.profile.displayName, 'bob@hotmail.com');
      expect(signIn.profile.email, 'bob@hotmail.com');
      expect(
        await client.discoverTodoEndpoint('cid999'),
        MsaAuthConfig.defaultTodoApiBaseUrl,
      );
    });
  });

  group('LandingScreen MSA flows', () {
    testWidgets('completes sign-in via Android WebView interactive client',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final interactive = _FakeInteractiveMsaClient(
        const MsaInteractiveSignInResult.success(code: 'webview-code-1'),
      );
      final fakeAuth = _FakeAuthClient();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(fakeAuth),
          msaInteractiveSignInProvider.overrideWithValue(interactive),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LandingScreen(),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'alice@outlook.com');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(interactive.lastAuthorizeUrl, contains('client_id=000000004C18365E'));
      final active = container.read(accountProvider).activeAccount;
      expect(active, isA<MicrosoftAccount>());
      expect((active! as MicrosoftAccount).microsoftUserId, 'cid12345');
    });

    testWidgets('falls back to redirect-URL paste dialog on desktop',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final interactive = _FakeInteractiveMsaClient(null);
      final fakeAuth = _FakeAuthClient();
      final launchedUrls = <String>[];

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(fakeAuth),
          msaInteractiveSignInProvider.overrideWithValue(interactive),
          externalUrlLauncherProvider.overrideWithValue((url) async {
            launchedUrls.add(url);
            return true;
          }),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LandingScreen(),
          ),
        ),
      );

      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(launchedUrls.length, 1);
      expect(launchedUrls.single, contains('login.live.com/oauth20_authorize.srf'));
      expect(find.text('Sign in with Microsoft'), findsOneWidget);
      final dialogInput = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(
        dialogInput,
        'https://login.live.com/oauth20_desktop.srf?code=desktop-code&state=ProjectCheshire',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign in'),
        ),
      );
      await tester.pumpAndSettle();

      final active = container.read(accountProvider).activeAccount;
      expect(active, isA<MicrosoftAccount>());
    });
  });

  group('HttpMicrosoftTodoApi', () {
    test(
        'sends Substrate headers, follows NextLink to DeltaLink, retries 429, and classifies errors',
        () async {
      var pageCall = 0;
      var throttledCalls = 0;

      final mockClient = MockClient((request) async {
        expect(request.headers['X-AnchorMailbox'], 'CID:cid123');
        expect(request.headers['X-FlaggedListEnabled'], 'false');
        expect(request.headers['User-Agent'], contains('Microsoft To-Do'));
        expect(request.headers['X-Todo-Request-Id'], isNotEmpty);
        expect(request.headers['MS-CV'], isNotEmpty);

        if (request.url.path.endsWith('/foldergroups')) {
          pageCall += 1;
          if (pageCall == 1) {
            expect(request.headers['Prefer'], contains('odata.track-changes'));
            return http.Response(
              jsonEncode({
                'Values': [
                  {'Id': 'g1', 'Name': 'Group 1'},
                ],
                'NextLink':
                    'https://substrate.office.com/todob2/api/v1/foldergroups?page=2',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 'g2', 'Name': 'Group 2'},
              ],
              'DeltaLink':
                  'https://substrate.office.com/todob2/api/v1/foldergroups?deltatoken=g-dt',
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/settings')) {
          throttledCalls += 1;
          if (throttledCalls == 1) {
            return http.Response(
              '{"error":{"code":"TooManyRequests","message":"slow down"}}',
              429,
              headers: {'Retry-After': '1'},
            );
          }
          return http.Response(
            jsonEncode({
              'Value': [
                {'Key': 'ConfirmOnDelete', 'Value': 'false'},
              ],
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/tasks/t1') &&
            request.method == 'PATCH') {
          expect(request.headers['If-Match'], 'ck-1');
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'ErrorIrresolvableConflict',
                'message': 'conflict',
              },
            }),
            409,
          );
        }

        if (request.url.path.endsWith('/tasks/t412') &&
            request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'PreconditionFailed',
                'message': 'precondition failed',
              },
            }),
            412,
          );
        }

        if (request.url.path.contains('tasks') &&
            request.url.queryParameters['deltatoken'] == 'expired') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'SyncStateInvalid', 'message': 'expired'},
            }),
            410,
          );
        }

        return http.Response('{}', 200);
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'CID:cid123',
      );

      final groups = await api.fetchFolderGroupsDelta(ctx);
      expect(groups.items.length, 2);
      expect(groups.items.first.name, 'Group 1');
      expect(groups.items.last.name, 'Group 2');
      expect(groups.deltaLink, contains('deltatoken=g-dt'));

      final settings = await api.getSettings(ctx);
      expect(settings['ConfirmOnDelete'], 'false');
      expect(throttledCalls, 2);

      await expectLater(
        () => api.patchTask(
          ctx,
          't1',
          const {'Subject': 'x'},
          changeKey: 'ck-1',
        ),
        throwsA(predicate<SyncApiException>((e) => e.isConflict)),
      );

      await expectLater(
        () => api.patchTask(
          ctx,
          't412',
          const {'Subject': 'x'},
          changeKey: 'ck-stale',
        ),
        throwsA(predicate<SyncApiException>((e) => e.isConflict)),
      );

      await expectLater(
        () => api.fetchTasksDelta(
          ctx,
          folderRemoteId: 'f1',
          deltaLink:
              'https://substrate.office.com/todob2/api/v1/tasks?deltatoken=expired',
        ),
        throwsA(predicate<SyncApiException>((e) => e.isDeltaExpired)),
      );
    });

    test('parses NDJSON realtime events and tracks own request IDs', () async {
      String? capturedReqId;
      final mockClient = MockClient.streaming((request, _) async {
        expect(request.headers['Long-Polling'], 'true');
        expect(request.headers['Accept-Encoding'], 'identity');
        capturedReqId = request.headers['X-Todo-Request-Id'];
        final body = [
          '{"Type":"KeepAlive"}',
          '',
          'not-json',
          '{"Id":"t1","Type":"Task","Operation":"Updated","RequestId":"other-req"}',
          '{"Id":"t2","Type":"Task","Operation":"Created","RequestId":"$capturedReqId"}',
        ].join('\n');
        return http.StreamedResponse(
          Stream.value(utf8.encode(body)),
          200,
        );
      });

      final api = HttpMicrosoftTodoApi(httpClient: mockClient);
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );
      final events = await api.connectRealtime(ctx).toList();
      expect(events.length, 3);
      expect(events[0].isKeepAlive, isTrue);
      expect(events[1].id, 't1');
      expect(api.isOwnRequestId(events[1].requestId), isFalse);
      expect(events[2].id, 't2');
      expect(api.isOwnRequestId(events[2].requestId), isTrue);
    });
  });

  group('CloudSyncService & SyncNotifier end-to-end', () {
    test('pulls remote groups, emoji/theme folders, tasks, HTML notes, MyDay, recurrence, settings and deletes via delta',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = TodoLocalStorage(prefs, accountId: 'acct_1');
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );

      final fakeApi = _FakeSubstrateApi();
      fakeApi.remoteSettings.addAll({
        TodoSettingKeys.confirmOnDelete: 'false',
        TodoSettingKeys.smartListPlannedDueDateFilter: '1', // today
        TodoSettingKeys.smartListPlannedGroupType: '2', // byList
        TodoSettingKeys.myDayThemeColor: 'photo_tv_tower',
        TodoSettingKeys.smartListStarredSortType: '6', // importance
        TodoSettingKeys.smartListStarredSortAscending: 'false',
      });

      var folderDeltaStep = 0;
      fakeApi.onFetchGroupsDelta = (dl) => DeltaPageResult(
            items: [
              RemoteFolderGroup(
                id: 'rg-work',
                name: 'Work Group',
                orderDateTime: DateTime.utc(2026, 11, 22, 10),
              ),
            ],
            deltaLink: 'dl-groups-v1',
          );
      fakeApi.onFetchFoldersDelta = (dl) {
        folderDeltaStep += 1;
        if (folderDeltaStep == 1) {
          return DeltaPageResult(
            items: [
              const RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
                themeColor: 'light_purple',
              ),
              const RemoteTodoFolder(
                id: 'rf-flagged',
                name: 'Flagged Emails',
                folderType: 'com.microsoft.outlook.email.flagged',
              ),
              const RemoteTodoFolder(
                id: 'rf-planner',
                name: 'Assigned to me',
                folderType: 'com.microsoft.planner',
              ),
              RemoteTodoFolder(
                id: 'rf-shop',
                name: '🛒 Groceries',
                parentFolderGroupId: 'rg-work',
                themeColor: 'light_teal',
                themeBackground: 'photo_beach',
                showCompletedTasks: false,
                sortOption: TaskSortOption.dueDate,
                sortAscending: true,
                orderDateTime: DateTime.utc(2026, 11, 22, 9),
              ),
            ],
            deltaLink: 'dl-folders-v1',
          );
        }
        return const DeltaPageResult(
          items: [
            RemoteTodoFolder(id: 'rf-shop', name: '', isDeleted: true),
          ],
          deltaLink: 'dl-folders-v2',
        );
      };

      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-shop') {
          final today = DateTime.now();
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-milk',
                'ChangeKey': 'ck-milk-1',
                'ParentFolderId': 'rf-shop',
                'Subject': 'Buy milk',
                'Body': {
                  'Content': '<p>Organic<br/>2 cartons</p>',
                  'ContentType': 'HTML',
                },
                'DueDate': formatDayString(today),
                'CommittedDay': formatDayString(today),
                'CommittedOrder': '2026-11-22T12:00:00.0000000Z',
                'Importance': 'High',
                'Status': 'NotStarted',
                'Recurrence': {
                  'RecurrenceType': 'WeekDays',
                  'IntervalType': 'Weeks',
                  'Interval': 1,
                  'WeekDays': [
                    'Monday',
                    'Tuesday',
                    'Wednesday',
                    'Thursday',
                    'Friday',
                  ],
                },
                'Subtasks': [
                  {
                    'Id': 'rs-1',
                    'Subject': 'Check fridge',
                    'IsCompleted': true,
                  },
                ],
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-ignored',
                'ParentFolderId': 'rf-shop',
                'Subject': 'Hidden suggestion',
                'IsIgnored': true,
              }),
            ],
            deltaLink: 'dl-tasks-shop-1',
          );
        }
        return DeltaPageResult(items: const [], deltaLink: 'dl-tasks-$folderId');
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await container.read(accountLocalStorageProvider).saveAccounts([account]);
      await container
          .read(accountLocalStorageProvider)
          .saveActiveAccountId('acct_1');
      container.invalidate(accountProvider);

      // Sync #1: initial full sync
      await container.read(syncProvider.notifier).syncNow();

      var state = container.read(todoProvider);
      expect(state.confirmBeforeDeleting, isFalse);
      expect(state.plannedDueDateFilter, PlannedDueDateFilter.today);
      expect(state.plannedGroupOption, PlannedGroupOption.byList);

      final myDay = state.lists.firstWhere((l) => l.id == 'my_day');
      expect(myDay.themePhoto, ListThemePhoto.tvTower);
      final important = state.lists.firstWhere((l) => l.id == 'important');
      expect(important.sortOption, TaskSortOption.importance);
      expect(important.sortAscending, isFalse);

      expect(state.groups.length, 1);
      expect(state.groups.first.title, 'Work Group');

      // Special folders are ignored
      expect(
        state.lists.where((l) => l.remoteId == 'rf-flagged' || l.remoteId == 'rf-planner'),
        isEmpty,
      );

      final tasksDefault = state.lists.firstWhere((l) => l.id == 'tasks');
      expect(tasksDefault.remoteId, 'rf-default');
      expect(tasksDefault.themeColor, ListThemeColor.lightPurple);

      final shop = state.lists.firstWhere((l) => l.remoteId == 'rf-shop');
      expect(shop.emoji, '🛒');
      expect(shop.title, 'Groceries');
      expect(shop.groupId, state.groups.first.id);
      expect(shop.themeColor, ListThemeColor.lightTeal);
      expect(shop.themePhoto, ListThemePhoto.beach);
      expect(shop.showCompleted, isFalse);
      expect(state.isCompletedExpanded(shop.id), isFalse);
      expect(shop.sortOption, TaskSortOption.dueDate);

      expect(state.tasks.length, 1);
      final milk = state.tasks.first;
      expect(milk.title, 'Buy milk');
      expect(milk.note, 'Organic\n2 cartons');
      expect(milk.isImportant, isTrue);
      expect(milk.isInMyDay, isTrue);
      expect(milk.recurrence, RecurrenceType.weekdays);
      expect(milk.changeKey, 'ck-milk-1');
      expect(milk.steps.single.title, 'Check fridge');
      expect(milk.steps.single.isCompleted, isTrue);

      // Sync #2: Delta folder deletion removes 'rf-shop' using saved DeltaLink
      expect(storage.loadFoldersDeltaLink(), 'dl-folders-v1');
      await container.read(syncProvider.notifier).syncNow();
      expect(
        fakeApi.callLog,
        contains('GET taskfolders(dl-folders-v1)'),
      );
      state = container.read(todoProvider);
      expect(state.lists.where((l) => l.remoteId == 'rf-shop'), isEmpty);
      expect(state.tasks, isEmpty);
    });

    test('ungroups folders before deleting folder group (prevents 9018)',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final storage = TodoLocalStorage(prefs, accountId: 'acct_1');
      await storage.saveGroups(const [
        ListGroup(id: 'grp_1', title: 'Work', remoteId: 'rg-1'),
      ]);
      await storage.saveLists([
        ...TodoLocalStorage.defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
        const TodoList(
          id: 'list_1',
          title: 'Project',
          groupId: 'grp_1',
          remoteId: 'rf-1',
        ),
      ]);

      final fakeApi = _FakeSubstrateApi();
      final remoteFolders = {'rf-1': 'rg-1'};
      fakeApi.onPatchFolder = (id, patch) async {
        if (patch.containsKey('ParentFolderGroupId') &&
            patch['ParentFolderGroupId'] == null) {
          remoteFolders.remove(id);
        }
        return RemoteTodoFolder(id: id, name: 'Project');
      };
      fakeApi.onDeleteGroup = (groupId) async {
        if (remoteFolders.values.contains(groupId)) {
          throw const SyncApiException(
            statusCode: 400,
            errorCode: 'FolderGroupNotEmpty',
            message: 'Group not empty',
          );
        }
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Delete group locally: ungroups 'list_1' and queues 'rg-1' deletion.
      container.read(homeViewPresenterProvider).deleteGroup('grp_1');

      await container.read(syncProvider.notifier).syncNow();
      expect(container.read(syncProvider).status, SyncStatus.success);
      final patchIdx = fakeApi.callLog.indexWhere(
        (c) => c.startsWith('PATCH taskfolders/rf-1'),
      );
      final delIdx = fakeApi.callLog.indexOf('DELETE foldergroups/rg-1');
      expect(patchIdx, greaterThanOrEqualTo(0));
      expect(delIdx, greaterThan(patchIdx));
    });

    test('handles 409 If-Match conflict retry, 410 delta reset, and cross-folder move safety',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final storage = TodoLocalStorage(prefs, accountId: 'acct_1');
      await storage.saveLists([
        ...TodoLocalStorage.defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-a')
              : l,
        ),
        const TodoList(id: 'list_b', title: 'List B', remoteId: 'rf-b'),
      ]);
      await storage.saveTasks([
        TaskItem(
          id: 't_1',
          listId: 'tasks',
          title: 'Initial',
          createdAt: DateTime(2026, 11, 22),
          remoteId: 'rt-1',
          changeKey: 'ck-stale',
        ),
      ]);
      await storage.saveTaskDeltaLinks({'rf-a': 'dl-expired'});

      final fakeApi = _FakeSubstrateApi();
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
            items: [
              RemoteTodoFolder(
                id: 'rf-a',
                name: 'Tasks',
                isDefaultFolder: true,
              ),
              RemoteTodoFolder(id: 'rf-b', name: 'List B'),
            ],
            deltaLink: 'dl-folders-ab',
          );
      var patchAttempts = 0;
      fakeApi.onPatchTask = (id, patch, ck) async {
        patchAttempts += 1;
        if (ck == 'ck-stale') {
          throw const SyncApiException(
            statusCode: 409,
            errorCode: 'ErrorIrresolvableConflict',
            message: 'stale',
          );
        }
        expect(ck, 'ck-fresh');
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-v3',
          parentFolderId: 'rf-a',
          subject: patch['Subject'] as String? ?? 'Updated',
        );
      };
      fakeApi.onGetTask = (id) async => RemoteTodoTask(
            id: id,
            changeKey: 'ck-fresh',
            parentFolderId: 'rf-a',
            subject: 'Remote',
          );

      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-a' && dl == 'dl-expired') {
          throw const SyncApiException(
            statusCode: 410,
            errorCode: 'SyncStateInvalid',
            message: 'expired',
          );
        }
        if (folderId == 'rf-a') {
          // Cross-folder move: rt-1 deleted from Folder A while active in Folder B
          return const DeltaPageResult(
            items: [RemoteTodoTask(id: 'rt-1', subject: '', isDeleted: true)],
            deltaLink: 'dl-a-fresh',
          );
        }
        if (folderId == 'rf-b') {
          return const DeltaPageResult(
            items: [
              RemoteTodoTask(
                id: 'rt-1',
                changeKey: 'ck-v4',
                parentFolderId: 'rf-b',
                subject: 'Moved Cleanly',
              ),
            ],
            deltaLink: 'dl-b-fresh',
          );
        }
        return const DeltaPageResult(items: []);
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Modify task locally so PATCH triggers with stale ChangeKey
      container.read(todoProvider.notifier).commit(
            container.read(todoProvider).copyWith(
              tasks: [
                container
                    .read(todoProvider)
                    .tasks
                    .first
                    .copyWith(title: 'Local Edit'),
              ],
            ),
          );

      await container.read(syncProvider.notifier).syncNow();
      expect(patchAttempts, 2);
      expect(fakeApi.callLog, contains('GET tasks/rt-1'));
      // 410 recovered full sync
      expect(fakeApi.callLog, contains('GET tasks(rf-a,null)'));
      expect(storage.loadTaskDeltaLinks()['rf-a'], 'dl-a-fresh');

      // Moved task MUST survive and belong to 'list_b'
      final tasks = container.read(todoProvider).tasks;
      expect(tasks.length, 1);
      expect(tasks.first.listId, 'list_b');
      expect(tasks.first.title, 'Moved Cleanly');
    });

    test('preserves concurrent local edits made during in-flight sync and syncs reorder OrderDateTime',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final storage = TodoLocalStorage(prefs, accountId: 'acct_1');
      await storage.saveLists([
        ...TodoLocalStorage.defaultSmartLists().map(
          (l) => l.smartType == SmartListType.tasks
              ? l.copyWith(remoteId: 'rf-default')
              : l,
        ),
      ]);
      final tOld = DateTime.utc(2026, 11, 22, 10);
      final tNew = DateTime.utc(2026, 11, 22, 12);
      await storage.saveTasks([
        TaskItem(
          id: 't_1',
          listId: 'tasks',
          title: 'Task 1',
          createdAt: tOld,
          orderDateTime: tNew,
          remoteId: 'rt-1',
          changeKey: 'ck-1',
        ),
        TaskItem(
          id: 't_2',
          listId: 'tasks',
          title: 'Task 2',
          createdAt: tOld,
          orderDateTime: tOld,
          remoteId: 'rt-2',
          changeKey: 'ck-2',
        ),
      ]);

      final fakeApi = _FakeSubstrateApi();
      final patchStarted = Completer<void>();
      final allowPatchFinish = Completer<void>();
      Map<String, dynamic>? capturedOrderPatch;

      fakeApi.onPatchTask = (id, patch, ck) async {
        capturedOrderPatch = Map<String, dynamic>.from(patch);
        if (!patchStarted.isCompleted) patchStarted.complete();
        await allowPatchFinish.future;
        return RemoteTodoTask(
          id: id,
          changeKey: 'ck-patched',
          parentFolderId: 'rf-default',
          subject: patch['Subject'] as String? ?? 'Task 1',
          orderDateTime: patch['OrderDateTime'] != null
              ? parseSubstrateTimestamp(patch['OrderDateTime'] as String)
              : tOld,
        );
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      // Reorder t_1 below t_2
      container.read(todoProvider.notifier).selectList('tasks');
      final initialOrdered = container.read(todoProvider).tasksForList(
            container.read(todoProvider).selectedList,
          );
      expect(initialOrdered.first.id, 't_1');
      container
          .read(tasksViewPresenterProvider)
          .reorderActiveTasks(initialOrdered, 0, 1);

      final syncFuture = container.read(syncProvider.notifier).syncNow();
      await patchStarted.future;

      // Make concurrent local edit to t_1 while sync is in flight
      container.read(todoProvider.notifier).commit(
            container.read(todoProvider).copyWith(
              tasks: [
                for (final t in container.read(todoProvider).tasks)
                  if (t.id == 't_1')
                    t.copyWith(title: 'Edited Mid-Sync')
                  else
                    t,
              ],
            ),
          );

      allowPatchFinish.complete();
      await syncFuture;

      expect(capturedOrderPatch?['OrderDateTime'], isNotNull);
      final updatedT1 = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id == 't_1');
      expect(updatedT1.title, 'Edited Mid-Sync');
      expect(updatedT1.changeKey, 'ck-patched');
      expect(storage.loadDirtyTaskIds(), contains('t_1'));
    });

    test(
        'realtime ignores KeepAlive and own RequestId, triggers sync on remote event, and handles settings/copy/reorder',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final fakeApi = _FakeSubstrateApi();
      addTearDown(fakeApi.realtimeController.close);
      fakeApi.ownRequestIds.add('my-req-id');
      var taskFetches = 0;
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        taskFetches += 1;
        return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncProvider);
      await pumpEventQueue();
      expect(fakeApi.callLog, contains('GET realtime'));

      // Own request echo & KeepAlive must NOT trigger sync
      fakeApi.realtimeController.add(const RealtimeEvent(type: 'KeepAlive'));
      fakeApi.realtimeController.add(
        const RealtimeEvent(
          id: 't1',
          type: 'Task',
          operation: 'Updated',
          requestId: 'my-req-id',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(taskFetches, 0);

      // External remote event triggers debounced sync
      fakeApi.realtimeController.add(
        const RealtimeEvent(
          id: 't1',
          type: 'Task',
          operation: 'Created',
          requestId: 'other-device-req',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(taskFetches, greaterThanOrEqualTo(1));

      // Changing settings marks dirty keys and pushes them cleanly
      container.read(settingsPresenterProvider).setConfirmBeforeDeleting(false);
      container
          .read(tasksViewPresenterProvider)
          .setPlannedDueDateFilter(PlannedDueDateFilter.thisWeek);
      container
          .read(tasksViewPresenterProvider)
          .setPlannedGroupOption(PlannedGroupOption.byList);

      // Copy / duplicate clears remoteId and changeKey
      final originalTask = TaskItem(
        id: 't_src',
        listId: 'tasks',
        title: 'Source',
        createdAt: DateTime(2026, 11, 22),
        remoteId: 'rt-src',
        changeKey: 'ck-src',
        steps: const [
          TaskStep(id: 's_1', title: 'Step 1', remoteId: 'rs-src'),
        ],
      );
      container.read(todoProvider.notifier).commit(
            container.read(todoProvider).copyWith(tasks: [originalTask]),
          );
      container.read(tasksActionPresenterProvider).batchCopyToList(
        {'t_src'},
        'tasks',
      );
      final copied = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.id != 't_src');
      expect(copied.remoteId, isNull);
      expect(copied.changeKey, isNull);
      expect(copied.steps.single.remoteId, isNull);

      await container.read(syncProvider.notifier).syncNow();
      expect(fakeApi.remoteSettings[TodoSettingKeys.confirmOnDelete], 'false');
      expect(
        fakeApi.remoteSettings[TodoSettingKeys.smartListPlannedDueDateFilter],
        '3',
      );
      expect(
        fakeApi.remoteSettings[TodoSettingKeys.smartListPlannedGroupType],
        '2',
      );
    });

    test('retries 401 with refreshed token and reports requiresRelogin when refresh fails',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = TodoLocalStorage(prefs, accountId: 'acct_1');
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'expired-tok',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_1',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );

      final fakeApi = _FakeSubstrateApi();
      var attempts = 0;
      fakeApi.onFetchFoldersDelta = (dl) {
        attempts += 1;
        if (attempts == 1) {
          throw const SyncApiException(statusCode: 401, message: 'Unauthorized');
        }
        return const DeltaPageResult(items: []);
      };

      final service = CloudSyncService(
        authClient: _FakeAuthClient(),
        todoApi: fakeApi,
        tokenStorage: tokenStorage,
      );
      final notifierContainer = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(notifierContainer.dispose);

      final outcome = await service.syncAccount(
        account: account,
        currentState: notifierContainer.read(todoProvider),
        storage: storage,
        idGenerator: notifierContainer.read(todoProvider.notifier).nextId,
      );
      expect(attempts, 2);
      expect(outcome.syncedAt, isNotNull);

      // Now test unrecoverable refresh -> SyncStatus.requiresRelogin
      final failingAuth = _FakeAuthClient(
        onRefreshTokens: (_) async => throw const MicrosoftAuthException(
          'Token revoked',
          code: 'invalid_grant',
          requiresReauth: true,
        ),
      );
      await tokenStorage.saveTokens(
        'acct_1',
        MicrosoftAuthTokens(
          accessToken: 'old',
          refreshToken: 'bad-rt',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_1');

      final container2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(failingAuth),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container2.dispose);

      await container2.read(syncProvider.notifier).syncNow();
      expect(container2.read(syncProvider).status, SyncStatus.requiresRelogin);
      expect(container2.read(syncProvider).requiresRelogin, isTrue);
    });

    test('backfills missing Microsoft displayName and avatar during syncNow',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_bf',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-bf',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cidbf',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_bf',
        displayName: 'Microsoft Account',
        email: '',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cidbf',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_bf');

      final avatar = base64Encode([0xFF, 0xD8, 0xFF, 0xE0]);
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(
            _FakeAuthClient(
              onFetchUserProfile: (cid, rt, _) async => MicrosoftUserProfile(
                id: cid,
                displayName: 'Leo Zhang',
                email: 'leo@outlook.com',
                avatarBase64: avatar,
              ),
            ),
          ),
          microsoftTodoApiProvider.overrideWithValue(_FakeSubstrateApi()),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncNow();
      expect(container.read(syncProvider).status, SyncStatus.success);

      final updated = container.read(accountProvider).activeAccount
          as MicrosoftAccount?;
      expect(updated, isNotNull);
      expect(updated!.displayName, 'Leo Zhang');
      expect(updated.email, 'leo@outlook.com');
      expect(updated.avatarBase64, avatar);
    });

    testWidgets(
        'Tasks default list displays Completed pill even when remote ShowCompletedTasks is false and syncs toggle',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_tasks_done',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_tasks_done',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_tasks_done');

      final fakeApi = _FakeSubstrateApi();
      Map<String, dynamic>? patchedDefaultFolder;
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
            items: [
              RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
                showCompletedTasks: false,
              ),
            ],
            deltaLink: 'dl-folders-1',
          );
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-default' && dl == null) {
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-active',
                'ChangeKey': 'ck-a',
                'ParentFolderId': 'rf-default',
                'Subject': 'Active default task',
                'Status': 'NotStarted',
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-done',
                'ChangeKey': 'ck-d',
                'ParentFolderId': 'rf-default',
                'Subject': 'Done default task',
                'Status': 'Completed',
              }),
            ],
            deltaLink: 'dl-tasks-default-1',
          );
        }
        return DeltaPageResult(items: const [], deltaLink: 'dl-tasks-$folderId');
      };
      fakeApi.onPatchFolder = (remoteId, patch) async {
        if (remoteId == 'rf-default') {
          patchedDefaultFolder = Map<String, dynamic>.from(patch);
        }
        return RemoteTodoFolder(
          id: remoteId,
          name: 'Tasks',
          isDefaultFolder: true,
          showCompletedTasks: patch['ShowCompletedTasks'] as bool? ?? true,
        );
      };

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      await container.read(syncProvider.notifier).syncNow();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      // Active task is visible and Completed pill appears even though ShowCompletedTasks was false
      expect(find.text('Active default task'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Done default task'), findsNothing);

      // Tapping Completed expands the section and marks default Tasks folder dirty
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Done default task'), findsOneWidget);
      expect(
        TodoLocalStorage(prefs, accountId: 'acct_tasks_done').loadDirtyListIds(),
        contains('tasks'),
      );

      await container.read(syncProvider.notifier).syncNow();
      expect(patchedDefaultFolder?['ShowCompletedTasks'], isTrue);
    });

    testWidgets(
        'Sidebar renders remote groups, interleaved ungrouped lists, and group members in descending OrderDateTime order across restarts',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_order_ui',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_order_ui',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_order_ui');

      final fakeApi = _FakeSubstrateApi();
      // Return groups and folders in deliberately scrambled array order.
      fakeApi.onFetchGroupsDelta = (dl) => DeltaPageResult(
            items: [
              RemoteFolderGroup(
                id: 'rg-work',
                name: 'Work Group',
                orderDateTime: DateTime.utc(2026, 11, 22, 9),
              ),
              RemoteFolderGroup(
                id: 'rg-personal',
                name: 'Personal Group',
                orderDateTime: DateTime.utc(2026, 11, 22, 11),
              ),
            ],
            deltaLink: 'dl-groups-1',
          );
      fakeApi.onFetchFoldersDelta = (dl) => DeltaPageResult(
            items: [
              const RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
              ),
              RemoteTodoFolder(
                id: 'rf-bot',
                name: 'Bottom Unfiled',
                orderDateTime: DateTime.utc(2026, 11, 22, 8),
              ),
              RemoteTodoFolder(
                id: 'rf-w2',
                name: 'Work Second',
                parentFolderGroupId: 'rg-work',
                orderDateTime: DateTime.utc(2026, 11, 22, 7),
              ),
              RemoteTodoFolder(
                id: 'rf-top',
                name: 'Top Unfiled',
                orderDateTime: DateTime.utc(2026, 11, 22, 12),
              ),
              RemoteTodoFolder(
                id: 'rf-mid',
                name: 'Middle Unfiled',
                orderDateTime: DateTime.utc(2026, 11, 22, 10),
              ),
              RemoteTodoFolder(
                id: 'rf-w1',
                name: 'Work First',
                parentFolderGroupId: 'rg-work',
                orderDateTime: DateTime.utc(2026, 11, 22, 7, 30),
              ),
            ],
            deltaLink: 'dl-folders-1',
          );

      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      await container.read(syncProvider.notifier).syncNow();
      await tester.pumpAndSettle();

      void assertOrder() {
        final yTop = tester.getTopLeft(find.text('Top Unfiled')).dy;
        final yPersonal = tester.getTopLeft(find.text('Personal Group')).dy;
        final yMid = tester.getTopLeft(find.text('Middle Unfiled')).dy;
        final yWork = tester.getTopLeft(find.text('Work Group')).dy;
        final yW1 = tester.getTopLeft(find.text('Work First')).dy;
        final yW2 = tester.getTopLeft(find.text('Work Second')).dy;
        final yBot = tester.getTopLeft(find.text('Bottom Unfiled')).dy;

        expect(yTop, lessThan(yPersonal));
        expect(yPersonal, lessThan(yMid));
        expect(yMid, lessThan(yWork));
        expect(yWork, lessThan(yW1));
        expect(yW1, lessThan(yW2));
        expect(yW2, lessThan(yBot));
      }

      assertOrder();

      // Verify exact same interleaved order persists across app restart without syncing
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();
      assertOrder();
    });

    test(
        'HomeViewPresenter manual reorder updates descending OrderDateTime, marks moved items dirty, and PATCHes remote',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_reorder_sync',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_reorder_sync',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs).saveActiveAccountId('acct_reorder_sync');

      final fakeApi = _FakeSubstrateApi();
      final patchedGroups = <String, Map<String, dynamic>>{};
      final patchedFolders = <String, Map<String, dynamic>>{};
      fakeApi.onFetchGroupsDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-groups-2')
          : DeltaPageResult(
              items: [
                RemoteFolderGroup(
                  id: 'rg-work',
                  name: 'Work Group',
                  orderDateTime: DateTime.utc(2026, 11, 22, 10),
                ),
              ],
              deltaLink: 'dl-groups-1',
            );
      fakeApi.onFetchFoldersDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-folders-2')
          : DeltaPageResult(
              items: [
              const RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
              ),
              RemoteTodoFolder(
                id: 'rf-alpha',
                name: 'Alpha',
                orderDateTime: DateTime.utc(2026, 11, 22, 12),
              ),
              RemoteTodoFolder(
                id: 'rf-beta',
                name: 'Beta',
                orderDateTime: DateTime.utc(2026, 11, 22, 8),
              ),
              RemoteTodoFolder(
                id: 'rf-m1',
                name: 'Member 1',
                parentFolderGroupId: 'rg-work',
                orderDateTime: DateTime.utc(2026, 11, 22, 11),
              ),
                RemoteTodoFolder(
                  id: 'rf-m2',
                  name: 'Member 2',
                  parentFolderGroupId: 'rg-work',
                  orderDateTime: DateTime.utc(2026, 11, 22, 9),
                ),
              ],
              deltaLink: 'dl-folders-1',
            );
      fakeApi.onPatchGroup = (remoteId, patch) async {
        patchedGroups[remoteId] = Map<String, dynamic>.from(patch);
        return RemoteFolderGroup(
          id: remoteId,
          name: patch['Name'] as String? ?? 'Work Group',
          orderDateTime: parseSubstrateTimestamp(patch['OrderDateTime'] as String?),
        );
      };
      fakeApi.onPatchFolder = (remoteId, patch) async {
        patchedFolders[remoteId] = Map<String, dynamic>.from(patch);
        return RemoteTodoFolder(
          id: remoteId,
          name: patch['Name'] as String? ?? 'List',
          parentFolderGroupId: patch['ParentFolderGroupId'] as String?,
          orderDateTime: parseSubstrateTimestamp(patch['OrderDateTime'] as String?),
        );
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncNow();

      final homePresenter = container.read(homeViewPresenterProvider);
      var state = container.read(todoProvider);
      var entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      expect(
        entries.map((e) => e.stableKey).toList(),
        [
          'list_${state.lists.firstWhere((l) => l.remoteId == 'rf-alpha').id}',
          'group_${state.groups.first.id}',
          'list_${state.lists.firstWhere((l) => l.remoteId == 'rf-beta').id}',
        ],
      );

      // Move Alpha (index 0) to bottom (index 2, below Beta)
      homePresenter.reorderTopLevelEntries(entries, 0, 2);
      // Move rg-work (now index 0) below Beta -> wait let's inspect first then move group to top/bottom
      state = container.read(todoProvider);
      entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      final alpha = state.lists.firstWhere((l) => l.remoteId == 'rf-alpha');
      final beta = state.lists.firstWhere((l) => l.remoteId == 'rf-beta');
      expect(alpha.orderDateTime!.isBefore(beta.orderDateTime!), isTrue);
      expect(
        entries.map((e) => e.stableKey).toList(),
        [
          'group_${state.groups.first.id}',
          'list_${beta.id}',
          'list_${alpha.id}',
        ],
      );

      // Move Beta (index 1) to top (index 0, above rg-work) & swap group members
      homePresenter.reorderTopLevelEntries(entries, 1, 0);
      // Also move rg-work between Beta and Alpha? Swap Beta back via moving rg-work so group PATCH is exercised too
      state = container.read(todoProvider);
      final workGroupEntry = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      ).whereType<HomeGroupEntry>().single;
      homePresenter.reorderGroupLists(
        workGroupEntry.group.id,
        workGroupEntry.lists,
        1,
        0,
      );
      // Now move rg-work from index 1 to index 0 (back to top) so group OrderDateTime updates too
      state = container.read(todoProvider);
      entries = buildOrderedHomeSidebarEntries(
        groups: state.groups,
        lists: state.lists,
      );
      homePresenter.reorderTopLevelEntries(entries, 1, 0);

      await container.read(syncProvider.notifier).syncNow();

      expect(patchedGroups['rg-work']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-alpha']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-beta']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-m2']?['OrderDateTime'], isNotNull);
      expect(patchedFolders['rf-m1']?['OrderDateTime'], isNull);

      state = container.read(todoProvider);
      final syncedM1 = state.lists.firstWhere((l) => l.remoteId == 'rf-m1');
      final syncedM2 = state.lists.firstWhere((l) => l.remoteId == 'rf-m2');
      expect(syncedM2.orderDateTime!.isAfter(syncedM1.orderDateTime!), isTrue);
    });

    testWidgets(
        'Pulls remote task and subtask manual order (including legacy .-Z timestamps, CreatedDateTime ASC tiebreak, and My Day CommittedOrder) and preserves across restarts',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_task_pull_order',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_task_pull_order',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs)
          .saveActiveAccountId('acct_task_pull_order');

      final fakeApi = _FakeSubstrateApi();
      final today = DateTime.now();
      var defaultTaskSyncCount = 0;
      Map<String, dynamic>? uiReorderPatch;
      fakeApi.onFetchFoldersDelta = (dl) => const DeltaPageResult(
            items: [
              RemoteTodoFolder(
                id: 'rf-default',
                name: 'Tasks',
                isDefaultFolder: true,
              ),
              RemoteTodoFolder(
                id: 'rf-custom',
                name: 'Work Tasks',
              ),
            ],
            deltaLink: 'dl-folders-1',
          );
      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (folderId == 'rf-default') {
          defaultTaskSyncCount += 1;
          if (dl == null) {
            return DeltaPageResult(
              items: [
                // Scrambled order; includes equal OrderDateTime tiebreak & legacy .-1234Z
                RemoteTodoTask.fromJson({
                  'Id': 'rt-tie-later',
                  'ChangeKey': 'ck-1',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Tie Created Later',
                  'OrderDateTime': '2026-11-22T10:00:00.000-1234Z',
                  'CreatedDateTime': '2026-11-22T09:00:00.0000000Z',
                  'Subtasks': [
                    {
                      'Id': 'st-low',
                      'Subject': 'Step Second',
                      'OrderDateTime': '2026-11-22T08:00:00.0000000Z',
                    },
                    {
                      'Id': 'st-high',
                      'Subject': 'Step First',
                      'OrderDateTime': '2026-11-22T12:00:00.0000000Z',
                    },
                  ],
                }),
                RemoteTodoTask.fromJson({
                  'Id': 'rt-bottom',
                  'ChangeKey': 'ck-2',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Default Third',
                  'OrderDateTime': '2026-11-22T08:00:00.0000000Z',
                  'CreatedDateTime': '2026-11-22T07:00:00.0000000Z',
                }),
                RemoteTodoTask.fromJson({
                  'Id': 'rt-tie-earlier',
                  'ChangeKey': 'ck-3',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Tie Created Earlier',
                  'OrderDateTime': '2026-11-22T10:00:00.000-1234Z',
                  'CreatedDateTime': '2026-11-22T06:00:00.0000000Z',
                }),
              ],
              deltaLink: 'dl-default-1',
            );
          }
          if (defaultTaskSyncCount == 2) {
            return DeltaPageResult(
              items: [
                RemoteTodoTask.fromJson({
                  'Id': 'rt-bottom',
                  'ChangeKey': 'ck-2b',
                  'ParentFolderId': 'rf-default',
                  'Subject': 'Default Third',
                  'OrderDateTime': '2026-11-22T14:00:00.0000000Z',
                  'CreatedDateTime': '2026-11-22T07:00:00.0000000Z',
                }),
              ],
              deltaLink: 'dl-default-2',
            );
          }
          return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId-latest');
        }
        if (dl != null) {
          return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId-2');
        }
        if (folderId == 'rf-custom') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-due-today-uncommitted',
                'ChangeKey': 'ck-c1',
                'ParentFolderId': 'rf-custom',
                'Subject': 'Due Today Uncommitted',
                // High OrderDateTime should NOT beat an explicit CommittedOrder in My Day!
                'OrderDateTime': '2026-11-22T15:00:00.0000000Z',
                'DueDate': formatDayString(today),
                'CreatedDateTime': '2026-11-22T05:00:00.0000000Z',
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-myday-low',
                'ChangeKey': 'ck-c2',
                'ParentFolderId': 'rf-custom',
                'Subject': 'MyDay Second',
                'OrderDateTime': '2026-11-22T07:00:00.0000000Z',
                'CommittedDay': formatDayString(today),
                'CommittedOrder': '2026-11-22T09:00:00.0000000Z',
                'CreatedDateTime': '2026-11-22T06:00:00.0000000Z',
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-myday-top',
                'ChangeKey': 'ck-c3',
                'ParentFolderId': 'rf-custom',
                'Subject': 'MyDay First',
                'OrderDateTime': '2026-11-22T12:00:00.0000000Z',
                'CommittedDay': formatDayString(today),
                'CommittedOrder': '2026-11-22T11:00:00.0000000Z',
                'CreatedDateTime': '2026-11-22T07:00:00.0000000Z',
              }),
            ],
            deltaLink: 'dl-custom-1',
          );
        }
        return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
      };
      fakeApi.onPatchTask = (taskRemoteId, patch, ck) async {
        if (taskRemoteId == 'rt-bottom') {
          uiReorderPatch = Map<String, dynamic>.from(patch);
        }
        return RemoteTodoTask(
          id: taskRemoteId,
          changeKey: 'ck-patched-$taskRemoteId',
          parentFolderId: 'rf-default',
          subject: patch['Subject'] as String? ?? 'Task',
          orderDateTime:
              parseSubstrateTimestamp(patch['OrderDateTime'] as String?),
        );
      };

      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      await container.read(syncProvider.notifier).syncNow();
      await tester.pumpAndSettle();

      // Verify Tasks default list manual order (including legacy .-1234Z & CreatedDateTime ASC tiebreak)
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      void assertTasksOrder() {
        final yTieEarlier =
            tester.getTopLeft(find.text('Tie Created Earlier')).dy;
        final yTieLater = tester.getTopLeft(find.text('Tie Created Later')).dy;
        final yDefaultThird =
            tester.getTopLeft(find.text('Default Third')).dy;
        expect(yTieEarlier, lessThan(yTieLater));
        expect(yTieLater, lessThan(yDefaultThird));
      }

      assertTasksOrder();

      // Verify subtasks sorted descending by OrderDateTime
      final tieTask = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-tie-later');
      expect(
        tieTask.steps.map((s) => s.title).toList(),
        ['Step First', 'Step Second'],
      );

      // Navigate back and verify custom list & My Day manual order
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Work Tasks'));
      await tester.pumpAndSettle();

      void assertCustomListOrder() {
        final yDueToday =
            tester.getTopLeft(find.text('Due Today Uncommitted')).dy;
        final yMyDayTop = tester.getTopLeft(find.text('MyDay First')).dy;
        final yMyDayLow = tester.getTopLeft(find.text('MyDay Second')).dy;
        expect(yDueToday, lessThan(yMyDayTop));
        expect(yMyDayTop, lessThan(yMyDayLow));
      }

      assertCustomListOrder();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Day'));
      await tester.pumpAndSettle();

      void assertMyDayOrder() {
        final yMyDayTop = tester.getTopLeft(find.text('MyDay First')).dy;
        final yMyDayLow = tester.getTopLeft(find.text('MyDay Second')).dy;
        final yDueToday =
            tester.getTopLeft(find.text('Due Today Uncommitted')).dy;
        expect(yMyDayTop, lessThan(yMyDayLow));
        expect(yMyDayLow, lessThan(yDueToday));
      }

      assertMyDayOrder();

      // Restart app (without syncing) and verify My Day & Tasks order persist
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(fakeApi),
            realtimeSyncEnabledProvider.overrideWithValue(false),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();
      // Last entered list was My Day (or Home if not persisted) -> open My Day if needed
      if (find.text('MyDay First').evaluate().isEmpty) {
        await tester.tap(find.text('My Day'));
        await tester.pumpAndSettle();
      }
      assertMyDayOrder();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      assertTasksOrder();

      final restartedContainer = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );

      // In-place remote delta reorder while viewing Tasks updates AnimatedTaskSliverList visually
      await restartedContainer.read(syncProvider.notifier).syncNow();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Default Third')).dy,
        lessThan(tester.getTopLeft(find.text('Tie Created Earlier')).dy),
      );

      // Reorder via UI menu + keyboard_arrow_down + check, then sync PATCH
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.reorder));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Tie Created Earlier')).dy,
        lessThan(tester.getTopLeft(find.text('Default Third')).dy),
      );
      await restartedContainer.read(syncProvider.notifier).syncNow();
      expect(uiReorderPatch?['OrderDateTime'], isNotNull);
    });

    test(
        'Task manual reorder pushes OrderDateTime / CommittedOrder cleanly without Reminder or stale ParentFolderId, retries 412 conflicts, and sends ParentFolderId on cross-list move',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tokenStorage = AuthTokenStorage(prefs);
      await tokenStorage.saveTokens(
        'acct_task_push_order',
        MicrosoftAuthTokens(
          accessToken: 'tok-1',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          userId: 'cid1',
        ),
      );
      final account = MicrosoftAccount(
        id: 'acct_task_push_order',
        displayName: 'Alice',
        email: 'alice@outlook.com',
        createdAt: DateTime(2026, 11, 22),
        microsoftUserId: 'cid1',
      );
      await AccountLocalStorage(prefs).saveAccounts([account]);
      await AccountLocalStorage(prefs)
          .saveActiveAccountId('acct_task_push_order');

      final fakeApi = _FakeSubstrateApi();
      final today = DateTime.now();
      final patchedPayloads = <String, List<Map<String, dynamic>>>{};
      var return412Once = true;

      fakeApi.onFetchFoldersDelta = (dl) => dl != null
          ? const DeltaPageResult(items: [], deltaLink: 'dl-folders-2')
          : const DeltaPageResult(
              items: [
                RemoteTodoFolder(
                  id: 'rf-default',
                  name: 'Tasks',
                  isDefaultFolder: true,
                ),
                RemoteTodoFolder(
                  id: 'rf-work',
                  name: 'Work',
                ),
              ],
              deltaLink: 'dl-folders-1',
            );

      final tWide1 = DateTime.utc(2026, 11, 22, 12);
      final tWide2 = DateTime.utc(2026, 11, 22, 10);
      final tTightBase = DateTime.utc(2026, 11, 22, 9, 0, 10);
      final tTightSecond = DateTime.utc(2026, 11, 22, 9, 0, 0);

      fakeApi.onFetchTasksDelta = (folderId, dl) {
        if (dl != null) {
          return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId-2');
        }
        if (folderId == 'rf-default') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-w1',
                'ChangeKey': 'ck-w1',
                'ParentFolderId': 'rf-default',
                'Subject': 'Wide Top',
                'OrderDateTime': formatSubstrateUtcTimestamp(tWide1),
                'CommittedDay': formatDayString(today),
                'CommittedOrder': '2026-11-22T12:00:00.0000000Z',
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-w2',
                'ChangeKey': 'ck-w2',
                'ParentFolderId': 'rf-default',
                'Subject': 'Wide Bottom',
                'OrderDateTime': formatSubstrateUtcTimestamp(tWide2),
              }),
            ],
            deltaLink: 'dl-default-1',
          );
        }
        if (folderId == 'rf-work') {
          return DeltaPageResult(
            items: [
              RemoteTodoTask.fromJson({
                'Id': 'rt-tight-1',
                'ChangeKey': 'ck-t1',
                'ParentFolderId': 'rf-work',
                'Subject': 'Tight First',
                'OrderDateTime': formatSubstrateUtcTimestamp(tTightBase),
                'DueDate': formatDayString(today),
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-tight-2',
                'ChangeKey': 'ck-t2',
                'ParentFolderId': 'rf-work',
                'Subject': 'Tight Second',
                'OrderDateTime': formatSubstrateUtcTimestamp(tTightSecond),
              }),
              RemoteTodoTask.fromJson({
                'Id': 'rt-tight-3',
                'ChangeKey': 'ck-t3',
                'ParentFolderId': 'rf-work',
                'Subject': 'Tight Third',
                'OrderDateTime': formatSubstrateUtcTimestamp(tTightSecond),
              }),
            ],
            deltaLink: 'dl-work-1',
          );
        }
        return DeltaPageResult(items: const [], deltaLink: 'dl-$folderId');
      };

      fakeApi.onGetTask = (taskRemoteId) async => RemoteTodoTask(
            id: taskRemoteId,
            changeKey: 'ck-refreshed',
            parentFolderId: 'rf-default',
            subject: 'Wide Top',
            orderDateTime: tWide1,
          );

      fakeApi.onPatchTask = (taskRemoteId, patch, changeKey) async {
        if (taskRemoteId == 'rt-w1' && return412Once) {
          return412Once = false;
          throw const SyncApiException(
            statusCode: 412,
            message: 'Precondition Failed',
          );
        }
        (patchedPayloads[taskRemoteId] ??= [])
            .add(Map<String, dynamic>.from(patch));
        return RemoteTodoTask(
          id: taskRemoteId,
          changeKey: 'ck-patched-$taskRemoteId',
          parentFolderId:
              (patch['ParentFolderId'] as String?) ?? 'rf-default',
          subject: patch['Subject'] as String? ?? 'Task',
          orderDateTime:
              parseSubstrateTimestamp(patch['OrderDateTime'] as String?),
          committedOrder:
              parseSubstrateTimestamp(patch['CommittedOrder'] as String?),
        );
      };

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(_FakeAuthClient()),
          microsoftTodoApiProvider.overrideWithValue(fakeApi),
          realtimeSyncEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);

      await container.read(syncProvider.notifier).syncNow();

      final presenter = container.read(tasksViewPresenterProvider);
      final detailPresenter = container.read(detailViewPresenterProvider);

      // 1) Wide-gap single move in Tasks (rt-w1 from index 0 to index 1)
      container.read(todoProvider.notifier).selectList('tasks');
      final tasksVisible = container.read(todoProvider).tasksForList(
            container.read(todoProvider).selectedList,
          );
      expect(tasksVisible.map((t) => t.remoteId), ['rt-w1', 'rt-w2']);
      presenter.reorderActiveTasks(tasksVisible, 0, 1);

      await container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads.keys, contains('rt-w1'));
      expect(patchedPayloads.containsKey('rt-w2'), isFalse);
      final w1Patch = patchedPayloads['rt-w1']!.single;
      expect(w1Patch.containsKey('Reminder'), isFalse);
      expect(w1Patch.containsKey('ParentFolderId'), isFalse);
      expect(w1Patch['OrderDateTime'], isNotNull);
      final w1Updated = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-w1');
      expect(w1Updated.changeKey, 'ck-patched-rt-w1');
      expect(w1Updated.orderDateTime!.isBefore(tWide2), isTrue);

      // 2) Tight <= 16s / equal timestamps in Work custom list trigger full re-space
      patchedPayloads.clear();
      final workList = container
          .read(todoProvider)
          .lists
          .firstWhere((l) => l.remoteId == 'rf-work');
      container.read(todoProvider.notifier).selectList(workList.id);
      final workVisible = container.read(todoProvider).tasksForList(workList);
      expect(
        workVisible.map((t) => t.remoteId),
        ['rt-tight-1', 'rt-tight-2', 'rt-tight-3'],
      );
      // Move rt-tight-3 (equal timestamp to rt-tight-2, only 10s below rt-tight-1) to middle
      presenter.reorderActiveTasks(workVisible, 2, 1);

      await container.read(syncProvider.notifier).syncNow();

      // Anchor equals rt-tight-1's timestamp so rt-tight-1 doesn't need a redundant PATCH,
      // while rt-tight-3 and rt-tight-2 are re-spaced descending in 4096s steps.
      expect(patchedPayloads.containsKey('rt-tight-1'), isFalse);
      expect(patchedPayloads.containsKey('rt-tight-2'), isTrue);
      expect(patchedPayloads.containsKey('rt-tight-3'), isTrue);
      for (final pList in patchedPayloads.values) {
        expect(pList.single.containsKey('Reminder'), isFalse);
        expect(pList.single.containsKey('ParentFolderId'), isFalse);
      }
      final afterTight = container.read(todoProvider).tasksForList(
            container
                .read(todoProvider)
                .lists
                .firstWhere((l) => l.remoteId == 'rf-work'),
          );
      expect(
        afterTight.map((t) => t.remoteId),
        ['rt-tight-1', 'rt-tight-3', 'rt-tight-2'],
      );
      expect(
        afterTight[0].orderDateTime!.isAfter(afterTight[1].orderDateTime!),
        isTrue,
      );
      expect(
        afterTight[1].orderDateTime!.isAfter(afterTight[2].orderDateTime!),
        isTrue,
      );

      // 3) Reorder due-today uncommitted task (rt-tight-1, myDayDate == null) above committed task (rt-w1) in My Day
      patchedPayloads.clear();
      container.read(todoProvider.notifier).selectList('my_day');
      final myDayVisible = container.read(todoProvider).tasksForList(
            container.read(todoProvider).selectedList,
          );
      expect(myDayVisible.map((t) => t.remoteId), ['rt-w1', 'rt-tight-1']);
      presenter.reorderActiveTasks(myDayVisible, 1, 0);

      await container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-tight-1'], isNotNull);
      final tightMyDayPatch = patchedPayloads['rt-tight-1']!.single;
      expect(tightMyDayPatch['CommittedOrder'], isNotNull);
      expect(tightMyDayPatch.containsKey('Reminder'), isFalse);
      final syncedMyDay = container.read(todoProvider).tasksForList(
            container.read(todoProvider).selectedList,
          );
      expect(syncedMyDay.map((t) => t.remoteId), ['rt-tight-1', 'rt-w1']);

      // 4) Cross-list move MUST include ParentFolderId; subsequent same-folder edit MUST omit it
      patchedPayloads.clear();
      final w2 = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.remoteId == 'rt-w2');
      detailPresenter.moveTaskToList(w2.id, workList.id);
      await container.read(syncProvider.notifier).syncNow();

      expect(patchedPayloads['rt-w2']!.single['ParentFolderId'], 'rf-work');

      patchedPayloads.clear();
      detailPresenter.updateTaskTitle(w2.id, 'Wide Bottom Renamed');
      await container.read(syncProvider.notifier).syncNow();

      expect(
        patchedPayloads['rt-w2']!.single.containsKey('ParentFolderId'),
        isFalse,
      );
      expect(
        patchedPayloads['rt-w2']!.single['Subject'],
        'Wide Bottom Renamed',
      );
    });
  });
}
