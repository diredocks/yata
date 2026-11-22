import 'dart:async';
import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../sync/todo_wire_codecs.dart';
import 'todo_database.dart';

part 'todo_local_storage.freezed.dart';
part 'todo_local_storage.g.dart';

@freezed
abstract class PendingStepDeletion with _$PendingStepDeletion {
  const factory PendingStepDeletion({
    required String taskRemoteId,
    required String stepRemoteId,
  }) = _PendingStepDeletion;

  factory PendingStepDeletion.fromJson(Map<String, dynamic> json) =>
      _$PendingStepDeletionFromJson(json);
}

@freezed
abstract class TodoSnapshot with _$TodoSnapshot {
  const factory TodoSnapshot({
    required List<TodoList> lists,
    required List<ListGroup> groups,
    required List<TaskItem> tasks,
    required String selectedListId,
    required ThemeMode themeMode,
    required bool addNewTasksOnTop,
    required bool moveStarredTasksToTop,
    required bool playCompletionSound,
    required bool confirmBeforeDeleting,
    required bool showDueTodayInMyDay,
    required WeekStart startOfWeek,
    required bool showSmartListImportant,
    required bool showSmartListPlanned,
    required bool showSmartListAll,
    required bool showSmartListCompleted,
    required bool autoHideEmptySmartLists,
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
    String? lastMyDayResetDate,
  }) = _TodoSnapshot;
}

class TodoLocalStorage {
  TodoLocalStorage(this._prefs, {this.accountId, TodoDatabase? database})
    : _database = database ?? _sharedFallbackDb;

  static final TodoDatabase _sharedFallbackDb = TodoDatabase();
  static const String _sessionKey = 'yata._db_session_id';

  final SharedPreferences _prefs;
  final String? accountId;
  final TodoDatabase _database;

  String get _accountKey =>
      (accountId == null || accountId!.isEmpty) ? 'default' : accountId!;

  String get _scopeKey {
    var session = _prefs.getString(_sessionKey);
    if (session == null || session.isEmpty) {
      session = generateUuidV4();
      unawaited(_prefs.setString(_sessionKey, session));
    }
    return '$session::$_accountKey';
  }

  /// Preloads this account's rows from the Drift SQLite database into memory.
  Future<void> hydrateFromDatabase() =>
      _database.preloadAccount(_accountKey, scopeKey: _scopeKey);

  /// Deletes all Drift records for this account.
  Future<void> clearAccountRecords() =>
      _database.deleteAccountRecords(_accountKey, scopeKey: _scopeKey);

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

  static List<TodoList> defaultSmartLists() {
    return const [
      TodoList(
        id: 'my_day',
        title: 'My Day',
        smartType: SmartListType.myDay,
        themeColor: ListThemeColor.blue,
        icon: Icons.wb_sunny_outlined,
      ),
      TodoList(
        id: 'important',
        title: 'Important',
        smartType: SmartListType.important,
        themeColor: ListThemeColor.rose,
        icon: Icons.star_outline,
        showCompleted: false,
      ),
      TodoList(
        id: 'planned',
        title: 'Planned',
        smartType: SmartListType.planned,
        themeColor: ListThemeColor.teal,
        icon: Icons.calendar_today_outlined,
      ),
      TodoList(
        id: 'all',
        title: 'All',
        smartType: SmartListType.all,
        themeColor: ListThemeColor.green,
        icon: Icons.all_inclusive,
        showCompleted: false,
      ),
      TodoList(
        id: 'completed',
        title: 'Completed',
        smartType: SmartListType.completed,
        themeColor: ListThemeColor.grey,
        icon: Icons.check_circle_outline,
      ),
      TodoList(
        id: 'tasks',
        title: 'Tasks',
        smartType: SmartListType.tasks,
        themeColor: ListThemeColor.blue,
        icon: Icons.home_outlined,
      ),
    ];
  }

