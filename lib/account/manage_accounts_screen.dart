import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../onboarding/landing_screen.dart';
import '../data/account_provider.dart';
import '../theme/todo_theme.dart';
import '../ui/widgets/persona_avatar.dart';

class ManageAccountsScreen extends ConsumerWidget {
  const ManageAccountsScreen({super.key});

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    Account account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.signOut),
        content: Text(l10n.signOutWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.yesSignOut),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(accountProvider.notifier).signOut(account.id);
    if (!context.mounted) return;
    if (ref.read(accountProvider).accounts.isEmpty) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _openAddAccount(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => const LandingScreen(isAddingAccount: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageAccounts),
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        scrolledUnderElevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
      ),
      body: ListView.separated(
        itemCount: accountState.accounts.length + 1,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          if (index == accountState.accounts.length) {
            return ListTile(
              leading: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.add),
              ),
              title: Text(
                l10n.addAccount,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              onTap: () => _openAddAccount(context),
            );
          }

          final account = accountState.accounts[index];
          final isActive = account.id == accountState.activeAccountId;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: PersonaAvatar(
              name: account.displayName,
              size: 40,
              avatarBase64: account is MicrosoftAccount
                  ? account.avatarBase64
                  : null,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    account.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.activeAccount,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              account.email,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? TodoColors.secondaryTextDark
                    : TodoColors.secondaryTextLight,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _confirmSignOut(context, ref, account),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(l10n.signOut),
            ),
            onTap: isActive
                ? null
                : () async {
                    await ref
                        .read(accountProvider.notifier)
                        .switchAccount(account.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
          );
        },
      ),
    );
  }
}
