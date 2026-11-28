import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account_provider.dart';
import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/result/app_result.dart';
import '../l10n/app_localizations.dart';
import '../sync/microsoft/todo_wire_codecs.dart';
import '../theme/todo_theme.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({super.key, this.isAddingAccount = false});

  final bool isAddingAccount;

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  final _inputController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleMicrosoftSignIn() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final l10n = AppLocalizations.of(context);
    final authClient = ref.read(microsoftAuthClientProvider);
    final interactiveClient = ref.read(msaInteractiveSignInProvider);
    final loginHint = _inputController.text.trim();
    final uaid = generateUuidV4();
    final authorizeUrl = authClient.buildAuthorizeUrl(
      loginHint: loginHint.isEmpty ? null : loginHint,
      uaid: uaid,
    );

    final interactiveResult = await interactiveClient.signIn(
      context: context,
      authorizeUrl: authorizeUrl,
      redirectUri: MsaAuthConfig.redirectUri,
    );

    if (!mounted) return;

    String? code;
    if (interactiveResult != null) {
      if (interactiveResult.cancelled) {
        setState(() => _isSubmitting = false);
        return;
      }
      if (interactiveResult.error != null) {
        _failSignIn(l10n.signInFailed(interactiveResult.error!));
        return;
      }
      code = interactiveResult.code;
    } else {
      // Desktop / non-WebView fallback: launch browser and prompt for redirect URL / code.
      final openUrl = ref.read(externalUrlLauncherProvider);
      unawaited(openUrl(authorizeUrl));
      code = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _MsaBrowserCodeDialog(
          onOpenBrowser: () => openUrl(authorizeUrl),
          onExtractCode: authClient.extractAuthorizationCode,
        ),
      );
    }

    if (!mounted) return;
    if (code == null || code.isEmpty) {
      setState(() => _isSubmitting = false);
      return;
    }

    final signInOutcome = await authClient.completeSignInWithCode(
      code: code,
      loginHint: loginHint.isEmpty ? null : loginHint,
      uaid: uaid,
    );

    if (!mounted) return;
    final authError = signInOutcome.exceptionOrNull();
    if (authError != null) {
      _failSignIn(l10n.signInFailed(authError.userMessage));
      return;
    }

    final saved = await guardAsync(
      () => ref
          .read(accountProvider.notifier)
          .signInMicrosoft(signInOutcome.getOrThrow()),
      operation: 'account.signInMicrosoft',
    );

    if (!mounted) return;
    final saveError = saved.exceptionOrNull();
    if (saveError != null) {
      _failSignIn(l10n.signInFailed(saveError.userMessage));
      return;
    }

    if (widget.isAddingAccount) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  void _failSignIn(String message) {
    setState(() {
      _isSubmitting = false;
      _errorMessage = message;
    });
  }

  Future<void> _handleLocalSignIn() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final l10n = AppLocalizations.of(context);
    final rawInput = _inputController.text;
    final existingCount = ref.read(accountProvider).accounts.length;
    final fallbackName = existingCount == 0
        ? l10n.userName
        : '${l10n.localAccount} ${existingCount + 1}';

    final signedIn = await guardAsync(
      () => ref
          .read(accountProvider.notifier)
          .signInLocal(
            rawInput,
            fallbackName: fallbackName,
            fallbackEmail: l10n.localAccount,
          ),
      operation: 'account.signInLocal',
    );

    if (!mounted) return;
    final error = signedIn.exceptionOrNull();
    if (error != null) {
      _failSignIn(l10n.signInFailed(error.userMessage));
      return;
    }

    if (widget.isAddingAccount) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? TodoColors.primaryBackgroundDark
          : TodoColors.primaryBackgroundLight,
      appBar: widget.isAddingAccount
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(l10n.addAccount),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.welcomeToApp(l10n.appTitle),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? TodoColors.primaryTextDark
                          : TodoColors.primaryTextLight,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Image.asset(
                    'assets/images/sign_in_illustration.webp',
                    height: 210,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.check_circle_outline,
                      size: 120,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _inputController,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _handleMicrosoftSignIn(),
                    decoration: InputDecoration(
                      hintText: l10n.loginInputHint,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _handleMicrosoftSignIn,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(l10n.signingIn),
                            ],
                          )
                        : Text(
                            l10n.signIn,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    l10n.landingSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? TodoColors.secondaryTextDark
                          : TodoColors.secondaryTextLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _isSubmitting ? null : _handleLocalSignIn,
                      child: Text(
                        l10n.useLocalAccount,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MsaBrowserCodeDialog extends StatefulWidget {
  const _MsaBrowserCodeDialog({
    required this.onOpenBrowser,
    required this.onExtractCode,
  });

  final Future<bool> Function() onOpenBrowser;
  final AppResult<String> Function(String rawInput) onExtractCode;

  @override
  State<_MsaBrowserCodeDialog> createState() => _MsaBrowserCodeDialogState();
}

class _MsaBrowserCodeDialogState extends State<_MsaBrowserCodeDialog> {
  final _codeController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    widget
        .onExtractCode(_codeController.text)
        .fold(
          (code) => Navigator.of(context).pop(code),
          (error) => setState(
            () => _validationError = error is ValidationError
                ? l10n.msaInvalidCodeError
                : error.userMessage,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.msaBrowserSignInTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.msaBrowserSignInInstructions),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            autofocus: true,
            maxLines: 2,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: l10n.msaPasteRedirectHint,
              errorText: _validationError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(widget.onOpenBrowser()),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(
                l10n.msaOpenBrowserAgain,
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.signIn)),
      ],
    );
  }
}
