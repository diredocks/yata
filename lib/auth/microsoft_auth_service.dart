import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';

class MicrosoftAuthConfig {
  const MicrosoftAuthConfig._();

  /// Configurable via `--dart-define=MS_CLIENT_ID=<your-azure-app-client-id>`.
  static const defaultClientId = String.fromEnvironment(
    'MS_CLIENT_ID',
    defaultValue: '14d82eec-204b-4c2f-b7e8-296a70dab67e',
  );

  static const authority = 'https://login.microsoftonline.com/common/oauth2/v2.0';
  static const graphBaseUrl = 'https://graph.microsoft.com/v1.0';
  static const scopes = [
    'User.Read',
    'Tasks.ReadWrite',
    'offline_access',
    'openid',
    'profile',
    'email',
  ];
}

class MicrosoftAuthException implements Exception {
  const MicrosoftAuthException(
    this.message, {
    this.requiresRelogin = false,
    this.isCancelled = false,
  });

  final String message;
  final bool requiresRelogin;
  final bool isCancelled;

  @override
  String toString() => message;
}

class MicrosoftAuthTokens {
  const MicrosoftAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.clientId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String clientId;

  bool get isExpired =>
      DateTime.now().toUtc().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
      'clientId': clientId,
    };
  }

  factory MicrosoftAuthTokens.fromJson(Map<String, dynamic> json) {
    return MicrosoftAuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      clientId: json['clientId'] as String? ?? MicrosoftAuthConfig.defaultClientId,
    );
  }
}

class MicrosoftDeviceCodePrompt {
  const MicrosoftDeviceCodePrompt({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
    required this.message,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
  final String message;
}

class MicrosoftUserProfile {
  const MicrosoftUserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.avatarBase64,
  });

  final String id;
  final String displayName;
  final String email;
  final String? avatarBase64;
}

class MicrosoftSignInResult {
  const MicrosoftSignInResult({
    required this.profile,
    required this.tokens,
  });

  final MicrosoftUserProfile profile;
  final MicrosoftAuthTokens tokens;
}

class AuthTokenStorage {
  AuthTokenStorage(this._prefs);

  final SharedPreferences _prefs;

  String _key(String accountId) =>
      '${AccountLocalStorage.accountKeyPrefix(accountId)}auth_tokens';

  MicrosoftAuthTokens? load(String accountId) {
    final raw = _prefs.getString(_key(accountId));
    if (raw == null) return null;
    try {
      return MicrosoftAuthTokens.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String accountId, MicrosoftAuthTokens tokens) async {
    await _prefs.setString(_key(accountId), jsonEncode(tokens.toJson()));
  }

  Future<void> delete(String accountId) async {
    await _prefs.remove(_key(accountId));
  }
}

abstract class MicrosoftAuthClient {
  Future<MicrosoftDeviceCodePrompt> startDeviceCodeFlow({
    String? loginHint,
    String? clientId,
  });

  Future<MicrosoftSignInResult> pollDeviceCodeToken(
    MicrosoftDeviceCodePrompt prompt, {
    String? clientId,
    bool Function()? isCancelled,
  });

  Future<MicrosoftSignInResult?> signInWithPkceLoopback({
    String? loginHint,
    String? clientId,
    required Future<void> Function(String authUrl) openBrowser,
    bool Function()? isCancelled,
  });

  Future<MicrosoftAuthTokens> refreshTokens(MicrosoftAuthTokens current);

  Future<MicrosoftUserProfile> fetchUserProfile(String accessToken);
}

class HttpMicrosoftAuthClient implements MicrosoftAuthClient {
  HttpMicrosoftAuthClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  String _resolveClientId(String? clientId) {
    final trimmed = clientId?.trim() ?? '';
    return trimmed.isEmpty ? MicrosoftAuthConfig.defaultClientId : trimmed;
  }

  String _scopeString() => MicrosoftAuthConfig.scopes.join(' ');

  @override
  Future<MicrosoftDeviceCodePrompt> startDeviceCodeFlow({
    String? loginHint,
    String? clientId,
  }) async {
    final resolvedClientId = _resolveClientId(clientId);
    final response = await _http.post(
      Uri.parse('${MicrosoftAuthConfig.authority}/devicecode'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': resolvedClientId,
        'scope': _scopeString(),
      },
    );

    final body = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw MicrosoftAuthException(
        body['error_description'] as String? ??
            body['error'] as String? ??
            'Failed to start Microsoft sign-in (${response.statusCode})',
      );
    }

