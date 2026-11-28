import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/state/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';
import '../ui/task_grouping.dart';

String sortOptionLabel(AppLocalizations l10n, TaskSortOption option) {
  return switch (option) {
    TaskSortOption.defaultOrder => l10n.sortByDefault,
    TaskSortOption.importance => l10n.sortByImportance,
    TaskSortOption.dueDate => l10n.sortByDueDate,
    TaskSortOption.addedToMyDay => l10n.sortByAddedToMyDay,
    TaskSortOption.alphabetical => l10n.sortByAlphabetical,
    TaskSortOption.creationDate => l10n.sortByCreationDate,
  };
}

String plannedBucketLabel(AppLocalizations l10n, PlannedBucket bucket) {
  return switch (bucket) {
    PlannedBucket.earlier => l10n.plannedEarlier,
    PlannedBucket.today => l10n.today,
    PlannedBucket.tomorrow => l10n.tomorrow,
    PlannedBucket.thisWeek => l10n.plannedThisWeek,
    PlannedBucket.later => l10n.plannedLater,
  };
}

String plannedFilterLabel(AppLocalizations l10n, PlannedDueDateFilter filter) {
  return switch (filter) {
    PlannedDueDateFilter.all => l10n.filterAllPlanned,
    PlannedDueDateFilter.overdue => l10n.filterOverdue,
    PlannedDueDateFilter.today => l10n.filterToday,
    PlannedDueDateFilter.tomorrow => l10n.filterTomorrow,
    PlannedDueDateFilter.thisWeek => l10n.filterThisWeek,
    PlannedDueDateFilter.later => l10n.filterLater,
  };
}

/// Formats a Planned filter option label for the filter menu, appending
/// date context in parentheses for Today, Tomorrow, and This week
/// (matching `PopupMenuUtils.s` in `mstodo.apk`).
String plannedFilterMenuLabel(
  AppLocalizations l10n,
  PlannedDueDateFilter filter, {
  DateTime? now,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final locale = l10n.localeName == 'en'
      ? null
      : (DateFormat.localeExists(l10n.localeName) ? l10n.localeName : null);
  return switch (filter) {
    PlannedDueDateFilter.today => l10n.labelWithHint(
      l10n.filterToday,
      DateFormat.E(locale).format(today),
    ),
    PlannedDueDateFilter.tomorrow => l10n.labelWithHint(
      l10n.filterTomorrow,
      DateFormat.E(locale).format(today.add(const Duration(days: 1))),
    ),
    PlannedDueDateFilter.thisWeek => () {
      final weekEnd = today.add(const Duration(days: 6));
      return l10n.labelWithHint(
        l10n.filterThisWeek,
        l10n.dateRangeShort(
          today.day,
          weekEnd.day,
          DateFormat.MMM(locale).format(weekEnd),
        ),
      );
    }(),
    _ => plannedFilterLabel(l10n, filter),
  };
}

Future<void> showTasksSortSheet({
  required BuildContext context,
  required TodoList currentList,
  required ValueChanged<TaskSortOption> onSelectSortOption,
}) async {
  final l10n = AppLocalizations.of(context);
  final options = <(TaskSortOption, String, IconData)>[
    (TaskSortOption.importance, l10n.sortByImportance, Icons.star_outline),
    (TaskSortOption.dueDate, l10n.sortByDueDate, Icons.calendar_today_outlined),
    (
      TaskSortOption.addedToMyDay,
      l10n.sortByAddedToMyDay,
      Icons.wb_sunny_outlined,
    ),
    (TaskSortOption.alphabetical, l10n.sortByAlphabetical, Icons.sort_by_alpha),
    (TaskSortOption.creationDate, l10n.sortByCreationDate, Icons.access_time),
  ];

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.sortBy,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (final (option, label, icon) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: currentList.sortOption == option
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                onSelectSortOption(option);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> showPlannedGroupSheet({
  required BuildContext context,
  required PlannedGroupOption currentOption,
  required ValueChanged<PlannedGroupOption> onSelectGroupOption,
}) async {
  final l10n = AppLocalizations.of(context);
  final options = <(PlannedGroupOption, String, IconData)>[
    (
      PlannedGroupOption.byDueDate,
      l10n.groupByDueDate,
      Icons.calendar_today_outlined,
    ),
    (PlannedGroupOption.byList, l10n.groupByList, Icons.format_list_bulleted),
    (
      PlannedGroupOption.ungroup,
      l10n.groupByUngroup,
      Icons.view_stream_outlined,
    ),
  ];

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.groupBy,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (final (option, label, icon) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: currentOption == option
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                onSelectGroupOption(option);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> showPlannedFilterSheet({
  required BuildContext context,
  required PlannedDueDateFilter currentFilter,
  required ValueChanged<PlannedDueDateFilter> onSelectFilter,
}) async {
  final l10n = AppLocalizations.of(context);
  final options = <(PlannedDueDateFilter, String, IconData)>[
    (
      PlannedDueDateFilter.all,
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.all),
      Icons.all_inclusive,
    ),
    (
      PlannedDueDateFilter.overdue,
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.overdue),
      Icons.warning_amber_outlined,
    ),
    (
      PlannedDueDateFilter.today,
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.today),
      Icons.today_outlined,
    ),
    (
      PlannedDueDateFilter.tomorrow,
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.tomorrow),
      Icons.wb_twilight_outlined,
    ),
    (
      PlannedDueDateFilter.thisWeek,
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.thisWeek),
      Icons.date_range_outlined,
    ),
    (
      PlannedDueDateFilter.later,
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.later),
      Icons.event_outlined,
    ),
  ];

  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.filterDueDate,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 1),
          for (final (filter, label, icon) in options)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: currentFilter == filter
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                onSelectFilter(filter);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}

Future<bool> showTasksConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<String?> pickTargetListSheet({
  required BuildContext context,
  required TodoState state,
  required String sheetTitle,
}) async {
  final l10n = AppLocalizations.of(context);
  final selectableLists = state.lists
      .where((l) => !l.isSmartList || l.smartType == SmartListType.tasks)
      .toList();

  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(sheetTitle, style: Theme.of(ctx).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final list in selectableLists)
                  ListTile(
                    leading: Icon(
                      list.icon,
                      color: TodoColors.listAccentFor(
                        list,
                        brightness: Theme.of(ctx).brightness,
                      ),
                    ),
                    title: Text(
                      list.smartType == SmartListType.tasks
                          ? l10n.tasks
                          : list.title,
                    ),
                    onTap: () => Navigator.pop(ctx, list.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<bool?> promptKeepCompletedOnDuplicate(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.keepTasksCompletedTitle),
      content: Text(l10n.keepTasksCompletedMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.no),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.yes),
        ),
      ],
    ),
  );
}
