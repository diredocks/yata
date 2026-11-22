import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'account_local_storage.dart';

class TodoSnapshot {
  const TodoSnapshot({
    required this.lists,
    required this.groups,
    required this.tasks,
    required this.selectedListId,
    required this.sortOption,
    required this.showCompleted,
    required this.themeMode,
    required this.addNewTasksOnTop,
    required this.moveStarredTasksToTop,
    required this.playCompletionSound,
    required this.confirmBeforeDeleting,
    required this.showDueTodayInMyDay,
    required this.startOfWeek,
    required this.showSmartListImportant,
    required this.showSmartListPlanned,
    required this.showSmartListAll,
    required this.showSmartListCompleted,
    required this.autoHideEmptySmartLists,
    this.lastMyDayResetDate,
  });

  final List<TodoList> lists;
  final List<ListGroup> groups;
  final List<TaskItem> tasks;
  final String selectedListId;
  final TaskSortOption sortOption;
  final bool showCompleted;
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
  final String? lastMyDayResetDate;
}

class TodoLocalStorage {
  TodoLocalStorage(this._prefs, {this.accountId});

  final SharedPreferences _prefs;
  final String? accountId;

  String _k(String suffix) {
    final id = accountId;
    if (id == null || id.isEmpty) {
      return 'yata.$suffix';
    }
    return '${AccountLocalStorage.accountKeyPrefix(id)}$suffix';
  }

  String get _listsKey => _k('lists');
  String get _groupsKey => _k('groups');
  String get _tasksKey => _k('tasks');
  String get _selectedListIdKey => _k('selected_list_id');
  String get _sortOptionKey => _k('sort_option');
  String get _showCompletedKey => _k('show_completed');
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
  String get _lastMyDayResetKey => _k('last_my_day_reset');

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
    final listsRaw = _prefs.getString(_listsKey);
    final groupsRaw = _prefs.getString(_groupsKey);
    final tasksRaw = _prefs.getString(_tasksKey);

    var lists = listsRaw != null
        ? (jsonDecode(listsRaw) as List<dynamic>)
            .map((e) => TodoList.fromJson(e as Map<String, dynamic>))
            .toList()
        : defaultSmartLists();

    if (lists.isEmpty) {
      lists = defaultSmartLists();
    } else if (!lists.any((l) => l.smartType == SmartListType.completed)) {
      final idx = lists.indexWhere((l) => l.smartType == SmartListType.tasks);
      final completedList = defaultSmartLists()
          .firstWhere((l) => l.smartType == SmartListType.completed);
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

    final groups = groupsRaw != null
        ? (jsonDecode(groupsRaw) as List<dynamic>)
            .map((e) => ListGroup.fromJson(e as Map<String, dynamic>))
            .toList()
        : <ListGroup>[];

    final tasks = tasksRaw != null
        ? (jsonDecode(tasksRaw) as List<dynamic>)
            .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
            .toList()
        : <TaskItem>[];

    final selectedListId = _prefs.getString(_selectedListIdKey) ?? 'my_day';
    final sortName = _prefs.getString(_sortOptionKey);
    final sortOption = TaskSortOption.values.firstWhere(
      (e) => e.name == sortName,
      orElse: () => TaskSortOption.defaultOrder,
    );
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

    return TodoSnapshot(
      lists: lists,
      groups: groups,
      tasks: tasks,
      selectedListId: selectedListId,
      sortOption: sortOption,
      showCompleted: _prefs.getBool(_showCompletedKey) ?? true,
      themeMode: themeMode,
      addNewTasksOnTop: _prefs.getBool(_addNewTasksOnTopKey) ?? true,
      moveStarredTasksToTop: _prefs.getBool(_moveStarredToTopKey) ?? true,
      playCompletionSound: _prefs.getBool(_playCompletionSoundKey) ?? true,
      confirmBeforeDeleting:
          _prefs.getBool(_confirmBeforeDeletingKey) ?? true,
      showDueTodayInMyDay: _prefs.getBool(_showDueTodayInMyDayKey) ?? true,
      startOfWeek: startOfWeek,
      showSmartListImportant: _prefs.getBool(_showImportantKey) ?? true,
      showSmartListPlanned: _prefs.getBool(_showPlannedKey) ?? true,
      showSmartListAll: _prefs.getBool(_showAllKey) ?? false,
      showSmartListCompleted: _prefs.getBool(_showCompletedListKey) ?? false,
      autoHideEmptySmartLists:
          _prefs.getBool(_autoHideSmartListsKey) ?? false,
      lastMyDayResetDate: _prefs.getString(_lastMyDayResetKey),
    );
  }

  Future<void> saveLists(List<TodoList> lists) async {
    await _prefs.setString(
      _listsKey,
      jsonEncode(lists.map((l) => l.toJson()).toList()),
    );
  }

  Future<void> saveGroups(List<ListGroup> groups) async {
    await _prefs.setString(
      _groupsKey,
      jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> saveTasks(List<TaskItem> tasks) async {
    await _prefs.setString(
      _tasksKey,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> saveSelectedListId(String listId) =>
      _prefs.setString(_selectedListIdKey, listId);

  Future<void> saveSortOption(TaskSortOption option) =>
      _prefs.setString(_sortOptionKey, option.name);

  Future<void> saveShowCompleted(bool value) =>
      _prefs.setBool(_showCompletedKey, value);

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

  Future<void> saveLastMyDayResetDate(String dateKey) =>
      _prefs.setString(_lastMyDayResetKey, dateKey);
}