    return MicrosoftDeviceCodePrompt(
      deviceCode: body['device_code'] as String,
      userCode: body['user_code'] as String,
      verificationUri:
          body['verification_uri'] as String? ?? 'https://microsoft.com/devicelogin',
      expiresIn: (body['expires_in'] as num?)?.toInt() ?? 900,
      interval: (body['interval'] as num?)?.toInt() ?? 5,
      message: body['message'] as String? ?? '',
    );
  }

  @override
  Future<MicrosoftSignInResult> pollDeviceCodeToken(
    MicrosoftDeviceCodePrompt prompt, {
    String? clientId,
    bool Function()? isCancelled,
  }) async {
    final resolvedClientId = _resolveClientId(clientId);
    final deadline = DateTime.now().add(Duration(seconds: prompt.expiresIn));
    var pollInterval = Duration(seconds: prompt.interval.clamp(2, 15));

    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() == true) {
        throw const MicrosoftAuthException(
          'Sign-in cancelled',
          isCancelled: true,
        );
      }

      await Future<void>.delayed(pollInterval);

      if (isCancelled?.call() == true) {
        throw const MicrosoftAuthException(
          'Sign-in cancelled',
          isCancelled: true,
        );
      }

      final response = await _http.post(
        Uri.parse('${MicrosoftAuthConfig.authority}/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          'client_id': resolvedClientId,
          'device_code': prompt.deviceCode,
        },
      );

      final body = _decodeJsonMap(response.body);
      if (response.statusCode == 200 && body['access_token'] != null) {
        final tokens = _tokensFromResponse(body, resolvedClientId);
        final profile = await fetchUserProfile(tokens.accessToken);
        return MicrosoftSignInResult(profile: profile, tokens: tokens);
      }

      final error = body['error'] as String? ?? '';
      if (error == 'authorization_pending') {
        continue;
      }
      if (error == 'slow_down') {
        pollInterval += const Duration(seconds: 5);
        continue;
      }
      if (error == 'authorization_declined') {
        throw const MicrosoftAuthException('Sign-in was declined.');
      }
      if (error == 'expired_token') {
        throw const MicrosoftAuthException('Sign-in code expired. Please try again.');
      }

