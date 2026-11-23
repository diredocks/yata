import 'dart:async';
import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:result_dart/result_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../core/result/app_result.dart';
import '../models/todo_list.dart';
import '../sync/todo_wire_codecs.dart';

part 'todo_settings_store.freezed.dart';

/// Per-account settings that live in [SharedPreferences].
@freezed
abstract class TodoSettings with _$TodoSettings {
  const factory TodoSettings({
    @Default('my_day') String selectedListId,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool addNewTasksOnTop,
    @Default(true) bool moveStarredTasksToTop,
    @Default(true) bool playCompletionSound,
    @Default(true) bool confirmBeforeDeleting,
    @Default(true) bool showDueTodayInMyDay,
    @Default(WeekStart.system) WeekStart startOfWeek,
    @Default(true) bool showSmartListImportant,
    @Default(true) bool showSmartListPlanned,
    @Default(false) bool showSmartListAll,
    @Default(false) bool showSmartListCompleted,
    @Default(false) bool autoHideEmptySmartLists,
    @Default(PlannedDueDateFilter.all)
    PlannedDueDateFilter plannedDueDateFilter,
    @Default(PlannedGroupOption.byDueDate)
    PlannedGroupOption plannedGroupOption,
    @Default(true) bool useDynamicColor,
    @Default(true) bool remindersEnabled,
    @Default(false) bool pinReminders,
    @Default(false) bool dueTodayNotificationsEnabled,
    @Default(9) int dueTodayNotificationHour,
    @Default(0) int dueTodayNotificationMinute,
    @Default(false) bool routineNotificationEnabled,
    @Default(8) int routineNotificationHour,
    @Default(30) int routineNotificationMinute,
    @Default(false) bool quickAddNotificationEnabled,
    @Default(<String, bool>{}) Map<String, bool> completedExpandedByList,
    String? lastMyDayResetDate,
  }) = _TodoSettings;
}

