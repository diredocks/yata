import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../providers/account_provider.dart';
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
  bool _isSubmitting = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn({bool forceNewDefault = false}) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final l10n = AppLocalizations.of(context);
    final rawInput = forceNewDefault ? '' : _inputController.text;
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
                    onSubmitted: (_) => _handleSignIn(),
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
                    onPressed: _isSubmitting ? null : () => _handleSignIn(),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.signIn,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
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
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => _handleSignIn(
                                forceNewDefault:
                                    _inputController.text.trim().isEmpty,
                              ),
                      child: Text(
                        l10n.createNewAccount,
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