  TodoSnapshot load() {
    final cachedLists = _database.readCachedLists(_scopeKey);
    var lists = cachedLists != null ? [...cachedLists] : defaultSmartLists();

    if (lists.isEmpty) {
      lists = defaultSmartLists();
    } else if (!lists.any((l) => l.smartType == SmartListType.completed)) {
      final idx = lists.indexWhere((l) => l.smartType == SmartListType.tasks);
      final completedList = defaultSmartLists().firstWhere(
        (l) => l.smartType == SmartListType.completed,
      );
      if (idx >= 0) {
        lists.insert(idx, completedList);
      } else {
        lists.add(completedList);
      }
    }
    lists = [
      for (final list in lists)
        if (list.smartType == SmartListType.all && list.showCompleted)
          list.copyWith(showCompleted: false)
        else if (list.smartType == SmartListType.completed &&
            !list.showCompleted)
          list.copyWith(showCompleted: true)
        else
          list,
    ];

    final groups = [..._database.readCachedGroups(_scopeKey)];
    final tasks = [..._database.readCachedTasks(_scopeKey)];

    final selectedListId = _prefs.getString(_selectedListIdKey) ?? 'my_day';
    final themeName = _prefs.getString(_themeModeKey);
    final themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == themeName,
      orElse: () => ThemeMode.system,
    );
    final weekStartName = _prefs.getString(_startOfWeekKey);
    final startOfWeek = WeekStart.values.firstWhere(
      (e) => e.name == weekStartName,
      orElse: () => WeekStart.system,
    );
    final plannedFilterName = _prefs.getString(_plannedDueDateFilterKey);
    final plannedDueDateFilter = PlannedDueDateFilter.values.firstWhere(
      (e) => e.name == plannedFilterName,
      orElse: () => PlannedDueDateFilter.all,
    );
    final plannedGroupName = _prefs.getString(_plannedGroupOptionKey);
    final plannedGroupOption = PlannedGroupOption.values.firstWhere(
      (e) => e.name == plannedGroupName,
      orElse: () => PlannedGroupOption.byDueDate,
    );

