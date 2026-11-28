import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/recurrence.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';

/// Formats a date relative to today (`Today`, `Tomorrow`, `Yesterday`, or `MMMd`/`yMMMd`),
/// matching `yp.r.D` in `mstodo.apk`.
String formatRelativeDate(
  AppLocalizations l10n,
  DateTime date, {
  DateTime? now,
  String? locale,
}) {
  final current = (now ?? DateTime.now()).toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return l10n.today;
  if (diff == 1) return l10n.tomorrow;
  if (diff == -1) return l10n.yesterday;
  if (date.year != current.year) {
    return DateFormat.yMMMd(locale).format(date);
  }
  return DateFormat.MMMd(locale).format(date);
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
  return '${l10n.remindMeAt(timeStr)}, ${formatRelativeDate(l10n, localReminder)}';
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
      l10n.labelWithHint(label, DateFormat.EEEE(locale).format(date));

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
  final laterTodayLocal = DateTime(
    today.year,
    today.month,
    today.day,
    baseHour,
  );
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
    return l10n.weekdayTimeHint(DateFormat.E(locale).format(dt), timeStr);
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
                l10n.labelWithHint(
                  l10n.laterToday,
                  formatHint(laterTodayLocal, includeWeekday: false),
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'later'),
            ),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: Text(
              l10n.labelWithHint(
                l10n.tomorrow,
                formatHint(tomorrowLocal, includeWeekday: true),
              ),
            ),
            onTap: () => Navigator.pop(ctx, 'tomorrow'),
          ),
          if (showNextWeek)
            ListTile(
              leading: const Icon(Icons.next_week),
              title: Text(
                l10n.labelWithHint(
                  l10n.nextWeek,
                  formatHint(nextWeekLocal, includeWeekday: true),
                ),
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

enum CustomRecurrenceUnit { days, weeks, months, years }

class RecurrencePickResult {
  const RecurrencePickResult({required this.recurrence, this.rawRecurrence});

  final RecurrenceType recurrence;
  final Map<String, dynamic>? rawRecurrence;
}

String _unitLabel(AppLocalizations l10n, CustomRecurrenceUnit unit, int count) {
  return switch (unit) {
    CustomRecurrenceUnit.days => l10n.repeatDaysUnit(count),
    CustomRecurrenceUnit.weeks => l10n.repeatWeeksUnit(count),
    CustomRecurrenceUnit.months => l10n.repeatMonthsUnit(count),
    CustomRecurrenceUnit.years => l10n.repeatYearsUnit(count),
  };
}

String _shortWeekdayLabel(int isoWeekday, String? locale) {
  // 2026-11-23 is a Monday (isoWeekday == 1).
  final ref = DateTime(2026, 11, 23 + (isoWeekday - 1));
  return DateFormat.E(locale).format(ref);
}

/// Formats a task's recurrence for display in detail view and quick-add chips.
String formatRecurrenceLabel(
  AppLocalizations l10n,
  RecurrenceType type, [
  Map<String, dynamic>? rawRecurrence,
]) {
  if (rawRecurrence != null && rawRecurrence.isNotEmpty) {
    final rawType = (rawRecurrence['RecurrenceType'] as String?)
        ?.trim()
        .toLowerCase();
    final intervalType = (rawRecurrence['IntervalType'] as String?)
        ?.trim()
        .toLowerCase();
    final interval = rawRecurrence['Interval'] is num
        ? (rawRecurrence['Interval'] as num).toInt()
        : 1;
    final weekDays = parseRecurrenceWeekDays(rawRecurrence);
    const monToFri = {1, 2, 3, 4, 5};
    final isMonToFri = weekDays.length == 5 && weekDays.containsAll(monToFri);
    final isCustom =
        rawType == 'custom' ||
        interval > 1 ||
        (intervalType == 'weeks' && weekDays.length > 1 && !isMonToFri);

    if (isCustom && interval >= 1) {
      final unit = switch (intervalType) {
        'days' => CustomRecurrenceUnit.days,
        'weeks' => CustomRecurrenceUnit.weeks,
        'months' => CustomRecurrenceUnit.months,
        'years' => CustomRecurrenceUnit.years,
        _ => null,
      };
      if (unit != null) {
        if (interval == 1 && unit == CustomRecurrenceUnit.weeks && isMonToFri) {
          return l10n.repeatWeekdays;
        }
        final unitStr = _unitLabel(l10n, unit, interval);
        if (unit == CustomRecurrenceUnit.weeks && weekDays.isNotEmpty) {
          final locale = l10n.localeName == 'en'
              ? null
              : (DateFormat.localeExists(l10n.localeName)
                    ? l10n.localeName
                    : null);
          final sorted = weekDays.toList()..sort();
          final daysStr = sorted
              .map((d) => _shortWeekdayLabel(d, locale))
              .join(', ');
          return l10n.repeatEveryIntervalOnDays(interval, unitStr, daysStr);
        }
        return l10n.repeatEveryInterval(interval, unitStr);
      }
    }
  }

  return switch (type) {
    RecurrenceType.none => l10n.repeat,
    RecurrenceType.daily => l10n.repeatDaily,
    RecurrenceType.weekdays => l10n.repeatWeekdays,
    RecurrenceType.weekly => l10n.repeatWeekly,
    RecurrenceType.monthly => l10n.repeatMonthly,
    RecurrenceType.yearly => l10n.repeatYearly,
  };
}

/// Shared recurrence bottom sheet matching `task_recurrence_menu.xml`,
/// including Custom recurrence dialog support.
Future<RecurrencePickResult?> showRecurrencePickerSheet(
  BuildContext context, {
  RecurrenceType initialRecurrence = RecurrenceType.none,
  Map<String, dynamic>? initialRawRecurrence,
  DateTime? dueDate,
}) async {
  final l10n = AppLocalizations.of(context);
  final presets = <(RecurrenceType, String)>[
    (RecurrenceType.daily, l10n.repeatDaily),
    (RecurrenceType.weekdays, l10n.repeatWeekdays),
    (RecurrenceType.weekly, l10n.repeatWeekly),
    (RecurrenceType.monthly, l10n.repeatMonthly),
    (RecurrenceType.yearly, l10n.repeatYearly),
  ];

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (type, label) in presets)
            ListTile(
              leading: const Icon(Icons.repeat),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, type.name),
            ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: Text(l10n.repeatCustom),
            onTap: () => Navigator.pop(ctx, 'custom'),
          ),
        ],
      ),
    ),
  );

  if (choice == null || !context.mounted) return null;
  if (choice == 'custom') {
    return showCustomRecurrenceDialog(
      context,
      initialRecurrence: initialRecurrence,
      initialRawRecurrence: initialRawRecurrence,
      dueDate: dueDate,
    );
  }
  for (final (type, _) in presets) {
    if (type.name == choice) {
      return RecurrencePickResult(recurrence: type);
    }
  }
  return null;
}

