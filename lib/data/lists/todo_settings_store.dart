import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../../core/logging/app_logger.dart';
import '../../models/todo_list.dart';
import '../../sync/microsoft/todo_wire_codecs.dart';
import 'custom_background_service.dart';

final _log = appLogFor('TodoSettingsStore');

/// Per-account settings that live in [SharedPreferences].
class TodoSettings {
  const TodoSettings({
    this.selectedListId = 'my_day',
    this.themeMode = ThemeMode.system,
    this.addNewTasksOnTop = true,
    this.moveStarredTasksToTop = true,
    this.playCompletionSound = true,
    this.confirmBeforeDeleting = true,
    this.showDueTodayInMyDay = true,
    this.startOfWeek = WeekStart.system,
    this.showSmartListImportant = true,
    this.showSmartListPlanned = true,
    this.showSmartListAll = false,
    this.showSmartListCompleted = false,
    this.autoHideEmptySmartLists = false,
    this.plannedDueDateFilter = PlannedDueDateFilter.all,
    this.plannedGroupOption = PlannedGroupOption.byDueDate,
    this.useDynamicColor = true,
    this.remindersEnabled = true,
    this.pinReminders = false,
    this.accurateReminders = true,
    this.dueTodayNotificationsEnabled = false,
    this.dueTodayNotificationHour = 9,
    this.dueTodayNotificationMinute = 0,
    this.routineNotificationEnabled = false,
    this.routineNotificationHour = 8,
    this.routineNotificationMinute = 30,
    this.routineNotificationDays = const <int>[1, 2, 3, 4, 5, 6, 7],
    this.quickAddNotificationEnabled = false,
    this.completedExpandedByList = const <String, bool>{},
    this.customBackgrounds = const <CustomBackground>[],
    this.lastMyDayResetDate,
  });

  final String selectedListId;
  final ThemeMode themeMode;
  final bool addNewTasksOnTop;
  final bool moveStarredTasksToTop;
  final bool playCompletionSound;
  final bool confirmBeforeDeleting;
  final bool showDueTodayInMyDay;
  final WeekStart startOfWeek;
  final bool showSmartListImportant;
  final bool showSmartListPlanned;
  final bool showSmartListAll;
  final bool showSmartListCompleted;
  final bool autoHideEmptySmartLists;
  final PlannedDueDateFilter plannedDueDateFilter;
  final PlannedGroupOption plannedGroupOption;
  final bool useDynamicColor;
  final bool remindersEnabled;
  final bool pinReminders;
  final bool accurateReminders;
  final bool dueTodayNotificationsEnabled;
  final int dueTodayNotificationHour;
  final int dueTodayNotificationMinute;
  final bool routineNotificationEnabled;
  final int routineNotificationHour;
  final int routineNotificationMinute;
  final List<int> routineNotificationDays;
  final bool quickAddNotificationEnabled;
  final Map<String, bool> completedExpandedByList;
  final List<CustomBackground> customBackgrounds;
  final String? lastMyDayResetDate;
}

/// Owns per-account user preferences in `SharedPreferences` (sync bookkeeping
/// lives in SQLite via `TodoRepository`).
///
/// It also derives the repository cache scope, so one prefs session cannot read
/// data cached by another.
class TodoSettingsStore {
  TodoSettingsStore(this._prefs, {this.accountId});

  static const String _sessionKey = 'yata._db_session_id';

  final SharedPreferences _prefs;
  final String? accountId;

  String get accountKey =>
      (accountId == null || accountId!.isEmpty) ? 'default' : accountId!;

  String get scopeKey {
    var session = _prefs.getString(_sessionKey);
    if (session == null || session.isEmpty) {
      session = generateUuidV4();
      unawaited(_prefs.setString(_sessionKey, session));
    }
    return '$session::$accountKey';
  }

  String _k(String suffix) {
    final id = accountId;
    if (id == null || id.isEmpty) {
      return 'yata.$suffix';
    }
    return '${AccountLocalStorage.accountKeyPrefix(id)}$suffix';
  }

