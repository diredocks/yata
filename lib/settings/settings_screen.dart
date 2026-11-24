import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../account/account_provider.dart';
import '../account/manage_accounts_screen.dart';
import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../notifications/notification_service.dart';
import '../sync/sync_provider.dart';
import 'settings_account_header.dart';
import 'settings_presenter.dart';
import 'settings_sections.dart';

export 'settings_sections.dart' show appPackageInfoProvider;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  NotificationPermissionStatus _permissionStatus =
      const NotificationPermissionStatus();
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

  Future<void> _refreshPermissionStatus({
    required bool allowInitialPrompt,
  }) async {
    final service = ref.read(notificationServiceProvider);
    final status = await service.getPermissionStatus();
    if (!mounted) return;
    setState(() => _permissionStatus = status);

    if (allowInitialPrompt && !_checkedInitialPrompt) {
      _checkedInitialPrompt = true;
      final settings = ref.read(todoProvider.notifier).settings;
      if (!status.notificationsEnabled &&
          !settings.notificationPermissionPrompted) {
        await settings.saveNotificationPermissionPrompted(true);
        if (mounted) {
          await _showNotificationPermissionDialog();
        }
      }
    }
  }

  Future<void> _showNotificationPermissionDialog() async {
    final l10n = AppLocalizations.of(context);
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.notificationPermissionDisabledTitle),
        content: Text(l10n.notificationPermissionRequiredRationale),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settings),
          ),
        ],
      ),
    );
    if (openSettings == true && mounted) {
      await _requestOrOpenNotificationSettings();
    }
  }

  Future<void> _requestOrOpenNotificationSettings() async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.requestPermissions();
    await _refreshPermissionStatus(allowInitialPrompt: false);
    if (!granted || !_permissionStatus.notificationsEnabled) {
      await service.openNotificationSettings();
    }
  }

  Future<void> _confirmSignOut(String accountId) async {
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
    if (!mounted) return;
    if (ref.read(accountProvider).accounts.isEmpty) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _ensureNotificationPermission() async {
    final granted = await ref
        .read(notificationServiceProvider)
        .requestPermissions();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).notificationPermissionDenied,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final syncState = ref.watch(syncProvider);
    final activeAccount = ref.watch(
      accountProvider.select((s) => s.activeAccount),
    );
    final presenter = ref.read(settingsPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        scrolledUnderElevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
      ),
      body: ListView(
        children: [
          if (activeAccount != null)
            SettingsAccountHeader(
              account: activeAccount,
              syncState: syncState,
              onSyncNow: () => ref
                  .read(syncProvider.notifier)
                  .syncNow(
                    forceFullSync: true,
                    reason: 'manual_settings_sync',
                  ),
              onManageAccounts: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ManageAccountsScreen(),
                ),
              ),
              onSignOut: () => _confirmSignOut(activeAccount.id),
            ),
          ...buildGeneralSettingsTiles(
            context: context,
            state: state,
            presenter: presenter,
          ),
          const Divider(),
          ...buildSmartListsSettingsTiles(
            context: context,
            state: state,
            presenter: presenter,
          ),
          const Divider(),
          ...buildNotificationsSettingsTiles(
            context: context,
            state: state,
            presenter: presenter,
            permissionStatus: _permissionStatus,
            onRequestOrOpenSettings: _requestOrOpenNotificationSettings,
            onEnsurePermission: _ensureNotificationPermission,
          ),
          const Divider(),
          SettingsSectionHeader(title: l10n.aboutSection),
          const SettingsAppVersionTile(),
        ],
      ),
    );
  }
}
