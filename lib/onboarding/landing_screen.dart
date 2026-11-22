import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../account/account_provider.dart';
import '../auth/browser_launcher.dart';
import '../auth/microsoft_auth_service.dart';
import '../theme/todo_theme.dart';

class LandingScreen extends ConsumerStatefulWidget {
  const LandingScreen({
    super.key,
    this.isAddingAccount = false,
  });

  final bool isAddingAccount;

  @override
  ConsumerState<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends ConsumerState<LandingScreen> {
  final _inputController = TextEditingController();
  final _clientIdController = TextEditingController();
  bool _isSubmitting = false;
  bool _showClientIdField = false;
  String? _errorMessage;

  @override
  void dispose() {
    _inputController.dispose();
    _clientIdController.dispose();
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
    final customClientId = _clientIdController.text.trim();
    final clientId = customClientId.isEmpty ? null : customClientId;

    var cancelled = false;
    var dialogOpen = false;

    try {
      final prompt = await authClient.startDeviceCodeFlow(
        loginHint: _inputController.text.trim(),
        clientId: clientId,
      );

      if (!mounted) return;

      final pollFuture = authClient.pollDeviceCodeToken(
        prompt,
        clientId: clientId,
        isCancelled: () => cancelled,
      );

      if (prompt.userCode.isNotEmpty) {
        dialogOpen = true;
        unawaited(
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _DeviceCodeDialog(
              prompt: prompt,
              onCancel: () {
                cancelled = true;
                dialogOpen = false;
                Navigator.of(ctx).pop();
              },
            ),
          ).then((_) {
            dialogOpen = false;
          }),
        );
      }

      final result = await pollFuture;

      if (!mounted) return;
      if (dialogOpen) {
        dialogOpen = false;
        Navigator.of(context).pop();
      }

      await ref.read(accountProvider.notifier).signInMicrosoft(result);

      if (!mounted) return;
      if (widget.isAddingAccount) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _isSubmitting = false);
      }
    } on MicrosoftAuthException catch (e) {
      if (!mounted) return;
      if (dialogOpen) {
        dialogOpen = false;
        Navigator.of(context).pop();
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.isCancelled ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      if (dialogOpen) {
        dialogOpen = false;
        Navigator.of(context).pop();
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = l10n.signInFailed(e.toString());
      });
    }
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

    await ref.read(accountProvider.notifier).signInLocal(
          rawInput,
          fallbackName: fallbackName,
          fallbackEmail: l10n.localAccount,
        );

    if (!mounted) return;
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
                  if (_showClientIdField) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _clientIdController,
                      decoration: InputDecoration(
                        labelText: l10n.clientIdLabel,
                        hintText: MicrosoftAuthConfig.defaultClientId,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          l10n.landingSubtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? TodoColors.secondaryTextDark
                                : TodoColors.secondaryTextLight,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _showClientIdField
                              ? Icons.expand_less
                              : Icons.tune_outlined,
                          size: 16,
                          color: isDark
                              ? TodoColors.secondaryTextDark
                              : TodoColors.secondaryTextLight,
                        ),
                        tooltip: l10n.clientIdLabel,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          setState(() {
                            _showClientIdField = !_showClientIdField;
                          });
                        },
                      ),
                    ],
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

class _DeviceCodeDialog extends StatelessWidget {
  const _DeviceCodeDialog({
    required this.prompt,
    required this.onCancel,
  });

  final MicrosoftDeviceCodePrompt prompt;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.deviceCodeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.deviceCodeInstructions),
          const SizedBox(height: 12),
          SelectableText(
            prompt.verificationUri,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: SelectableText(
                    prompt.userCode,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: l10n.copyCode,
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: prompt.userCode),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.codeCopied)),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.waitingForSignIn,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(l10n.cancel),
        ),
        FilledButton.icon(
          onPressed: () {
            launchExternalUrl(prompt.verificationUri);
          },
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l10n.openBrowser),
        ),
      ],
    );
  }
}