  String get _selectedListIdKey => _k('selected_list_id');
  String get _lastEnteredListIdKey => _k('last_entered_list_id');
  String get _completedExpandedByListKey => _k('completed_expanded_by_list');
  String get _customBackgroundsKey => _k('custom_backgrounds');
  String get _themeModeKey => _k('theme_mode');
  String get _addNewTasksOnTopKey => _k('add_new_tasks_on_top');
  String get _moveStarredToTopKey => _k('move_starred_to_top');
  String get _playCompletionSoundKey => _k('play_completion_sound');
  String get _confirmBeforeDeletingKey => _k('confirm_before_deleting');
  String get _showDueTodayInMyDayKey => _k('show_due_today_in_my_day');
  String get _startOfWeekKey => _k('start_of_week');
  String get _showImportantKey => _k('show_smart_important');
  String get _showPlannedKey => _k('show_smart_planned');
  String get _showAllKey => _k('show_smart_all');
  String get _showCompletedListKey => _k('show_smart_completed');
  String get _autoHideSmartListsKey => _k('autohide_smart_lists');
  String get _useDynamicColorKey => _k('use_dynamic_color');
  String get _remindersEnabledKey => _k('reminder_notification_enabled');
  String get _pinRemindersKey => _k('reminder_pin_setting');
  String get _accurateRemindersKey => _k('accurate_alarms_preference');
  String get _dueTodayNotificationsKey => _k('due_date_notification_enabled');
  String get _dueTodayNotificationHourKey => _k('due_date_notification_hour');
  String get _dueTodayNotificationMinuteKey =>
      _k('due_date_notification_minute');
  String get _routineNotificationKey => _k('routine_notification_enabled');
  String get _routineNotificationHourKey => _k('routine_notification_hour');
  String get _routineNotificationMinuteKey => _k('routine_notification_minute');
  String get _routineNotificationDaysKey => _k('routine_notification_days');
  String get _quickAddNotificationKey => _k('quick_add_notification_enabled');
  String get _notificationPermissionPromptedKey =>
      _k('notification_permission_prompted');
  String get _reminderPermissionPromptedKey =>
      _k('reminder_permission_prompted');
  String get _lastMyDayResetKey => _k('last_my_day_reset');
  String get _plannedDueDateFilterKey => _k('planned_due_date_filter');
  String get _plannedGroupOptionKey => _k('planned_group_option');

