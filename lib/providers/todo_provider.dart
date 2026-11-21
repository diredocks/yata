import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/todo_local_storage.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final todoLocalStorageProvider = Provider<TodoLocalStorage>((ref) {
  return TodoLocalStorage(ref.watch(sharedPreferencesProvider));
});

@immutable
class TodoState {
  const TodoState({
    required this.lists,
    required this.groups,
    required this.tasks,
    required this.selectedListId,
    this.selectedTaskId,
    this.sortOption = TaskSortOption.defaultOrder,
    this.showCompleted = true,
    this.themeMode = ThemeMode.system,
    this.addNewTasksOnTop = true,
    this.moveStarredTasksToTop = true,
    this.confirmBeforeDeleting = true,
    this.showDueTodayInMyDay = true,
    this.startOfWeek = WeekStart.system,
    this.showSmartListImportant = true,
    this.showSmartListPlanned = true,
    this.showSmartListAll = true,
    this.showSmartListCompleted = false,
    this.autoHideEmptySmartLists = false,
  });

  final List<TodoList> lists;
  final List<ListGroup> groups;
  final List<TaskItem> tasks;
  final String selectedListId;
  final String? selectedTaskId;
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

  TodoList get selectedList {
    return lists.firstWhere(
      (list) => list.id == selectedListId,
      orElse: () => lists.first,
    );
  }

  TaskItem? get selectedTask {
    if (selectedTaskId == null) return null;
    for (final task in tasks) {
      if (task.id == selectedTaskId) return task;
    }
    return null;
  }

  List<TaskItem> tasksForList(TodoList list) {
    final Iterable<TaskItem> filtered = switch (list.smartType) {
      SmartListType.myDay => tasks.where((t) => t.isInMyDay),
      SmartListType.important => tasks.where((t) => t.isImportant),
      SmartListType.planned =>
        tasks.where((t) => t.dueDate != null || t.reminderAt != null),
      SmartListType.all => tasks,
      SmartListType.completed => tasks.where((t) => t.isCompleted),
      SmartListType.tasks => tasks.where((t) => t.listId == 'tasks'),
      null => tasks.where((t) => t.listId == list.id),
    };

    final result = filtered.toList();
    final dir = list.sortAscending ? 1 : -1;
    switch (list.sortOption) {
      case TaskSortOption.defaultOrder:
        if (moveStarredTasksToTop &&
            list.smartType != SmartListType.important) {
          final starred = result.where((t) => t.isImportant).toList();
          final unstarred = result.where((t) => !t.isImportant).toList();
          return [...starred, ...unstarred];
        }
      case TaskSortOption.importance:
        result.sort((a, b) {
          if (a.isImportant == b.isImportant) return 0;
          return (a.isImportant ? -1 : 1) * dir;
        });
      case TaskSortOption.dueDate:
        result.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!) * dir;
        });
      case TaskSortOption.addedToMyDay:
        result.sort((a, b) {
          if (a.isInMyDay != b.isInMyDay) {
            return (a.isInMyDay ? -1 : 1) * dir;
          }
          final aDate = a.myDayDate ?? a.createdAt;
          final bDate = b.myDayDate ?? b.createdAt;
          return bDate.compareTo(aDate) * dir;
        });
      case TaskSortOption.alphabetical:
        result.sort(
          (a, b) =>
              a.title.toLowerCase().compareTo(b.title.toLowerCase()) * dir,
        );
      case TaskSortOption.creationDate:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt) * dir);
    }
    return result;
  }

  int activeCountForList(TodoList list) {
    if (list.smartType == SmartListType.completed) {
      return tasks.where((t) => t.isCompleted).length;
    }
    return tasksForList(list).where((t) => !t.isCompleted).length;
  }

  bool isSmartListVisible(TodoList list) {
    final visibleByToggle = switch (list.smartType) {
      SmartListType.myDay => true,
      SmartListType.important => showSmartListImportant,
      SmartListType.planned => showSmartListPlanned,
      SmartListType.all => showSmartListAll,
      SmartListType.completed => showSmartListCompleted,
      SmartListType.tasks => true,
      null => true,
    };
    if (!visibleByToggle) return false;

    if (autoHideEmptySmartLists &&
        list.smartType != SmartListType.myDay &&
        list.smartType != SmartListType.tasks) {
      return tasksForList(list).isNotEmpty;
    }
    return true;
  }

  TodoState copyWith({
    List<TodoList>? lists,
    List<ListGroup>? groups,
    List<TaskItem>? tasks,
    String? selectedListId,
    String? selectedTaskId,
    bool clearSelectedTaskId = false,
    TaskSortOption? sortOption,
    bool? showCompleted,
    ThemeMode? themeMode,
    bool? addNewTasksOnTop,
    bool? moveStarredTasksToTop,
    bool? confirmBeforeDeleting,
    bool? showDueTodayInMyDay,
    WeekStart? startOfWeek,
    bool? showSmartListImportant,
    bool? showSmartListPlanned,
    bool? showSmartListAll,
    bool? showSmartListCompleted,
    bool? autoHideEmptySmartLists,
  }) {
    return TodoState(
      lists: lists ?? this.lists,
      groups: groups ?? this.groups,
      tasks: tasks ?? this.tasks,
      selectedListId: selectedListId ?? this.selectedListId,
      selectedTaskId:
          clearSelectedTaskId ? null : (selectedTaskId ?? this.selectedTaskId),
      sortOption: sortOption ?? this.sortOption,
      showCompleted: showCompleted ?? this.showCompleted,
      themeMode: themeMode ?? this.themeMode,
      addNewTasksOnTop: addNewTasksOnTop ?? this.addNewTasksOnTop,
      moveStarredTasksToTop:
          moveStarredTasksToTop ?? this.moveStarredTasksToTop,
      confirmBeforeDeleting:
          confirmBeforeDeleting ?? this.confirmBeforeDeleting,
      showDueTodayInMyDay: showDueTodayInMyDay ?? this.showDueTodayInMyDay,
      startOfWeek: startOfWeek ?? this.startOfWeek,
      showSmartListImportant:
          showSmartListImportant ?? this.showSmartListImportant,
      showSmartListPlanned: showSmartListPlanned ?? this.showSmartListPlanned,
      showSmartListAll: showSmartListAll ?? this.showSmartListAll,
      showSmartListCompleted:
          showSmartListCompleted ?? this.showSmartListCompleted,
      autoHideEmptySmartLists:
          autoHideEmptySmartLists ?? this.autoHideEmptySmartLists,
    );
  }
}

