import 'package:characters/characters.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:uuid/uuid.dart';

import '../models/task_item.dart';
import '../models/todo_list.dart';

const Uuid _uuid = Uuid();

/// Generates a random RFC-4122 version 4 UUID string.
String generateUuidV4() => _uuid.v4();

/// Substrate `/settings` keys synchronized for personal Microsoft To Do accounts.
abstract final class TodoSettingKeys {
  // General
  static const confirmOnDelete = 'ConfirmOnDelete';
  static const soundOnCompletion = 'SoundOnCompletion';
  static const myDayShowDueTasks = 'MyDay_ShowDueTasks';
  static const addTasksToTop = 'AddTasksToTop';
  static const moveStarredTasksToTop = 'MoveStarredTasksToTop';
  static const startWeekFrom = 'start_week_from';

  // Notifications
  static const reminderNotifications = 'ReminderNotifications';
  static const dueDateNotifications = 'DueDateNotifications';
  static const dueDateNotificationTime = 'DuedateNotification_Time';
  static const pinReminders = 'PinReminders';
  static const setAlarmClockReminderAndroid = 'SetAlarmClock_Reminder_Android';
  static const routineNotification = 'RoutineNotification';
  static const routineNotificationConfiguration =
      'RoutineNotification_Configuration';

  // Smart list visibility
  static const smartListStarredEnabled = 'SmartListStarred_Enabled';
  static const smartListPlannedEnabled = 'SmartListPlanned_Enabled';
  static const smartListAllEnabled = 'SmartListAll_Enabled';
  static const smartListCompletedEnabled = 'SmartListCompleted_Enabled';
  static const smartListsAutoHide = 'SmartLists_AutoHide';

  // My Day
  static const myDayShowCompletedTasks = 'MyDay_ShowCompletedTasks';
  static const myDayThemeColor = 'MyDay_ThemeColor';
  static const myDaySortType = 'MyDay_SortType';
  static const myDaySortAscending = 'MyDay_SortAscending';

  // Planned
  static const plannedShowCompletedTasks = 'Planned_ShowCompletedTasks';
  static const plannedThemeColor = 'Planned_ThemeColor';
  static const smartListPlannedDueDateFilter = 'SmartListPlanned_DueDateFilter';
  static const smartListPlannedGroupType = 'SmartListPlanned_GroupType';

  // Important (Starred)
  static const smartListStarredShowCompletedTasks =
      'SmartListStarred_ShowCompletedTasks';
  static const smartListStarredThemeColor = 'SmartListStarred_ThemeColor';
  static const smartListStarredSortType = 'SmartListStarred_SortType';
  static const smartListStarredSortAscending = 'SmartListStarred_SortAscending';

  // All
  static const smartListAllThemeColor = 'SmartListAll_ThemeColor';
  static const smartListAllSortType = 'SmartListAll_SortType';
  static const smartListAllSortAscending = 'SmartListAll_SortAscending';

  // Completed
  static const smartListCompletedThemeColor = 'SmartListCompleted_ThemeColor';
  static const smartListCompletedSortType = 'SmartListCompleted_SortType';
  static const smartListCompletedSortAscending =
      'SmartListCompleted_SortAscending';

  static const List<String> allSyncableKeys = [
    confirmOnDelete,
    soundOnCompletion,
    myDayShowDueTasks,
    addTasksToTop,
    moveStarredTasksToTop,
    startWeekFrom,
    reminderNotifications,
    dueDateNotifications,
    dueDateNotificationTime,
    pinReminders,
    setAlarmClockReminderAndroid,
    routineNotification,
    routineNotificationConfiguration,
    smartListStarredEnabled,
    smartListPlannedEnabled,
    smartListAllEnabled,
    smartListCompletedEnabled,
    smartListsAutoHide,
    myDayShowCompletedTasks,
    myDayThemeColor,
    myDaySortType,
    myDaySortAscending,
    plannedShowCompletedTasks,
    plannedThemeColor,
    smartListPlannedDueDateFilter,
    smartListPlannedGroupType,
    smartListStarredShowCompletedTasks,
    smartListStarredThemeColor,
    smartListStarredSortType,
    smartListStarredSortAscending,
    smartListAllThemeColor,
    smartListAllSortType,
    smartListAllSortAscending,
    smartListCompletedThemeColor,
    smartListCompletedSortType,
    smartListCompletedSortAscending,
  ];
}

/// Decoded folder/smart-list theme pair from Substrate `ThemeColor`.
class DecodedTheme {
  const DecodedTheme({required this.themeColor, this.themePhoto});

