import '../../models/account.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'my_day.dart';

/// Computes the default due date when setting [recurrence] with no due date,
/// matching `RecurrenceUtils.java` (`yp.v1.a`) in `mstodo.apk`.
DateTime? defaultDueDateForRecurrence(
  RecurrenceType recurrence, {
  DateTime? reminderAt,
}) {
  if (recurrence == RecurrenceType.none) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (recurrence == RecurrenceType.weekdays) {
    var candidate = today;
    while (candidate.weekday == DateTime.saturday ||
        candidate.weekday == DateTime.sunday) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
  if (reminderAt != null) {
    final localReminder = reminderAt.toLocal();
    return DateTime(localReminder.year, localReminder.month, localReminder.day);
  }
  return today;
}

/// Computes the first day of next week respecting [startOfWeek].
DateTime computeNextWeekDate(DateTime from, WeekStart startOfWeek) {
  final today = DateTime(from.year, from.month, from.day);
  final targetWeekday = startOfWeek.resolvedWeekday;
  var daysAhead = (targetWeekday - today.weekday + 7) % 7;
  if (daysAhead == 0) daysAhead = 7;
  return today.add(Duration(days: daysAhead));
}

const List<String> kIsoWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Decodes Substrate `Recurrence` JSON object into [RecurrenceType].
RecurrenceType decodeSubstrateRecurrence(Map<String, dynamic>? map) {
  if (map == null || map.isEmpty) return RecurrenceType.none;
  final type = (map['RecurrenceType'] as String?)?.trim().toLowerCase();
  final intervalType = (map['IntervalType'] as String?)?.trim().toLowerCase();
  final weekDaysRaw = map['WeekDays'] as List<dynamic>?;
  final weekDays =
      weekDaysRaw?.map((e) => e.toString().trim().toLowerCase()).toSet() ??
      const <String>{};
  const monToFri = {'monday', 'tuesday', 'wednesday', 'thursday', 'friday'};

  switch (type) {
    case 'daily':
      return RecurrenceType.daily;
    case 'weekdays':
      return RecurrenceType.weekdays;
    case 'weekly':
      if (weekDays.length == 5 && weekDays.containsAll(monToFri)) {
        return RecurrenceType.weekdays;
      }
      return RecurrenceType.weekly;
    case 'monthly':
      return RecurrenceType.monthly;
    case 'yearly':
      return RecurrenceType.yearly;
    case 'custom':
      return switch (intervalType) {
        'days' => RecurrenceType.daily,
        'weeks' =>
          weekDays.length == 5 && weekDays.containsAll(monToFri)
              ? RecurrenceType.weekdays
              : RecurrenceType.weekly,
        'months' => RecurrenceType.monthly,
        'years' => RecurrenceType.yearly,
        _ => RecurrenceType.weekly,
      };
    default:
      return RecurrenceType.none;
  }
}

Set<int> parseRecurrenceWeekDays(Map<String, dynamic>? raw) {
  final list = raw?['WeekDays'] as List<dynamic>?;
  if (list == null) return const <int>{};
  final result = <int>{};
  for (final item in list) {
    final index = kIsoWeekdayNames.indexWhere(
      (w) => w.toLowerCase() == item.toString().trim().toLowerCase(),
    );
    if (index >= 0) result.add(index + 1);
  }
  return result;
}

/// Computes the next due date after [base] for [recurrence] and optional [rawRecurrence].
DateTime computeNextDueDate(
  DateTime base,
  RecurrenceType recurrence, {
  Map<String, dynamic>? rawRecurrence,
}) {
  if (rawRecurrence != null && rawRecurrence.isNotEmpty) {
    final interval = rawRecurrence['Interval'] is num
        ? (rawRecurrence['Interval'] as num).toInt().clamp(1, 9999)
        : 1;
    final intervalType = (rawRecurrence['IntervalType'] as String?)
        ?.trim()
        .toLowerCase();
    switch (intervalType) {
      case 'days':
        return base.add(Duration(days: interval));
      case 'weeks':
        final weekDays = parseRecurrenceWeekDays(rawRecurrence);
        if (weekDays.isEmpty) {
          return base.add(Duration(days: 7 * interval));
        }
        final remainingInWeek = 7 - base.weekday;
        for (var d = 1; d <= remainingInWeek; d++) {
          final candidate = base.add(Duration(days: d));
          if (weekDays.contains(candidate.weekday)) {
            return candidate;
          }
        }
        final nextCycleStart = base.add(
          Duration(days: remainingInWeek + 1 + (interval - 1) * 7),
        );
        for (var d = 0; d < 7; d++) {
          final candidate = nextCycleStart.add(Duration(days: d));
          if (weekDays.contains(candidate.weekday)) {
            return candidate;
          }
        }
        return base.add(Duration(days: 7 * interval));
      case 'months':
        final totalMonths = base.year * 12 + (base.month - 1) + interval;
        final targetYear = totalMonths ~/ 12;
        final targetMonth = (totalMonths % 12) + 1;
        final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
        return DateTime(
          targetYear,
          targetMonth,
          base.day > lastDay ? lastDay : base.day,
        );
      case 'years':
        final targetYear = base.year + interval;
        final lastDay = DateTime(targetYear, base.month + 1, 0).day;
        return DateTime(
          targetYear,
          base.month,
          base.day > lastDay ? lastDay : base.day,
        );
    }
  }

  switch (recurrence) {
    case RecurrenceType.none:
      return base;
    case RecurrenceType.daily:
      return base.add(const Duration(days: 1));
    case RecurrenceType.weekdays:
      var next = base.add(const Duration(days: 1));
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
      return next;
    case RecurrenceType.weekly:
      return base.add(const Duration(days: 7));
    case RecurrenceType.monthly:
      final totalMonths = base.year * 12 + (base.month - 1) + 1;
      final targetYear = totalMonths ~/ 12;
      final targetMonth = (totalMonths % 12) + 1;
      final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
      return DateTime(
        targetYear,
        targetMonth,
        base.day > lastDay ? lastDay : base.day,
      );
    case RecurrenceType.yearly:
      final targetYear = base.year + 1;
      final lastDay = DateTime(targetYear, base.month + 1, 0).day;
      return DateTime(
        targetYear,
        base.month,
        base.day > lastDay ? lastDay : base.day,
      );
  }
}

/// Updates [task]'s recurrence preset or custom rule.
TaskItem applyRecurrence(
  TaskItem task,
  RecurrenceType recurrence, {
  required DateTime now,
  required bool showDueTodayInMyDay,
  DateTime? fallbackDueDate,
  Map<String, dynamic>? rawRecurrence,
}) {
  final hasRecurrence =
      recurrence != RecurrenceType.none ||
      (rawRecurrence != null && rawRecurrence.isNotEmpty);
  final nextDue = (hasRecurrence && task.dueDate == null)
      ? fallbackDueDate
      : task.dueDate;
  return syncMyDayFlag(
    task.copyWith(
      recurrence: recurrence,
      rawRecurrence: recurrence == RecurrenceType.none ? null : rawRecurrence,
      dueDate: nextDue,
    ),
    now: now,
    showDueTodayInMyDay: showDueTodayInMyDay,
  );
}

/// Whether completing [task] should immediately spawn the next local occurrence.
///
/// For synced Microsoft account tasks (`remoteId != null`), Exchange/Substrate
/// spawns the next instance on completion PATCH.
bool shouldSpawnRecurringLocally(
  TaskItem task, {
  required Account? activeAccount,
}) => task.remoteId == null || activeAccount is! MicrosoftAccount;
