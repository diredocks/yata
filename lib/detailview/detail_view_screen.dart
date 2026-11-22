import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../services/completion_sound_service.dart';
import '../theme/todo_theme.dart';
import 'detail_view_presenter.dart';
import 'details/detail_cards.dart';
import 'header/details_header_view.dart';
import 'note/note_card_view.dart';
import 'recurrence/task_pickers.dart';
import 'steps/steps_section.dart';

/// Task detail view matching `detailview/DetailViewFragment`.
/// Route matching the original app's `DetailViewActivity` shared-element
/// expand/collapse + fade transition (`detailview_shared_enter.xml` &
/// `detailview_enter.xml` / `detailview_return.xml`).
Route<void> buildDetailViewRoute({required String taskId}) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) =>
        DetailViewScreen(taskId: taskId),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

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
      includeRemoveOption: task.dueDate != null,
    );
    if (result == null || !mounted) return;
    if (result.cleared) {
      ref.read(detailViewPresenterProvider).setTaskDueDate(task.id, null);
    } else if (result.date != null) {
      ref
          .read(detailViewPresenterProvider)
          .setTaskDueDate(task.id, result.date);
    }
  }

  Future<void> _pickReminder(TaskItem task, WeekStart startOfWeek) async {
    final picked = await showReminderPickerSheet(
      context,
      startOfWeek: startOfWeek,
      initialReminder: task.reminderAt,
    );
    if (picked != null && mounted) {
      ref.read(detailViewPresenterProvider).setTaskReminder(task.id, picked);
    }
  }

  Future<void> _pickRecurrence(TaskItem task) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(detailViewPresenterProvider);
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

  Future<void> _confirmDeleteStep(TaskItem task, String stepId) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(detailViewPresenterProvider);
    final confirmRequired = ref.read(todoProvider).confirmBeforeDeleting;

    if (confirmRequired) {
      final stepTitle = task.steps
              .where((s) => s.id == stepId)
              .map((s) => s.title)
              .firstOrNull ??
          '';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.deleteStep),
          content: Text(l10n.deleteTaskConfirm(stepTitle)),
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

    notifier.deleteStep(task.id, stepId);
  }

  Future<void> _confirmDelete(TaskItem task) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(detailViewPresenterProvider);
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
    final notifier = ref.read(detailViewPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final task = state.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (task == null) {
      return const SizedBox.shrink();
    }

    final primaryBg = TodoColors.detailHeaderBackground(theme.brightness);
    final bodyBg = TodoColors.detailBodyBackground(theme.brightness);
    final cardBg = isDark ? TodoColors.secondaryBackgroundDark : Colors.white;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;

    final originList =
        state.lists.where((l) => l.id == task.listId).firstOrNull;
    final listAccent = originList == null
        ? (isDark ? TodoColors.attentionDark : TodoColors.attentionLight)
        : (originList.themePhoto != null
            ? TodoColors.photoFabBackgroundFor(originList.themePhoto!)
            : TodoColors.accentFor(
                originList.themeColor,
                brightness: theme.brightness,
              ));
    final originListTitle = widget.listTitle ??
        (originList == null
            ? l10n.tasks
            : (originList.smartType == SmartListType.tasks
                ? l10n.tasks
                : originList.title));

    return HeroMode(
      enabled: widget.onClose == null,
      child: Hero(
        tag: 'task_card_${widget.taskId}',
        flightShuttleBuilder: (
          flightContext,
          animation,
          flightDirection,
          fromHeroContext,
          toHeroContext,
        ) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return AnimatedBuilder(
            animation: curved,
            builder: (context, _) {
              final radius = 4.0 * (1.0 - curved.value);
              return Material(
                color: Color.lerp(cardBg, bodyBg, curved.value),
                borderRadius: BorderRadius.circular(radius),
                elevation: 1.0 * (1.0 - curved.value),
              );
            },
          );
        },
        child: Scaffold(
          backgroundColor: bodyBg,
      body: SafeArea(
        child: Column(
          children: [
            DetailsHeaderView(
              task: task,
              originListTitle: originListTitle,
              backgroundColor: primaryBg,
              accentColor: listAccent,
              onToggleCompleted: () {
                if (!task.isCompleted) {
                  ref.read(completionSoundServiceProvider).playIfEnabled();
                }
                notifier.toggleTaskCompleted(task.id);
              },
              onToggleImportant: () => notifier.toggleTaskImportant(task.id),
              onTitleSubmitted: (val) => notifier.updateTaskTitle(task.id, val),
              onClose: widget.onClose,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  StepsSection(
                    task: task,
                    backgroundColor: primaryBg,
                    accentColor: listAccent,
                    onToggleStepCompleted: (stepId) =>
                        notifier.toggleStepCompleted(task.id, stepId),
                    onRenameStep: (stepId, val) =>
                        notifier.renameStep(task.id, stepId, val),
                    onPromoteStepToTask: (stepId) =>
                        notifier.promoteStepToTask(task.id, stepId),
                    onDeleteStep: (stepId) => _confirmDeleteStep(task, stepId),
                    onAddStep: (val) => notifier.addStep(task.id, val),
                  ),
                  Container(
                    height: 3,
                    decoration: TodoColors.horizontalShadowDecoration,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        MyDayCardView(
                          task: task,
                          cardColor: cardBg,
                          accentColor: listAccent,
                          onToggleMyDay: () =>
                              notifier.toggleTaskMyDay(task.id),
                        ),
                        TaskSchedulingCardView(
                          task: task,
                          cardColor: cardBg,
                          accentColor: listAccent,
                          recurrenceLabel:
                              _recurrenceLabel(l10n, task.recurrence),
                          onPickReminder: () =>
                              _pickReminder(task, state.startOfWeek),
                          onClearReminder: () =>
                              notifier.setTaskReminder(task.id, null),
                          onPickDueDate: () =>
                              _pickDueDate(task, state.startOfWeek),
                          onClearDueDate: () =>
                              notifier.setTaskDueDate(task.id, null),
                          onPickRecurrence: () => _pickRecurrence(task),
                          onClearRecurrence: () => notifier.setTaskRecurrence(
                            task.id,
                            RecurrenceType.none,
                          ),
                        ),
                        NoteCardView(
                          task: task,
                          cardColor: cardBg,
                          onNoteChanged: (val) =>
                              notifier.updateTaskNote(task.id, val),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
                            formatCreatedDateLabel(context, task.createdAt),
                            style: theme.textTheme.bodyMedium?.copyWith(
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
        ),
      ),
    );
  }
}
