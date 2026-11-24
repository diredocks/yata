import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../core/time/local_timezone.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

const List<String> kIsoWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats [dt] as a 7-fractional-digit UTC ISO-8601 string for Substrate.
String formatSubstrateUtcTimestamp(DateTime dt) {
  final utc = dt.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  final hh = utc.hour.toString().padLeft(2, '0');
  final mm = utc.minute.toString().padLeft(2, '0');
  final ss = utc.second.toString().padLeft(2, '0');
  final subSecondMicros = utc.millisecond * 1000 + utc.microsecond;
  final sevenDigits = '${subSecondMicros.toString().padLeft(6, '0')}0';
  return '$y-$m-${d}T$hh:$mm:$ss.${sevenDigits}Z';
}

/// Formats a calendar day [day] as `YYYY-MM-DD`.
String formatDayString(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Minimum valid epoch millisecond matching MS To Do `kh/a.java:122`
/// (`-9223372036853L`), filtering `.NET` `0001-01-01` and Windows FILETIME
/// `1601-01-01` sentinel timestamps.
const int _kMinSubstrateTimestampMillis = -9223372036853;

bool _isValidSubstrateTimestamp(DateTime? parsed) =>
    parsed != null &&
    parsed.year > 1 &&
    parsed.millisecondsSinceEpoch >= _kMinSubstrateTimestampMillis;

/// Parses an ISO timestamp string, ignoring MS `.NET` sentinel `0001-01-01`.
///
/// Strips legacy `-` separators after `T` when ending in `Z` (matching MS To Do
/// `kh/a.java:22-28`) and treats timezone-less ISO datetimes as UTC.
DateTime? parseSubstrateTimestamp(String? raw) {
  if (raw == null) return null;
  var trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('0001-01-01')) {
    return null;
  }
  final tIndex = trimmed.indexOf('T');
  if (tIndex >= 0 && (trimmed.endsWith('Z') || trimmed.endsWith('z'))) {
    trimmed =
        trimmed.substring(0, tIndex) +
        trimmed.substring(tIndex).replaceAll('-', '');
  }
  final hasExplicitOffset =
      trimmed.endsWith('Z') ||
      trimmed.endsWith('z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed);
  if (tIndex >= 0 && !hasExplicitOffset) {
    trimmed = '${trimmed}Z';
  }
  final parsed = DateTime.tryParse(trimmed);
  if (!_isValidSubstrateTimestamp(parsed)) return null;
  return parsed!.toUtc();
}

/// Formats [dt] into Substrate `DateTimeTimeZone` (`UTC`).
Map<String, dynamic> formatDateTimeTimeZoneUtc(DateTime dt) {
  return {'DateTime': formatSubstrateUtcTimestamp(dt), 'TimeZone': 'UTC'};
}

/// Formats calendar [date] into Substrate `DateTimeTimeZone` (`YYYY-MM-DD`
/// with local IANA timezone, matching `GswTask` / `DateTimeTimeZone.fromLocalTime`).
Map<String, dynamic> formatDueDateTimeZone(
  DateTime date, {
  String? timeZoneId,
}) {
  return {
    'DateTime': formatDayString(date),
    'TimeZone': timeZoneId ?? resolveLocalIanaTimeZone(),
  };
}

/// Parses Substrate `DateTimeTimeZone` object into a UTC [DateTime].
DateTime? parseSubstrateDateTimeTimeZone(Map<String, dynamic>? map) {
  if (map == null) return null;
  final raw = map['DateTime'] as String?;
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('0001-01-01')) {
    return null;
  }
  final hasExplicitOffset =
      trimmed.endsWith('Z') ||
      trimmed.endsWith('z') ||
      RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed);
  if (hasExplicitOffset) {
    final parsed = DateTime.tryParse(trimmed);
    if (!_isValidSubstrateTimestamp(parsed)) return null;
    return parsed!.toUtc();
  }

  final rawTz = (map['TimeZone'] as String?)?.trim();
  final tzLower = rawTz?.toLowerCase();
  if (rawTz == null || rawTz.isEmpty || tzLower == 'utc') {
    final parsed = DateTime.tryParse('${trimmed}Z');
    if (!_isValidSubstrateTimestamp(parsed)) return null;
    return parsed!.toUtc();
  }

  final parsedInTz =
      parseDateTimeInTimeZone(trimmed, rawTz) ??
      DateTime.tryParse(trimmed)?.toUtc();
  if (!_isValidSubstrateTimestamp(parsedInTz)) return null;
  return parsedInTz!.toUtc();
}

