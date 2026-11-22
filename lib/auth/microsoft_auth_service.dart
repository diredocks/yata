import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../sync/todo_wire_codecs.dart';

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
  const MicrosoftSignInResult({
    required this.profile,
    required this.tokens,
  });

  final MicrosoftUserProfile profile;
  final MicrosoftAuthTokens tokens;
}

class MicrosoftAuthException implements Exception {
  const MicrosoftAuthException(
    this.message, {
    this.code,
    this.requiresReauth = false,
  });

  final String message;
  final String? code;
  final bool requiresReauth;

  @override
  String toString() =>
      code == null ? message : 'MicrosoftAuthException($code): $message';
}

/// Interface for personal MSA OAuth2, Substrate profile & To Do autodiscovery.
abstract class MicrosoftAuthClient {
  /// Builds the MSA OAuth2 authorize URL for WebView or system browser sign-in.
  String buildAuthorizeUrl({String? loginHint, String? uaid});

  /// Extracts an authorization `code` from a pasted `oauth20_desktop.srf` URL
  /// or directly pasted code string.
  String? extractAuthorizationCode(String rawInput);

  /// Exchanges an authorization [code] for To Do Substrate tokens (`user_id` = CID).
  Future<MicrosoftAuthTokens> exchangeAuthorizationCode({
    required String code,
    String? uaid,
  });

  /// Refreshes tokens using [refreshToken], optionally requesting [scope].
  Future<MicrosoftAuthTokens> refreshTokens({
    required String refreshToken,
    String? scope,
    String? fallbackUserId,
    String? uaid,
  });

  /// Completes sign-in from an authorization [code]: exchanges tokens and does
  /// a best-effort profile + avatar fetch without failing sign-in if profile fails.
  Future<MicrosoftSignInResult> completeSignInWithCode({
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
  Future<MicrosoftAuthTokens> ensureValidTokens({
    required String accountId,
    required AuthTokenStorage storage,
    String? fallbackCid,
  });
}

class HttpMicrosoftAuthClient implements MicrosoftAuthClient {
  HttpMicrosoftAuthClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  @override
  String buildAuthorizeUrl({String? loginHint, String? uaid}) {
    final params = <String, String>{
      'lw': '1',
      'client_id': MsaAuthConfig.clientId,
      'scope': MsaAuthConfig.todoScope,
      'response_type': 'code',
      'redirect_uri': MsaAuthConfig.redirectUri,
      'state': MsaAuthConfig.state,
      'display': 'touch',
      'noauthcancel': '1',
      'uaid': (uaid != null && uaid.isNotEmpty)
          ? uaid
          : MsaAuthConfig.generateMsaUaid(),
    };
    final trimmedHint = loginHint?.trim();
    if (trimmedHint != null && trimmedHint.isNotEmpty) {
      params['username'] = trimmedHint;
    }
    return Uri.parse(MsaAuthConfig.authorizeEndpoint)
        .replace(queryParameters: params)
        .toString();
  }

  @override
  String? extractAuthorizationCode(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

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
          throw MicrosoftAuthException(
            desc != null && desc.isNotEmpty ? desc : error,
            code: error,
          );
        }
        final state = params['state'];
        if (state != null &&
            state.isNotEmpty &&
            state != MsaAuthConfig.state) {
          throw const MicrosoftAuthException(
            'OAuth state mismatch in redirect URL.',
            code: 'invalid_state',
          );
        }
        final code = params['code']?.trim();
        if (code != null && code.isNotEmpty) {
          return code;
        }
      }
      return null;
    }

    // Raw code pasted directly.
    if (trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    return trimmed;
  }

  @override
  Future<MicrosoftAuthTokens> exchangeAuthorizationCode({
    required String code,
    String? uaid,
  }) async {
    return _postTokenRequest({
      'client_id': MsaAuthConfig.clientId,
      'client_secret': MsaAuthConfig.clientSecret,
      'code': code.trim(),
      'redirect_uri': MsaAuthConfig.redirectUri,
      'grant_type': 'authorization_code',
      'uaid': (uaid != null && uaid.isNotEmpty)
          ? uaid
          : MsaAuthConfig.generateMsaUaid(),
    });
  }