/// Dialog for configuring a custom recurrence rule (`Repeat every...`),
/// matching `CustomRecurrenceDialogFragment` in `mstodo.apk`.
Future<RecurrencePickResult?> showCustomRecurrenceDialog(
  BuildContext context, {
  RecurrenceType initialRecurrence = RecurrenceType.none,
  Map<String, dynamic>? initialRawRecurrence,
  DateTime? dueDate,
}) {
  return showDialog<RecurrencePickResult>(
    context: context,
    builder: (_) => _CustomRecurrenceDialog(
      initialRecurrence: initialRecurrence,
      initialRawRecurrence: initialRawRecurrence,
      dueDate: dueDate,
    ),
  );
}

class _CustomRecurrenceDialog extends StatefulWidget {
  const _CustomRecurrenceDialog({
    required this.initialRecurrence,
    required this.initialRawRecurrence,
    required this.dueDate,
  });

  final RecurrenceType initialRecurrence;
  final Map<String, dynamic>? initialRawRecurrence;
  final DateTime? dueDate;

  @override
  State<_CustomRecurrenceDialog> createState() =>
      _CustomRecurrenceDialogState();
}

class _CustomRecurrenceDialogState extends State<_CustomRecurrenceDialog> {
  late final TextEditingController _controller;
  late CustomRecurrenceUnit _unit;
  late final Set<int> _selectedDays;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialRawRecurrence;
    var initialInterval = 1;
    if (raw != null && raw['Interval'] is num) {
      final parsed = (raw['Interval'] as num).toInt();
      if (parsed >= 1) initialInterval = parsed;
    }
    _controller = TextEditingController(text: '$initialInterval');