/// Parses Substrate day values (`DueDate`, `DueDateTime`, `CommittedDay`,
/// `PostponedDay`), matching MS To Do `zg/e.java` (+14h heuristic).
DateTime? parseSubstrateDay(dynamic raw) {
  String? rawStr;
  String? tz;
  if (raw is Map<String, dynamic>) {
    rawStr = raw['DateTime'] as String?;
    tz = (raw['TimeZone'] as String?)?.trim().toLowerCase();
  } else if (raw is Map) {
    rawStr = raw['DateTime']?.toString();
    tz = raw['TimeZone']?.toString().trim().toLowerCase();
  } else if (raw is String) {
    rawStr = raw;
  }
  if (rawStr == null) return null;
  final trimmed = rawStr.trim();
  if (trimmed.isEmpty || trimmed.startsWith('0001-01-01')) {
    return null;
  }
  if (trimmed.length <= 10 || trimmed.contains('T00:')) {
    final datePart = trimmed.substring(
      0,
      trimmed.length >= 10 ? 10 : trimmed.length,
    );
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(datePart);
    if (match != null) {
      final y = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      final d = int.parse(match.group(3)!);
      if (y <= 1) return null;
      return DateTime(y, m, d);
    }
  }
  final hasExplicitOffset =
      trimmed.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed);
  final candidate = (!hasExplicitOffset && tz == 'utc')
      ? '${trimmed}Z'
      : trimmed;
  final parsed = DateTime.tryParse(candidate);
  if (parsed == null || parsed.year <= 1) return null;
  final local = parsed.toLocal();
  if (local.hour == 0) {
    return DateTime(local.year, local.month, local.day);
  }
  final shifted = parsed.toUtc().add(const Duration(hours: 14));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Encodes local [RecurrenceType] into Substrate `Recurrence` JSON object.
Map<String, dynamic>? encodeSubstrateRecurrence(
  RecurrenceType type, {
  DateTime? dueDate,
  WeekStart firstDayOfWeek = WeekStart.system,
}) {
  if (type == RecurrenceType.none) return null;
  final firstDay = switch (firstDayOfWeek) {
    WeekStart.system || WeekStart.monday => 'Monday',
    WeekStart.tuesday => 'Tuesday',
    WeekStart.wednesday => 'Wednesday',
    WeekStart.thursday => 'Thursday',
    WeekStart.friday => 'Friday',
    WeekStart.saturday => 'Saturday',
    WeekStart.sunday => 'Sunday',
  };
  return switch (type) {
    RecurrenceType.none => null,
    RecurrenceType.daily => {
      'RecurrenceType': 'Daily',
      'IntervalType': 'Days',
      'Interval': 1,
      'FirstDayOfWeek': firstDay,
    },
    RecurrenceType.weekdays => {
      'RecurrenceType': 'WeekDays',
      'IntervalType': 'Weeks',
      'Interval': 1,
      'FirstDayOfWeek': firstDay,
      'WeekDays': const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
      ],
    },
    RecurrenceType.weekly => {
      'RecurrenceType': 'Weekly',
      'IntervalType': 'Weeks',
      'Interval': 1,
      'FirstDayOfWeek': firstDay,
      if (dueDate != null) 'WeekDays': [kIsoWeekdayNames[dueDate.weekday - 1]],
    },
    RecurrenceType.monthly => {
      'RecurrenceType': 'Monthly',
      'IntervalType': 'Months',
      'Interval': 1,
      'FirstDayOfWeek': firstDay,
    },
    RecurrenceType.yearly => {
      'RecurrenceType': 'Yearly',
      'IntervalType': 'Years',
      'Interval': 1,
      'FirstDayOfWeek': firstDay,
    },
  };
}

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

/// Returns a shallow defensive copy of a raw Substrate `Recurrence` map, or
/// `null` when absent/empty so custom intervals/weekdays survive round-trips.
Map<String, dynamic>? normalizeRawRecurrence(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return null;
  final copy = <String, dynamic>{};
  for (final entry in raw.entries) {
    final val = entry.value;
    if (val is List) {
      copy[entry.key] = List<dynamic>.from(val);
    } else if (val is Map) {
      copy[entry.key] = Map<String, dynamic>.from(val);
    } else {
      copy[entry.key] = val;
    }
  }
  return copy;
}

const Set<String> _htmlBlockTags = {
  'p',
  'div',
  'li',
  'tr',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};

/// Strips HTML task body markup to plain text when [contentType] is `"HTML"`
/// using `package:html`.
String stripHtmlToPlainText(String raw, {String? contentType}) {
  if (raw.isEmpty) return '';
  final isHtml = contentType?.trim().toLowerCase() == 'html';
  if (!isHtml) {
    return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
  final doc = html_parser.parse(raw);
  for (final el in doc.querySelectorAll('head, style, script')) {
    el.remove();
  }
  final buffer = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text.replaceAll('\u00A0', ' '));
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'br') {
        buffer.write('\n');
        return;
      }
      for (final child in node.nodes) {
        walk(child);
      }
      if (tag != null && _htmlBlockTags.contains(tag)) {
        buffer.write('\n');
      }
      return;
    }
    for (final child in node.nodes) {
      walk(child);
    }
  }

  walk(doc.body ?? doc);
  return buffer
      .toString()
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n+$'), '');
}