    return TodoSnapshot(
      lists: lists,
      groups: groups,
      tasks: tasks,
      selectedListId: selectedListId,
      themeMode: themeMode,
      addNewTasksOnTop: _prefs.getBool(_addNewTasksOnTopKey) ?? true,
      moveStarredTasksToTop: _prefs.getBool(_moveStarredToTopKey) ?? true,
      playCompletionSound: _prefs.getBool(_playCompletionSoundKey) ?? true,
      confirmBeforeDeleting: _prefs.getBool(_confirmBeforeDeletingKey) ?? true,
      showDueTodayInMyDay: _prefs.getBool(_showDueTodayInMyDayKey) ?? true,
      startOfWeek: startOfWeek,
      showSmartListImportant: _prefs.getBool(_showImportantKey) ?? true,
      showSmartListPlanned: _prefs.getBool(_showPlannedKey) ?? true,
      showSmartListAll: _prefs.getBool(_showAllKey) ?? false,
      showSmartListCompleted: _prefs.getBool(_showCompletedListKey) ?? false,
      autoHideEmptySmartLists: _prefs.getBool(_autoHideSmartListsKey) ?? false,
      plannedDueDateFilter: plannedDueDateFilter,
      plannedGroupOption: plannedGroupOption,
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
      lastMyDayResetDate: _prefs.getString(_lastMyDayResetKey),
    );
  }

  Future<void> saveLists(List<TodoList> lists) =>
      _database.writeLists(_accountKey, lists, scopeKey: _scopeKey);

  Future<void> saveGroups(List<ListGroup> groups) =>
      _database.writeGroups(_accountKey, groups, scopeKey: _scopeKey);

  Future<void> saveTasks(List<TaskItem> tasks) =>
      _database.writeTasks(_accountKey, tasks, scopeKey: _scopeKey);

  Future<void> saveSelectedListId(String listId) =>
      _prefs.setString(_selectedListIdKey, listId);

  String? loadLastEnteredListId() => _prefs.getString(_lastEnteredListIdKey);

  Future<void> saveLastEnteredListId(String? listId) async {
    if (listId == null) {
      await _prefs.remove(_lastEnteredListIdKey);
    } else {
      await _prefs.setString(_lastEnteredListIdKey, listId);
    }
  }

  Map<String, bool> loadCompletedExpandedByList() {
    final raw = _prefs.getString(_completedExpandedByListKey);
    if (raw == null) return const {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in decoded.entries)
        if (entry.value is bool) entry.key: entry.value as bool,
    };
  }

  Future<void> saveCompletedExpandedByList(Map<String, bool> value) async {
    if (value.isEmpty) {
      await _prefs.remove(_completedExpandedByListKey);
    } else {
      await _prefs.setString(_completedExpandedByListKey, jsonEncode(value));
    }
  }

  Future<void> saveThemeMode(ThemeMode mode) =>
      _prefs.setString(_themeModeKey, mode.name);

  Future<void> saveBoolSetting(String key, bool value) =>
      _prefs.setBool(key, value);

  Future<void> saveAddNewTasksOnTop(bool value) =>
      saveBoolSetting(_addNewTasksOnTopKey, value);

  Future<void> saveMoveStarredTasksToTop(bool value) =>
      saveBoolSetting(_moveStarredToTopKey, value);

  Future<void> savePlayCompletionSound(bool value) =>
      saveBoolSetting(_playCompletionSoundKey, value);

  Future<void> saveConfirmBeforeDeleting(bool value) =>
      saveBoolSetting(_confirmBeforeDeletingKey, value);

  Future<void> saveShowDueTodayInMyDay(bool value) =>
      saveBoolSetting(_showDueTodayInMyDayKey, value);

  Future<void> saveStartOfWeek(WeekStart value) =>
      _prefs.setString(_startOfWeekKey, value.name);

  Future<void> saveShowSmartListImportant(bool value) =>
      saveBoolSetting(_showImportantKey, value);

  Future<void> saveShowSmartListPlanned(bool value) =>
      saveBoolSetting(_showPlannedKey, value);

  Future<void> saveShowSmartListAll(bool value) =>
      saveBoolSetting(_showAllKey, value);

  Future<void> saveShowSmartListCompleted(bool value) =>
      saveBoolSetting(_showCompletedListKey, value);

  Future<void> saveAutoHideEmptySmartLists(bool value) =>
      saveBoolSetting(_autoHideSmartListsKey, value);

  Future<void> saveUseDynamicColor(bool value) =>
      saveBoolSetting(_useDynamicColorKey, value);

  Future<void> saveRemindersEnabled(bool value) =>
      saveBoolSetting(_remindersEnabledKey, value);

  Future<void> savePinReminders(bool value) =>
      saveBoolSetting(_pinRemindersKey, value);

  Future<void> saveDueTodayNotificationsEnabled(bool value) =>
      saveBoolSetting(_dueTodayNotificationsKey, value);

  Future<void> saveDueTodayNotificationTime(int hour, int minute) async {
    await _prefs.setInt(_dueTodayNotificationHourKey, hour);
    await _prefs.setInt(_dueTodayNotificationMinuteKey, minute);
  }

  Future<void> saveRoutineNotificationEnabled(bool value) =>
      saveBoolSetting(_routineNotificationKey, value);

  Future<void> saveRoutineNotificationTime(int hour, int minute) async {
    await _prefs.setInt(_routineNotificationHourKey, hour);
    await _prefs.setInt(_routineNotificationMinuteKey, minute);
  }

  Future<void> saveQuickAddNotificationEnabled(bool value) =>
      saveBoolSetting(_quickAddNotificationKey, value);

  Future<void> saveLastMyDayResetDate(String dateKey) =>
      _prefs.setString(_lastMyDayResetKey, dateKey);

  Future<void> savePlannedDueDateFilter(PlannedDueDateFilter filter) =>
      _prefs.setString(_plannedDueDateFilterKey, filter.name);

  Future<void> savePlannedGroupOption(PlannedGroupOption option) =>
      _prefs.setString(_plannedGroupOptionKey, option.name);

  List<String> loadPendingDeletedListRemoteIds() =>
      _database.readCachedMutationKeys(_scopeKey, 'deleted_list');

  Future<void> savePendingDeletedListRemoteIds(List<String> ids) => _database
      .writeMutationKeys(_accountKey, 'deleted_list', ids, scopeKey: _scopeKey);

  List<String> loadPendingDeletedTaskRemoteIds() =>
      _database.readCachedMutationKeys(_scopeKey, 'deleted_task');

  Future<void> savePendingDeletedTaskRemoteIds(List<String> ids) => _database
      .writeMutationKeys(_accountKey, 'deleted_task', ids, scopeKey: _scopeKey);

  List<String> loadPendingDeletedGroupRemoteIds() =>
      _database.readCachedMutationKeys(_scopeKey, 'deleted_group');

  Future<void> savePendingDeletedGroupRemoteIds(List<String> ids) =>
      _database.writeMutationKeys(
        _accountKey,
        'deleted_group',
        ids,
        scopeKey: _scopeKey,
      );

  List<PendingStepDeletion> loadPendingDeletedSteps() =>
      _database.readCachedPendingDeletedSteps(_scopeKey);

  Future<void> savePendingDeletedSteps(List<PendingStepDeletion> items) =>
      _database.writePendingDeletedSteps(
        _accountKey,
        items,
        scopeKey: _scopeKey,
      );

  Set<String> loadDirtyListIds() =>
      _database.readCachedMutationKeys(_scopeKey, 'dirty_list').toSet();

  Future<void> saveDirtyListIds(Set<String> ids) => _database.writeMutationKeys(
    _accountKey,
    'dirty_list',
    ids,
    scopeKey: _scopeKey,
  );

  Set<String> loadDirtyGroupIds() =>
      _database.readCachedMutationKeys(_scopeKey, 'dirty_group').toSet();

  Future<void> saveDirtyGroupIds(Set<String> ids) => _database
      .writeMutationKeys(_accountKey, 'dirty_group', ids, scopeKey: _scopeKey);

  Set<String> loadDirtyTaskIds() =>
      _database.readCachedMutationKeys(_scopeKey, 'dirty_task').toSet();

  Future<void> saveDirtyTaskIds(Set<String> ids) => _database.writeMutationKeys(
    _accountKey,
    'dirty_task',
    ids,
    scopeKey: _scopeKey,
  );

  Set<String> loadDirtySettingKeys() =>
      (_prefs.getStringList(_dirtySettingKeysKey) ?? const []).toSet();

  Future<void> saveDirtySettingKeys(Set<String> keys) async {
    if (keys.isEmpty) {
      await _prefs.remove(_dirtySettingKeysKey);
    } else {
      await _prefs.setStringList(_dirtySettingKeysKey, keys.toList());
    }
  }

  String? loadGroupsDeltaLink() => _prefs.getString(_groupsDeltaLinkKey);

  Future<void> saveGroupsDeltaLink(String? deltaLink) async {
    if (deltaLink == null || deltaLink.isEmpty) {
      await _prefs.remove(_groupsDeltaLinkKey);
    } else {
      await _prefs.setString(_groupsDeltaLinkKey, deltaLink);
    }
  }

  String? loadFoldersDeltaLink() => _prefs.getString(_foldersDeltaLinkKey);

  Future<void> saveFoldersDeltaLink(String? deltaLink) async {
    if (deltaLink == null || deltaLink.isEmpty) {
      await _prefs.remove(_foldersDeltaLinkKey);
    } else {
      await _prefs.setString(_foldersDeltaLinkKey, deltaLink);
    }
  }

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

  Future<void> saveTaskDeltaLinks(Map<String, String> links) async {
    if (links.isEmpty) {
      await _prefs.remove(_taskDeltaLinksKey);
    } else {
      await _prefs.setString(_taskDeltaLinksKey, jsonEncode(links));
    }
  }

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

  Future<void> saveCachedEndpointUrl(String url) async {
    await _prefs.setString(_cachedEndpointUrlKey, url);
    await _prefs.setString(
      _cachedEndpointFetchedAtKey,
      DateTime.now().toUtc().toIso8601String(),
    );
  }
}