  T _loadEnum<T extends Enum>(String key, List<T> values, T fallback) {
    final name = _prefs.getString(key);
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  Future<void> _setOrRemoveString(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  TodoSettings load() {
    return TodoSettings(
      selectedListId: _prefs.getString(_selectedListIdKey) ?? 'my_day',
      themeMode: _loadEnum(_themeModeKey, ThemeMode.values, ThemeMode.system),
      addNewTasksOnTop: _prefs.getBool(_addNewTasksOnTopKey) ?? true,
      moveStarredTasksToTop: _prefs.getBool(_moveStarredToTopKey) ?? true,
      playCompletionSound: _prefs.getBool(_playCompletionSoundKey) ?? true,
      confirmBeforeDeleting: _prefs.getBool(_confirmBeforeDeletingKey) ?? true,
      showDueTodayInMyDay: _prefs.getBool(_showDueTodayInMyDayKey) ?? true,
      startOfWeek: _loadEnum(
        _startOfWeekKey,
        WeekStart.values,
        WeekStart.system,
      ),
      showSmartListImportant: _prefs.getBool(_showImportantKey) ?? true,
      showSmartListPlanned: _prefs.getBool(_showPlannedKey) ?? true,
      showSmartListAll: _prefs.getBool(_showAllKey) ?? false,
      showSmartListCompleted: _prefs.getBool(_showCompletedListKey) ?? false,
      autoHideEmptySmartLists: _prefs.getBool(_autoHideSmartListsKey) ?? false,
      plannedDueDateFilter: _loadEnum(
        _plannedDueDateFilterKey,
        PlannedDueDateFilter.values,
        PlannedDueDateFilter.all,
      ),
      plannedGroupOption: _loadEnum(
        _plannedGroupOptionKey,
        PlannedGroupOption.values,
        PlannedGroupOption.byDueDate,
      ),
      useDynamicColor: _prefs.getBool(_useDynamicColorKey) ?? true,
      remindersEnabled: _prefs.getBool(_remindersEnabledKey) ?? true,
      pinReminders: _prefs.getBool(_pinRemindersKey) ?? false,
      accurateReminders: _prefs.getBool(_accurateRemindersKey) ?? true,
      dueTodayNotificationsEnabled:
          _prefs.getBool(_dueTodayNotificationsKey) ?? false,
      dueTodayNotificationHour:
          _prefs.getInt(_dueTodayNotificationHourKey) ?? 9,
      dueTodayNotificationMinute:
          _prefs.getInt(_dueTodayNotificationMinuteKey) ?? 0,
      routineNotificationEnabled:
          _prefs.getBool(_routineNotificationKey) ?? false,
      routineNotificationHour: _prefs.getInt(_routineNotificationHourKey) ?? 8,
      routineNotificationMinute:
          _prefs.getInt(_routineNotificationMinuteKey) ?? 30,
      routineNotificationDays: _parseRoutineDays(),
      quickAddNotificationEnabled:
          _prefs.getBool(_quickAddNotificationKey) ?? false,
      completedExpandedByList: _parseCompletedExpandedByList(),
      customBackgrounds: _parseCustomBackgrounds(),
      lastMyDayResetDate: _prefs.getString(_lastMyDayResetKey),
    );
  }

  List<int> _parseRoutineDays() {
    final raw = _prefs.getStringList(_routineNotificationDaysKey);
    if (raw == null || raw.isEmpty) {
      return const <int>[1, 2, 3, 4, 5, 6, 7];
    }
    final parsed = SplayTreeSet<int>.of(
      raw
          .map(int.tryParse)
          .whereType<int>()
          .where((d) => d >= DateTime.monday && d <= DateTime.sunday),
    ).toList();
    return parsed.isEmpty ? const <int>[1, 2, 3, 4, 5, 6, 7] : parsed;
  }

  Map<String, bool> _parseCompletedExpandedByList() {
    final raw = _prefs.getString(_completedExpandedByListKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      };
    } catch (error) {
      _log.warning('discarding unreadable $_completedExpandedByListKey', error);
      return const {};
    }
  }

  Future<void> saveSelectedListId(String listId) =>
      _prefs.setString(_selectedListIdKey, listId);

  String? loadLastEnteredListId() => _prefs.getString(_lastEnteredListIdKey);

  Future<void> saveLastEnteredListId(String? listId) =>
      _setOrRemoveString(_lastEnteredListIdKey, listId);

  Future<void> saveCompletedExpandedByList(Map<String, bool> value) =>
      _setOrRemoveString(
        _completedExpandedByListKey,
        value.isEmpty ? null : jsonEncode(value),
      );

  List<CustomBackground> _parseCustomBackgrounds() {
    final raw = _prefs.getString(_customBackgroundsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(CustomBackground.fromJson)
          .whereType<CustomBackground>()
          .toList(growable: false);
    } catch (error) {
      _log.warning('discarding unreadable $_customBackgroundsKey', error);
      return const [];
    }
  }

  Future<void> saveCustomBackgrounds(List<CustomBackground> value) =>
      _setOrRemoveString(
        _customBackgroundsKey,
        value.isEmpty
            ? null
            : jsonEncode(value.map((e) => e.toJson()).toList()),
      );

  Future<void> saveThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeModeKey, mode.name);

  Future<void> saveAddNewTasksOnTop(bool value) =>
      _prefs.setBool(_addNewTasksOnTopKey, value);

