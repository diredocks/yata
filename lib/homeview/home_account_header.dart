import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/account/account_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../sync/sync_provider.dart';
import '../theme/todo_theme.dart';
import '../ui/widgets/persona_avatar.dart';
import '../ui/widgets/sync_status_label.dart';

/// Animated header morphing between `homeview_header_collapsed.xml` and `homeview_header.xml`.
class HomeAccountHeader extends StatelessWidget {
  const HomeAccountHeader({
    super.key,
    required this.displayName,
    required this.displayEmail,
    required this.activeAccount,
    required this.expanded,
    required this.collapsedAvatarSize,
    required this.onToggleExpanded,
    required this.onCollapse,
    required this.onOpenSearch,
  });

  final String displayName;
  final String displayEmail;
  final Account? activeAccount;
  final bool expanded;
  final double collapsedAvatarSize;
  final VoidCallback onToggleExpanded;
  final VoidCallback onCollapse;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final account = activeAccount;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: expanded ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final headerHeight = lerpDouble(62, 148, t)!;
        final avatarSize = lerpDouble(collapsedAvatarSize, 64, t)!;
        final avatarLeft = lerpDouble(12, 16, t)!;
        final avatarTop = lerpDouble(12, 16, t)!;
        final textLeft = lerpDouble(12 + collapsedAvatarSize + 12, 16, t)!;
        final textTop = lerpDouble(12, 88, t)!;
        final textRight = lerpDouble(52, 16, t)!;
        final nameFontSize = lerpDouble(14, 17, t)!;
        final searchOpacity = (1.0 - t * 2.0).clamp(0.0, 1.0);
        final closeOpacity = ((t - 0.5) * 2.0).clamp(0.0, 1.0);

        return InkWell(
          onTap: onToggleExpanded,
          child: SizedBox(
            height: headerHeight,
            width: double.infinity,
            child: Stack(
              children: [
                Positioned(
                  left: avatarLeft,
                  top: avatarTop,
                  child: PersonaAvatar(
                    name: displayName,
                    size: avatarSize,
                    avatarBase64: account is MicrosoftAccount
                        ? account.avatarBase64
                        : null,
                  ),
                ),
                Positioned(
                  left: textLeft,
                  top: textTop,
                  right: textRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontSize: nameFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Transform.rotate(
                            angle: t * math.pi,
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        displayEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? TodoColors.secondaryTextDark
                              : TodoColors.secondaryTextLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (t < 0.99)
                  Positioned(
                    right: 4,
                    top: lerpDouble(7, 12, t)!,
                    child: IgnorePointer(
                      ignoring: expanded,
                      child: Opacity(
                        opacity: searchOpacity,
                        child: IconButton(
                          onPressed: onOpenSearch,
                          icon: Icon(
                            Icons.search,
                            color: TodoColors.homeViewIconColor(
                              theme.brightness,
                            ),
                          ),
                          tooltip: l10n.search,
                        ),
                      ),
                    ),
                  ),
                if (t > 0.01)
                  Positioned(
                    right: 4,
                    top: lerpDouble(7, 12, t)!,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: Opacity(
                        opacity: closeOpacity,
                        child: IconButton(
                          onPressed: onCollapse,
                          icon: Icon(
                            Icons.close,
                            color: TodoColors.homeViewIconColor(
                              theme.brightness,
                            ),
                          ),
                          tooltip: l10n.cancel,
                        ),
                      ),
                    ),
                  ),
                if (t > 0.01)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Opacity(opacity: t, child: const Divider(height: 1)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Account switcher menu displayed when [HomeAccountHeader] is expanded.
class HomeAccountMenuList extends ConsumerWidget {
  const HomeAccountMenuList({
    super.key,
    required this.onSwitchAccount,
    required this.onAddAccount,
    required this.onManageAccounts,
    required this.onOpenSettings,
  });

  final ValueChanged<String> onSwitchAccount;
  final VoidCallback onAddAccount;
  final VoidCallback onManageAccounts;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider);
    final syncState = ref.watch(syncProvider);
    final activeAccount = accountState.activeAccount;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final account in accountState.accounts)
          ListTile(
            leading: PersonaAvatar(
              name: account.displayName,
              size: 38,
              avatarBase64: account is MicrosoftAccount
                  ? account.avatarBase64
                  : null,
            ),
            title: Text(
              account.displayName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: account.id == activeAccount?.id
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
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
            trailing: account.id == activeAccount?.id
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (account.isMicrosoft && syncState.isSyncing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (account is MicrosoftAccount &&
                          (syncState.error != null ||
                              account.syncError != null))
                        Icon(
                          Icons.sync_problem_outlined,
                          size: 18,
                          color: theme.colorScheme.error,
                        )
                      else
                        Icon(
                          Icons.check,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  )
                : null,
            onTap: () => onSwitchAccount(account.id),
          ),
        if (activeAccount is MicrosoftAccount)
          ListTile(
            leading: SizedBox(
              width: 38,
              child: syncState.isSyncing
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.sync, size: 22),
            ),
            title: Text(l10n.syncNow),
            subtitle: Text(
              formatAccountSyncStatus(
                l10n: l10n,
                account: activeAccount,
                syncState: syncState,
                isActive: true,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    (syncState.error != null || activeAccount.syncError != null)
                    ? theme.colorScheme.error
                    : (isDark
                          ? TodoColors.secondaryTextDark
                          : TodoColors.secondaryTextLight),
              ),
            ),
            onTap: syncState.isSyncing
                ? null
                : () {
                    ref.read(syncProvider.notifier).refresh();
                  },
          ),
        ListTile(
          leading: const SizedBox(width: 38, child: Icon(Icons.add, size: 22)),
          title: Text(l10n.addAccount),
          onTap: onAddAccount,
        ),
        ListTile(
          leading: const SizedBox(
            width: 38,
            child: Icon(Icons.manage_accounts_outlined, size: 22),
          ),
          title: Text(l10n.manageAccounts),
          onTap: onManageAccounts,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Divider(height: 1),
        ),
        ListTile(
          leading: const SizedBox(
            width: 38,
            child: Icon(Icons.settings_outlined, size: 22),
          ),
          title: Text(l10n.settings),
          onTap: onOpenSettings,
        ),
      ],
    );
  }
}
