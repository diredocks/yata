import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../accounts/manage_accounts_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../providers/account_provider.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import '../view/persona_avatar.dart';
import 'settings_presenter.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    String accountId,
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
    await ref.read(accountProvider.notifier).signOut(accountId);
    if (!context.mounted) return;
    if (ref.read(accountProvider).accounts.isEmpty) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _themeLabel(AppLocalizations l10n, ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => l10n.themeSystem,
      ThemeMode.light => l10n.themeLight,
      ThemeMode.dark => l10n.themeDark,
    };
  }

  String _weekStartLabel(AppLocalizations l10n, WeekStart start) {
    return switch (start) {
      WeekStart.system => l10n.weekStartSystem,
      WeekStart.sunday => l10n.weekStartSunday,
      WeekStart.monday => l10n.weekStartMonday,
      WeekStart.saturday => l10n.weekStartSaturday,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todoProvider);
    final activeAccount = ref.watch(
      accountProvider.select((s) => s.activeAccount),
    );
    final notifier = ref.read(settingsPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        backgroundColor: isDark
            ? TodoColors.primaryBackgroundDark
            : TodoColors.primaryBackgroundLight,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        scrolledUnderElevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
      ),
      body: ListView(
        children: [
          if (activeAccount != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: PersonaAvatar(
                    name: activeAccount.displayName,
                    size: 64,
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
                          activeAccount.displayName,
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
                          activeAccount.email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? TodoColors.secondaryTextDark
                                : TodoColors.secondaryTextLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Divider(height: 1),
                      ),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ManageAccountsScreen(),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(
                            l10n.manageAccounts,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Divider(height: 1),
                      ),
                      InkWell(
                        onTap: () => _confirmSignOut(
                          context,
                          ref,
                          activeAccount.id,
                        ),
                        child: Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(minHeight: 48),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(right: 16),
                          child: Text(
                            l10n.signOut,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
          ],
          _SectionHeader(title: l10n.general),
          SwitchListTile(
            secondary: const Icon(Icons.vertical_align_top),
            title: Text(l10n.addNewTasksOnTop),
            value: state.addNewTasksOnTop,
            onChanged: notifier.setAddNewTasksOnTop,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.star_outline),
            title: Text(l10n.moveStarredTasksToTop),
            value: state.moveStarredTasksToTop,
            onChanged: notifier.setMoveStarredTasksToTop,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_outlined),
            title: Text(l10n.playCompletionSound),
            value: state.playCompletionSound,
            onChanged: notifier.setPlayCompletionSound,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.delete_outline),
            title: Text(l10n.confirmBeforeDeleting),
            value: state.confirmBeforeDeleting,
            onChanged: notifier.setConfirmBeforeDeleting,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny_outlined),
            title: Text(l10n.showDueTodayInMyDay),
            value: state.showDueTodayInMyDay,
            onChanged: notifier.setShowDueTodayInMyDay,
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.theme),
            subtitle: Text(_themeLabel(l10n, state.themeMode)),
            onTap: () async {
              final selected = await showDialog<ThemeMode>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(l10n.theme),
                  children: [
                    for (final mode in ThemeMode.values)
                      ListTile(
                        leading: Icon(
                          state.themeMode == mode
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(_themeLabel(l10n, mode)),
                        onTap: () => Navigator.pop(ctx, mode),
                      ),
                  ],
                ),
              );
              if (selected != null) {
                notifier.setThemeMode(selected);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_view_week_outlined),
            title: Text(l10n.startOfWeek),
            subtitle: Text(_weekStartLabel(l10n, state.startOfWeek)),
            onTap: () async {
              final selected = await showDialog<WeekStart>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: Text(l10n.startOfWeek),
                  children: [
                    for (final option in WeekStart.values)
                      ListTile(
                        leading: Icon(
                          state.startOfWeek == option
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(_weekStartLabel(l10n, option)),
                        onTap: () => Navigator.pop(ctx, option),
                      ),
                  ],
                ),
              );
              if (selected != null) {
                notifier.setStartOfWeek(selected);
              }
            },
          ),
          const Divider(),
          _SectionHeader(title: l10n.smartListsSection),
          SwitchListTile(
            secondary: Icon(
              Icons.star_outline,
              color: theme.brightness == Brightness.dark
                  ? TodoColors.secondaryTextDark
                  : null,
            ),
            title: Text(l10n.important),
            value: state.showSmartListImportant,
            onChanged: notifier.setShowSmartListImportant,
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.calendar_today_outlined,
              color: theme.brightness == Brightness.dark
                  ? TodoColors.secondaryTextDark
                  : null,
            ),
            title: Text(l10n.planned),
            value: state.showSmartListPlanned,
            onChanged: notifier.setShowSmartListPlanned,
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.all_inclusive,
              color: theme.brightness == Brightness.dark
                  ? TodoColors.secondaryTextDark
                  : null,
            ),
            title: Text(l10n.all),
            value: state.showSmartListAll,
            onChanged: notifier.setShowSmartListAll,
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.check_circle_outline,
              color: theme.brightness == Brightness.dark
                  ? TodoColors.secondaryTextDark
                  : null,
            ),
            title: Text(l10n.completedList),
            value: state.showSmartListCompleted,
            onChanged: notifier.setShowSmartListCompleted,
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.visibility_off_outlined,
              color: theme.brightness == Brightness.dark
                  ? TodoColors.secondaryTextDark
                  : null,
            ),
            title: Text(l10n.autoHideEmptySmartLists),
            value: state.autoHideEmptySmartLists,
            onChanged: notifier.setAutoHideEmptySmartLists,
          ),
          const Divider(),
          _SectionHeader(title: l10n.aboutSection),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.appVersion),
            subtitle: Text(
              '1.0.0',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: isDark
              ? TodoColors.secondaryTextDark
              : theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
