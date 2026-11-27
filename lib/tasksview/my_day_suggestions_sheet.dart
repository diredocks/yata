import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';
import '../view/task_checkbox.dart';
import 'my_day_suggestions.dart';
import 'recyclerview/animated_task_sliver_list.dart';
import 'tasks_action_presenter.dart';
import 'tasks_view_grouping.dart';
import 'tasks_view_presenter.dart';

/// Bottom-center floating pill button matching `suggestions_entry_point`
/// in `tasksview_layout.xml`, using the same color scheme as the add FAB.
class MyDaySuggestionsButton extends StatelessWidget {
  const MyDaySuggestionsButton({
    super.key,
    required this.currentList,
    required this.label,
    required this.onPressed,
  });

  final TodoList currentList;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fabColors = TodoColors.fabColorsFor(
      currentList,
      brightness: Theme.of(context).brightness,
    );

    return Material(
      color: fabColors.background,
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const ValueKey('my_day_suggestions_button'),
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 23, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 20,
                  color: fabColors.foreground,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: fabColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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

/// Opens the My Day Suggestions bottom sheet computed from local incomplete
/// tasks that are not yet in My Day.
Future<void> showMyDaySuggestionsSheet({
  required BuildContext context,
  required Color accentColor,
  required ValueChanged<TaskItem> onOpenTask,
}) {
  final isWide = MediaQuery.sizeOf(context).width >= 600;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) {
          return _MyDaySuggestionsSheetBody(
            accentColor: accentColor,
            scrollController: scrollController,
            onOpenTask: (task) {
              if (isWide) Navigator.of(sheetContext).pop();
              onOpenTask(task);
            },
          );
        },
      );
    },
  );
}

class _MyDaySuggestionsSheetBody extends ConsumerWidget {
  const _MyDaySuggestionsSheetBody({
    required this.accentColor,
    required this.scrollController,
    required this.onOpenTask,
  });

  final Color accentColor;
  final ScrollController scrollController;
  final ValueChanged<TaskItem> onOpenTask;

  String _bucketTitle(AppLocalizations l10n, SuggestionBucketType type) {
    return switch (type) {
      SuggestionBucketType.today => l10n.suggestionsBucketToday,
      SuggestionBucketType.yesterday => l10n.suggestionsBucketYesterday,
      SuggestionBucketType.overdue => l10n.suggestionsBucketOverdue,
      SuggestionBucketType.upcoming => l10n.suggestionsBucketUpcoming,
      SuggestionBucketType.recentlyAdded => l10n.suggestionsBucketRecentlyAdded,
    };
  }

  String? _subtitleFor(
    AppLocalizations l10n,
    TaskItem task,
    String? originListName,
  ) {
    final parts = <String>[
      if (originListName != null && originListName.isNotEmpty) originListName,
      if (task.dueDate != null)
        l10n.dueOn(DateFormat.MMMd().format(task.dueDate!)),
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  Widget _bucketHeaderSliver({
    required AppLocalizations l10n,
    required ThemeData theme,
    required bool isDark,
    required SuggestionBucketType type,
    required bool isVisible,
  }) {
    return SliverToBoxAdapter(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: isVisible
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text(
                    _bucketTitle(l10n, type),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isDark
                          ? TodoColors.secondaryTextDark
                          : TodoColors.secondaryTextLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(todoProvider);
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    final buckets = computeMyDaySuggestions(state.tasks);
    final tasksByBucket = <SuggestionBucketType, List<TaskItem>>{
      for (final bucket in buckets) bucket.type: bucket.tasks,
    };

    Widget buildSuggestionRow(TaskItem task) => _SuggestionTaskRow(
      task: task,
      subtitle: _subtitleFor(
        l10n,
        task,
        resolveOriginListName(l10n, state.lists, task.listId),
      ),
      accentColor: accentColor,
      isDark: isDark,
      addTooltip: l10n.addToMyDay,
      onTap: () => onOpenTask(task),
      onAddToMyDay: () => actionPresenter.batchSetMyDay({task.id}, true),
      onToggleComplete: () =>
          ref.read(tasksViewPresenterProvider).toggleTaskCompleted(task.id),
    );

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? TodoColors.secondaryTextDark.withValues(alpha: 0.4)
                    : TodoColors.secondaryTextLight.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: accentColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.suggestions,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.done,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                for (final type in SuggestionBucketType.values) ...[
                  _bucketHeaderSliver(
                    l10n: l10n,
                    theme: theme,
                    isDark: isDark,
                    type: type,
                    isVisible: tasksByBucket.containsKey(type),
                  ),
                  CollapsibleTaskBucketSliver(
                    key: ValueKey('suggestion_bucket_${type.name}'),
                    isExpanded: tasksByBucket.containsKey(type),
                    tasks: tasksByBucket[type] ?? const <TaskItem>[],
                    padding: EdgeInsets.zero,
                    itemBuilder: (context, task) => buildSuggestionRow(task),
                  ),
                ],
                if (buckets.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 48,
                              color: isDark
                                  ? TodoColors.secondaryTextDark
                                  : TodoColors.secondaryTextLight,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.suggestionsEmpty,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isDark
                                    ? TodoColors.secondaryTextDark
                                    : TodoColors.secondaryTextLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionTaskRow extends StatelessWidget {
  const _SuggestionTaskRow({
    required this.task,
    required this.subtitle,
    required this.accentColor,
    required this.isDark,
    required this.addTooltip,
    required this.onTap,
    required this.onAddToMyDay,
    required this.onToggleComplete,
  });

  final TaskItem task;
  final String? subtitle;
  final Color accentColor;
  final bool isDark;
  final String addTooltip;
  final VoidCallback onTap;
  final VoidCallback onAddToMyDay;
  final VoidCallback onToggleComplete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            TaskCheckbox(
              isChecked: task.isCompleted,
              accentColor: accentColor,
              onTap: onToggleComplete,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: task.isOverdue
                            ? TodoColors.overdueRed
                            : (isDark
                                  ? TodoColors.secondaryTextDark
                                  : TodoColors.secondaryTextLight),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              key: ValueKey('add_suggestion_${task.id}'),
              icon: Icon(Icons.add, color: accentColor),
              tooltip: addTooltip,
              onPressed: onAddToMyDay,
            ),
          ],
        ),
      ),
    );
  }
}
