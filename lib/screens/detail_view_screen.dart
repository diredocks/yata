import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import '../widgets/task_checkbox.dart';
import '../widgets/task_pickers.dart';

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
  final _stepEditController = TextEditingController();
  final _noteController = TextEditingController();
  final _addStepFocusNode = FocusNode();
  String? _syncedTaskId;
  bool _isEditingTitle = false;
  String? _editingStepId;
  bool _isAddStepFocused = false;

  @override
  void initState() {
    super.initState();
    _addStepFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isAddStepFocused = _addStepFocusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _stepController.dispose();
    _stepEditController.dispose();
    _noteController.dispose();
    _addStepFocusNode.dispose();
    super.dispose();
  }

  void _syncControllers(TaskItem task) {
    if (_syncedTaskId != task.id) {
      _syncedTaskId = task.id;
      _titleController.text = task.title;
      _noteController.text = task.note;
      _stepController.clear();
      _isEditingTitle = false;
      _editingStepId = null;
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

  Future<void> _pickDueDate(TaskItem task, WeekStart startOfWeek) async {
    final result = await showDueDatePickerSheet(
      context,
      startOfWeek: startOfWeek,
      initialDate: task.dueDate,
    );
    if (result != null && result.date != null && mounted) {
      ref.read(todoProvider.notifier).setTaskDueDate(task.id, result.date);
    }
  }

  Future<void> _pickReminder(TaskItem task, WeekStart startOfWeek) async {
    final picked = await showReminderPickerSheet(
      context,
      startOfWeek: startOfWeek,
      initialReminder: task.reminderAt,
    );
    if (picked != null && mounted) {
      ref.read(todoProvider.notifier).setTaskReminder(task.id, picked);
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

    final primaryBg = TodoColors.detailHeaderBackground(theme.brightness);
    final bodyBg = TodoColors.detailBodyBackground(theme.brightness);
    final cardBg = isDark ? TodoColors.secondaryBackgroundDark : Colors.white;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;
    final accent =
        isDark ? TodoColors.attentionDark : TodoColors.attentionLight;

    final originListTitle = widget.listTitle ??
        state.lists
            .where((l) => l.id == task.listId)
            .map(
              (l) => l.smartType == SmartListType.tasks ? l10n.tasks : l.title,
            )
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
                    padding: const EdgeInsets.fromLTRB(6, 0, 4, 12),
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
                          child: _isEditingTitle
                              ? TextField(
                                  controller: _titleController,
                                  autofocus: true,
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
                                  onSubmitted: (val) {
                                    notifier.updateTaskTitle(task.id, val);
                                    setState(() => _isEditingTitle = false);
                                  },
                                  onTapOutside: (_) {
                                    notifier.updateTaskTitle(
                                      task.id,
                                      _titleController.text,
                                    );
                                    setState(() => _isEditingTitle = false);
                                  },
                                )
                              : GestureDetector(
                                  onTap: () {
                                    _titleController.text = task.title;
                                    setState(() => _isEditingTitle = true);
                                  },
                                  child: Text(
                                    task.title,
                                    style:
                                        theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      decoration: task.isCompleted
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
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
                padding: EdgeInsets.zero,
                children: [
                  // Steps section on @color/detailview_background (detailview_step.xml + detailview_add_step.xml)
                  Material(
                    color: primaryBg,
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
                                child: _editingStepId == step.id
                                    ? TextField(
                                        controller: _stepEditController,
                                        autofocus: true,
                                        style: theme.textTheme.bodyMedium,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                        ),
                                        onSubmitted: (val) {
                                          notifier.renameStep(
                                            task.id,
                                            step.id,
                                            val,
                                          );
                                          setState(() => _editingStepId = null);
                                        },
                                        onTapOutside: (_) {
                                          notifier.renameStep(
                                            task.id,
                                            step.id,
                                            _stepEditController.text,
                                          );
                                          setState(() => _editingStepId = null);
                                        },
                                      )
                                    : GestureDetector(
                                        onTap: () {
                                          _stepEditController.text = step.title;
                                          setState(
                                            () => _editingStepId = step.id,
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: Text(
                                            step.title,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              decoration: step.isCompleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: step.isCompleted
                                                  ? secondaryText
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_vert,
                                    size: 20,
                                    color: secondaryText,
                                  ),
                                  onSelected: (action) {
                                    if (action == 'promote') {
                                      notifier.promoteStepToTask(
                                        task.id,
                                        step.id,
                                      );
                                    } else if (action == 'delete') {
                                      notifier.deleteStep(task.id, step.id);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'promote',
                                      child: ListTile(
                                        leading: const Icon(Icons.add),
                                        title: Text(l10n.promoteStepToTask),
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: ListTile(
                                        leading:
                                            const Icon(Icons.delete_outline),
                                        title: Text(l10n.deleteStep),
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 1, indent: 66, endIndent: 16),
                        ],
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 4, 12, 8),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 160),
                                child: _isAddStepFocused
                                    ? Container(
                                        key: const ValueKey('step_circle'),
                                        width: 18,
                                        height: 18,
                                        margin: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: secondaryText,
                                            width: 1.6,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.add,
                                        key: const ValueKey('step_plus'),
                                        size: 22,
                                        color: accent,
                                      ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextField(
                                  controller: _stepController,
                                  focusNode: _addStepFocusNode,
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
                  // Header + Steps shadow (default_shadow_horizontal.xml)
                  Container(
                    height: 3,
                    decoration: TodoColors.horizontalShadowDecoration,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [

                  // My Day card (detailview_my_day.xml)
                  Card(
                    color: cardBg,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _DetailActionRow(
                      icon: Icons.wb_sunny_outlined,
                      iconColor: task.isInMyDay ? accent : secondaryText,
                      label: task.isInMyDay
                          ? l10n.addedToMyDay
                          : l10n.addToMyDay,
                      labelColor: task.isInMyDay ? accent : secondaryText,
                      removeColor: secondaryText,
                      onTap: () {
                        if (!task.isInMyDay) {
                          notifier.toggleTaskMyDay(task.id);
                        }
                      },
                      onRemove: task.isInMyDay
                          ? () => notifier.toggleTaskMyDay(task.id)
                          : null,
                    ),
                  ),

                  // Date / Reminder / Repeat card (detailview_date.xml)
                  Card(
                    color: cardBg,
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        _DetailActionRow(
                          icon: Icons.notifications_none,
                          iconColor: task.reminderAt != null
                              ? accent
                              : secondaryText,
                          label: task.reminderAt != null
                              ? DateFormat.MMMd()
                                  .add_jm()
                                  .format(task.reminderAt!)
                              : l10n.remindMe,
                          labelColor: task.reminderAt != null
                              ? accent
                              : secondaryText,
                          removeColor: secondaryText,
                          onTap: () => _pickReminder(task, state.startOfWeek),
                          onRemove: task.reminderAt != null
                              ? () => notifier.setTaskReminder(task.id, null)
                              : null,
                        ),
                        const Divider(height: 1, indent: 64),
                        _DetailActionRow(
                          icon: Icons.calendar_today_outlined,
                          iconColor: task.dueDate != null
                              ? (task.isOverdue
                                  ? TodoColors.overdueRed
                                  : accent)
                              : secondaryText,
                          label: task.dueDate != null
                              ? DateFormat.yMMMd().format(task.dueDate!)
                              : l10n.addDueDate,
                          labelColor: task.dueDate != null
                              ? (task.isOverdue
                                  ? TodoColors.overdueRed
                                  : accent)
                              : secondaryText,
                          removeColor: secondaryText,
                          onTap: () => _pickDueDate(task, state.startOfWeek),
                          onRemove: task.dueDate != null
                              ? () => notifier.setTaskDueDate(task.id, null)
                              : null,
                        ),
                        const Divider(height: 1, indent: 64),
                        _DetailActionRow(
                          icon: Icons.repeat,
                          iconColor: task.recurrence != RecurrenceType.none
                              ? accent
                              : secondaryText,
                          label: _recurrenceLabel(l10n, task.recurrence),
                          labelColor: task.recurrence != RecurrenceType.none
                              ? accent
                              : secondaryText,
                          removeColor: secondaryText,
                          onTap: () => _pickRecurrence(task),
                          onRemove: task.recurrence != RecurrenceType.none
                              ? () => notifier.setTaskRecurrence(
                                    task.id,
                                    RecurrenceType.none,
                                  )
                              : null,
                        ),
                      ],
                    ),
                  ),

                  // Note card (detailview_note.xml)
                  Card(
                    color: cardBg,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 132),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextField(
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
                            if (task.noteUpdatedAt != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                l10n.updatedOn(
                                  DateFormat.MMMd()
                                      .add_jm()
                                      .format(task.noteUpdatedAt!),
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: secondaryText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer (detailview_footer.xml)
            Material(
              color: primaryBg,
              elevation: 3,
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

/// Row layout matching `DetailViewCardRow` & `DetailViewRowRemove` in `styles.xml`.
class _DetailActionRow extends StatelessWidget {
  const _DetailActionRow({
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
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      color: labelColor,
                    ),
              ),
            ),
            if (onRemove != null)
              InkWell(
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
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}
