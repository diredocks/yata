import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../data/todo_provider.dart';
import '../tasksview/completion_sound_service.dart';
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
    final notifier = ref.read(detailViewPresenterProvider);
    final picked = await showRecurrencePickerSheet(
      context,
      initialRecurrence: task.recurrence,
      initialRawRecurrence: task.rawRecurrence,
      dueDate: task.dueDate,
    );

    if (picked != null && mounted) {
      notifier.setTaskRecurrence(
        task.id,
        picked.recurrence,
        rawRecurrence: picked.rawRecurrence,
      );
    }
  }

  Future<void> _confirmDeleteStep(TaskItem task, String stepId) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(detailViewPresenterProvider);
    final confirmRequired = ref.read(todoProvider).confirmBeforeDeleting;

    if (confirmRequired) {
      final stepTitle =
          task.steps
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

    final useDynamicColors =
        state.useDynamicColor &&
        theme.scaffoldBackgroundColor != TodoColors.primaryBackgroundLight &&
        theme.scaffoldBackgroundColor != TodoColors.primaryBackgroundDark;
    final primaryBg = useDynamicColors
        ? theme.colorScheme.surfaceContainerLow
        : TodoColors.detailHeaderBackground(theme.brightness);
    final bodyBg = useDynamicColors
        ? theme.scaffoldBackgroundColor
        : TodoColors.detailBodyBackground(theme.brightness);
    final cardBg = useDynamicColors
        ? theme.colorScheme.surfaceContainerLow
        : (isDark ? TodoColors.secondaryBackgroundDark : Colors.white);
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;

    final originList = state.lists
        .where((l) => l.id == task.listId)
        .firstOrNull;
    final listAccent = originList == null
        ? (isDark ? TodoColors.attentionDark : TodoColors.attentionLight)
        : TodoColors.listAccentFor(originList, brightness: theme.brightness);
    final originListTitle =
        widget.listTitle ??
        (originList == null
            ? l10n.tasks
            : (originList.smartType == SmartListType.tasks
                  ? l10n.tasks
                  : originList.title));

    final detailContent = _DetailHeroContainer(
      taskId: widget.taskId,
      enabled: widget.onClose == null,
      cardColor: cardBg,
      bodyColor: bodyBg,
      child: Scaffold(
        backgroundColor: bodyBg,
        body: Column(
          children: [
            ColoredBox(
              color: primaryBg,
              child: SafeArea(
                bottom: false,
                child: DetailsHeaderView(
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
                  onToggleImportant: () =>
                      notifier.toggleTaskImportant(task.id),
                  onTitleSubmitted: (val) =>
                      notifier.updateTaskTitle(task.id, val),
                  onClose: widget.onClose,
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
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
                            onDeleteStep: (stepId) =>
                                _confirmDeleteStep(task, stepId),
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
                                  recurrenceLabel: formatRecurrenceLabel(
                                    l10n,
                                    task.recurrence,
                                    task.rawRecurrence,
                                  ),
                                  onPickReminder: () =>
                                      _pickReminder(task, state.startOfWeek),
                                  onClearReminder: () =>
                                      notifier.setTaskReminder(task.id, null),
                                  onPickDueDate: () =>
                                      _pickDueDate(task, state.startOfWeek),
                                  onClearDueDate: () =>
                                      notifier.setTaskDueDate(task.id, null),
                                  onPickRecurrence: () => _pickRecurrence(task),
                                  onClearRecurrence: () =>
                                      notifier.setTaskRecurrence(
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
                    _DetailFooterBar(
                      backgroundColor: primaryBg,
                      textColor: secondaryText,
                      createdAt: task.createdAt,
                      deleteTooltip: l10n.delete,
                      onDelete: () => _confirmDelete(task),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.onClose != null) {
      return detailContent;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: TodoTheme.systemUiOverlayStyleFor(primaryBg),
      child: detailContent,
    );
  }
}

class _DetailHeroContainer extends StatelessWidget {
  const _DetailHeroContainer({
    required this.taskId,
    required this.enabled,
    required this.cardColor,
    required this.bodyColor,
    required this.child,
  });

  final String taskId;
  final bool enabled;
  final Color cardColor;
  final Color bodyColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HeroMode(
      enabled: enabled,
      child: Hero(
        tag: 'task_card_$taskId',
        flightShuttleBuilder:
            (
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
                    color: Color.lerp(cardColor, bodyColor, curved.value),
                    borderRadius: BorderRadius.circular(radius),
                    elevation: 1.0 * (1.0 - curved.value),
                  );
                },
              );
            },
        child: child,
      ),
    );
  }
}

class _DetailFooterBar extends StatelessWidget {
  const _DetailFooterBar({
    required this.backgroundColor,
    required this.textColor,
    required this.createdAt,
    required this.deleteTooltip,
    required this.onDelete,
  });

  final Color backgroundColor;
  final Color textColor;
  final DateTime createdAt;
  final String deleteTooltip;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: backgroundColor,
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
                    formatCreatedDateLabel(context, createdAt),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: textColor),
                  tooltip: deleteTooltip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
