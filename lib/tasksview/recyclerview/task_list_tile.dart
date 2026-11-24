import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../detailview/recurrence/task_pickers.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../../view/task_checkbox.dart';

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
    this.isMultiSelecting = false,
    this.isMultiSelected = false,
    this.isReordering = false,
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
  final bool isMultiSelecting;
  final bool isMultiSelected;
  final bool isReordering;
  final Widget? trailingHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final cardColor = isMultiSelected
        ? (isDark ? const Color(0xFF34373D) : const Color(0xFFF7F7F7))
        : isSelected
        ? (isDark ? TodoColors.selectedCardDark : TodoColors.selectedCardLight)
        : (isDark ? TodoColors.cardDark : TodoColors.primaryBackgroundLight);
    final secondaryColor = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final starActiveColor =
        accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final textMetaItems = <Widget>[];
    final trailingIconItems = <Widget>[];

    if (showMyDayBadge && task.isInMyDay) {
      textMetaItems.add(
        _MetaItem(
          icon: Icons.wb_sunny_outlined,
          label: l10n.myDay,
          color: secondaryColor,
        ),
      );
    }

    if (listName != null && listName!.isNotEmpty) {
      textMetaItems.add(_MetaText(label: listName!, color: secondaryColor));
    }

    if (task.steps.isNotEmpty) {
      final allStepsDone = task.completedStepsCount == task.steps.length;
      final stepsLabel = l10n.stepsProgress(
        task.completedStepsCount,
        task.steps.length,
      );
      textMetaItems.add(
        allStepsDone
            ? _MetaItem(
                icon: Icons.check,
                label: stepsLabel,
                color: secondaryColor,
              )
            : _MetaText(label: stepsLabel, color: secondaryColor),
      );
    }

    if (task.dueDate != null) {
      final dueDay = DateTime(
        task.dueDate!.year,
        task.dueDate!.month,
        task.dueDate!.day,
      );
      final Color dueColor;
      if (task.isCompleted) {
        dueColor = secondaryColor;
      } else if (dueDay.isBefore(today)) {
        dueColor = TodoColors.overdueRed;
      } else if (dueDay == today) {
        dueColor = starActiveColor;
      } else {
        dueColor = secondaryColor;
      }

      textMetaItems.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MetaItem(
              icon: Icons.calendar_today_outlined,
              label: formatRelativeDate(context, task.dueDate!),
              color: dueColor,
            ),
            if (task.hasRecurrence) ...[
              const SizedBox(width: 4),
              Icon(Icons.repeat, size: 13, color: secondaryColor),
            ],
          ],
        ),
      );
    }

    if (task.reminderAt != null && task.reminderAt!.isAfter(now)) {
      final localReminder = task.reminderAt!.toLocal();
      final reminderDay = DateTime(
        localReminder.year,
        localReminder.month,
        localReminder.day,
      );
      final reminderColor = (!task.isCompleted && reminderDay == today)
          ? starActiveColor
          : secondaryColor;
      if (task.dueDate == null) {
        textMetaItems.add(
          _MetaItem(
            icon: Icons.notifications_none,
            label: DateFormat.jm().format(localReminder),
            color: reminderColor,
          ),
        );
      } else {
        trailingIconItems.add(
          Icon(Icons.notifications_none, size: 13, color: reminderColor),
        );
      }
    }

    if (task.note.trim().isNotEmpty) {
      trailingIconItems.add(
        Icon(Icons.sticky_note_2_outlined, size: 13, color: secondaryColor),
      );
    }

    // Insert TaskMetadataDivider ('•') between text items, and a single
    // lastDivider ('•') before trailing icon-only items matching MetadataContainer.
    final separatedMeta = <Widget>[];
    for (var i = 0; i < textMetaItems.length; i++) {
      if (i > 0) {
        separatedMeta.add(
          Text('•', style: TextStyle(fontSize: 11, color: secondaryColor)),
        );
      }
      separatedMeta.add(textMetaItems[i]);
    }
    if (trailingIconItems.isNotEmpty) {
      if (textMetaItems.isNotEmpty) {
        separatedMeta.add(
          Text('•', style: TextStyle(fontSize: 11, color: secondaryColor)),
        );
      }
      separatedMeta.addAll(trailingIconItems);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HeroMode(
        enabled: MediaQuery.sizeOf(context).width < 960,
        child: Hero(
          tag: 'task_card_${task.id}',
          child: Material(
            color: cardColor,
            animationDuration: const Duration(milliseconds: 180),
            borderRadius: BorderRadius.circular(4),
            elevation: 1,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(4),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isReordering && !task.isCompleted)
                        const SizedBox(width: 10)
                      else ...[
                        IgnorePointer(
                          ignoring: isReordering,
                          child: TaskCheckbox(
                            isChecked: isMultiSelecting
                                ? isMultiSelected
                                : task.isCompleted,
                            onTap: isMultiSelecting ? onTap : onToggleCompleted,
                            accentColor: accentColor,
                            mode: isMultiSelecting
                                ? CheckboxMode.select
                                : CheckboxMode.complete,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              style:
                                  (theme.textTheme.bodyLarge ??
                                          const TextStyle())
                                      .copyWith(
                                        fontSize: 15.5,
                                        decoration: task.isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: task.isCompleted
                                            ? secondaryColor
                                            : (isDark
                                                  ? TodoColors.primaryTextDark
                                                  : TodoColors
                                                        .primaryTextLight),
                                      ),
                              child: Text(task.title),
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
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: trailingHandle != null
                            ? KeyedSubtree(
                                key: const ValueKey('trailing_handle'),
                                child: trailingHandle!,
                              )
                            : IconButton(
                                key: ValueKey(
                                  'trailing_star_${task.isImportant}',
                                ),
                                onPressed: onToggleImportant,
                                icon: Icon(
                                  task.isImportant
                                      ? Icons.star
                                      : Icons.star_outline,
                                  color: task.isImportant
                                      ? starActiveColor
                                      : secondaryColor,
                                  size: 22,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                      ),
                    ],
                  ),
                ),
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
        Text(label, style: TextStyle(fontSize: 12, color: color)),
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
    return Text(label, style: TextStyle(fontSize: 12, color: color));
  }
}