  final ListThemeColor themeColor;
  final ListThemePhoto? themePhoto;
}

/// Decoded folder title + optional leading emoji from Substrate `Name`.
class DecodedFolderName {
  const DecodedFolderName({this.emoji, required this.title});

  final String? emoji;
  final String title;
}

const Map<ListThemeColor, String> _colorToWire = {
  ListThemeColor.blue: 'dark_blue',
  ListThemeColor.rose: 'dark_rose',
  ListThemeColor.teal: 'dark_teal',
  ListThemeColor.green: 'dark_green',
  ListThemeColor.purple: 'dark_purple',
  ListThemeColor.red: 'dark_red',
  ListThemeColor.grey: 'dark_grey',
  ListThemeColor.lightBlue: 'light_blue',
  ListThemeColor.lightRose: 'light_rose',
  ListThemeColor.lightTeal: 'light_teal',
  ListThemeColor.lightGreen: 'light_green',
  ListThemeColor.lightPurple: 'light_purple',
  ListThemeColor.lightRed: 'light_red',
  ListThemeColor.lightGrey: 'light_grey',
};

const Map<ListThemePhoto, String> _photoToWire = {
  ListThemePhoto.beach: 'photo_beach',
  ListThemePhoto.desert: 'photo_desert',
  ListThemePhoto.fern: 'photo_fern',
  ListThemePhoto.field: 'photo_field',
  ListThemePhoto.gradient: 'photo_gradient',
  ListThemePhoto.lighthouse: 'photo_lighthouse',
  ListThemePhoto.safari: 'photo_safari',
  ListThemePhoto.sea: 'photo_sea',
  ListThemePhoto.tvTower: 'photo_tv_tower',
};

final Map<String, ListThemeColor> _wireToColor = {
  for (final e in _colorToWire.entries) e.value: e.key,
  // Legacy MS To Do color aliases (`customizations/d.java`)
  'blue': ListThemeColor.blue,
  'skyblue': ListThemeColor.blue,
  'purple': ListThemeColor.purple,
  'red': ListThemeColor.red,
  'green': ListThemeColor.green,
  'rose': ListThemeColor.rose,
  'teal': ListThemeColor.teal,
  'grey': ListThemeColor.grey,
  'gray': ListThemeColor.grey,
  'dark_gray': ListThemeColor.grey,
  'light_gray': ListThemeColor.lightGrey,
};

final Map<String, ListThemePhoto> _wireToPhoto = {
  for (final e in _photoToWire.entries) e.value: e.key,
};

/// Encodes local [color] and optional [photo] into a single string setting
/// (used for SmartList `*_ThemeColor` settings where photos are stored directly).
String encodeThemeColor(ListThemeColor color, ListThemePhoto? photo) {
  if (photo != null) {
    return _photoToWire[photo] ?? 'photo_beach';
  }
  return _colorToWire[color] ?? 'dark_blue';
}

/// Encodes [color] for Substrate `TaskFolder.ThemeColor` (`dark_*` / `light_*`).
String encodeFolderThemeColor(ListThemeColor color) {
  return _colorToWire[color] ?? 'dark_blue';
}

/// Encodes [photo] for Substrate `TaskFolder.ThemeBackground` (`photo_*` or `'mountain'`).
///
/// Substrate ignores `null` in `PATCH /taskfolders/{id}` and leaves the previous
/// photo background intact; official To Do sends `'mountain'` when no photo is set.
String encodeFolderThemeBackground(ListThemePhoto? photo) {
  if (photo == null) return 'mountain';
  return _photoToWire[photo] ?? 'photo_beach';
}

/// Decodes a single theme string (setting or `ThemeColor`) into [DecodedTheme].
DecodedTheme decodeThemeColor(
  String? raw, {
  ListThemeColor fallbackColor = ListThemeColor.blue,
}) {
  final normalized = raw?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return DecodedTheme(themeColor: fallbackColor);
  }
  final photo = _wireToPhoto[normalized];
  if (photo != null) {
    return DecodedTheme(themeColor: fallbackColor, themePhoto: photo);
  }
  final color = _wireToColor[normalized];
  if (color != null) {
    return DecodedTheme(themeColor: color);
  }
  return DecodedTheme(themeColor: fallbackColor);
}

