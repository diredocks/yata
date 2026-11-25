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
  final localReminder = reminderAt.toLocal();
  final timeStr = DateFormat.jm().format(localReminder);
  final now = DateTime.now();
  final isToday =
      localReminder.year == now.year &&
      localReminder.month == now.month &&
      localReminder.day == now.day;
  if (isToday) {
    return l10n.remindMeAt(timeStr);
  }
  return '${l10n.remindMeAt(timeStr)}, ${formatRelativeDate(context, localReminder)}';
}

String _formatRelativeTimestampLabel(
  AppLocalizations l10n,
  DateTime timestamp, {
  required String Function(String relative) formatAgo,
  required String Function(String date) formatOn,
  DateTime? now,
}) {
  final localNow = (now ?? DateTime.now()).toLocal();
  final localTarget = timestamp.toLocal();
  // Use UTC midnight dates so DST transitions never skew calendar-day diffs.
  final todayUtc = DateTime.utc(localNow.year, localNow.month, localNow.day);
  final targetDayUtc = DateTime.utc(
    localTarget.year,
    localTarget.month,
    localTarget.day,
  );
  final dayDiff = todayUtc.difference(targetDayUtc).inDays;

  if (dayDiff == 0) {
    final diff = localNow.difference(localTarget);
    if (diff.inHours > 0) {
      return formatAgo(l10n.createdHoursAgo(diff.inHours));
    }
    if (diff.inMinutes > 0) {
      return formatAgo(l10n.createdMinutesAgo(diff.inMinutes));
    }
    return formatAgo(l10n.createdMomentsAgo);
  }
  if (dayDiff == 1) {
    return formatAgo(l10n.createdYesterday);
  }
  final locale = DateFormat.localeExists(l10n.localeName)
      ? l10n.localeName
      : null;
  final formatted = localTarget.year != localNow.year
      ? DateFormat.yMMMEd(locale).format(localTarget)
      : DateFormat.MMMEd(locale).format(localTarget);
  return formatOn(formatted);
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
  return _formatRelativeTimestampLabel(
    l10n,
    createdAt,
    formatAgo: l10n.createdAgo,
    formatOn: l10n.createdOn,
    now: now,
  );
}

/// Formats note modification timestamp matching `yp.r.F` in the original app:
/// - Today: `Updated a few moments ago` / `Updated X minute(s) ago` / `Updated X hour(s) ago`
/// - Yesterday: `Updated yesterday`
/// - Earlier: `Updated on <MMMEd>` (or `<yMMMEd>` if different year)
String formatNoteUpdatedDateLabel(
  BuildContext context,
  DateTime updatedAt, {
  DateTime? now,
}) {
  final l10n = AppLocalizations.of(context);
  return _formatRelativeTimestampLabel(
    l10n,
    updatedAt,
    formatAgo: l10n.updatedAgo,
    formatOn: l10n.updatedOn,
    now: now,
  );
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
  final tomorrow = today.add(const Duration(days: 1));
  final nextWeekDate = computeNextWeekDate(today, startOfWeek);
  final locale = DateFormat.localeExists(l10n.localeName)
      ? l10n.localeName
      : null;
  String withWeekday(String label, DateTime date) =>
      '$label (${DateFormat.EEEE(locale).format(date)})';

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
            title: Text(withWeekday(l10n.today, today)),
            onTap: () => Navigator.pop(ctx, 'today'),
          ),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: Text(withWeekday(l10n.tomorrow, tomorrow)),
            onTap: () => Navigator.pop(ctx, 'tomorrow'),
          ),
          ListTile(
            leading: const Icon(Icons.next_week),
            title: Text(withWeekday(l10n.nextWeek, nextWeekDate)),
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
      return DueDatePickResult(date: tomorrow);
    case 'next_week':
      return DueDatePickResult(date: nextWeekDate);
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
  final baseHour = now.hour + (now.minute >= 29 ? 1 : 0) + 3;
  final laterTodayLocal = DateTime(today.year, today.month, today.day, baseHour);
  final tmr = today.add(const Duration(days: 1));
  final tomorrowLocal = DateTime(tmr.year, tmr.month, tmr.day, 9);
  final nextWeekDate = computeNextWeekDate(today, startOfWeek);
  final nextWeekLocal = DateTime(
    nextWeekDate.year,
    nextWeekDate.month,
    nextWeekDate.day,
    9,
  );
  final showNextWeek = nextWeekDate != tmr;
  final locale = DateFormat.localeExists(l10n.localeName)
      ? l10n.localeName
      : null;
  String formatHint(DateTime dt, {required bool includeWeekday}) {
    final timeStr = DateFormat.jm(locale).format(dt);
    if (!includeWeekday) return timeStr;
    return '${DateFormat.E(locale).format(dt)} $timeStr';
  }

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLaterToday)
            ListTile(
              leading: const Icon(Icons.access_time),
              title: Text(
                '${l10n.laterToday} (${formatHint(laterTodayLocal, includeWeekday: false)})',
              ),
              onTap: () => Navigator.pop(ctx, 'later'),
            ),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: Text(
              '${l10n.tomorrow} (${formatHint(tomorrowLocal, includeWeekday: true)})',
            ),
            onTap: () => Navigator.pop(ctx, 'tomorrow'),
          ),
          if (showNextWeek)
            ListTile(
              leading: const Icon(Icons.next_week),
              title: Text(
                '${l10n.nextWeek} (${formatHint(nextWeekLocal, includeWeekday: true)})',
              ),
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
      return laterTodayLocal.toUtc();
    case 'tomorrow':
      return tomorrowLocal.toUtc();
    case 'next_week':
      return nextWeekLocal.toUtc();
    case 'custom':
      final localInitial = initialReminder?.toLocal();
      final pickedDate = await showDatePicker(
        context: context,
        initialDate: localInitial ?? today,
        firstDate: today.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (pickedDate == null || !context.mounted) return null;
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: localInitial != null
            ? TimeOfDay.fromDateTime(localInitial)
            : TimeOfDay.now(),
      );
      if (pickedTime == null) return null;
      return DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      ).toUtc();
    default:
      return null;
  }
}
