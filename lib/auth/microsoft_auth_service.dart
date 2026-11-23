import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/result/app_result.dart';
import '../sync/todo_wire_codecs.dart';
import 'auth_token_storage.dart';
import 'msa_profile_parser.dart';

export 'auth_token_storage.dart';

/// Fixed personal Microsoft Account (MSA) OAuth2 constants extracted from
/// Microsoft To Do 2.178 (`MsaSignInActivity` / `UserProfileProvider`).
abstract final class MsaAuthConfig {
  static const clientId = '000000004C18365E';
  static const clientSecret = 'jnHdzbxXzkKuiFMlNE-We3mEyUwWkT8e';
  static const redirectUri = 'https://login.live.com/oauth20_desktop.srf';
  static const state = 'ProjectCheshire';

  static const authorizeEndpoint =
      'https://login.live.com/oauth20_authorize.srf';
  static const tokenEndpoint = 'https://login.live.com/oauth20_token.srf';

  static const todoScope =
      'https://substrate.office.com/todo-internal.readwrite offline_access';
  static const graphProfileScope = 'https://graph.microsoft.com/User.Read';
  static const profileScope =
      'https://substrate.office.com/User-Internal.ReadWrite';

  static const graphMeBetaEndpoint = 'https://graph.microsoft.com/beta/me';
  static const graphMeV1Endpoint = 'https://graph.microsoft.com/v1.0/me';
  static const graphPhotoBetaEndpoint =
      r'https://graph.microsoft.com/beta/me/photo/$value';
  static const graphPhotoV1Endpoint =
      r'https://graph.microsoft.com/v1.0/me/photo/$value';
  static const profileEndpoint =
      'https://substrate.office.com/profile/v1.0/me/profile';
  static const autodiscoverEndpoint =
      'https://outlook.office365.com/autodiscover/autodiscover.json/v1.0';
  static const defaultTodoApiBaseUrl =
      'https://substrate.office.com/todob2/api/v1/';
  static const autodiscoverCacheTtl = Duration(hours: 12);

  /// 32-hex correlation/UAID format matching `MsaSignInActivity.U0()`.
  static String generateMsaUaid() => generateUuidV4().replaceAll('-', '');

  static String avatarUrlForCid(String cid) {
    var normalized = normalizeCid(cid);
    if (normalized.toLowerCase().startsWith('0x')) {
      normalized = normalized.substring(2);
    }
    return 'https://storage.live.com/users/0x$normalized/myprofile/expressionprofile/profilephoto:UserTileMedium/avatar?ck=1&ex=1&fofoff=1';
  }

  /// Strips an optional `CID:` prefix from [rawCid].
  static String normalizeCid(String rawCid) {
    final trimmed = rawCid.trim();
    if (trimmed.toUpperCase().startsWith('CID:')) {
      return trimmed.substring(4).trim();
    }
    return trimmed;
  }

  /// Formats `CID:<cid>` for `X-AnchorMailbox` and autodiscover lookups.
  static String anchorMailboxForCid(String cid) {
    return 'CID:${normalizeCid(cid)}';
  }
}

/// OAuth2 token bundle persisted per personal Microsoft account.
class MicrosoftAuthTokens {
  const MicrosoftAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  /// Personal MSA `user_id` (CID) returned by `login.live.com/oauth20_token.srf`.
  final String userId;

  bool get isExpired {
    return DateTime.now().toUtc().isAfter(
      expiresAt.toUtc().subtract(const Duration(minutes: 5)),
    );
  }

  MicrosoftAuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? userId,
  }) {
    return MicrosoftAuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      userId: userId ?? this.userId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'userId': userId,
    };
  }

  factory MicrosoftAuthTokens.fromJson(Map<String, dynamic> json) {
    return MicrosoftAuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      userId: json['userId'] as String? ?? '',
    );
  }
}

/// User identity fetched from Substrate `/profile/v1.0/me/profile` + avatar.
class MicrosoftUserProfile {
  const MicrosoftUserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.avatarBase64,
  });

  /// Canonical MSA CID (`tokens.userId`).
  final String id;
  final String displayName;
  final String email;
  final String? avatarBase64;
}