/// Decodes Substrate folder `ThemeColor` + `ThemeBackground` pair.
DecodedTheme decodeFolderTheme({
  String? themeColor,
  String? themeBackground,
  ListThemeColor fallbackColor = ListThemeColor.blue,
}) {
  final colorDecoded = decodeThemeColor(
    themeColor,
    fallbackColor: fallbackColor,
  );
  final bgDecoded = decodeThemeColor(
    themeBackground,
    fallbackColor: colorDecoded.themeColor,
  );
  return DecodedTheme(
    themeColor: colorDecoded.themeColor,
    themePhoto: bgDecoded.themePhoto ?? colorDecoded.themePhoto,
  );
}

final RegExp _emojiCodePointRegex = RegExp(
  r'[\u{1F1E6}-\u{1FAFF}\u{2300}-\u{27BF}\u20E3\u2B50\u2B55\u2934\u2935\u3030\u303D\u3297\u3299]',
  unicode: true,
);

/// Combines [title] and optional leading [emoji] into Substrate folder `Name`.
String encodeFolderName(String title, String? emoji) {
  final cleanTitle = title.trim();
  final cleanEmoji = emoji?.trim();
  if (cleanEmoji == null || cleanEmoji.isEmpty) {
    return cleanTitle.isEmpty ? title : cleanTitle;
  }
  if (cleanTitle.isEmpty) {
    return cleanEmoji;
  }
  return '$cleanEmoji $cleanTitle';
}

/// Splits a Substrate folder `Name` into leading [emoji] and [title] using
/// Unicode extended grapheme clusters via `package:characters`.
DecodedFolderName decodeFolderName(String raw) {
  final trimmed = raw.trimLeft();
  if (trimmed.isEmpty) {
    return const DecodedFolderName(title: '');
  }
  final firstGrapheme = trimmed.characters.first;
  if (!_emojiCodePointRegex.hasMatch(firstGrapheme)) {
    return DecodedFolderName(title: raw);
  }
  final remainder = trimmed.substring(firstGrapheme.length).trimLeft();
  if (remainder.isEmpty) {
    return DecodedFolderName(title: raw);
  }
  return DecodedFolderName(emoji: firstGrapheme, title: remainder);
}

T _decodeWireEnum<T>({
  required dynamic raw,
  required Map<int, T> byInt,
  required Map<String, T> byString,
  required T fallback,
}) {
  final intVal = parseWireInt(raw);
  if (intVal != null) {
    return byInt[intVal] ?? fallback;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    return byString[normalized] ?? fallback;
  }
  return fallback;
}

/// Encodes [TaskSortOption] to MS To Do `TasksSortOrder` integer (`0..6`).
int encodeSortType(TaskSortOption option) => switch (option) {
  TaskSortOption.defaultOrder => 0,
  TaskSortOption.alphabetical => 1,
  TaskSortOption.dueDate => 2,
  TaskSortOption.creationDate => 3,
  TaskSortOption.addedToMyDay => 5,
  TaskSortOption.importance => 6,
};

/// Decodes `SortType` wire integer or string into [TaskSortOption].
TaskSortOption decodeSortType(dynamic raw) => _decodeWireEnum(
  raw: raw,
  byInt: const {
    0: TaskSortOption.defaultOrder,
    1: TaskSortOption.alphabetical,
    2: TaskSortOption.dueDate,
    3: TaskSortOption.creationDate,
    4: TaskSortOption.defaultOrder,
    5: TaskSortOption.addedToMyDay,
    6: TaskSortOption.importance,
  },
  byString: const {
    'alphabetical': TaskSortOption.alphabetical,
    'subject': TaskSortOption.alphabetical,
    'duedate': TaskSortOption.dueDate,
    'due_date': TaskSortOption.dueDate,
    'creationdate': TaskSortOption.creationDate,
    'created': TaskSortOption.creationDate,
    'creation_date': TaskSortOption.creationDate,
    'addedtomyday': TaskSortOption.addedToMyDay,
    'committed': TaskSortOption.addedToMyDay,
    'added_to_my_day': TaskSortOption.addedToMyDay,
    'importance': TaskSortOption.importance,
    'priority': TaskSortOption.importance,
  },
  fallback: TaskSortOption.defaultOrder,
);

/// Parses wire booleans represented as `bool`, `num`, or `String`.
bool parseWireBool(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'enabled') return true;
    if (lower == 'false' || lower == '0' || lower == 'disabled') return false;
  }
  return fallback;
}

/// Parses wire integers represented as `num` or numeric `String`.
int? parseWireInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Encodes [PlannedDueDateFilter] to `SmartListPlanned_DueDateFilter` (`0..5`).
int encodePlannedDueDateFilter(PlannedDueDateFilter filter) => filter.index;