  @override
  Future<MicrosoftAuthTokens> refreshTokens({
    required String refreshToken,
    String? scope,
    String? fallbackUserId,
    String? uaid,
  }) async {
    return _postTokenRequest(
      {
        'client_id': MsaAuthConfig.clientId,
        'client_secret': MsaAuthConfig.clientSecret,
        'scope': scope ?? MsaAuthConfig.todoScope,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
        'uaid': (uaid != null && uaid.isNotEmpty)
            ? uaid
            : MsaAuthConfig.generateMsaUaid(),
      },
      fallbackRefreshToken: refreshToken,
      fallbackUserId: fallbackUserId,
    );
  }

  Future<MicrosoftAuthTokens> _postTokenRequest(
    Map<String, String> body, {
    String? fallbackRefreshToken,
    String? fallbackUserId,
  }) async {
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
      final requiresReauth = error == 'invalid_grant' ||
          error == 'interaction_required' ||
          error == 'bad_refresh_token' ||
          response.statusCode == 401;
      throw MicrosoftAuthException(
        desc ?? error ?? 'Token request failed (${response.statusCode})',
        code: error,
        requiresReauth: requiresReauth,
      );
    }

    final accessToken = decoded['access_token'] as String?;
    final refreshToken =
        (decoded['refresh_token'] as String?) ?? fallbackRefreshToken ?? '';
    final rawUserId =
        (decoded['user_id'] as String?) ?? fallbackUserId ?? '';
    final expiresIn = (decoded['expires_in'] as num?)?.toInt() ?? 3600;

    if (accessToken == null || accessToken.isEmpty) {
      throw const MicrosoftAuthException('Token response missing access_token');
    }
    final normalizedCid = MsaAuthConfig.normalizeCid(rawUserId);
    if (normalizedCid.isEmpty) {
      throw const MicrosoftAuthException(
        'Token response missing MSA user_id (CID)',
      );
    }

