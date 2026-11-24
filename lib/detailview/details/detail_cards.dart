import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../recurrence/task_pickers.dart';

/// My Day card matching `detailview/details/MyDayCardView` (`detailview_my_day.xml`).
class MyDayCardView extends StatelessWidget {
  const MyDayCardView({
    super.key,
    required this.task,
    required this.cardColor,
    required this.onToggleMyDay,
    this.accentColor,
  });

  final TaskItem task;
  final Color cardColor;
  final VoidCallback onToggleMyDay;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final accent =
        accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    return Card(
      color: cardColor,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: DetailActionRow(
        icon: Icons.wb_sunny_outlined,
        iconColor: task.isInMyDay ? accent : secondaryText,
        label: task.isInMyDay ? l10n.addedToMyDay : l10n.addToMyDay,
        labelColor: task.isInMyDay ? accent : secondaryText,
        removeColor: secondaryText,
        onTap: onToggleMyDay,
        onRemove: task.isInMyDay ? onToggleMyDay : null,
      ),
    );
  }
}

/// Reminder / DueDate / Recurrence card matching `detailview/details/`
/// (`ReminderCardView`, `DueDateCardView`, `RecurrenceCardView` in `detailview_date.xml`).
class TaskSchedulingCardView extends StatelessWidget {
  const TaskSchedulingCardView({
    super.key,
    required this.task,
    required this.cardColor,
    required this.recurrenceLabel,
    required this.onPickReminder,
    required this.onClearReminder,
    required this.onPickDueDate,
    required this.onClearDueDate,
    required this.onPickRecurrence,
    required this.onClearRecurrence,
    this.accentColor,
  });

  final TaskItem task;
  final Color cardColor;
  final String recurrenceLabel;
  final VoidCallback onPickReminder;
  final VoidCallback onClearReminder;
  final VoidCallback onPickDueDate;
  final VoidCallback onClearDueDate;
  final VoidCallback onPickRecurrence;
  final VoidCallback onClearRecurrence;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final accent =
        accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    return Card(
      color: cardColor,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          DetailActionRow(
            icon: Icons.notifications_none,
            iconColor: task.reminderAt != null ? accent : secondaryText,
            label: task.reminderAt != null
                ? formatReminderLabel(context, task.reminderAt!)
                : l10n.remindMe,
            labelColor: task.reminderAt != null ? accent : secondaryText,
            removeColor: secondaryText,
            onTap: onPickReminder,
            onRemove: task.reminderAt != null ? onClearReminder : null,
          ),
          const Divider(height: 1, indent: 64),
          DetailActionRow(
            icon: Icons.calendar_today_outlined,
            iconColor: task.dueDate != null
                ? (task.isOverdue ? TodoColors.overdueRed : accent)
                : secondaryText,
            label: task.dueDate != null
                ? l10n.dueOn(formatRelativeDate(context, task.dueDate!))
                : l10n.addDueDate,
            labelColor: task.dueDate != null
                ? (task.isOverdue ? TodoColors.overdueRed : accent)
                : secondaryText,
            removeColor: secondaryText,
            onTap: onPickDueDate,
            onRemove: task.dueDate != null ? onClearDueDate : null,
          ),
          const Divider(height: 1, indent: 64),
          DetailActionRow(
            icon: Icons.repeat,
            iconColor: task.hasRecurrence ? accent : secondaryText,
            label: recurrenceLabel,
            labelColor: task.hasRecurrence ? accent : secondaryText,
            removeColor: secondaryText,
            onTap: onPickRecurrence,
            onRemove: task.hasRecurrence ? onClearRecurrence : null,
          ),
        ],
      ),
    );
  }
}

/// Row layout matching `DetailViewCardRow` & `DetailViewRowRemove` in `styles.xml`.
class DetailActionRow extends StatelessWidget {
  const DetailActionRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.removeColor,
    required this.onTap,
    this.onRemove,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final Color removeColor;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 24),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style:
                    (Theme.of(context).textTheme.bodyLarge ?? const TextStyle())
                        .copyWith(fontSize: 15, color: labelColor),
                child: Text(label),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: onRemove != null
                  ? InkWell(
                      key: const ValueKey('detail_remove_visible'),
                      onTap: onRemove,
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 16,
                          end: 14,
                          top: 13,
                          bottom: 13,
                        ),
                        child: Icon(Icons.close, size: 22, color: removeColor),
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('detail_remove_hidden'),
                      width: 16,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