class TodoNotifier extends Notifier<TodoState> {
  int _idCounter = 0;

  String nextId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  TodoLocalStorage get storage => ref.read(todoLocalStorageProvider);

  String _todayKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  TodoState build() {
    final snapshot = storage.load();
    final now = DateTime.now();
    final todayKey = _todayKey(now);
    var tasks = snapshot.tasks;

    if (snapshot.lastMyDayResetDate != null &&
        snapshot.lastMyDayResetDate != todayKey) {
      var changed = false;
      tasks = [
        for (final task in tasks)
          if (task.isInMyDay &&
              (task.myDayDate == null || !_isSameDay(task.myDayDate!, now)))
            () {
              changed = true;
              return task.copyWith(isInMyDay: false, clearMyDayDate: true);
            }()
          else
            task,
      ];
      if (changed) {
        storage.saveTasks(tasks);
      }
      storage.saveLastMyDayResetDate(todayKey);
    } else if (snapshot.lastMyDayResetDate == null) {
      storage.saveLastMyDayResetDate(todayKey);
    }

    if (snapshot.showDueTodayInMyDay) {
      var autoAdded = false;
      tasks = [
        for (final task in tasks)
          if (!task.isInMyDay &&
              task.dueDate != null &&
              _isSameDay(task.dueDate!, now))
            () {
              autoAdded = true;
              return task.copyWith(isInMyDay: true, myDayDate: now);
            }()
          else
            task,
      ];
      if (autoAdded) {
        storage.saveTasks(tasks);
      }
    }

    return TodoState(
      lists: snapshot.lists,
      groups: snapshot.groups,
      tasks: tasks,
      selectedListId: snapshot.selectedListId,
      sortOption: snapshot.sortOption,
      showCompleted: snapshot.showCompleted,
      themeMode: snapshot.themeMode,
      addNewTasksOnTop: snapshot.addNewTasksOnTop,
      moveStarredTasksToTop: snapshot.moveStarredTasksToTop,
      confirmBeforeDeleting: snapshot.confirmBeforeDeleting,
      showDueTodayInMyDay: snapshot.showDueTodayInMyDay,
      startOfWeek: snapshot.startOfWeek,
      showSmartListImportant: snapshot.showSmartListImportant,
      showSmartListPlanned: snapshot.showSmartListPlanned,
      showSmartListAll: snapshot.showSmartListAll,
      showSmartListCompleted: snapshot.showSmartListCompleted,
      autoHideEmptySmartLists: snapshot.autoHideEmptySmartLists,
    );
  }

  void commit(TodoState nextState) {
    state = nextState;
  }

  void selectList(String listId) {
    state = state.copyWith(
      selectedListId: listId,
      clearSelectedTaskId: true,
    );
    storage.saveSelectedListId(listId);
  }

  void selectTask(String? taskId) {
    state = state.copyWith(
      selectedTaskId: taskId,
      clearSelectedTaskId: taskId == null,
    );
  }
}

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);
