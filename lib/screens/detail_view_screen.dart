import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import '../widgets/task_checkbox.dart';

class DetailViewScreen extends ConsumerStatefulWidget {
  const DetailViewScreen({
    super.key,
    required this.taskId,
    this.listTitle,
    this.onClose,
  });

  final String taskId;
  final String? listTitle;
  final VoidCallback? onClose;

  @override
  ConsumerState<DetailViewScreen> createState() => _DetailViewScreenState();
}

class _DetailViewScreenState extends ConsumerState<DetailViewScreen> {
  final _titleController = TextEditingController();
  final _stepController = TextEditingController();
  final _noteController = TextEditingController();
  String? _syncedTaskId;

  @override
  void dispose() {
    _titleController.dispose();
    _stepController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _syncControllers(TaskItem task) {
    if (_syncedTaskId != task.id) {
      _syncedTaskId = task.id;
      _titleController.text = task.title;
      _noteController.text = task.note;
      _stepController.clear();
    }
  }

  String _recurrenceLabel(AppLocalizations l10n, RecurrenceType type) {
    return switch (type) {
      RecurrenceType.none => l10n.repeat,
      RecurrenceType.daily => l10n.repeatDaily,
      RecurrenceType.weekdays => l10n.repeatWeekdays,
      RecurrenceType.weekly => l10n.repeatWeekly,
      RecurrenceType.monthly => l10n.repeatMonthly,
      RecurrenceType.yearly => l10n.repeatYearly,
    };
  }

  Future<void> _pickDueDate(TaskItem task) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todoProvider.notifier);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: Text(l10n.today),
              onTap: () => Navigator.pop(ctx, 'today'),
            ),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: Text(l10n.tomorrow),
              onTap: () => Navigator.pop(ctx, 'tomorrow'),
            ),
            ListTile(
              leading: const Icon(Icons.next_week),
              title: Text(l10n.nextWeek),
              onTap: () => Navigator.pop(ctx, 'next_week'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(l10n.pickDate),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'today') {
      notifier.setTaskDueDate(task.id, today);
    } else if (choice == 'tomorrow') {
      notifier.setTaskDueDate(task.id, today.add(const Duration(days: 1)));
    } else if (choice == 'next_week') {
      notifier.setTaskDueDate(task.id, today.add(const Duration(days: 7)));
    } else if (choice == 'pick') {
      final picked = await showDatePicker(
        context: context,
        initialDate: task.dueDate ?? today,
        firstDate: today.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (picked != null) {
        notifier.setTaskDueDate(task.id, picked);
      }
    }
  }

  Future<void> _pickReminder(TaskItem task) async {
    final notifier = ref.read(todoProvider.notifier);
    final time = await showTimePicker(
      context: context,
      initialTime: task.reminderAt != null
          ? TimeOfDay.fromDateTime(task.reminderAt!)
          : TimeOfDay.now(),
    );
    if (time != null) {
      final now = DateTime.now();
      notifier.setTaskReminder(
        task.id,
        DateTime(now.year, now.month, now.day, time.hour, time.minute),
      );
    }
  }

  Future<void> _pickRecurrence(TaskItem task) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todoProvider.notifier);
    final options = [
      RecurrenceType.daily,
      RecurrenceType.weekdays,
      RecurrenceType.weekly,
      RecurrenceType.monthly,
      RecurrenceType.yearly,
    ];

    final picked = await showModalBottomSheet<RecurrenceType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in options)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: Text(_recurrenceLabel(l10n, type)),
                onTap: () => Navigator.pop(ctx, type),
              ),
          ],
        ),
      ),
    );

    if (picked != null) {
      notifier.setTaskRecurrence(task.id, picked);
    }
  }

  Future<void> _confirmDelete(TaskItem task) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todoProvider.notifier);
    final confirmRequired = ref.read(todoProvider).confirmBeforeDeleting;

    if (confirmRequired) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.deleteTaskTitle),
          content: Text(l10n.deleteTaskConfirm(task.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    notifier.deleteTask(task.id);
    if (widget.onClose != null) {
      widget.onClose!();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final notifier = ref.read(todoProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final task =
        state.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (task == null) {
      return const SizedBox.shrink();
    }

    _syncControllers(task);

    final primaryBg = isDark
        ? TodoColors.primaryBackgroundDark
        : TodoColors.primaryBackgroundLight;
    final bodyBg = isDark
        ? TodoColors.secondaryBackgroundDark
        : TodoColors.secondaryBackgroundLight;
    final cardBg = isDark ? TodoColors.cardDark : Colors.white;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;
    final accent =
        isDark ? TodoColors.attentionDark : TodoColors.attentionLight;

    final originListTitle = widget.listTitle ??
        state.lists
            .where((l) => l.id == task.listId)
            .map((l) => l.title)
            .firstOrNull ??
        l10n.tasks;

    return Scaffold(
      backgroundColor: bodyBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header (detailview_header.xml)
            Material(
              color: primaryBg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: widget.onClose ??
                              () => Navigator.of(context).pop(),
                          icon: Icon(
                            widget.onClose != null
                                ? Icons.close
                                : Icons.arrow_back,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            originListTitle,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 8, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        TaskCheckbox(
                          isChecked: task.isCompleted,
                          onTap: () => notifier.toggleTaskCompleted(task.id),
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _titleController,
                            maxLines: null,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (val) =>
                                notifier.updateTaskTitle(task.id, val),
                            onTapOutside: (_) => notifier.updateTaskTitle(
                              task.id,
                              _titleController.text,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              notifier.toggleTaskImportant(task.id),
                          icon: Icon(
                            task.isImportant ? Icons.star : Icons.star_outline,
                            color: task.isImportant ? accent : secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body (detailview_content.xml)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(10),
                children: [
                  // Steps card (detailview_step.xml + detailview_add_step.xml)
                  Card(
                    color: cardBg,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        for (final step in task.steps) ...[
                          Row(
                            children: [
                              const SizedBox(width: 8),
                              TaskCheckbox(
                                isChecked: step.isCompleted,
                                onTap: () => notifier.toggleStepCompleted(
                                  task.id,
                                  step.id,
                                ),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  step.title,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    decoration: step.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: step.isCompleted
                                        ? secondaryText
                                        : null,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    notifier.deleteStep(task.id, step.id),
                                icon: Icon(
                                  Icons.close,
                                  size: 18,
                                  color: secondaryText,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 1, indent: 48),
                        ],
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 22, color: accent),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextField(
                                  controller: _stepController,
                                  decoration: InputDecoration(
                                    hintText: l10n.addStepPlaceholder,
                                    hintStyle: TextStyle(color: accent),
                                    border: InputBorder.none,
                                  ),
                                  onSubmitted: (val) {
                                    notifier.addStep(task.id, val);
                                    _stepController.clear();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // My Day card (detailview_my_day.xml)
                  Card(
                    color: cardBg,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.wb_sunny_outlined,
                        color: task.isInMyDay ? accent : secondaryText,
                      ),
                      title: Text(
                        task.isInMyDay ? l10n.addedToMyDay : l10n.addToMyDay,
                        style: TextStyle(
                          color: task.isInMyDay ? accent : secondaryText,
                        ),
                      ),
                      trailing: task.isInMyDay
                          ? IconButton(
                              onPressed: () =>
                                  notifier.toggleTaskMyDay(task.id),
                              icon: Icon(Icons.close,
                                  size: 18, color: secondaryText),
                            )
                          : null,
                      onTap: () {
                        if (!task.isInMyDay) {
                          notifier.toggleTaskMyDay(task.id);
                        }
                      },
                    ),
                  ),

                  // Date / Reminder / Repeat card (detailview_date.xml)
                  Card(
                    color: cardBg,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            Icons.notifications_none,
                            color: task.reminderAt != null
                                ? accent
                                : secondaryText,
                          ),
                          title: Text(
                            task.reminderAt != null
                                ? DateFormat.jm().format(task.reminderAt!)
                                : l10n.remindMe,
                            style: TextStyle(
                              color: task.reminderAt != null
                                  ? accent
                                  : secondaryText,
                            ),
                          ),
                          trailing: task.reminderAt != null
                              ? IconButton(
                                  onPressed: () =>
                                      notifier.setTaskReminder(task.id, null),
                                  icon: Icon(Icons.close,
                                      size: 18, color: secondaryText),
                                )
                              : null,
                          onTap: () => _pickReminder(task),
                        ),
                        const Divider(height: 1, indent: 52),
                        ListTile(
                          leading: Icon(
                            Icons.calendar_today_outlined,
                            color: task.dueDate != null
                                ? (task.isOverdue
                                    ? TodoColors.overdueRed
                                    : accent)
                                : secondaryText,
                          ),
                          title: Text(
                            task.dueDate != null
                                ? DateFormat.yMMMd().format(task.dueDate!)
                                : l10n.addDueDate,
                            style: TextStyle(
                              color: task.dueDate != null
                                  ? (task.isOverdue
                                      ? TodoColors.overdueRed
                                      : accent)
                                  : secondaryText,
                            ),
                          ),
                          trailing: task.dueDate != null
                              ? IconButton(
                                  onPressed: () =>
                                      notifier.setTaskDueDate(task.id, null),
                                  icon: Icon(Icons.close,
                                      size: 18, color: secondaryText),
                                )
                              : null,
                          onTap: () => _pickDueDate(task),
                        ),
                        const Divider(height: 1, indent: 52),
                        ListTile(
                          leading: Icon(
                            Icons.repeat,
                            color: task.recurrence != RecurrenceType.none
                                ? accent
                                : secondaryText,
                          ),
                          title: Text(
                            _recurrenceLabel(l10n, task.recurrence),
                            style: TextStyle(
                              color: task.recurrence != RecurrenceType.none
                                  ? accent
                                  : secondaryText,
                            ),
                          ),
                          trailing: task.recurrence != RecurrenceType.none
                              ? IconButton(
                                  onPressed: () => notifier.setTaskRecurrence(
                                    task.id,
                                    RecurrenceType.none,
                                  ),
                                  icon: Icon(Icons.close,
                                      size: 18, color: secondaryText),
                                )
                              : null,
                          onTap: () => _pickRecurrence(task),
                        ),
                      ],
                    ),
                  ),

                  // Note card (detailview_note.xml)
                  Card(
                    color: cardBg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _noteController,
                        minLines: 4,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: l10n.addNotePlaceholder,
                          border: InputBorder.none,
                        ),
                        onChanged: (val) =>
                            notifier.updateTaskNote(task.id, val),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer (detailview_footer.xml)
            Material(
              color: primaryBg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(height: 1),
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            l10n.createdOn(
                              DateFormat.MMMd().format(task.createdAt),
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondaryText,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _confirmDelete(task),
                          icon: Icon(
                            Icons.delete_outline,
                            color: secondaryText,
                          ),
                          tooltip: l10n.delete,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
