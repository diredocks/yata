import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../notifications/notification_service.dart';
import '../theme/todo_theme.dart';
import 'reminder_settings_screen.dart';
import 'routine_settings_screen.dart';
import 'settings_presenter.dart';

final appPackageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

/// Section title header used across [SettingsScreen].
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({super.key, required this.title});

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

Future<T?> _showRadioOptionDialog<T>({
  required BuildContext context,
  required String title,
  required List<T> values,
  required T currentValue,
  required String Function(T value) labelFor,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        for (final option in values)
          ListTile(
            leading: Icon(
              currentValue == option
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(labelFor(option)),
            onTap: () => Navigator.pop(ctx, option),
          ),
      ],
    ),
  );
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
    WeekStart.tuesday => l10n.weekStartTuesday,
    WeekStart.wednesday => l10n.weekStartWednesday,
    WeekStart.thursday => l10n.weekStartThursday,
    WeekStart.friday => l10n.weekStartFriday,
    WeekStart.saturday => l10n.weekStartSaturday,
  };
}

/// Builds the General settings tiles as direct [ListView] children.
List<Widget> buildGeneralSettingsTiles({
  required BuildContext context,
  required TodoState state,
  required SettingsPresenter presenter,
}) {
  final l10n = AppLocalizations.of(context);
  return [
    SettingsSectionHeader(title: l10n.general),
    SwitchListTile(
      secondary: const Icon(Icons.vertical_align_top),
      title: Text(l10n.addNewTasksOnTop),
      value: state.addNewTasksOnTop,
      onChanged: presenter.setAddNewTasksOnTop,
    ),
    SwitchListTile(
      secondary: const Icon(Icons.star_outline),
      title: Text(l10n.moveStarredTasksToTop),
      value: state.moveStarredTasksToTop,
      onChanged: presenter.setMoveStarredTasksToTop,
    ),
    SwitchListTile(
      secondary: const Icon(Icons.volume_up_outlined),
      title: Text(l10n.playCompletionSound),
      value: state.playCompletionSound,
      onChanged: presenter.setPlayCompletionSound,
    ),
    SwitchListTile(
      secondary: const Icon(Icons.delete_outline),
      title: Text(l10n.confirmBeforeDeleting),
      value: state.confirmBeforeDeleting,
      onChanged: presenter.setConfirmBeforeDeleting,
    ),
    SwitchListTile(
      secondary: const Icon(Icons.wb_sunny_outlined),
      title: Text(l10n.showDueTodayInMyDay),
      value: state.showDueTodayInMyDay,
      onChanged: presenter.setShowDueTodayInMyDay,
    ),
    ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: Text(l10n.theme),
      subtitle: Text(_themeLabel(l10n, state.themeMode)),
      onTap: () async {
        final selected = await _showRadioOptionDialog<ThemeMode>(
          context: context,
          title: l10n.theme,
          values: ThemeMode.values,
          currentValue: state.themeMode,
          labelFor: (mode) => _themeLabel(l10n, mode),
        );
        if (selected != null) {
          presenter.setThemeMode(selected);
        }
      },
    ),
    SwitchListTile(
      secondary: const Icon(Icons.color_lens_outlined),
      title: Text(l10n.useDynamicColor),
      subtitle: Text(l10n.useDynamicColorSummary),
      value: state.useDynamicColor,
      onChanged: presenter.setUseDynamicColor,
    ),
    ListTile(
      leading: const Icon(Icons.calendar_view_week_outlined),
      title: Text(l10n.startOfWeek),
      subtitle: Text(_weekStartLabel(l10n, state.startOfWeek)),
      onTap: () async {
        final selected = await _showRadioOptionDialog<WeekStart>(
          context: context,
          title: l10n.startOfWeek,
          values: WeekStart.values,
          currentValue: state.startOfWeek,
          labelFor: (option) => _weekStartLabel(l10n, option),
        );
        if (selected != null) {
          presenter.setStartOfWeek(selected);
        }
      },
    ),
  ];
}

