import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../sync/sync_provider.dart';
import '../theme/todo_theme.dart';
import '../view/persona_avatar.dart';
import '../view/sync_status_label.dart';

/// Account summary card at the top of [SettingsScreen] with sync, manage, and sign-out actions.
class SettingsAccountHeader extends StatelessWidget {
  const SettingsAccountHeader({
    super.key,
    required this.account,
    required this.syncState,
    required this.onSyncNow,
    required this.onManageAccounts,
    required this.onSignOut,
  });

  final Account account;
  final SyncState syncState;
  final VoidCallback onSyncNow;
  final VoidCallback onManageAccounts;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryColor = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final msAccount = switch (account) {
      MicrosoftAccount ms => ms,
      _ => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: PersonaAvatar(
                name: account.displayName,
                size: 64,
                avatarBase64: msAccount?.avatarBase64,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      account.displayName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      account.email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (msAccount != null)
                    _SyncActionRow(
                      account: msAccount,
                      syncState: syncState,
                      secondaryColor: secondaryColor,
                      onTap: onSyncNow,
                    ),
                  _AccountActionRow(
                    label: l10n.manageAccounts,
                    color: theme.colorScheme.primary,
                    onTap: onManageAccounts,
                  ),
                  _AccountActionRow(
                    label: l10n.signOut,
                    color: theme.colorScheme.error,
                    onTap: onSignOut,
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _SyncActionRow extends StatelessWidget {
  const _SyncActionRow({
    required this.account,
    required this.syncState,
    required this.secondaryColor,
    required this.onTap,
  });

  final MicrosoftAccount account;
  final SyncState syncState;
  final Color secondaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final hasError = syncState.error != null || account.syncError != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Divider(height: 1),
        ),
        InkWell(
          onTap: syncState.isSyncing ? null : onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l10n.syncNow,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        formatAccountSyncStatus(
                          l10n: l10n,
                          account: account,
                          syncState: syncState,
                          isActive: true,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasError
                              ? theme.colorScheme.error
                              : secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (syncState.isSyncing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.sync, size: 20, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountActionRow extends StatelessWidget {
  const _AccountActionRow({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Divider(height: 1),
        ),
        InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