    return MicrosoftAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      userId: normalizedCid,
    );
  }

  @override
  Future<MicrosoftSignInResult> completeSignInWithCode({
    required String code,
    String? loginHint,
    String? uaid,
  }) async {
    final effectiveUaid = (uaid != null && uaid.isNotEmpty)
        ? uaid
        : MsaAuthConfig.generateMsaUaid();
    var tokens = await exchangeAuthorizationCode(
      code: code,
      uaid: effectiveUaid,
    );
    final resolved = await _resolveProfileAndAvatar(
      cid: tokens.userId,
      refreshToken: tokens.refreshToken,
      fallbackEmail: loginHint,
      uaid: effectiveUaid,
    );
    if (resolved.latestRefreshToken != null &&
        resolved.latestRefreshToken!.isNotEmpty) {
      tokens = tokens.copyWith(refreshToken: resolved.latestRefreshToken);
    }
    return MicrosoftSignInResult(
      profile: resolved.profile,
      tokens: tokens,
    );
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

    // 1. Primary path matching MS To Do 2.178 default (`yp/n0.f0 == true`):
    //    Graph `User.Read` -> `/beta/me` -> `/v1.0/me` + `/photo/$value`.
    if (activeRefreshToken.isNotEmpty) {
      try {
        final graphTokens = await refreshTokens(
          refreshToken: activeRefreshToken,
          scope: MsaAuthConfig.graphProfileScope,
          fallbackUserId: normalizedCid,
          uaid: uaid,
        );
        if (graphTokens.refreshToken.isNotEmpty) {
          activeRefreshToken = graphTokens.refreshToken;
          rotatedRefreshToken = graphTokens.refreshToken;
        }
        final graphHeaders = {
          'Authorization': 'Bearer ${graphTokens.accessToken}',
          'X-AnchorMailbox': MsaAuthConfig.anchorMailboxForCid(normalizedCid),
          'Accept': 'application/json',
        };

        for (final endpoint in const [
          MsaAuthConfig.graphMeBetaEndpoint,
          MsaAuthConfig.graphMeV1Endpoint,
        ]) {
          final parsed = await _tryFetchProfileJson(
            endpoint: endpoint,
            headers: graphHeaders,
          );
          if (parsed == null) continue;
          resolvedName ??= _extractProfileDisplayName(parsed);
          final candidateEmail = _extractProfileEmail(parsed);
          if (candidateEmail != null && candidateEmail.isNotEmpty) {
            resolvedEmail = candidateEmail;
          }
          if (resolvedName != null && resolvedEmail != null) break;
        }

        avatarBase64 ??= await _tryFetchImageBase64(
          MsaAuthConfig.graphPhotoBetaEndpoint,
          headers: {'Authorization': 'Bearer ${graphTokens.accessToken}'},
        );
        avatarBase64 ??= await _tryFetchImageBase64(
          MsaAuthConfig.graphPhotoV1Endpoint,
          headers: {'Authorization': 'Bearer ${graphTokens.accessToken}'},
        );
      } catch (_) {
        // Non-fatal: fall through to Substrate profile & Live avatar fallback.
      }
    }

    // 2. Fallback path: Substrate `User-Internal.ReadWrite` -> `/profile/v1.0/me/profile`.
    if ((resolvedName == null || resolvedEmail == null) &&
        activeRefreshToken.isNotEmpty) {
      try {
        final subTokens = await refreshTokens(
          refreshToken: activeRefreshToken,
          scope: MsaAuthConfig.profileScope,
          fallbackUserId: normalizedCid,
          uaid: uaid,
        );
        if (subTokens.refreshToken.isNotEmpty) {
          activeRefreshToken = subTokens.refreshToken;
          rotatedRefreshToken = subTokens.refreshToken;
        }
        final parsed = await _tryFetchProfileJson(
          endpoint: MsaAuthConfig.profileEndpoint,
          headers: {
            'Authorization': 'Bearer ${subTokens.accessToken}',
            'X-AnchorMailbox': MsaAuthConfig.anchorMailboxForCid(normalizedCid),
            'Accept': 'application/json',
          },
        );
        if (parsed != null) {
          resolvedName ??= _extractProfileDisplayName(parsed);
          final candidateEmail = _extractProfileEmail(parsed);
          if (candidateEmail != null && candidateEmail.isNotEmpty) {
            resolvedEmail ??= candidateEmail;
          }
        }
      } catch (_) {
        // Non-fatal per UserProfileProvider.java.
      }
    }

    // 3. Avatar fallback: unauthenticated Windows Live public tile URL.
    avatarBase64 ??= await _tryFetchImageBase64(
      MsaAuthConfig.avatarUrlForCid(normalizedCid),
    );

    final effectiveEmail = resolvedEmail ?? '';
    final effectiveDisplayName = resolvedName ??
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

  String? _extractProfileDisplayName(Map<String, dynamic> json) {
    final direct =
        (json['displayName'] ?? json['DisplayName']) as String?;
    if (direct != null &&
        direct.trim().isNotEmpty &&
        direct.trim().toLowerCase() != 'null') {
      return direct.trim();
    }

    final topGiven =
        ((json['givenName'] ?? json['GivenName']) as String?)?.trim() ?? '';
    final topFamily =
        ((json['surname'] ?? json['Surname'] ?? json['lastName']) as String?)
                ?.trim() ??
            '';
    final topJoined = '$topGiven $topFamily'.trim();
    if (topJoined.isNotEmpty) return topJoined;

    final names = (json['names'] ?? json['Names']) as List<dynamic>?;
    if (names != null && names.isNotEmpty && names.first is Map) {
      final first = Map<String, dynamic>.from(names.first as Map);
      final formatted =
          (first['displayName'] ?? first['DisplayName']) as String?;
      if (formatted != null &&
          formatted.trim().isNotEmpty &&
          formatted.trim().toLowerCase() != 'null') {
        return formatted.trim();
      }
      final given = ((first['givenName'] ?? first['First']) as String?)?.trim() ?? '';
      final family = ((first['lastName'] ?? first['surname'] ?? first['Last'])
                  as String?)
              ?.trim() ??
          '';
      final joined = '$given $family'.trim();
      if (joined.isNotEmpty) return joined;
    }
    return null;
  }

  String? _extractProfileEmail(Map<String, dynamic> json) {
    for (final key in const [
      'mail',
      'Mail',
      'userPrincipalName',
      'UserPrincipalName',
      'EmailAddress',
      'email',
    ]) {
      final val = json[key] as String?;
      if (val != null &&
          val.trim().isNotEmpty &&
          val.trim().toLowerCase() != 'null') {
        return val.trim();
      }
    }
    final accounts = (json['accounts'] ?? json['Accounts']) as List<dynamic>?;
    if (accounts != null && accounts.isNotEmpty && accounts.first is Map) {
      final first = Map<String, dynamic>.from(accounts.first as Map);
      for (final key in const [
        'passportMemberName',
        'userPrincipalName',
        'emailAddress',
        'EmailAddress',
      ]) {
        final val = first[key] as String?;
        if (val != null &&
            val.trim().isNotEmpty &&
            val.trim().toLowerCase() != 'null') {
          return val.trim();
        }
      }
    }
    for (final listKey in const ['EmailAddresses', 'Emails', 'emails']) {
      final list = json[listKey] as List<dynamic>?;
      if (list != null && list.isNotEmpty) {
        final item = list.first;
        if (item is Map) {
          final addr =
              (item['Address'] ?? item['address'] ?? item['EmailAddress'])
                  as String?;
          if (addr != null &&
              addr.trim().isNotEmpty &&
              addr.trim().toLowerCase() != 'null') {
            return addr.trim();
          }
        } else if (item is String &&
            item.trim().isNotEmpty &&
            item.trim().toLowerCase() != 'null') {
          return item.trim();
        }
      }
    }
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
      if (_isValidImageResponse(resp)) {
        return base64Encode(resp.bodyBytes);
      }
    } catch (_) {}
    return null;
  }

  static bool _isValidImageResponse(http.Response resp) {
    if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return false;
    final contentType = resp.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.startsWith('image/')) return true;
    final bytes = resp.bodyBytes;
    // JPEG (FF D8 FF)
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    // PNG (89 50 4E 47)
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // GIF ("GIF8")
    if (bytes.length >= 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }
    // WebP ("RIFF....WEBP")
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  @override
  Future<String> discoverTodoEndpoint(String cid) async {
    final normalizedCid = MsaAuthConfig.normalizeCid(cid);
    final url = '${MsaAuthConfig.autodiscoverEndpoint}/'
        'CID:${Uri.encodeComponent(normalizedCid)}?Protocol=todo';
    try {
      final response = await _http
          .get(
            Uri.parse(url),
            headers: const {'Accept': 'application/json'},
          )
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
  Future<MicrosoftAuthTokens> ensureValidTokens({
    required String accountId,
    required AuthTokenStorage storage,
    String? fallbackCid,
  }) async {
    final stored = await storage.loadTokens(accountId);
    if (stored == null) {
      throw const MicrosoftAuthException(
        'Not signed in to Microsoft account.',
        code: 'no_tokens',
        requiresReauth: true,
      );
    }
    if (!stored.isExpired && stored.accessToken.isNotEmpty) {
      return stored;
    }
    if (stored.refreshToken.isEmpty) {
      throw const MicrosoftAuthException(
        'Refresh token unavailable; please sign in again.',
        code: 'no_refresh_token',
        requiresReauth: true,
      );
    }
    final refreshed = await refreshTokens(
      refreshToken: stored.refreshToken,
      fallbackUserId:
          stored.userId.isNotEmpty ? stored.userId : fallbackCid,
    );
    await storage.saveTokens(accountId, refreshed);
    return refreshed;
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

/// Persists personal MSA OAuth2 tokens in SharedPreferences scoped by account.
class AuthTokenStorage {
  const AuthTokenStorage(this._prefs);

  final SharedPreferences _prefs;

  static String _keyFor(String accountId) => 'yata.msa.tokens.$accountId';

  Future<void> saveTokens(
    String accountId,
    MicrosoftAuthTokens tokens,
  ) async {
    await _prefs.setString(_keyFor(accountId), jsonEncode(tokens.toJson()));
  }

  Future<MicrosoftAuthTokens?> loadTokens(String accountId) async {
    final raw = _prefs.getString(_keyFor(accountId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return MicrosoftAuthTokens.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearTokens(String accountId) async {
    await _prefs.remove(_keyFor(accountId));
  }
}
