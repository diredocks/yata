import 'dart:collection';

import 'package:characters/characters.dart';
import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:uuid/uuid.dart';

import '../../models/todo_list.dart';
import 'substrate_time_codecs.dart';

export '../../data/order_date_time.dart';
export 'substrate_time_codecs.dart' hide kIsoWeekdayNames;

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
/// (used for both SmartList `*_ThemeColor` settings and `TaskFolder.ThemeColor`).
String encodeThemeColor(ListThemeColor color, ListThemePhoto? photo) {
  if (photo != null) {
    return _photoToWire[photo] ?? 'photo_beach';
  }
  return _colorToWire[color] ?? 'dark_blue';
}

/// Decodes a single theme string (`*_ThemeColor` or `TaskFolder.ThemeColor`) into [DecodedTheme].
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
  final dayNames = SplayTreeSet<int>.of(
    days.where((d) => d >= DateTime.monday && d <= DateTime.sunday),
  );
  final encodedDays = dayNames.isEmpty
      ? kIsoWeekdayNames
      : [for (final d in dayNames) kIsoWeekdayNames[d - 1]];
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
  final result = SplayTreeSet<int>();
  for (final token in daysPart.split(',')) {
    final normalized = token.trim().toLowerCase();
    final idx = kIsoWeekdayNames.indexWhere(
      (name) => name.toLowerCase() == normalized,
    );
    if (idx >= 0) {
      result.add(idx + 1);
    }
  }
  if (result.isEmpty) return null;
  return result.toList();
}
