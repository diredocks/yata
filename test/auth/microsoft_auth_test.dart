import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/account_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/auth/msa_webview_launcher.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/account.dart';
import 'package:yata/onboarding/landing_screen.dart';
import 'package:yata/sync/sync_provider.dart';

import '../helpers/microsoft_sync_fakes.dart';

import 'package:yata/data/preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HttpMicrosoftAuthClient', () {
    test(
      'builds MSA authorize URL and extracts code from redirect or raw code',
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
          client
              .extractAuthorizationCode(
                'https://login.live.com/oauth20_desktop.srf?code=M.C509_ABC&state=ProjectCheshire&lc=1033',
              )
              .getOrThrow(),
          'M.C509_ABC',
        );
        expect(
          client.extractAuthorizationCode('M.RAW_CODE').getOrThrow(),
          'M.RAW_CODE',
        );
        expect(
          client
              .extractAuthorizationCode(
                'https://login.live.com/oauth20_desktop.srf?code=X&state=WrongState',
              )
              .exceptionOrNull(),
          isA<AuthError>(),
        );
        expect(
          client
              .extractAuthorizationCode(
                'https://login.live.com/oauth20_desktop.srf?error=access_denied&error_description=User+cancelled',
              )
              .exceptionOrNull(),
          isA<AuthError>(),
        );
      },
    );

    test('exchanges code, fetches primary Graph /beta/me profile+photo, and discovers endpoint', () async {
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
      final signIn = (await client.completeSignInWithCode(
        code: 'code-1',
        uaid: 'uaid-1',
      )).getOrThrow();
      expect(signIn.profile.id, 'abcdef123456');
      expect(signIn.profile.displayName, 'Alice Lee');
      expect(signIn.profile.email, 'alice@outlook.com');
      expect(
        signIn.profile.avatarBase64,
        base64Encode([0xFF, 0xD8, 0xFF, 0xE0]),
      );
      expect(signIn.tokens.accessToken, 'todo-access');
      expect(signIn.tokens.refreshToken, 'rt-graph-2');

      final endpoint = await client.discoverTodoEndpoint('abcdef123456');
      expect(endpoint, 'https://eur.substrate.office.com/todob2/api/v1/');
    });

    test('falls back to Substrate /profile/v1.0/me/profile and storage.live PNG octet-stream avatar when Graph fails', () async {
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
      final signIn = (await client.completeSignInWithCode(
        code: 'code-fallback',
      )).getOrThrow();
      expect(signIn.profile.id, 'abcdef123456');
      expect(signIn.profile.displayName, 'Alice Lee');
      expect(signIn.profile.email, 'alice@outlook.com');
      expect(signIn.profile.avatarBase64, base64Encode(pngBytes));
      expect(signIn.tokens.refreshToken, 'rt-sub-2');
    });

    test(
      'treats profile fetch failure as non-fatal and falls back autodiscover',
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
        final signIn = (await client.completeSignInWithCode(
          code: 'code-x',
          loginHint: 'bob@hotmail.com',
        )).getOrThrow();
        expect(signIn.profile.id, 'cid999');
        expect(signIn.profile.displayName, 'bob@hotmail.com');
        expect(signIn.profile.email, 'bob@hotmail.com');
        expect(
          await client.discoverTodoEndpoint('cid999'),
          MsaAuthConfig.defaultTodoApiBaseUrl,
        );
      },
    );
  });

  group('parseMsaRedirectUrl', () {
    test('returns null for non-redirect URLs and extracts code or error from redirect URL', () {
      expect(
        parseMsaRedirectUrl(
          url: 'https://login.live.com/oauth20_authorize.srf?client_id=123',
          redirectUri: MsaAuthConfig.redirectUri,
        ),
        isNull,
      );

      final success = parseMsaRedirectUrl(
        url: 'https://login.live.com/oauth20_desktop.srf?code=M.C509_XYZ&state=ProjectCheshire',
        redirectUri: MsaAuthConfig.redirectUri,
      );
      expect(success, isNotNull);
      expect(success!.cancelled, isFalse);
      expect(success.error, isNull);
      expect(success.code, 'M.C509_XYZ');

      final failure = parseMsaRedirectUrl(
        url: 'https://login.live.com/oauth20_desktop.srf?error=access_denied&error_description=User+denied',
        redirectUri: MsaAuthConfig.redirectUri,
      );
      expect(failure, isNotNull);
      expect(failure!.cancelled, isFalse);
      expect(failure.code, isNull);
      expect(failure.error, 'User denied');

      final cancelled = parseMsaRedirectUrl(
        url: 'https://login.live.com/oauth20_desktop.srf?lc=1033',
        redirectUri: MsaAuthConfig.redirectUri,
      );
      expect(cancelled, isNotNull);
      expect(cancelled!.cancelled, isTrue);
    });
  });

  group('LandingScreen MSA flows', () {
    testWidgets('completes sign-in via webview_all interactive client', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final interactive = FakeInteractiveMsaClient(
        const MsaInteractiveSignInResult.success(code: 'webview-code-1'),
      );
      final fakeAuth = FakeAuthClient();

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

      expect(
        interactive.lastAuthorizeUrl,
        contains('client_id=000000004C18365E'),
      );
      final active = container.read(accountProvider).activeAccount;
      expect(active, isA<MicrosoftAccount>());
      expect((active! as MicrosoftAccount).microsoftUserId, 'cid12345');
    });

    testWidgets('falls back to redirect-URL paste dialog on desktop', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final interactive = FakeInteractiveMsaClient(null);
      final fakeAuth = FakeAuthClient();
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
      expect(
        launchedUrls.single,
        contains('login.live.com/oauth20_authorize.srf'),
      );
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
}
