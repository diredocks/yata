import 'dart:convert';

import 'package:intl/intl.dart';

import '../data/state/todo_state.dart';
import '../ui/widgets/task_pickers.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import 'tasks_view_dialogs.dart';
import '../ui/task_grouping.dart';

typedef ExportTaskGroup = ({
  String? header,
  bool isListBucket,
  List<TaskItem> tasks,
});

/// Builds the ordered task groups for [currentList] matching the current UI
/// grouping and completed-visibility settings.
List<ExportTaskGroup> buildExportTaskGroups({
  required AppLocalizations l10n,
  required TodoState state,
  required TodoList currentList,
}) {
  final allTasks = state.tasksForList(currentList);
  final (:active, :completed) = splitTasksForDisplay(allTasks, currentList);
  final groups = <ExportTaskGroup>[];

  if (currentList.smartType == SmartListType.planned &&
      currentList.sortOption == TaskSortOption.defaultOrder) {
    switch (state.plannedGroupOption) {
      case PlannedGroupOption.byDueDate:
        for (final group in groupPlannedTasks(active, state.startOfWeek)) {
          groups.add((
            header: plannedBucketLabel(l10n, group.bucket),
            isListBucket: false,
            tasks: group.tasks,
          ));
        }
      case PlannedGroupOption.byList:
        for (final group in groupTasksByList(l10n, active, state.lists)) {
          groups.add((
            header: group.title,
            isListBucket: true,
            tasks: group.tasks,
          ));
        }
      case PlannedGroupOption.ungroup:
        if (active.isNotEmpty) {
          groups.add((header: null, isListBucket: false, tasks: active));
        }
    }
  } else if ((currentList.smartType == SmartListType.all ||
          currentList.smartType == SmartListType.completed) &&
      currentList.sortOption == TaskSortOption.defaultOrder) {
    for (final group in groupTasksByList(l10n, active, state.lists)) {
      groups.add((header: group.title, isListBucket: true, tasks: group.tasks));
    }
  } else if (active.isNotEmpty) {
    groups.add((header: null, isListBucket: false, tasks: active));
  }

  if (currentList.showCompleted && completed.isNotEmpty) {
    groups.add((header: l10n.completed, isListBucket: false, tasks: completed));
  }

  return groups;
}

/// Formats a list and its tasks as plain text for "Send a copy", matching
/// Microsoft To Do's `yp.n` format.
String formatListForShare({
  required AppLocalizations l10n,
  required TodoState state,
  required TodoList currentList,
  DateTime? now,
}) {
  final listTitle = _displayListTitle(l10n, currentList);
  final groups = buildExportTaskGroups(
    l10n: l10n,
    state: state,
    currentList: currentList,
  );
  final buffer = StringBuffer()
    ..write(listTitle)
    ..write('\n\n');

  final locale = _dateLocale(l10n);
  final referenceNow = (now ?? DateTime.now()).toLocal();

  for (final group in groups) {
    if (group.tasks.isEmpty) continue;
    if (group.header != null && group.header!.isNotEmpty) {
      buffer
        ..write(group.header)
        ..write('\n');
    }
    for (final task in group.tasks) {
      buffer
        ..write('\u2002\u2002')
        ..write(task.isCompleted ? '✔ ' : '❏ ')
        ..write(task.title);
      if (task.dueDate != null) {
        final formattedDate = formatRelativeDate(
          l10n,
          task.dueDate!,
          now: referenceNow,
          locale: locale,
        );
        buffer
          ..write(' (')
          ..write(formattedDate)
          ..write(')');
      }
      if (task.isImportant) {
        buffer.write(' ✭');
      }
      buffer.write('\n');

      for (final step in task.steps) {
        buffer
          ..write('\u2002\u2002\u2002')
          ..write(step.isCompleted ? '✔ ' : '❏ ')
          ..write(step.title)
          ..write('\n');
      }
    }
  }

  return buffer.toString();
}

