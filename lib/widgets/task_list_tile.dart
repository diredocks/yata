import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../theme/todo_theme.dart';
import 'task_checkbox.dart';

class TaskListTile extends StatelessWidget {
  const TaskListTile({
    super.key,
    required this.task,
    required this.onTap,
    required this.onToggleCompleted,
    required this.onToggleImportant,
    this.onLongPress,
    this.listName,
    this.showMyDayBadge = false,
    this.accentColor,
    this.isSelected = false,
    this.isMultiSelected = false,
    this.trailingHandle,
  });

  final TaskItem task;
  final VoidCallback onTap;
  final VoidCallback onToggleCompleted;
  final VoidCallback onToggleImportant;
  final VoidCallback? onLongPress;
  final String? listName;
  final bool showMyDayBadge;
  final Color? accentColor;
  final bool isSelected;
  final bool isMultiSelected;
  final Widget? trailingHandle;

  String _formatDueDate(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return l10n.today;
    if (diff == 1) return l10n.tomorrow;
    return DateFormat.MMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final cardColor = (isSelected || isMultiSelected)
        ? (isDark ? TodoColors.selectedCardDark : TodoColors.selectedCardLight)
        : (isDark ? TodoColors.cardDark : TodoColors.primaryBackgroundLight);
    final secondaryColor =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;
    final starActiveColor = accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    final metadataWidgets = <Widget>[];

    if (showMyDayBadge && task.isInMyDay) {
      metadataWidgets.add(
        _MetaItem(
          icon: Icons.wb_sunny_outlined,
          label: l10n.myDay,
          color: secondaryColor,
        ),
      );
    }

    if (listName != null && listName!.isNotEmpty) {
      metadataWidgets.add(
        _MetaText(label: listName!, color: secondaryColor),
      );
    }

    if (task.steps.isNotEmpty) {
      metadataWidgets.add(
        _MetaText(
          label: l10n.stepsProgress(
            task.completedStepsCount,
            task.steps.length,
          ),
          color: secondaryColor,
        ),
      );
    }

    if (task.dueDate != null) {
      final dueColor =
          task.isOverdue ? TodoColors.overdueRed : secondaryColor;
      metadataWidgets.add(
        _MetaItem(
          icon: Icons.calendar_today_outlined,
          label: _formatDueDate(context, task.dueDate!),
          color: dueColor,
        ),
      );
    }

    if (task.recurrence != RecurrenceType.none) {
      metadataWidgets.add(
        Icon(Icons.repeat, size: 13, color: secondaryColor),
      );
    }

    if (task.reminderAt != null) {
      metadataWidgets.add(
        _MetaItem(
          icon: Icons.notifications_none,
          label: DateFormat.jm().format(task.reminderAt!),
          color: secondaryColor,
        ),
      );
    }

    if (task.note.trim().isNotEmpty) {
      metadataWidgets.add(
        Icon(Icons.sticky_note_2_outlined, size: 13, color: secondaryColor),
      );
    }

    // Insert TaskMetadataDivider ('•') between metadata items matching task_metadata.xml
    final separatedMeta = <Widget>[];
    for (var i = 0; i < metadataWidgets.length; i++) {
      if (i > 0) {
        separatedMeta.add(
          Text(
            '•',
            style: TextStyle(fontSize: 11, color: secondaryColor),
          ),
        );
      }
      separatedMeta.add(metadataWidgets[i]);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(4),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TaskCheckbox(
                    isChecked: task.isCompleted,
                    onTap: onToggleCompleted,
                    accentColor: accentColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          task.title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: 15.5,
                            decoration: task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: task.isCompleted
                                ? secondaryColor
                                : (isDark
                                    ? TodoColors.primaryTextDark
                                    : TodoColors.primaryTextLight),
                          ),
                        ),
                        if (separatedMeta.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: separatedMeta,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailingHandle != null)
                    trailingHandle!
                  else if (isMultiSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        Icons.check_circle,
                        color: starActiveColor,
                        size: 22,
                      ),
                    )
                  else
                    IconButton(
                      onPressed: onToggleImportant,
                      icon: Icon(
                        task.isImportant ? Icons.star : Icons.star_outline,
                        color:
                            task.isImportant ? starActiveColor : secondaryColor,
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(fontSize: 12, color: color),
    );
  }
}