/// Complete personal MSA sign-in payload passed to [AccountNotifier.signInMicrosoft].
class MicrosoftSignInResult {
  const MicrosoftSignInResult({required this.profile, required this.tokens});

  final MicrosoftUserProfile profile;
  final MicrosoftAuthTokens tokens;
}

AppError _mapAuthError(Object error) => switch (error) {
  AppError() => error,
  http.ClientException() => AppError.network(
    message: 'The network request failed: ${error.message}',
  ),
  TimeoutException() => const AppError.network(
    message: 'The request timed out. Please try again.',
  ),
  _ => AppError.auth(message: error.toString()),
};

Future<AppResult<T>> _guardAuthCall<T extends Object>(
  FutureOr<T> Function() call, {
  String? operation,
}) => guardAsync(call, operation: operation, onError: _mapAuthError);

/// Interface for personal MSA OAuth2, Substrate profile & To Do autodiscovery.
abstract class MicrosoftAuthClient {
  /// Builds the MSA OAuth2 authorize URL for WebView or system browser sign-in.
  String buildAuthorizeUrl({String? loginHint, String? uaid});

  /// Extracts an authorization `code` from a pasted `oauth20_desktop.srf` URL
  /// or directly pasted code string.
  AppResult<String> extractAuthorizationCode(String rawInput);

  /// Exchanges an authorization [code] for To Do Substrate tokens (`user_id` = CID).
  AsyncAppResult<MicrosoftAuthTokens> exchangeAuthorizationCode({
    required String code,
    String? uaid,
  });

  /// Refreshes tokens using [refreshToken], optionally requesting [scope].
  AsyncAppResult<MicrosoftAuthTokens> refreshTokens({
    required String refreshToken,
    String? scope,
    String? fallbackUserId,
    String? uaid,
  });

  /// Completes sign-in from an authorization [code]: exchanges tokens and does
  /// a best-effort profile + avatar fetch without failing sign-in if profile fails.
  AsyncAppResult<MicrosoftSignInResult> completeSignInWithCode({
    required String code,
    String? loginHint,
    String? uaid,
  });

  /// Fetches profile + avatar from Substrate `/profile/v1.0/me/profile`.
  /// Non-fatal fallback returns synthetic profile containing [cid].
  Future<MicrosoftUserProfile> fetchUserProfile({
    required String cid,
    required String refreshToken,
    String? fallbackEmail,
  });

  /// Queries Outlook autodiscovery for the user's Substrate To Do `/api/v1/` base URL.
  Future<String> discoverTodoEndpoint(String cid);

  /// Ensures tokens in [storage] for [accountId] are valid, refreshing if expired.
  AsyncAppResult<MicrosoftAuthTokens> ensureValidTokens({
    required String accountId,
    required AuthTokenStorage storage,
    String? fallbackCid,
  });
}

class HttpMicrosoftAuthClient implements MicrosoftAuthClient {
  HttpMicrosoftAuthClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  static String _resolveUaid(String? uaid) =>
      (uaid != null && uaid.isNotEmpty) ? uaid : MsaAuthConfig.generateMsaUaid();

  @override
  String buildAuthorizeUrl({String? loginHint, String? uaid}) {
    final trimmedHint = loginHint?.trim();
    final params = <String, String>{
      'lw': '1',
      'client_id': MsaAuthConfig.clientId,
      'scope': MsaAuthConfig.todoScope,
      'response_type': 'code',
      'redirect_uri': MsaAuthConfig.redirectUri,
      'state': MsaAuthConfig.state,
      'display': 'touch',
      'noauthcancel': '1',
      'uaid': _resolveUaid(uaid),
      if (trimmedHint != null && trimmedHint.isNotEmpty)
        'username': trimmedHint,
    };
    return Uri.parse(MsaAuthConfig.authorizeEndpoint)
        .replace(queryParameters: params)
        .toString();
  }

  @override
  AppResult<String> extractAuthorizationCode(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const Failure(
        AppError.validation(
          message: 'Authorization code cannot be empty.',
          field: 'code',
        ),
      );
    }