/// Formats a list and its tasks as printable HTML, matching Microsoft To Do's
/// `fq.a` print layout.
String formatListForPrintHtml({
  required AppLocalizations l10n,
  required TodoState state,
  required TodoList currentList,
  DateTime? now,
}) {
  final escape = const HtmlEscape().convert;
  final referenceNow = (now ?? DateTime.now()).toLocal();
  final locale = _dateLocale(l10n);
  final listTitle = _displayListTitle(l10n, currentList);
  final dateHeader = DateFormat.yMMMMd(locale).format(referenceNow);
  final groups = buildExportTaskGroups(
    l10n: l10n,
    state: state,
    currentList: currentList,
  );

  final sb = StringBuffer()
    ..write(
      '<html><head><meta charset="utf-8"><style>'
      '@media print { table { page-break-inside:avoid; table-layout:fixed; word-wrap:break-word; } td { vertical-align: middle; } }'
      '</style></head><body>',
    )
    ..write(
      '<div class="printStamp"><p align="center">'
      '<table border="0" cellpadding="0" cellspacing="0"><tbody><tr>'
      '<td>${_fontSpan(escape(l10n.printedWithApp(l10n.appTitle)), size: '-1')}</td>'
      '</tr></tbody></table></p></div>',
    )
    ..write(
      '<table border="0" cellpadding="3" cellspacing="1" style="width:100%">'
      '<tbody><tr>'
      '<td style="width:75%">${_fontSpan(escape(listTitle), size: '+2')}</td>'
      '<td style="text-align:right">${_fontSpan(escape(dateHeader), size: '-1')}</td>'
      '</tr></tbody></table>',
    );

  for (final group in groups) {
    if (group.tasks.isEmpty) continue;
    if (group.header != null && group.header!.isNotEmpty) {
      sb.write(
        '<br>${_fontSpan(escape(group.header!), size: group.isListBucket ? '+1' : '-1')}<hr>',
      );
    } else {
      sb.write('<br>');
    }

    for (final task in group.tasks) {
      final checkbox = task.isCompleted ? '&#9745;' : '&#9744;';
      final titleHtml = _fontSpan(escape(task.title), strike: task.isCompleted);
      final metaHtml = _buildPrintMetadataRow(
        l10n: l10n,
        state: state,
        currentList: currentList,
        task: task,
        isListBucket: group.isListBucket,
        now: referenceNow,
        locale: locale,
        escape: escape,
      );
      final starHtml = task.isImportant ? '&#9733;' : '';

      sb.write(
        '<table border="0" cellpadding="3" cellspacing="1" style="width:100%">'
        '<tbody><tr>'
        '<td style="width:30px"><p style="text-align:center">$checkbox</p></td>'
        '<td>$titleHtml${metaHtml.isNotEmpty ? '<br />$metaHtml' : ''}</td>'
        '<td style="text-align:center; width:30px">$starHtml</td>'
        '</tr></tbody></table>',
      );

      for (final step in task.steps) {
        final stepCheckbox = step.isCompleted ? '&#9745;' : '&#9744;';
        final stepTitle = _fontSpan(
          escape(step.title),
          strike: step.isCompleted,
        );
        sb.write(
          '<table border="0" cellpadding="3" cellspacing="1" style="width:100%">'
          '<tbody><tr>'
          '<td style="text-align:right; width:60px">$stepCheckbox</td>'
          '<td>$stepTitle</td>'
          '<td style="width:30px">&nbsp;</td>'
          '</tr></tbody></table>',
        );
      }
    }
  }

  sb.write('</body></html>');
  return sb.toString();
}

String _buildPrintMetadataRow({
  required AppLocalizations l10n,
  required TodoState state,
  required TodoList currentList,
  required TaskItem task,
  required bool isListBucket,
  required DateTime now,
  required String? locale,
  required String Function(String) escape,
}) {
  final parts = <String>[];
  if (task.isInMyDay && currentList.smartType != SmartListType.myDay) {
    parts.add('&#9728; ${escape(l10n.myDay)}');
  }
  if (currentList.isSmartList && !isListBucket) {
    final origin = resolveOriginListName(l10n, state.lists, task.listId);
    if (origin != null && origin.isNotEmpty) {
      parts.add(escape(origin));
    }
  }
  if (task.steps.isNotEmpty) {
    final completedCount = task.steps.where((s) => s.isCompleted).length;
    parts.add(escape(l10n.stepsProgress(completedCount, task.steps.length)));
  }
  if (task.dueDate != null) {
    parts.add(
      escape(formatRelativeDate(l10n, task.dueDate!, now: now, locale: locale)),
    );
  }
  if (parts.isEmpty) return '';
  final cells = parts
      .map((p) => '<td>${_fontSpan(p, size: '-2', color: '#6E6E6E')}</td>')
      .join(
        '<td>${_fontSpan('\u2002•\u2002', size: '-2', color: '#6E6E6E')}</td>',
      );
  return '<table border="0" cellpadding="1" cellspacing="1"><tbody><tr>$cells</tr></tbody></table>';
}

String _fontSpan(
  String content, {
  String size = '-1',
  String color = '#292929',
  bool strike = false,
}) {
  final span =
      '<font face="sans-serif" size="$size" color="$color">$content</font>';
  return strike ? '<strike>$span</strike>' : span;
}

String _displayListTitle(AppLocalizations l10n, TodoList list) {
  final baseTitle = localizedListTitle(l10n, list);
  final emoji = list.emoji;
  if (emoji != null && emoji.isNotEmpty) {
    return '$emoji $baseTitle';
  }
  return baseTitle;
}

String? _dateLocale(AppLocalizations l10n) {
  try {
    return DateFormat.localeExists(l10n.localeName) ? l10n.localeName : null;
  } on Object {
    return null;
  }
}
