import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';

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
  TodoLocalStorage(this._prefs);

  final SharedPreferences _prefs;

  static const _listsKey = 'yata.lists';
  static const _groupsKey = 'yata.groups';
  static const _tasksKey = 'yata.tasks';
  static const _selectedListIdKey = 'yata.selected_list_id';
  static const _sortOptionKey = 'yata.sort_option';
  static const _showCompletedKey = 'yata.show_completed';
  static const _themeModeKey = 'yata.theme_mode';
  static const _addNewTasksOnTopKey = 'yata.add_new_tasks_on_top';
  static const _moveStarredToTopKey = 'yata.move_starred_to_top';
  static const _confirmBeforeDeletingKey = 'yata.confirm_before_deleting';
  static const _showDueTodayInMyDayKey = 'yata.show_due_today_in_my_day';
  static const _startOfWeekKey = 'yata.start_of_week';
  static const _showImportantKey = 'yata.show_smart_important';
  static const _showPlannedKey = 'yata.show_smart_planned';
  static const _showAllKey = 'yata.show_smart_all';
  static const _showCompletedListKey = 'yata.show_smart_completed';
  static const _autoHideSmartListsKey = 'yata.autohide_smart_lists';
  static const _lastMyDayResetKey = 'yata.last_my_day_reset';

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