/// Decodes `SmartListPlanned_DueDateFilter` (`0..5` or name) into [PlannedDueDateFilter].
PlannedDueDateFilter decodePlannedDueDateFilter(
  dynamic raw, {
  PlannedDueDateFilter fallback = PlannedDueDateFilter.all,
}) => _decodeWireEnum(
  raw: raw,
  byInt: {for (final v in PlannedDueDateFilter.values) v.index: v},
  byString: const {
    'overdue': PlannedDueDateFilter.overdue,
    'today': PlannedDueDateFilter.today,
    'tomorrow': PlannedDueDateFilter.tomorrow,
    'thisweek': PlannedDueDateFilter.thisWeek,
    'this_week': PlannedDueDateFilter.thisWeek,
    'later': PlannedDueDateFilter.later,
    'all': PlannedDueDateFilter.all,
  },
  fallback: fallback,
);

/// Encodes [PlannedGroupOption] to `SmartListPlanned_GroupType` (`0..2`).
int encodePlannedGroupOption(PlannedGroupOption option) => option.index;

/// Decodes `SmartListPlanned_GroupType` (`0..2` or name) into [PlannedGroupOption].
PlannedGroupOption decodePlannedGroupOption(
  dynamic raw, {
  PlannedGroupOption fallback = PlannedGroupOption.byDueDate,
}) => _decodeWireEnum(
  raw: raw,
  byInt: {for (final v in PlannedGroupOption.values) v.index: v},
  byString: const {
    'ungroup': PlannedGroupOption.ungroup,
    'none': PlannedGroupOption.ungroup,
    'byduedate': PlannedGroupOption.byDueDate,
    'by_due_date': PlannedGroupOption.byDueDate,
    'duedate': PlannedGroupOption.byDueDate,
    'bylist': PlannedGroupOption.byList,
    'by_list': PlannedGroupOption.byList,
    'list': PlannedGroupOption.byList,
  },
  fallback: fallback,
);

/// Encodes [WeekStart] to Substrate `start_week_from` (`0..7`).
int encodeWeekStart(WeekStart weekStart) => switch (weekStart) {
  WeekStart.system => 0,
  WeekStart.sunday => 1,
  WeekStart.monday => 2,
  WeekStart.tuesday => 3,
  WeekStart.wednesday => 4,
  WeekStart.thursday => 5,
  WeekStart.friday => 6,
  WeekStart.saturday => 7,
};

/// Decodes Substrate `start_week_from` (`0..7` or name) into [WeekStart].
WeekStart decodeWeekStart(
  dynamic raw, {
  WeekStart fallback = WeekStart.system,
}) => _decodeWireEnum(
  raw: raw,
  byInt: const {
    0: WeekStart.system,
    1: WeekStart.sunday,
    2: WeekStart.monday,
    3: WeekStart.tuesday,
    4: WeekStart.wednesday,
    5: WeekStart.thursday,
    6: WeekStart.friday,
    7: WeekStart.saturday,
  },
  byString: {for (final v in WeekStart.values) v.name: v},
  fallback: fallback,
);

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