/// Owns every `SharedPreferences` key: user settings and sync bookkeeping.
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
  String get _dueTodayNotificationsKey => _k('due_date_notification_enabled');
  String get _dueTodayNotificationHourKey => _k('due_date_notification_hour');
  String get _dueTodayNotificationMinuteKey =>
      _k('due_date_notification_minute');
  String get _routineNotificationKey => _k('routine_notification_enabled');
  String get _routineNotificationHourKey => _k('routine_notification_hour');
  String get _routineNotificationMinuteKey => _k('routine_notification_minute');
  String get _quickAddNotificationKey => _k('quick_add_notification_enabled');
  String get _lastMyDayResetKey => _k('last_my_day_reset');
  String get _plannedDueDateFilterKey => _k('planned_due_date_filter');
  String get _plannedGroupOptionKey => _k('planned_group_option');
  String get _dirtySettingKeysKey => _k('dirty_setting_keys');
  String get _groupsDeltaLinkKey => _k('groups_delta_link');
  String get _foldersDeltaLinkKey => _k('folders_delta_link');
  String get _taskDeltaLinksKey => _k('task_delta_links');
  String get _cachedEndpointUrlKey => _k('cached_endpoint_url');
  String get _cachedEndpointFetchedAtKey => _k('cached_endpoint_fetched_at');

  AppResult<TodoSettings> load() =>
      guardSync(_buildSettings, operation: 'loadTodoSettings');

  TodoSettings _buildSettings() {
    final themeName = _prefs.getString(_themeModeKey);
    final weekStartName = _prefs.getString(_startOfWeekKey);
    final plannedFilterName = _prefs.getString(_plannedDueDateFilterKey);
    final plannedGroupName = _prefs.getString(_plannedGroupOptionKey);
    return TodoSettings(
      selectedListId: _prefs.getString(_selectedListIdKey) ?? 'my_day',
      themeMode: ThemeMode.values.firstWhere(
        (e) => e.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      addNewTasksOnTop: _prefs.getBool(_addNewTasksOnTopKey) ?? true,
      moveStarredTasksToTop: _prefs.getBool(_moveStarredToTopKey) ?? true,
      playCompletionSound: _prefs.getBool(_playCompletionSoundKey) ?? true,
      confirmBeforeDeleting: _prefs.getBool(_confirmBeforeDeletingKey) ?? true,
      showDueTodayInMyDay: _prefs.getBool(_showDueTodayInMyDayKey) ?? true,
      startOfWeek: WeekStart.values.firstWhere(
        (e) => e.name == weekStartName,
        orElse: () => WeekStart.system,
      ),
      showSmartListImportant: _prefs.getBool(_showImportantKey) ?? true,
      showSmartListPlanned: _prefs.getBool(_showPlannedKey) ?? true,
      showSmartListAll: _prefs.getBool(_showAllKey) ?? false,
      showSmartListCompleted: _prefs.getBool(_showCompletedListKey) ?? false,
      autoHideEmptySmartLists: _prefs.getBool(_autoHideSmartListsKey) ?? false,
      plannedDueDateFilter: PlannedDueDateFilter.values.firstWhere(
        (e) => e.name == plannedFilterName,
        orElse: () => PlannedDueDateFilter.all,
      ),
      plannedGroupOption: PlannedGroupOption.values.firstWhere(
        (e) => e.name == plannedGroupName,
        orElse: () => PlannedGroupOption.byDueDate,
      ),
      useDynamicColor: _prefs.getBool(_useDynamicColorKey) ?? true,
      remindersEnabled: _prefs.getBool(_remindersEnabledKey) ?? true,
      pinReminders: _prefs.getBool(_pinRemindersKey) ?? false,
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
      quickAddNotificationEnabled:
          _prefs.getBool(_quickAddNotificationKey) ?? false,
      completedExpandedByList: _parseCompletedExpandedByList(),
      lastMyDayResetDate: _prefs.getString(_lastMyDayResetKey),
    );
  }

  Map<String, bool> _parseCompletedExpandedByList() {
    final raw = _prefs.getString(_completedExpandedByListKey);
    if (raw == null) return const {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        if (entry.value is bool) entry.key: entry.value as bool,
    };
  }

  AsyncAppResult<Unit> saveSelectedListId(String listId) => guardAsyncUnit(
    () => _prefs.setString(_selectedListIdKey, listId),
    operation: 'saveSelectedListId',
  );

  String? loadLastEnteredListId() => _prefs.getString(_lastEnteredListIdKey);

  AsyncAppResult<Unit> saveLastEnteredListId(String? listId) =>
      guardAsyncUnit(() async {
        if (listId == null) {
          await _prefs.remove(_lastEnteredListIdKey);
        } else {
          await _prefs.setString(_lastEnteredListIdKey, listId);
        }
      }, operation: 'saveLastEnteredListId');

  AsyncAppResult<Unit> saveCompletedExpandedByList(Map<String, bool> value) =>
      guardAsyncUnit(() async {
        if (value.isEmpty) {
          await _prefs.remove(_completedExpandedByListKey);
        } else {
          await _prefs.setString(
            _completedExpandedByListKey,
            jsonEncode(value),
          );
        }
      }, operation: 'saveCompletedExpandedByList');

  AsyncAppResult<Unit> saveThemeMode(ThemeMode mode) => guardAsyncUnit(
    () => _prefs.setString(_themeModeKey, mode.name),
    operation: 'saveThemeMode',
  );

  AsyncAppResult<Unit> saveBoolSetting(String key, bool value) =>
      guardAsyncUnit(
        () => _prefs.setBool(key, value),
        operation: 'saveBoolSetting',
      );

  AsyncAppResult<Unit> saveAddNewTasksOnTop(bool value) =>
      saveBoolSetting(_addNewTasksOnTopKey, value);

  AsyncAppResult<Unit> saveMoveStarredTasksToTop(bool value) =>
      saveBoolSetting(_moveStarredToTopKey, value);

  AsyncAppResult<Unit> savePlayCompletionSound(bool value) =>
      saveBoolSetting(_playCompletionSoundKey, value);

  AsyncAppResult<Unit> saveConfirmBeforeDeleting(bool value) =>
      saveBoolSetting(_confirmBeforeDeletingKey, value);

  AsyncAppResult<Unit> saveShowDueTodayInMyDay(bool value) =>
      saveBoolSetting(_showDueTodayInMyDayKey, value);

  AsyncAppResult<Unit> saveStartOfWeek(WeekStart value) => guardAsyncUnit(
    () => _prefs.setString(_startOfWeekKey, value.name),
    operation: 'saveStartOfWeek',
  );

  AsyncAppResult<Unit> saveShowSmartListImportant(bool value) =>
      saveBoolSetting(_showImportantKey, value);

  AsyncAppResult<Unit> saveShowSmartListPlanned(bool value) =>
      saveBoolSetting(_showPlannedKey, value);

  AsyncAppResult<Unit> saveShowSmartListAll(bool value) =>
      saveBoolSetting(_showAllKey, value);

  AsyncAppResult<Unit> saveShowSmartListCompleted(bool value) =>
      saveBoolSetting(_showCompletedListKey, value);

  AsyncAppResult<Unit> saveAutoHideEmptySmartLists(bool value) =>
      saveBoolSetting(_autoHideSmartListsKey, value);

  AsyncAppResult<Unit> saveUseDynamicColor(bool value) =>
      saveBoolSetting(_useDynamicColorKey, value);

  AsyncAppResult<Unit> saveRemindersEnabled(bool value) =>
      saveBoolSetting(_remindersEnabledKey, value);

  AsyncAppResult<Unit> savePinReminders(bool value) =>
      saveBoolSetting(_pinRemindersKey, value);

  AsyncAppResult<Unit> saveDueTodayNotificationsEnabled(bool value) =>
      saveBoolSetting(_dueTodayNotificationsKey, value);

  AsyncAppResult<Unit> saveDueTodayNotificationTime(int hour, int minute) =>
      guardAsyncUnit(() async {
        await _prefs.setInt(_dueTodayNotificationHourKey, hour);
        await _prefs.setInt(_dueTodayNotificationMinuteKey, minute);
      }, operation: 'saveDueTodayNotificationTime');

  AsyncAppResult<Unit> saveRoutineNotificationEnabled(bool value) =>
      saveBoolSetting(_routineNotificationKey, value);

  AsyncAppResult<Unit> saveRoutineNotificationTime(int hour, int minute) =>
      guardAsyncUnit(() async {
        await _prefs.setInt(_routineNotificationHourKey, hour);
        await _prefs.setInt(_routineNotificationMinuteKey, minute);
      }, operation: 'saveRoutineNotificationTime');

  AsyncAppResult<Unit> saveQuickAddNotificationEnabled(bool value) =>
      saveBoolSetting(_quickAddNotificationKey, value);

  AsyncAppResult<Unit> saveLastMyDayResetDate(String dateKey) => guardAsyncUnit(
    () => _prefs.setString(_lastMyDayResetKey, dateKey),
    operation: 'saveLastMyDayResetDate',
  );

  AsyncAppResult<Unit> savePlannedDueDateFilter(PlannedDueDateFilter filter) =>
      guardAsyncUnit(
        () => _prefs.setString(_plannedDueDateFilterKey, filter.name),
        operation: 'savePlannedDueDateFilter',
      );

  AsyncAppResult<Unit> savePlannedGroupOption(PlannedGroupOption option) =>
      guardAsyncUnit(
        () => _prefs.setString(_plannedGroupOptionKey, option.name),
        operation: 'savePlannedGroupOption',
      );

  Set<String> loadDirtySettingKeys() =>
      (_prefs.getStringList(_dirtySettingKeysKey) ?? const []).toSet();

  AsyncAppResult<Unit> saveDirtySettingKeys(Set<String> keys) =>
      guardAsyncUnit(() async {
        if (keys.isEmpty) {
          await _prefs.remove(_dirtySettingKeysKey);
        } else {
          await _prefs.setStringList(_dirtySettingKeysKey, keys.toList());
        }
      }, operation: 'saveDirtySettingKeys');

  String? loadGroupsDeltaLink() => _prefs.getString(_groupsDeltaLinkKey);

  AsyncAppResult<Unit> saveGroupsDeltaLink(String? deltaLink) =>
      guardAsyncUnit(() async {
        if (deltaLink == null || deltaLink.isEmpty) {
          await _prefs.remove(_groupsDeltaLinkKey);
        } else {
          await _prefs.setString(_groupsDeltaLinkKey, deltaLink);
        }
      }, operation: 'saveGroupsDeltaLink');

  String? loadFoldersDeltaLink() => _prefs.getString(_foldersDeltaLinkKey);

  AsyncAppResult<Unit> saveFoldersDeltaLink(String? deltaLink) =>
      guardAsyncUnit(() async {
        if (deltaLink == null || deltaLink.isEmpty) {
          await _prefs.remove(_foldersDeltaLinkKey);
        } else {
          await _prefs.setString(_foldersDeltaLinkKey, deltaLink);
        }
      }, operation: 'saveFoldersDeltaLink');

  Map<String, String> loadTaskDeltaLinks() {
    final raw = _prefs.getString(_taskDeltaLinksKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (entry.value is String && (entry.value as String).isNotEmpty)
            entry.key: entry.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  AsyncAppResult<Unit> saveTaskDeltaLinks(Map<String, String> links) =>
      guardAsyncUnit(() async {
        if (links.isEmpty) {
          await _prefs.remove(_taskDeltaLinksKey);
        } else {
          await _prefs.setString(_taskDeltaLinksKey, jsonEncode(links));
        }
      }, operation: 'saveTaskDeltaLinks');

  String? loadCachedEndpointUrl({Duration maxAge = const Duration(hours: 12)}) {
    final url = _prefs.getString(_cachedEndpointUrlKey);
    final fetchedRaw = _prefs.getString(_cachedEndpointFetchedAtKey);
    if (url == null || url.isEmpty || fetchedRaw == null) return null;
    final fetchedAt = DateTime.tryParse(fetchedRaw);
    if (fetchedAt == null) return null;
    if (DateTime.now().toUtc().difference(fetchedAt.toUtc()) > maxAge) {
      return null;
    }
    return url;
  }

  AsyncAppResult<Unit> saveCachedEndpointUrl(String url) =>
      guardAsyncUnit(() async {
        await _prefs.setString(_cachedEndpointUrlKey, url);
        await _prefs.setString(
          _cachedEndpointFetchedAtKey,
          DateTime.now().toUtc().toIso8601String(),
        );
      }, operation: 'saveCachedEndpointUrl');
}