      throw MicrosoftAuthException(
        body['error_description'] as String? ??
            'Microsoft sign-in failed ($error)',
      );
    }

    throw const MicrosoftAuthException('Sign-in timed out. Please try again.');
  }

  @override
  Future<MicrosoftSignInResult?> signInWithPkceLoopback({
    String? loginHint,
    String? clientId,
    required Future<void> Function(String authUrl) openBrowser,
    bool Function()? isCancelled,
  }) async {
    final resolvedClientId = _resolveClientId(clientId);
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _computeCodeChallenge(codeVerifier);
    final state = _generateRandomToken(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://localhost:${server.port}/callback';

    try {
      final authUri = Uri.parse('${MicrosoftAuthConfig.authority}/authorize').replace(
        queryParameters: {
          'client_id': resolvedClientId,
          'response_type': 'code',
          'redirect_uri': redirectUri,
          'response_mode': 'query',
          'scope': _scopeString(),
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          if (loginHint != null && loginHint.trim().isNotEmpty)
            'login_hint': loginHint.trim(),
        },
      );

      await openBrowser(authUri.toString());

      String? authCode;
      await for (final request in server.timeout(const Duration(minutes: 5))) {
        if (isCancelled?.call() == true) {
          throw const MicrosoftAuthException(
            'Sign-in cancelled',
            isCancelled: true,
          );
        }

        if (request.uri.path != '/callback') {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
          continue;
        }

        final params = request.uri.queryParameters;
        final error = params['error'];
        final returnedState = params['state'];
        if (error != null) {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(
              '<html><body><h3>Sign-in failed</h3><p>${const HtmlEscape().convert(params['error_description'] ?? error)}</p></body></html>',
            );
          await request.response.close();
          throw MicrosoftAuthException(
            params['error_description'] ?? error,
          );
        }

        if (returnedState != state || params['code'] == null) {
          request.response
            ..statusCode = HttpStatus.badRequest
            ..write('Invalid OAuth response');
          await request.response.close();
          throw const MicrosoftAuthException('Invalid OAuth state received.');
        }

        authCode = params['code'];
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write(
            '<html><body><h3>Signed in to Yata</h3><p>You can close this window and return to the app.</p></body></html>',
          );
        await request.response.close();
        break;
      }

      if (authCode == null) return null;

      final tokenResponse = await _http.post(
        Uri.parse('${MicrosoftAuthConfig.authority}/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': resolvedClientId,
          'grant_type': 'authorization_code',
          'code': authCode,
          'redirect_uri': redirectUri,
          'code_verifier': codeVerifier,
          'scope': _scopeString(),
        },
      );

      final body = _decodeJsonMap(tokenResponse.body);
      if (tokenResponse.statusCode != 200 || body['access_token'] == null) {
        throw MicrosoftAuthException(
          body['error_description'] as String? ??
              'Token exchange failed (${tokenResponse.statusCode})',
        );
      }

      final tokens = _tokensFromResponse(body, resolvedClientId);
      final profile = await fetchUserProfile(tokens.accessToken);
      return MicrosoftSignInResult(profile: profile, tokens: tokens);
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<MicrosoftAuthTokens> refreshTokens(MicrosoftAuthTokens current) async {
    if (current.refreshToken.isEmpty) {
      throw const MicrosoftAuthException(
        'Session expired. Please sign in again.',
        requiresRelogin: true,
      );
    }

    final response = await _http.post(
      Uri.parse('${MicrosoftAuthConfig.authority}/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': current.clientId,
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
        'scope': _scopeString(),
      },
    );

    final body = _decodeJsonMap(response.body);
    if (response.statusCode != 200 || body['access_token'] == null) {
      final error = body['error'] as String? ?? '';
      final relogin = error == 'invalid_grant' ||
          error == 'interaction_required' ||
          response.statusCode == 400 ||
          response.statusCode == 401;
      throw MicrosoftAuthException(
        body['error_description'] as String? ??
            'Failed to refresh Microsoft session (${response.statusCode})',
        requiresRelogin: relogin,
      );
    }

    final refreshed = _tokensFromResponse(body, current.clientId);
    return MicrosoftAuthTokens(
      accessToken: refreshed.accessToken,
      refreshToken: refreshed.refreshToken.isNotEmpty
          ? refreshed.refreshToken
          : current.refreshToken,
      expiresAt: refreshed.expiresAt,
      clientId: current.clientId,
    );
  }

  @override
  Future<MicrosoftUserProfile> fetchUserProfile(String accessToken) async {
    final response = await _http.get(
      Uri.parse('${MicrosoftAuthConfig.graphBaseUrl}/me'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    final body = _decodeJsonMap(response.body);
    if (response.statusCode != 200) {
      throw MicrosoftAuthException(
        'Failed to load Microsoft profile (${response.statusCode})',
        requiresRelogin: response.statusCode == 401,
      );
    }

    final email = (body['mail'] as String?)?.trim().isNotEmpty == true
        ? body['mail'] as String
        : (body['userPrincipalName'] as String? ?? '');
    final displayName = (body['displayName'] as String?)?.trim().isNotEmpty == true
        ? body['displayName'] as String
        : email;

    final avatarBase64 = await _fetchUserPhotoBase64(accessToken);

    return MicrosoftUserProfile(
      id: body['id'] as String? ?? email,
      displayName: displayName,
      email: email,
      avatarBase64: avatarBase64,
    );
  }

  Future<String?> _fetchUserPhotoBase64(String accessToken) async {
    try {
      final response = await _http.get(
        Uri.parse('${MicrosoftAuthConfig.graphBaseUrl}/me/photo/\$value'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return base64Encode(response.bodyBytes);
      }
    } catch (_) {
      // Avatar fetch is best-effort; fallback to initials on 404 or network error.
    }
    return null;
  }

  MicrosoftAuthTokens _tokensFromResponse(
    Map<String, dynamic> body,
    String clientId,
  ) {
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    return MicrosoftAuthTokens(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String? ?? '',
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      clientId: clientId,
    );
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    if (raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  String _generateCodeVerifier() => _generateRandomToken(64);

  String _computeCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  String _generateRandomToken(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }
}
