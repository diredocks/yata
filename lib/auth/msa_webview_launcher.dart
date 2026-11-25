import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_all/webview_all.dart';

import '../core/logging/app_logger.dart';

final _log = appLogFor('MsaWebView');

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
  }) : cancelled = false,
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

/// Abstracts launching an in-app WebView MSA sign-in page (Android & Linux via
/// `webview_all`) vs falling back to external browser + code paste.
abstract class MsaInteractiveSignInClient {
  Future<MsaInteractiveSignInResult?> signIn({
    BuildContext? context,
    required String authorizeUrl,
    required String redirectUri,
    bool clearCookies = true,
  });
}

class PlatformMsaInteractiveSignInClient implements MsaInteractiveSignInClient {
  @override
  Future<MsaInteractiveSignInResult?> signIn({
    BuildContext? context,
    required String authorizeUrl,
    required String redirectUri,
    bool clearCookies = true,
  }) async {
    if (kIsWeb ||
        (!Platform.isAndroid && !Platform.isLinux) ||
        context == null ||
        !context.mounted ||
        WebViewPlatform.instance == null) {
      return null;
    }

    try {
      final result = await Navigator.of(context)
          .push<MsaInteractiveSignInResult>(
            MaterialPageRoute<MsaInteractiveSignInResult>(
              builder: (_) => MsaWebViewSignInScreen(
                authorizeUrl: authorizeUrl,
                redirectUri: redirectUri,
                clearCookies: clearCookies,
              ),
            ),
          );
      return result ?? const MsaInteractiveSignInResult.cancelled();
    } catch (e) {
      return MsaInteractiveSignInResult.failure(e.toString());
    }
  }
}

/// Parses an OAuth redirect URL matching [redirectUri] prefix into an
/// [MsaInteractiveSignInResult], or returns `null` if [url] is not a redirect.
@visibleForTesting
MsaInteractiveSignInResult? parseMsaRedirectUrl({
  required String url,
  required String redirectUri,
}) {
  if (!url.toLowerCase().startsWith(redirectUri.toLowerCase())) {
    return null;
  }

  final uri = Uri.tryParse(url);
  if (uri == null) {
    return const MsaInteractiveSignInResult.cancelled();
  }

  final params = <String, String>{...uri.queryParameters};
  if (uri.fragment.isNotEmpty && uri.fragment.contains('=')) {
    try {
      params.addAll(Uri.splitQueryString(uri.fragment));
    } on FormatException catch (_) {}
  }

  final code = params['code']?.trim();
  if (code != null && code.isNotEmpty) {
    return MsaInteractiveSignInResult.success(code: code, redirectUrl: url);
  }

  final error = params['error']?.trim();
  final errorDesc = params['error_description']?.trim();
  final message = (errorDesc != null && errorDesc.isNotEmpty)
      ? errorDesc
      : ((error != null && error.isNotEmpty) ? error : null);
  if (message != null) {
    return MsaInteractiveSignInResult.failure(message);
  }

  return const MsaInteractiveSignInResult.cancelled();
}

class MsaWebViewSignInScreen extends StatefulWidget {
  const MsaWebViewSignInScreen({
    super.key,
    required this.authorizeUrl,
    required this.redirectUri,
    this.clearCookies = true,
  });

  final String authorizeUrl;
  final String redirectUri;
  final bool clearCookies;

  @override
  State<MsaWebViewSignInScreen> createState() => _MsaWebViewSignInScreenState();
}

class _MsaWebViewSignInScreenState extends State<MsaWebViewSignInScreen> {
  WebViewController? _controller;
  int _progress = 0;
  bool _handledRedirect = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initWebView());
  }

  Future<void> _initWebView() async {
    try {
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted && !_closing) {
              setState(() => _progress = progress);
            }
          },
          onNavigationRequest: (request) {
            if (_maybeHandleRedirect(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            _maybeHandleRedirect(url);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null && url.isNotEmpty) {
              _maybeHandleRedirect(url);
            }
          },
          onPageFinished: (_) {
            if (mounted && !_closing) {
              setState(() => _progress = 100);
            }
          },
          onWebResourceError: (error) {
            _log.fine(
              'WebResourceError (${error.errorCode}): '
              '${error.description} (url=${error.url}, isMainFrame=${error.isForMainFrame})',
            );
          },
        ),
      );

      if (widget.clearCookies) {
        try {
          await WebViewCookieManager().clearCookies();
        } catch (_) {}
      }

      if (!mounted || _closing) {
        unawaited(controller.platform.closeWebViewSession().catchError((_) {}));
        return;
      }

      setState(() => _controller = controller);
      await controller.loadRequest(Uri.parse(widget.authorizeUrl));
    } catch (e) {
      _finishWithResult(MsaInteractiveSignInResult.failure(e.toString()));
    }
  }

  bool _maybeHandleRedirect(String url) {
    final result = parseMsaRedirectUrl(
      url: url,
      redirectUri: widget.redirectUri,
    );
    if (result == null) {
      return false;
    }
    if (_handledRedirect) {
      return true;
    }
    _handledRedirect = true;
    _finishWithResult(result);
    return true;
  }

  void _finishWithResult(MsaInteractiveSignInResult result) {
    if (_closing || !mounted) return;
    _closing = true;
    final controller = _controller;
    if (controller != null) {
      setState(() => _controller = null);
      unawaited(controller.platform.closeWebViewSession().catchError((_) {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<void> _handleBackPressed() async {
    final controller = _controller;
    if (controller != null) {
      try {
        if (await controller.canGoBack()) {
          await controller.goBack();
          return;
        }
      } catch (_) {}
    }
    _finishWithResult(const MsaInteractiveSignInResult.cancelled());
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.platform.closeWebViewSession().catchError((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showWebView = controller != null && !_closing;
    final transparentHole = !kIsWeb && Platform.isLinux && showWebView;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_handleBackPressed());
        }
      },
      child: Scaffold(
        backgroundColor: transparentHole ? Colors.transparent : null,
        appBar: AppBar(
          title: const Text('Microsoft'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                _finishWithResult(const MsaInteractiveSignInResult.cancelled()),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _progress < 100
                ? LinearProgressIndicator(
                    value: _progress > 0 ? _progress / 100 : null,
                  )
                : const SizedBox(height: 3),
          ),
        ),
        body: controller != null && !_closing
            ? WebViewWidget(controller: controller)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
