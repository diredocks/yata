import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import 'settings_presenter.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

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
    final notifier = ref.read(settingsPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
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
            secondary: const Icon(Icons.star_outline),
            title: Text(l10n.important),
            value: state.showSmartListImportant,
            onChanged: notifier.setShowSmartListImportant,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.calendar_today_outlined),
            title: Text(l10n.planned),
            value: state.showSmartListPlanned,
            onChanged: notifier.setShowSmartListPlanned,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.all_inclusive),
            title: Text(l10n.all),
            value: state.showSmartListAll,
            onChanged: notifier.setShowSmartListAll,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.check_circle_outline),
            title: Text(l10n.completedList),
            value: state.showSmartListCompleted,
            onChanged: notifier.setShowSmartListCompleted,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
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
