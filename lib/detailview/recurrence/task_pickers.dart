import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';

/// Formats a date relative to today (`Today`, `Tomorrow`, `Yesterday`, or `MMMd`/`yMMMd`),
/// matching `yp.r.D` in `mstodo.apk`.
String formatRelativeDate(BuildContext context, DateTime date) {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.tomorrow;
  if (diff == -1) return l10n.yesterday;
  if (date.year != now.year) return DateFormat.yMMMd().format(date);
  return DateFormat.MMMd().format(date);
}

/// Formats a reminder timestamp as `Remind me at <time>` (plus relative date if not today).
String formatReminderLabel(BuildContext context, DateTime reminderAt) {
  final l10n = AppLocalizations.of(context);
  final timeStr = DateFormat.jm().format(reminderAt);
  final now = DateTime.now();
  final isToday = reminderAt.year == now.year &&
      reminderAt.month == now.month &&
      reminderAt.day == now.day;
  if (isToday) {
    return l10n.remindMeAt(timeStr);
  }
  return '${l10n.remindMeAt(timeStr)}, ${formatRelativeDate(context, reminderAt)}';
}

/// Formats task creation timestamp matching `yp.r.j` in the original app:
/// - Today: `Created a few moments ago` / `Created X minute(s) ago` / `Created X hour(s) ago`
/// - Yesterday: `Created yesterday`
/// - Earlier: `Created on <MMMEd>` (or `<yMMMEd>` if different year)
String formatCreatedDateLabel(
  BuildContext context,
  DateTime createdAt, {
  DateTime? now,
}) {
  final l10n = AppLocalizations.of(context);
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final createdDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final dayDiff = today.difference(createdDay).inDays;

  if (dayDiff == 0) {
    final diff = current.difference(createdAt);
    if (diff.inHours > 0) {
      return l10n.createdAgo(l10n.createdHoursAgo(diff.inHours));
    }
    if (diff.inMinutes > 0) {
      return l10n.createdAgo(l10n.createdMinutesAgo(diff.inMinutes));
    }
    return l10n.createdAgo(l10n.createdMomentsAgo);
  }
  if (dayDiff == 1) {
    return l10n.createdAgo(l10n.createdYesterday);
  }
  final formatted = createdAt.year != current.year
      ? DateFormat.yMMMEd().format(createdAt)
      : DateFormat.MMMEd().format(createdAt);
  return l10n.createdOn(formatted);
}

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
    return DateTime(reminderAt.year, reminderAt.month, reminderAt.day);
  }
  return today;
}

/// Computes the first day of next week respecting [startOfWeek].
DateTime computeNextWeekDate(DateTime from, WeekStart startOfWeek) {
  final today = DateTime(from.year, from.month, from.day);
  final targetWeekday = switch (startOfWeek) {
    WeekStart.sunday => DateTime.sunday,
    WeekStart.monday || WeekStart.system => DateTime.monday,
    WeekStart.saturday => DateTime.saturday,
  };
  var daysAhead = (targetWeekday - today.weekday + 7) % 7;
  if (daysAhead == 0) daysAhead = 7;
  return today.add(Duration(days: daysAhead));
}

class DueDatePickResult {
  const DueDatePickResult({this.date, this.cleared = false});

  final DateTime? date;
  final bool cleared;
}

/// Shared due-date bottom sheet matching `task_due_date_menu.xml`.
Future<DueDatePickResult?> showDueDatePickerSheet(
  BuildContext context, {
  required WeekStart startOfWeek,
  DateTime? initialDate,
  bool includeRemoveOption = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (includeRemoveOption)
            ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(l10n.removeDueDate),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
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

  if (choice == null || !context.mounted) return null;

  switch (choice) {
    case 'remove':
      return const DueDatePickResult(cleared: true);
    case 'today':
      return DueDatePickResult(date: today);
    case 'tomorrow':
      return DueDatePickResult(date: today.add(const Duration(days: 1)));
    case 'next_week':
      return DueDatePickResult(date: computeNextWeekDate(today, startOfWeek));
    case 'pick':
      final picked = await showDatePicker(
        context: context,
        initialDate: initialDate ?? today,
        firstDate: today.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (picked == null) return null;
      return DueDatePickResult(date: picked);
    default:
      return null;
  }
}

/// Shared reminder bottom sheet matching `task_reminder_menu.xml`.
Future<DateTime?> showReminderPickerSheet(
  BuildContext context, {
  required WeekStart startOfWeek,
  DateTime? initialReminder,
}) async {
  final l10n = AppLocalizations.of(context);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final showLaterToday = now.hour < 20 || (now.hour == 20 && now.minute <= 29);
  final nextWeekDate = computeNextWeekDate(today, startOfWeek);
  final showNextWeek = nextWeekDate != today.add(const Duration(days: 1));

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLaterToday)
            ListTile(
              leading: const Icon(Icons.access_time),
              title: Text(l10n.laterToday),
              onTap: () => Navigator.pop(ctx, 'later'),
            ),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: Text(l10n.tomorrow),
            onTap: () => Navigator.pop(ctx, 'tomorrow'),
          ),
          if (showNextWeek)
            ListTile(
              leading: const Icon(Icons.next_week),
              title: Text(l10n.nextWeek),
              onTap: () => Navigator.pop(ctx, 'next_week'),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(l10n.pickDateTime),
            onTap: () => Navigator.pop(ctx, 'custom'),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return null;

  switch (choice) {
    case 'later':
      final baseHour = now.hour + (now.minute >= 29 ? 1 : 0) + 3;
      return DateTime(today.year, today.month, today.day, baseHour, 0);
    case 'tomorrow':
      final tmr = today.add(const Duration(days: 1));
      return DateTime(tmr.year, tmr.month, tmr.day, 9, 0);
    case 'next_week':
      return DateTime(nextWeekDate.year, nextWeekDate.month, nextWeekDate.day, 9, 0);
    case 'custom':
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: initialReminder ?? today,
        firstDate: today.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (pickedDate == null || !context.mounted) return null;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: initialReminder != null
            ? TimeOfDay.fromDateTime(initialReminder)
            : TimeOfDay.now(),
      );
      if (pickedTime == null) return null;
      return DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    default:
      return null;
  }
}
