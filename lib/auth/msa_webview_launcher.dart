import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result returned from an in-app interactive MSA OAuth sign-in flow.
class MsaInteractiveSignInResult {
  const MsaInteractiveSignInResult({
    this.code,
    this.redirectUrl,
    this.cancelled = false,
    this.error,
  });

  const MsaInteractiveSignInResult.success({
    required String this.code,
    this.redirectUrl,
  })  : cancelled = false,
        error = null;

  const MsaInteractiveSignInResult.cancelled()
      : code = null,
        redirectUrl = null,
        cancelled = true,
        error = null;

  const MsaInteractiveSignInResult.failure(String this.error)
      : code = null,
        redirectUrl = null,
        cancelled = false;

  final String? code;
  final String? redirectUrl;
  final bool cancelled;
  final String? error;
}

/// Abstracts launching an in-app WebView MSA sign-in page (Android) vs falling
/// back to external browser + code paste on desktop platforms.
abstract class MsaInteractiveSignInClient {
  Future<MsaInteractiveSignInResult?> signIn({
    required String authorizeUrl,
    required String redirectUri,
    bool clearCookies = true,
  });
}

class PlatformMsaInteractiveSignInClient implements MsaInteractiveSignInClient {
  static const MethodChannel _channel = MethodChannel(
    'top.clickfling.yata/msa_auth',
  );

  @override
  Future<MsaInteractiveSignInResult?> signIn({
    required String authorizeUrl,
    required String redirectUri,
    bool clearCookies = true,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'signIn',
        {
          'authorizeUrl': authorizeUrl,
          'redirectUri': redirectUri,
          'clearCookies': clearCookies,
        },
      );
      if (result == null) {
        return const MsaInteractiveSignInResult.cancelled();
      }
      final cancelled = result['cancelled'] as bool? ?? false;
      if (cancelled) {
        final error = result['error'] as String?;
        if (error != null && error.isNotEmpty) {
          return MsaInteractiveSignInResult.failure(error);
        }
        return const MsaInteractiveSignInResult.cancelled();
      }
      final code = result['code'] as String?;
      final redirectUrl = result['redirectUrl'] as String?;
      if (code != null && code.isNotEmpty) {
        return MsaInteractiveSignInResult.success(
          code: code,
          redirectUrl: redirectUrl,
        );
      }
      final error = result['error'] as String?;
      if (error != null && error.isNotEmpty) {
        return MsaInteractiveSignInResult.failure(error);
      }
      return const MsaInteractiveSignInResult.cancelled();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELLED') {
        return const MsaInteractiveSignInResult.cancelled();
      }
      return MsaInteractiveSignInResult.failure(
        e.message ?? e.code,
      );
    }
  }
}
