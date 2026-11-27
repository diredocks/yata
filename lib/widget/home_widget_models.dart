import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/todo_sorting.dart';
import '../data/todo_state.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';

enum HomeWidgetActionType { quickAdd, openList, openTask }

class HomeWidgetAction {
  const HomeWidgetAction({required this.type, this.listId, this.taskId});

  final HomeWidgetActionType type;
  final String? listId;
  final String? taskId;

  static HomeWidgetAction? fromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'yata' || uri.host != 'widget') {
      return null;
    }
    final params = uri.queryParameters;
    return switch (uri.path) {
      '/add' => HomeWidgetAction(
        type: HomeWidgetActionType.quickAdd,
        listId: params['listId'],
      ),
      '/open_list' => HomeWidgetAction(
        type: HomeWidgetActionType.openList,
        listId: params['listId'],
      ),
      '/open_task' => HomeWidgetAction(
        type: HomeWidgetActionType.openTask,
        taskId: params['taskId'],
        listId: params['listId'],
      ),
      _ => null,
    };
  }
}

@immutable
class HomeWidgetStrings {
  const HomeWidgetStrings({
    this.localeName = 'en',
    this.myDay = 'My Day',
    this.important = 'Important',
    this.planned = 'Planned',
    this.all = 'All',
    this.completedList = 'Completed',
    this.tasks = 'Tasks',
    this.today = 'Today',
    this.tomorrow = 'Tomorrow',
    this.yesterday = 'Yesterday',
    this.emptyListMessage = 'No tasks in this list',
  });

  factory HomeWidgetStrings.fromLocalizations(AppLocalizations l10n) {
    return HomeWidgetStrings(
      localeName: l10n.localeName,
      myDay: l10n.myDay,
      important: l10n.important,
      planned: l10n.planned,
      all: l10n.all,
      completedList: l10n.completedList,
      tasks: l10n.tasks,
      today: l10n.today,
      tomorrow: l10n.tomorrow,
      yesterday: l10n.createdYesterday,
      emptyListMessage: l10n.emptyListTitle,
    );
  }

  factory HomeWidgetStrings.fromLocale(Locale locale) {
    final supported = AppLocalizations.delegate.isSupported(locale)
        ? locale
        : const Locale('en');
    return HomeWidgetStrings.fromLocalizations(
      lookupAppLocalizations(supported),
    );
  }

  factory HomeWidgetStrings.fromLocales(List<Locale> preferredLocales) {
    final resolved = basicLocaleListResolution(
      preferredLocales,
      AppLocalizations.supportedLocales,
    );
    return HomeWidgetStrings.fromLocale(resolved);
  }

  final String localeName;
  final String myDay;
  final String important;
  final String planned;
  final String all;
  final String completedList;
  final String tasks;
  final String today;
  final String tomorrow;
  final String yesterday;
  final String emptyListMessage;

  String titleForList(TodoList list) {
    return switch (list.smartType) {
      SmartListType.myDay => myDay,
      SmartListType.important => important,
      SmartListType.planned => planned,
      SmartListType.all => all,
      SmartListType.completed => completedList,
      SmartListType.tasks => tasks,
      null => list.title,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HomeWidgetStrings &&
            other.localeName == localeName &&
            other.myDay == myDay &&
            other.important == important &&
            other.planned == planned &&
            other.all == all &&
            other.completedList == completedList &&
            other.tasks == tasks &&
            other.today == today &&
            other.tomorrow == tomorrow &&
            other.yesterday == yesterday &&
            other.emptyListMessage == emptyListMessage;
  }

  @override
  int get hashCode => Object.hash(
    localeName,
    myDay,
    important,
    planned,
    all,
    completedList,
    tasks,
    today,
    tomorrow,
    yesterday,
    emptyListMessage,
  );
}

enum WidgetPendingOpType {
  toggleComplete('toggle_complete'),
  toggleImportant('toggle_important');

  const WidgetPendingOpType(this.wireName);

  final String wireName;
}

@immutable
class WidgetPendingOp {
  const WidgetPendingOp({
    required this.opId,
    required this.type,
    required this.taskId,
    required this.value,
    this.accountId,
    this.timestampMs = 0,
  });

  final int opId;
  final WidgetPendingOpType type;
  final String taskId;
  final bool value;
  final String? accountId;
  final int timestampMs;