/// Formats calendar [date] into Substrate `DateTimeTimeZone` at midnight UTC.
Map<String, dynamic> formatDueDateTimeZone(DateTime date) {
  final midnightUtc = DateTime.utc(date.year, date.month, date.day);
  return {
    'DateTime': formatSubstrateUtcTimestamp(midnightUtc),
    'TimeZone': 'UTC',
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
  final tz = (map['TimeZone'] as String?)?.trim().toLowerCase();
  final hasExplicitOffset =
      trimmed.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed);
  final candidate = (!hasExplicitOffset && tz == 'utc')
      ? '${trimmed}Z'
      : trimmed;
  final parsed = DateTime.tryParse(candidate);
  if (!_isValidSubstrateTimestamp(parsed)) return null;
  return parsed!.toUtc();
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

/// Encodes a local [TimeOfDay] onto `1970-01-01` UTC ISO timestamp for
/// `DuedateNotification_Time`.
String encodeTimeOfDaySetting(TimeOfDay time) {
  final now = DateTime.now();
  final localRef = DateTime(
    now.year,
    now.month,
    now.day,
    time.hour,
    time.minute,
  );
  final utcRef = localRef.toUtc();
  final normalized = DateTime.utc(1970, 1, 1, utcRef.hour, utcRef.minute);
  return formatSubstrateUtcTimestamp(normalized);
}

/// Decodes a time-of-day UTC ISO string from `DuedateNotification_Time`.
TimeOfDay? decodeTimeOfDaySetting(dynamic raw) {
  if (raw is! String) return null;
  final parsed = parseSubstrateTimestamp(raw);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return TimeOfDay(hour: local.hour, minute: local.minute);
}

const List<String> _allDaysConfigurationList = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Encodes `RoutineNotification` setting value (`"true"` / `"false"`).
String encodeRoutineNotificationEnabled(bool enabled) {
  return enabled ? 'true' : 'false';
}

/// Encodes boolean setting wire string (`"true"` / `"false"`).
String encodeBoolSetting(bool value) => value ? 'true' : 'false';

/// Encodes integer setting wire string.
String encodeIntSetting(int value) => value.toString();

/// Decodes `RoutineNotification` setting value (`true`/`false`/`Enabled`/`Disabled`).
bool decodeRoutineNotificationEnabled(dynamic raw, {bool fallback = false}) {
  if (raw == null) return fallback;
  return parseWireBool(raw, fallback: fallback);
}

/// Encodes `RoutineNotification_Configuration` as `"<ISO>;Monday,...,Sunday"`.
String encodeRoutineConfig(
  TimeOfDay time, {
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
}) {
  final dayNames = days
      .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
      .toSet()
      .toList()
    ..sort();
  final encodedDays = dayNames.isEmpty
      ? _allDaysConfigurationList
      : [for (final d in dayNames) _isoWeekdayNames[d - 1]];
  return '${encodeTimeOfDaySetting(time)};${encodedDays.join(',')}';
}

/// Decodes time-of-day from `RoutineNotification_Configuration`.
TimeOfDay? decodeRoutineConfigTime(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  final timePart = raw.split(';').first.trim();
  return decodeTimeOfDaySetting(timePart);
}

/// Decodes selected weekdays (1=Monday .. 7=Sunday) from
/// `RoutineNotification_Configuration`.
List<int>? decodeRoutineConfigDays(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  final parts = raw.split(';');
  if (parts.length < 2) return null;
  final daysPart = parts[1].trim();
  if (daysPart.isEmpty) return const <int>[];
  final result = <int>{};
  for (final token in daysPart.split(',')) {
    final normalized = token.trim().toLowerCase();
    final idx = _isoWeekdayNames.indexWhere(
      (name) => name.toLowerCase() == normalized,
    );
    if (idx >= 0) {
      result.add(idx + 1);
    }
  }
  if (result.isEmpty) return null;
  return result.toList()..sort();
}

const List<String> _isoWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

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
      if (dueDate != null) 'WeekDays': [_isoWeekdayNames[dueDate.weekday - 1]],
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

/// Default spacing (`4096s`) used by Microsoft To Do for `OrderDateTime`
/// and `CommittedOrder` positioning (higher timestamp = closer to top).
const Duration kOrderDateTimeStep = Duration(seconds: 4096);

/// Minimum neighbor spacing (`16s`) before Microsoft To Do re-spaces all items
/// (`bj/u.java:197`).
const Duration kOrderDateTimeMinGap = Duration(seconds: 16);

/// Computes updated descending `OrderDateTime` / `CommittedOrder` values for
/// [reorderedOrders] after an item has moved to [movedIndex].
///
/// Returns a map of index -> new UTC [DateTime]. Updates only [movedIndex]
/// when surrounding timestamps are already monotonic and have > 16s gap;
/// otherwise re-spaces all items descending in [kOrderDateTimeStep] (`4096s`)
/// increments.
Map<int, DateTime> computeReorderedOrderDateTimes(
  List<DateTime?> reorderedOrders,
  int movedIndex, {
  DateTime? fallbackNow,
}) {
  final n = reorderedOrders.length;
  if (n == 0 || movedIndex < 0 || movedIndex >= n) {
    return const {};
  }

  final prev = movedIndex > 0 ? reorderedOrders[movedIndex - 1]?.toUtc() : null;
  final next = movedIndex + 1 < n
      ? reorderedOrders[movedIndex + 1]?.toUtc()
      : null;

  var beforeAllOrdered = true;
  DateTime? prevCursor;
  for (var i = 0; i < movedIndex; i++) {
    final raw = reorderedOrders[i];
    if (raw == null) {
      beforeAllOrdered = false;
      break;
    }
    final utc = raw.toUtc();
    if ((prevCursor != null && utc.isAfter(prevCursor)) ||
        (prev != null && utc.isBefore(prev))) {
      beforeAllOrdered = false;
      break;
    }
    prevCursor = utc;
  }

  var afterAllAtMostNext = next != null;
  var sawNullAfter = false;
  DateTime? afterCursor = next;
  for (var i = movedIndex + 1; i < n; i++) {
    final raw = reorderedOrders[i];
    if (raw == null) {
      sawNullAfter = true;
      continue;
    }
    if (sawNullAfter || afterCursor == null) {
      afterAllAtMostNext = false;
      break;
    }
    final utc = raw.toUtc();
    if (utc.isAfter(afterCursor) || (next != null && utc.isAfter(next))) {
      afterAllAtMostNext = false;
      break;
    }
    afterCursor = utc;
  }

  var afterAllNull = true;
  for (var i = movedIndex + 1; i < n; i++) {
    if (reorderedOrders[i] != null) {
      afterAllNull = false;
      break;
    }
  }

  final canUpdateMovedOnly =
      (prev == null &&
          beforeAllOrdered &&
          next != null &&
          afterAllAtMostNext) ||
      (prev != null && next == null && beforeAllOrdered && afterAllNull) ||
      (prev != null &&
          next != null &&
          prev.isAfter(next) &&
          prev.difference(next) > kOrderDateTimeMinGap &&
          beforeAllOrdered &&
          afterAllAtMostNext);

  if (canUpdateMovedOnly) {
    return {
      movedIndex: computeInsertedOrderDateTime(
        prev: prev,
        next: next,
        fallbackNow: fallbackNow,
      ),
    };
  }

  final nonNull = reorderedOrders
      .whereType<DateTime>()
      .map((d) => d.toUtc())
      .toList();
  DateTime anchor;
  if (nonNull.isNotEmpty) {
    anchor = nonNull.first;
    for (final dt in nonNull.skip(1)) {
      if (dt.isAfter(anchor)) anchor = dt;
    }
  } else {
    anchor = (fallbackNow ?? DateTime.now()).toUtc();
  }
  return {
    for (var i = 0; i < n; i++)
      i: anchor.subtract(Duration(seconds: kOrderDateTimeStep.inSeconds * i)),
  };
}

/// Computes a new `OrderDateTime` or `CommittedOrder` between [prev] (above)
/// and [next] (below) in descending-order lists.
DateTime computeInsertedOrderDateTime({
  DateTime? prev,
  DateTime? next,
  DateTime? fallbackNow,
}) {
  final prevUtc = prev?.toUtc();
  final nextUtc = next?.toUtc();
  if (prevUtc != null && nextUtc != null) {
    if (prevUtc.isAfter(nextUtc)) {
      final midMicros =
          (prevUtc.microsecondsSinceEpoch + nextUtc.microsecondsSinceEpoch) ~/
          2;
      return DateTime.fromMicrosecondsSinceEpoch(midMicros, isUtc: true);
    }
    return nextUtc.add(const Duration(milliseconds: 1));
  }
  if (prevUtc == null && nextUtc != null) {
    return nextUtc.add(kOrderDateTimeStep);
  }
  if (prevUtc != null && nextUtc == null) {
    return prevUtc.subtract(kOrderDateTimeStep);
  }
  return (fallbackNow ?? DateTime.now()).toUtc();
}

/// Computes an initial `OrderDateTime` when creating an item at either the
/// top (`addToTop == true`) or bottom (`addToTop == false`) of a list.
DateTime computeNewOrderDateTime({
  required Iterable<DateTime?> existingOrders,
  required bool addToTop,
  DateTime? fallbackNow,
}) {
  final nonNull = existingOrders
      .whereType<DateTime>()
      .map((d) => d.toUtc())
      .toList();
  if (nonNull.isEmpty) {
    return (fallbackNow ?? DateTime.now()).toUtc();
  }
  if (addToTop) {
    var maxDt = nonNull.first;
    for (final dt in nonNull.skip(1)) {
      if (dt.isAfter(maxDt)) maxDt = dt;
    }
    final now = (fallbackNow ?? DateTime.now()).toUtc();
    final minNext = maxDt.add(kOrderDateTimeStep);
    return now.isAfter(minNext) ? now : minNext;
  }
  var minDt = nonNull.first;
  for (final dt in nonNull.skip(1)) {
    if (dt.isBefore(minDt)) minDt = dt;
  }
  return minDt.subtract(kOrderDateTimeStep);
}