  Future<void> saveMoveStarredTasksToTop(bool value) =>
      _prefs.setBool(_moveStarredToTopKey, value);

  Future<void> savePlayCompletionSound(bool value) =>
      _prefs.setBool(_playCompletionSoundKey, value);

  Future<void> saveConfirmBeforeDeleting(bool value) =>
      _prefs.setBool(_confirmBeforeDeletingKey, value);

  Future<void> saveShowDueTodayInMyDay(bool value) =>
      _prefs.setBool(_showDueTodayInMyDayKey, value);

  Future<void> saveStartOfWeek(WeekStart value) =>
      _prefs.setString(_startOfWeekKey, value.name);

  Future<void> saveShowSmartListImportant(bool value) =>
      _prefs.setBool(_showImportantKey, value);

  Future<void> saveShowSmartListPlanned(bool value) =>
      _prefs.setBool(_showPlannedKey, value);

  Future<void> saveShowSmartListAll(bool value) =>
      _prefs.setBool(_showAllKey, value);

  Future<void> saveShowSmartListCompleted(bool value) =>
      _prefs.setBool(_showCompletedListKey, value);

  Future<void> saveAutoHideEmptySmartLists(bool value) =>
      _prefs.setBool(_autoHideSmartListsKey, value);

  Future<void> saveUseDynamicColor(bool value) =>
      _prefs.setBool(_useDynamicColorKey, value);

  Future<void> saveRemindersEnabled(bool value) =>
      _prefs.setBool(_remindersEnabledKey, value);

  Future<void> savePinReminders(bool value) =>
      _prefs.setBool(_pinRemindersKey, value);

  Future<void> saveAccurateReminders(bool value) =>
      _prefs.setBool(_accurateRemindersKey, value);

  Future<void> saveDueTodayNotificationsEnabled(bool value) =>
      _prefs.setBool(_dueTodayNotificationsKey, value);

  Future<void> saveDueTodayNotificationTime(int hour, int minute) async {
    await _prefs.setInt(_dueTodayNotificationHourKey, hour);
    await _prefs.setInt(_dueTodayNotificationMinuteKey, minute);
  }

  Future<void> saveRoutineNotificationEnabled(bool value) =>
      _prefs.setBool(_routineNotificationKey, value);

  Future<void> saveRoutineNotificationTime(int hour, int minute) async {
    await _prefs.setInt(_routineNotificationHourKey, hour);
    await _prefs.setInt(_routineNotificationMinuteKey, minute);
  }

  Future<void> saveRoutineNotificationDays(List<int> days) async {
    final sorted = SplayTreeSet<int>.of(days).toList();
    await _prefs.setStringList(
      _routineNotificationDaysKey,
      sorted.map((d) => d.toString()).toList(),
    );
  }

  Future<void> saveQuickAddNotificationEnabled(bool value) =>
      _prefs.setBool(_quickAddNotificationKey, value);

  bool get notificationPermissionPrompted =>
      _prefs.getBool(_notificationPermissionPromptedKey) ?? false;

  Future<void> saveNotificationPermissionPrompted(bool value) =>
      _prefs.setBool(_notificationPermissionPromptedKey, value);

  bool get reminderPermissionPrompted =>
      _prefs.getBool(_reminderPermissionPromptedKey) ?? false;

  Future<void> saveReminderPermissionPrompted(bool value) =>
      _prefs.setBool(_reminderPermissionPromptedKey, value);

  Future<void> saveLastMyDayResetDate(String dateKey) =>
      _prefs.setString(_lastMyDayResetKey, dateKey);

  Future<void> savePlannedDueDateFilter(PlannedDueDateFilter filter) =>
      _prefs.setString(_plannedDueDateFilterKey, filter.name);

  Future<void> savePlannedGroupOption(PlannedGroupOption option) =>
      _prefs.setString(_plannedGroupOptionKey, option.name);
}