  static WidgetPendingOp? fromMap(Map<Object?, Object?> raw) {
    final opId = (raw['opId'] as num?)?.toInt();
    final rawType = raw['type'] as String?;
    final taskId = raw['taskId'] as String?;
    final value = raw['value'] as bool?;
    if (opId == null || rawType == null || taskId == null || value == null) {
      return null;
    }
    final type = switch (rawType) {
      'toggle_complete' => WidgetPendingOpType.toggleComplete,
      'toggle_important' => WidgetPendingOpType.toggleImportant,
      _ => null,
    };
    if (type == null) return null;
    final rawAccountId = raw['accountId'] as String?;
    return WidgetPendingOp(
      opId: opId,
      type: type,
      taskId: taskId,
      value: value,
      accountId: (rawAccountId != null && rawAccountId.isNotEmpty)
          ? rawAccountId
          : null,
      timestampMs: (raw['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class HomeWidgetSnapshotSerializer {
  HomeWidgetSnapshotSerializer._();

  static String formatDateYmd(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static Map<String, dynamic> buildCanonicalPayload(
    TodoState state, {
    required String? accountId,
    required String accountName,
    required HomeWidgetStrings strings,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final dateLocale = _resolveDateLocale(strings.localeName);
    final listById = {for (final l in state.lists) l.id: l};
    final listTaskIds = <String, List<String>>{};
    final serializedLists = <Map<String, dynamic>>[];

    for (final list in state.lists) {
      final tasksInList = state.tasksForList(list);
      final List<TaskItem> orderedTasks;
      if (list.smartType == SmartListType.completed) {
        orderedTasks = tasksInList;
      } else {
        final active = tasksInList.where((t) => !t.isCompleted).toList();
        final completed = tasksInList.where((t) => t.isCompleted).toList();
        if (list.sortOption == TaskSortOption.defaultOrder) {
          completed.sort(compareCompletedTasksDesc);
        }
        orderedTasks = [...active, ...completed];
      }
      listTaskIds[list.id] = [for (final t in orderedTasks) t.id];
      final activeCount = list.smartType == SmartListType.completed
          ? tasksInList.length
          : tasksInList.where((t) => !t.isCompleted).length;
      serializedLists.add({
        'id': list.id,
        'title': strings.titleForList(list),
        'smartType': list.smartType?.name,
        'emoji': list.emoji,
        'activeCount': activeCount,
        'sortOption': list.sortOption.name,
        'accentColorLight': TodoColors.listAccentFor(
          list,
          brightness: Brightness.light,
        ).toARGB32(),
        'accentColorDark': TodoColors.listAccentFor(
          list,
          brightness: Brightness.dark,
        ).toARGB32(),
      });
    }

    final serializedTasks = <Map<String, dynamic>>[
      for (final task in state.tasks)
        _serializeTask(
          task,
          list: listById[task.listId],
          strings: strings,
          now: effectiveNow,
          dateLocale: dateLocale,
        ),
    ];

    return {
      'version': 1,
      'accountId': accountId,
      'accountName': accountName,
      'dateKey': formatDateYmd(effectiveNow),
      'locale': strings.localeName,
      'emptyMessage': strings.emptyListMessage,
      'myDayLabel': strings.myDay,
      'todayLabel': strings.today,
      'tomorrowLabel': strings.tomorrow,
      'yesterdayLabel': strings.yesterday,
      'moveStarredToTop': state.moveStarredTasksToTop,
      'lists': serializedLists,
      'tasks': serializedTasks,
      'listTaskIds': listTaskIds,
    };
  }

  static String? _resolveDateLocale(String localeName) {
    try {
      if (DateFormat.localeExists(localeName)) {
        return localeName;
      }
    } catch (_) {
      // Locale symbols may be uninitialized in headless or pure Dart tests.
    }
    return null;
  }

  static Map<String, dynamic> _serializeTask(
    TaskItem task, {
    required TodoList? list,
    required HomeWidgetStrings strings,
    required DateTime now,
    required String? dateLocale,
  }) {
    final listTitle = list == null ? '' : strings.titleForList(list);
    final dueDate = task.dueDate;
    final todayDay = DateTime(now.year, now.month, now.day);
    final isOverdue =
        dueDate != null &&
        !task.isCompleted &&
        DateTime(dueDate.year, dueDate.month, dueDate.day).isBefore(todayDay);
    return {
      'id': task.id,
      'listId': task.listId,
      'listTitle': listTitle,
      'title': task.title,
      'isCompleted': task.isCompleted,
      'isImportant': task.isImportant,
      'isInMyDay': task.isInMyDay,
      'hasDueDate': dueDate != null,
      'dueDateYmd': dueDate == null ? null : formatDateYmd(dueDate),
      'hasReminder': task.reminderAt != null,
      'reminderAtMs': task.reminderAt?.toUtc().millisecondsSinceEpoch,
      'isRecurring': task.hasRecurrence,
      'isOverdue': isOverdue,
      'dueLabel': _formatDueDate(
        dueDate,
        strings: strings,
        now: now,
        dateLocale: dateLocale,
      ),
      'reminderLabel': _formatReminder(
        task.reminderAt,
        strings: strings,
        now: now,
        dateLocale: dateLocale,
      ),
    };
  }

  static String _formatDueDate(
    DateTime? date, {
    required HomeWidgetStrings strings,
    required DateTime now,
    required String? dateLocale,
  }) {
    if (date == null) return '';
    final today = DateTime.utc(now.year, now.month, now.day);
    final target = DateTime.utc(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return strings.today;
    if (diff == 1) return strings.tomorrow;
    if (diff == -1) return strings.yesterday;
    return DateFormat.MMMd(dateLocale).format(date);
  }

  static String _formatReminder(
    DateTime? reminder, {
    required HomeWidgetStrings strings,
    required DateTime now,
    required String? dateLocale,
  }) {
    if (reminder == null) return '';
    final localReminder = reminder.toLocal();
    final localNow = now.toLocal();
    final timeStr = DateFormat.Hm(dateLocale).format(localReminder);
    final today = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final target = DateTime.utc(
      localReminder.year,
      localReminder.month,
      localReminder.day,
    );
    final diff = target.difference(today).inDays;
    if (diff == 0) return timeStr;
    if (diff == 1) return '${strings.tomorrow} $timeStr';
    return '${DateFormat.MMMd(dateLocale).format(localReminder)} $timeStr';
  }
}
