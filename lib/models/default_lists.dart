import 'todo_list.dart';

/// Built-in smart lists shown for every account.
List<TodoList> defaultSmartLists() {
  return const [
    TodoList(
      id: 'my_day',
      title: 'My Day',
      smartType: SmartListType.myDay,
      themeColor: ListThemeColor.blue,
    ),
    TodoList(
      id: 'important',
      title: 'Important',
      smartType: SmartListType.important,
      themeColor: ListThemeColor.rose,
      showCompleted: false,
    ),
    TodoList(
      id: 'planned',
      title: 'Planned',
      smartType: SmartListType.planned,
      themeColor: ListThemeColor.teal,
    ),
    TodoList(
      id: 'all',
      title: 'All',
      smartType: SmartListType.all,
      themeColor: ListThemeColor.green,
      showCompleted: false,
    ),
    TodoList(
      id: 'completed',
      title: 'Completed',
      smartType: SmartListType.completed,
      themeColor: ListThemeColor.grey,
    ),
    TodoList(
      id: 'tasks',
      title: 'Tasks',
      smartType: SmartListType.tasks,
      themeColor: ListThemeColor.blue,
    ),
  ];
}

/// Fills in missing built-in lists and enforces their fixed visibility flags.
List<TodoList> normalizeSmartLists(List<TodoList>? cached) {
  var lists = cached == null ? defaultSmartLists() : [...cached];
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
  return [
    for (final list in lists)
      if (list.smartType == SmartListType.all && list.showCompleted)
        list.copyWith(showCompleted: false)
      else if (list.smartType == SmartListType.completed && !list.showCompleted)
        list.copyWith(showCompleted: true)
      else
        list,
  ];
}
