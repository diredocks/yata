import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import 'microsoft_auth_service.dart';

final _log = appLogFor('AuthTokenStorage');

/// Persists personal MSA OAuth2 tokens in encrypted OS storage via
/// [FlutterSecureStorage], with fallback in headless test environments.
class AuthTokenStorage {
  const AuthTokenStorage(this._prefs, {this.secureStorage});

  final SharedPreferences _prefs;
  final FlutterSecureStorage? secureStorage;

  static const FlutterSecureStorage _defaultSecureStorage =
      FlutterSecureStorage();

  static String _keyFor(String accountId) => 'yata.msa.tokens.$accountId';

  FlutterSecureStorage? get _effectiveSecureStorage {
    if (secureStorage != null) return secureStorage;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    return _defaultSecureStorage;
  }

  Future<void> saveTokens(String accountId, MicrosoftAuthTokens tokens) async {
    final key = _keyFor(accountId);
    final encoded = jsonEncode(tokens.toJson());
    final secure = _effectiveSecureStorage;
    if (secure != null) {
      await secure.write(key: key, value: encoded);
    } else {
      await _prefs.setString(key, encoded);
    }
  }

  Future<MicrosoftAuthTokens?> loadTokens(String accountId) async {
    final key = _keyFor(accountId);
    final secure = _effectiveSecureStorage;
    final raw = secure != null
        ? await secure.read(key: key)
        : _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return MicrosoftAuthTokens.fromJson(map);
    } catch (error) {
      _log.warning('discarding unreadable tokens for $accountId', error);
      return null;
    }
  }

  Future<void> clearTokens(String accountId) async {
    final key = _keyFor(accountId);
    final secure = _effectiveSecureStorage;
    if (secure != null) {
      await secure.delete(key: key);
    } else {
      await _prefs.remove(key);
    }
  }
}