    if (trimmed.contains('://') || trimmed.startsWith('?')) {
      final uri = Uri.tryParse(
        trimmed.startsWith('?') ? 'https://localhost/$trimmed' : trimmed,
      );
      if (uri != null) {
        final params = <String, String>{...uri.queryParameters};
        if (uri.fragment.isNotEmpty && uri.fragment.contains('=')) {
          try {
            params.addAll(Uri.splitQueryString(uri.fragment));
          } on FormatException catch (_) {}
        }
        final error = params['error'];
        if (error != null && error.isNotEmpty) {
          final desc = params['error_description'];
          return Failure(
            AppError.auth(
              message: desc != null && desc.isNotEmpty ? desc : error,
              code: error,
            ),
          );
        }
        final state = params['state'];
        if (state != null && state.isNotEmpty && state != MsaAuthConfig.state) {
          return const Failure(
            AppError.auth(
              message: 'OAuth state mismatch in redirect URL.',
              code: 'invalid_state',
            ),
          );
        }
        final code = params['code']?.trim();
        if (code != null && code.isNotEmpty) {
          return Success(code);
        }
      }
      return const Failure(
        AppError.validation(
          message: 'Redirect URL does not contain an authorization code.',
          field: 'code',
        ),
      );
    }

    if (trimmed.contains(RegExp(r'\s'))) {
      return const Failure(
        AppError.validation(
          message: 'Invalid authorization code format.',
          field: 'code',
        ),
      );
    }
    return Success(trimmed);
  }

  @override
  AsyncAppResult<MicrosoftAuthTokens> exchangeAuthorizationCode({
    required String code,
    String? uaid,
  }) => _postTokenRequest({
    'client_id': MsaAuthConfig.clientId,
    'client_secret': MsaAuthConfig.clientSecret,
    'code': code.trim(),
    'redirect_uri': MsaAuthConfig.redirectUri,
    'grant_type': 'authorization_code',
    'uaid': _resolveUaid(uaid),
  }, operation: 'exchangeAuthorizationCode');

  @override
  AsyncAppResult<MicrosoftAuthTokens> refreshTokens({
    required String refreshToken,
    String? scope,
    String? fallbackUserId,
    String? uaid,
  }) => _postTokenRequest(
    {
      'client_id': MsaAuthConfig.clientId,
      'client_secret': MsaAuthConfig.clientSecret,
      'scope': scope ?? MsaAuthConfig.todoScope,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
      'uaid': _resolveUaid(uaid),
    },
    fallbackRefreshToken: refreshToken,
    fallbackUserId: fallbackUserId,
    operation: 'refreshTokens',
  );

  AsyncAppResult<MicrosoftAuthTokens> _postTokenRequest(
    Map<String, String> body, {
    String? fallbackRefreshToken,
    String? fallbackUserId,
    required String operation,
  }) {
    return _guardAuthCall(() async {
      final response = await _http
          .post(
            Uri.parse(MsaAuthConfig.tokenEndpoint),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      final decoded = _decodeJsonMap(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'] as String?;
        final desc = decoded['error_description'] as String?;
        final requiresReauth =
            error == 'invalid_grant' ||
            error == 'interaction_required' ||
            error == 'bad_refresh_token' ||
            response.statusCode == 401;
        throw AppError.auth(
          message:
              desc ?? error ?? 'Token request failed (${response.statusCode})',
          code: error,
          requiresReauth: requiresReauth,
        );
      }

      final accessToken = decoded['access_token'] as String?;
      final refreshToken =
          (decoded['refresh_token'] as String?) ?? fallbackRefreshToken ?? '';
      final rawUserId = (decoded['user_id'] as String?) ?? fallbackUserId ?? '';
      final expiresIn = (decoded['expires_in'] as num?)?.toInt() ?? 3600;

      if (accessToken == null || accessToken.isEmpty) {
        throw const AppError.auth(
          message: 'Token response missing access_token',
        );
      }
      final normalizedCid = MsaAuthConfig.normalizeCid(rawUserId);
      if (normalizedCid.isEmpty) {
        throw const AppError.auth(
          message: 'Token response missing MSA user_id (CID)',
        );
      }

      return MicrosoftAuthTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
        userId: normalizedCid,
      );
    }, operation: operation);
  }

  @override
  AsyncAppResult<MicrosoftSignInResult> completeSignInWithCode({
    required String code,
    String? loginHint,
    String? uaid,
  }) {
    final effectiveUaid = _resolveUaid(uaid);
    return exchangeAuthorizationCode(code: code, uaid: effectiveUaid).flatMap((
      initialTokens,
    ) async {
      final resolved = await _resolveProfileAndAvatar(
        cid: initialTokens.userId,
        refreshToken: initialTokens.refreshToken,
        fallbackEmail: loginHint,
        uaid: effectiveUaid,
      );
      final tokens =
          (resolved.latestRefreshToken != null &&
              resolved.latestRefreshToken!.isNotEmpty)
          ? initialTokens.copyWith(refreshToken: resolved.latestRefreshToken)
          : initialTokens;
      return Success(
        MicrosoftSignInResult(profile: resolved.profile, tokens: tokens),
      );
    });
  }

  @override
  Future<MicrosoftUserProfile> fetchUserProfile({
    required String cid,
    required String refreshToken,
    String? fallbackEmail,
  }) async {
    final resolved = await _resolveProfileAndAvatar(
      cid: MsaAuthConfig.normalizeCid(cid),
      refreshToken: refreshToken,
      fallbackEmail: fallbackEmail,
      uaid: MsaAuthConfig.generateMsaUaid(),
    );
    return resolved.profile;
  }

  Future<({MicrosoftUserProfile profile, String? latestRefreshToken})>
  _resolveProfileAndAvatar({
    required String cid,
    required String refreshToken,
    String? fallbackEmail,
    required String uaid,
  }) async {
    final normalizedCid = MsaAuthConfig.normalizeCid(cid);
    final fallback = fallbackEmail?.trim() ?? '';
    String? resolvedName;
    String? resolvedEmail = fallback.isNotEmpty ? fallback : null;
    String? avatarBase64;
    var activeRefreshToken = refreshToken;
    String? rotatedRefreshToken;

    Future<MicrosoftAuthTokens?> refreshForScope(String scope) async {
      if (activeRefreshToken.isEmpty) return null;
      final tokens = (await refreshTokens(
        refreshToken: activeRefreshToken,
        scope: scope,
        fallbackUserId: normalizedCid,
        uaid: uaid,
      )).getOrNull();
      if (tokens != null && tokens.refreshToken.isNotEmpty) {
        activeRefreshToken = tokens.refreshToken;
        rotatedRefreshToken = tokens.refreshToken;
      }
      return tokens;
    }

    Map<String, String> authHeaders(String accessToken) => {
      'Authorization': 'Bearer $accessToken',
      'X-AnchorMailbox': MsaAuthConfig.anchorMailboxForCid(normalizedCid),
      'Accept': 'application/json',
    };

    // 1. Primary path: Graph `User.Read` -> `/beta/me` -> `/v1.0/me` + `/photo/$value`.
    final graphTokens = await refreshForScope(MsaAuthConfig.graphProfileScope);
    if (graphTokens != null) {
      final headers = authHeaders(graphTokens.accessToken);
      for (final endpoint in const [
        MsaAuthConfig.graphMeBetaEndpoint,
        MsaAuthConfig.graphMeV1Endpoint,
      ]) {
        final parsed = await _tryFetchProfileJson(
          endpoint: endpoint,
          headers: headers,
        );
        if (parsed == null) continue;
        resolvedName ??= extractMsaProfileDisplayName(parsed);
        final candidateEmail = extractMsaProfileEmail(parsed);
        if (candidateEmail != null && candidateEmail.isNotEmpty) {
          resolvedEmail = candidateEmail;
        }
        if (resolvedName != null && resolvedEmail != null) break;
      }

      final photoAuth = {'Authorization': 'Bearer ${graphTokens.accessToken}'};
      avatarBase64 ??= await _tryFetchImageBase64(
        MsaAuthConfig.graphPhotoBetaEndpoint,
        headers: photoAuth,
      );
      avatarBase64 ??= await _tryFetchImageBase64(
        MsaAuthConfig.graphPhotoV1Endpoint,
        headers: photoAuth,
      );
    }

    // 2. Fallback path: Substrate `User-Internal.ReadWrite` -> `/profile/v1.0/me/profile`.
    if (resolvedName == null || resolvedEmail == null) {
      final subTokens = await refreshForScope(MsaAuthConfig.profileScope);
      if (subTokens != null) {
        final parsed = await _tryFetchProfileJson(
          endpoint: MsaAuthConfig.profileEndpoint,
          headers: authHeaders(subTokens.accessToken),
        );
        if (parsed != null) {
          resolvedName ??= extractMsaProfileDisplayName(parsed);
          resolvedEmail ??= extractMsaProfileEmail(parsed);
        }
      }
    }

    // 3. Avatar fallback: unauthenticated Windows Live public tile URL.
    avatarBase64 ??= await _tryFetchImageBase64(
      MsaAuthConfig.avatarUrlForCid(normalizedCid),
    );

    final effectiveEmail = resolvedEmail ?? '';
    final effectiveDisplayName =
        resolvedName ??
        (effectiveEmail.isNotEmpty ? effectiveEmail : 'Microsoft Account');

    return (
      profile: MicrosoftUserProfile(
        id: normalizedCid,
        displayName: effectiveDisplayName,
        email: effectiveEmail,
        avatarBase64: avatarBase64,
      ),
      latestRefreshToken: rotatedRefreshToken,
    );
  }

  Future<Map<String, dynamic>?> _tryFetchProfileJson({
    required String endpoint,
    required Map<String, String> headers,
  }) async {
    try {
      final response = await _http
          .get(Uri.parse(endpoint), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final map = _decodeJsonMap(response.body);
        if (map.isNotEmpty) return map;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _tryFetchImageBase64(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final resp = await _http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 6));
      if (isValidImageResponse(resp)) {
        return base64Encode(resp.bodyBytes);
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<String> discoverTodoEndpoint(String cid) async {
    final normalizedCid = MsaAuthConfig.normalizeCid(cid);
    final url =
        '${MsaAuthConfig.autodiscoverEndpoint}/'
        'CID:${Uri.encodeComponent(normalizedCid)}?Protocol=todo';
    try {
      final response = await _http
          .get(Uri.parse(url), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = _decodeJsonMap(response.body);
        final rawUrl = (json['Url'] ?? json['url']) as String?;
        if (rawUrl != null && rawUrl.trim().isNotEmpty) {
          return normalizeTodoApiBaseUrl(rawUrl);
        }
      }
    } catch (_) {
      // Fallback per AutoDiscovery specification.
    }
    return MsaAuthConfig.defaultTodoApiBaseUrl;
  }

  static String normalizeTodoApiBaseUrl(String rawUrl) {
    var trimmed = rawUrl.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.toLowerCase().endsWith('/api/v1')) {
      return '$trimmed/';
    }
    return '$trimmed/api/v1/';
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
        AppError.auth(
          message: 'Not signed in to Microsoft account.',
          code: 'no_tokens',
          requiresReauth: true,
        ),
      );
    }
    if (!stored.isExpired && stored.accessToken.isNotEmpty) {
      return Success(stored);
    }
    if (stored.refreshToken.isEmpty) {
      return const Failure(
        AppError.auth(
          message: 'Refresh token unavailable; please sign in again.',
          code: 'no_refresh_token',
          requiresReauth: true,
        ),
      );
    }
    final refreshedResult = await refreshTokens(
      refreshToken: stored.refreshToken,
      fallbackUserId: stored.userId.isNotEmpty ? stored.userId : fallbackCid,
    );
    if (refreshedResult.isSuccess()) {
      await storage.saveTokens(accountId, refreshedResult.getOrThrow());
    }
    return refreshedResult;
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException catch (_) {}
    return const {};
  }
}
