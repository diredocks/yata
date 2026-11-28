import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/state/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_service.dart';
import '../theme/todo_theme.dart';
import 'settings_presenter.dart';

/// Secondary settings screen for "Reminder Settings" (`RemindersSettingsActivity`).
class ReminderSettingsScreen extends ConsumerStatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  ConsumerState<ReminderSettingsScreen> createState() =>
      _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends ConsumerState<ReminderSettingsScreen>
    with WidgetsBindingObserver {
  NotificationPermissionStatus _status = const NotificationPermissionStatus();
  bool _checkedInitialPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermissionStatus(allowInitialPrompt: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPermissionStatus(allowInitialPrompt: false));
    }
  }

  bool _needsExactAlarmPermission(NotificationPermissionStatus status) {
    return status.isAndroid &&
        status.androidSdkInt >= 31 &&
        !status.exactAlarmsEnabled;
  }

  Future<void> _refreshPermissionStatus({
    required bool allowInitialPrompt,
  }) async {
    final service = ref.read(notificationServiceProvider);
    final status = await service.getPermissionStatus();
    if (!mounted) return;
    setState(() => _status = status);

    if (allowInitialPrompt && !_checkedInitialPrompt) {
      _checkedInitialPrompt = true;
      final settings = ref.read(todoProvider.notifier).settings;
      if (_needsExactAlarmPermission(status) &&
          !settings.reminderPermissionPrompted) {
        await settings.saveReminderPermissionPrompted(true);
        if (mounted) {
          await _showExactAlarmPromptDialog();
        }
      }
    }
  }

  Future<void> _showExactAlarmPromptDialog() async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(notificationServiceProvider);
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.reminderPermissionDialogTitle),
        content: Text(l10n.reminderPermissionDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.turnOn),
          ),
        ],
      ),
    );
    if (shouldOpen == true) {
      await service.openExactAlarmSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final presenter = ref.read(settingsPresenterProvider);
    final service = ref.read(notificationServiceProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasExactAlarm = !_needsExactAlarmPermission(_status);
    final effectiveRemindersEnabled = state.remindersEnabled && hasExactAlarm;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reminderSettings),
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        scrolledUnderElevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.remindersEnabled),
            subtitle: Text(l10n.remindersEnabledSummary),
            value: effectiveRemindersEnabled,
            onChanged: (value) async {
              presenter.setRemindersEnabled(value);
              if (value) {
                await service.requestPermissions();
                await _refreshPermissionStatus(allowInitialPrompt: false);
                if (mounted && _needsExactAlarmPermission(_status)) {
                  await _showExactAlarmPromptDialog();
                }
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.push_pin_outlined),
            title: Text(l10n.pinReminders),
            subtitle: Text(l10n.pinRemindersSummary),
            value: state.pinReminders,
            onChanged: effectiveRemindersEnabled
                ? presenter.setPinReminders
                : null,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              l10n.remindersNotWorking,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isDark
                    ? TodoColors.secondaryTextDark
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_status.isAndroid && _status.androidSdkInt >= 31)
            ListTile(
              leading: const Icon(Icons.alarm_on_outlined),
              title: Text(l10n.enableReminderPermission),
              subtitle: Text(l10n.enableReminderPermissionSummary),
              enabled: effectiveRemindersEnabled,
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: effectiveRemindersEnabled
                  ? () => service.openExactAlarmSettings()
                  : null,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.bolt_outlined),
            title: Text(l10n.accurateReminders),
            subtitle: Text(l10n.accurateRemindersSummary),
            value: state.accurateReminders,
            onChanged: effectiveRemindersEnabled
                ? presenter.setAccurateReminders
                : null,
          ),
          if (_status.isAndroid)
            SwitchListTile(
              secondary: const Icon(Icons.battery_saver_outlined),
              title: Text(l10n.ignoreBatteryOptimization),
              subtitle: Text(l10n.ignoreBatteryOptimizationSummary),
              value: _status.ignoringBatteryOptimizations,
              onChanged: effectiveRemindersEnabled
                  ? (_) => service.openBatteryOptimizationSettings()
                  : null,
            ),
          if (_status.isAndroid && _status.androidSdkInt >= 28)
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: Text(l10n.removeBackgroundRestriction),
              subtitle: Text(l10n.removeBackgroundRestrictionSummary),
              value: !_status.backgroundRestricted,
              onChanged: effectiveRemindersEnabled
                  ? (_) => service.openAppDetailsSettings()
                  : null,
            ),
        ],
      ),
    );
  }
}
