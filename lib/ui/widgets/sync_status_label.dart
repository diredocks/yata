import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../sync/sync_provider.dart';

String formatAccountSyncStatus({
  required AppLocalizations l10n,
  required Account account,
  required SyncState syncState,
  bool isActive = false,
}) {
  switch (account) {
    case LocalAccount():
      return l10n.localAccount;
    case MicrosoftAccount():
      if (isActive) {
        if (syncState.isSyncing) return l10n.syncing;
        if (syncState.requiresRelogin) return l10n.reloginRequired;
        if (syncState.error != null) return l10n.unableToSync;
      }
      if (account.syncError != null) {
        return l10n.unableToSync;
      }
      final lastSynced = account.lastSyncedAt;
      if (lastSynced == null) {
        return l10n.notYetSynced;
      }
      final diff = DateTime.now().difference(lastSynced.toLocal());
      if (diff.inMinutes < 1) {
        return l10n.syncedJustNow;
      }
      final formatted = DateFormat.Hm().format(lastSynced.toLocal());
      return l10n.lastSyncedAt(formatted);
  }
}