    _unit = switch ((raw?['IntervalType'] as String?)?.trim().toLowerCase()) {
      'days' => CustomRecurrenceUnit.days,
      'weeks' => CustomRecurrenceUnit.weeks,
      'months' => CustomRecurrenceUnit.months,
      'years' => CustomRecurrenceUnit.years,
      _ => switch (widget.initialRecurrence) {
        RecurrenceType.daily => CustomRecurrenceUnit.days,
        RecurrenceType.monthly => CustomRecurrenceUnit.months,
        RecurrenceType.yearly => CustomRecurrenceUnit.years,
        _ => CustomRecurrenceUnit.weeks,
      },
    };

    final initialDays = parseRecurrenceWeekDays(raw);
    _selectedDays = <int>{
      if (initialDays.isNotEmpty)
        ...initialDays
      else if (widget.initialRecurrence == RecurrenceType.weekdays) ...const [
        1,
        2,
        3,
        4,
        5,
      ] else
        (widget.dueDate ?? DateTime.now()).weekday,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName == 'en'
        ? null
        : (DateFormat.localeExists(l10n.localeName) ? l10n.localeName : null);
    final parsedInterval = int.tryParse(_controller.text.trim());
    final isValid = parsedInterval != null && parsedInterval >= 1;

    return AlertDialog(
      title: Text(l10n.repeatCustomTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<CustomRecurrenceUnit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final u in CustomRecurrenceUnit.values)
                      DropdownMenuItem(
                        value: u,
                        child: Text(_unitLabel(l10n, u, 2)),
                      ),
                  ],
                  onChanged: (next) {
                    if (next == null) return;
                    setState(() => _unit = next);
                  },
                ),
              ),
            ],
          ),
          if (_unit == CustomRecurrenceUnit.weeks) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  FilterChip(
                    label: Text(_shortWeekdayLabel(weekday, locale)),
                    selected: _selectedDays.contains(weekday),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDays.add(weekday);
                        } else if (_selectedDays.length > 1) {
                          _selectedDays.remove(weekday);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: !isValid
              ? null
              : () {
                  final intervalTypeWire = switch (_unit) {
                    CustomRecurrenceUnit.days => 'Days',
                    CustomRecurrenceUnit.weeks => 'Weeks',
                    CustomRecurrenceUnit.months => 'Months',
                    CustomRecurrenceUnit.years => 'Years',
                  };
                  final sortedDays = _selectedDays.toList()..sort();
                  final rawMap = <String, dynamic>{
                    'RecurrenceType': 'Custom',
                    'IntervalType': intervalTypeWire,
                    'Interval': parsedInterval,
                    if (_unit == CustomRecurrenceUnit.weeks &&
                        sortedDays.isNotEmpty)
                      'WeekDays': [
                        for (final d in sortedDays) kIsoWeekdayNames[d - 1],
                      ],
                  };
                  Navigator.pop(
                    context,
                    RecurrencePickResult(
                      recurrence: decodeSubstrateRecurrence(rawMap),
                      rawRecurrence: rawMap,
                    ),
                  );
                },
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