/// Builds the Smart Lists visibility toggle tiles as direct [ListView] children.
List<Widget> buildSmartListsSettingsTiles({
  required BuildContext context,
  required TodoState state,
  required SettingsPresenter presenter,
}) {
  final l10n = AppLocalizations.of(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final iconColor = isDark ? TodoColors.secondaryTextDark : null;

  final items =
      <
        ({
          IconData icon,
          String title,
          bool value,
          ValueChanged<bool> onChanged,
        })
      >[
        (
          icon: Icons.star_outline,
          title: l10n.important,
          value: state.showSmartListImportant,
          onChanged: presenter.setShowSmartListImportant,
        ),
        (
          icon: Icons.calendar_today_outlined,
          title: l10n.planned,
          value: state.showSmartListPlanned,
          onChanged: presenter.setShowSmartListPlanned,
        ),
        (
          icon: Icons.all_inclusive,
          title: l10n.all,
          value: state.showSmartListAll,
          onChanged: presenter.setShowSmartListAll,
        ),
        (
          icon: Icons.check_circle_outline,
          title: l10n.completedList,
          value: state.showSmartListCompleted,
          onChanged: presenter.setShowSmartListCompleted,
        ),
        (
          icon: Icons.visibility_off_outlined,
          title: l10n.autoHideEmptySmartLists,
          value: state.autoHideEmptySmartLists,
          onChanged: presenter.setAutoHideEmptySmartLists,
        ),
      ];

  return [
    SettingsSectionHeader(title: l10n.smartListsSection),
    for (final item in items)
      SwitchListTile(
        secondary: Icon(item.icon, color: iconColor),
        title: Text(item.title),
        value: item.value,
        onChanged: item.onChanged,
      ),
  ];
}

/// Builds the Notifications settings tiles as direct [ListView] children.
List<Widget> buildNotificationsSettingsTiles({
  required BuildContext context,
  required TodoState state,
  required SettingsPresenter presenter,
  required NotificationPermissionStatus permissionStatus,
  required VoidCallback onRequestOrOpenSettings,
  required Future<void> Function() onEnsurePermission,
}) {
  final l10n = AppLocalizations.of(context);
  return [
    SettingsSectionHeader(title: l10n.notificationsSection),
    if (!permissionStatus.notificationsEnabled)
      ListTile(
        leading: const Icon(Icons.notifications_off_outlined),
        title: Text(l10n.enableNotificationsFromSettings),
        subtitle: Text(l10n.notificationPermissionRequiredRationale),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: onRequestOrOpenSettings,
      )
    else ...[
      SwitchListTile(
        secondary: const Icon(Icons.add_alert_outlined),
        title: Text(l10n.quickAddNotification),
        subtitle: Text(l10n.quickAddNotificationSummary),
        value: state.quickAddNotificationEnabled,
        onChanged: (value) async {
          presenter.setQuickAddNotificationEnabled(value);
          if (value) await onEnsurePermission();
        },
      ),
      ListTile(
        leading: const Icon(Icons.wb_sunny_outlined),
        title: Text(l10n.routineNotifications),
        subtitle: Text(l10n.routineNotificationsSummary),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const RoutineSettingsScreen(),
          ),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text(l10n.reminderSettings),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const ReminderSettingsScreen(),
          ),
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.today_outlined),
        title: Text(l10n.dueTodayNotifications),
        value: state.dueTodayNotificationsEnabled,
        onChanged: (value) async {
          presenter.setDueTodayNotificationsEnabled(value);
          if (value) await onEnsurePermission();
        },
      ),
      if (state.dueTodayNotificationsEnabled)
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: Text(l10n.dueTodayNotificationTime),
          subtitle: Text(
            TimeOfDay(
              hour: state.dueTodayNotificationHour,
              minute: state.dueTodayNotificationMinute,
            ).format(context),
          ),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: state.dueTodayNotificationHour,
                minute: state.dueTodayNotificationMinute,
              ),
            );
            if (picked != null) {
              presenter.setDueTodayNotificationTime(picked.hour, picked.minute);
            }
          },
        ),
    ],
  ];
}

/// App version tile in the About section.
class SettingsAppVersionTile extends ConsumerWidget {
  const SettingsAppVersionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final versionText = ref
        .watch(appPackageInfoProvider)
        .when(
          data: (info) => info.buildNumber.isNotEmpty
              ? '${info.version}+${info.buildNumber}'
              : info.version,
          loading: () => '...',
          error: (_, _) => '1.0.0',
        );

    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(l10n.appVersion),
      subtitle: Text(versionText, style: theme.textTheme.bodyMedium),
    );
  }
}
