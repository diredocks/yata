import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// Bottom sheet for snoozing a task reminder, aligned with
/// `SnoozeReminderDialogFragment.kt` (5 min, 10 min, 15 min, 30 min, 1 hour).
Future<Duration?> showSnoozeReminderSheet(
  BuildContext context, {
  String? taskTitle,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);

  final options = <(String, Duration)>[
    (l10n.snoozeMinutes(5), const Duration(minutes: 5)),
    (l10n.snoozeMinutes(10), const Duration(minutes: 10)),
    (l10n.snoozeMinutes(15), const Duration(minutes: 15)),
    (l10n.snoozeMinutes(30), const Duration(minutes: 30)),
    (l10n.snoozeOneHour, const Duration(hours: 1)),
  ];

  return showModalBottomSheet<Duration>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.snoozeReminderTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (taskTitle != null && taskTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final (label, duration) in options)
                ListTile(
                  leading: const Icon(Icons.snooze_outlined),
                  title: Text(label),
                  onTap: () => Navigator.of(ctx).pop(duration),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
