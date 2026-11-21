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

  bool _isDueToday(DateTime? date) {
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  List<TaskItem> tasksForList(TodoList list) {
    final Iterable<TaskItem> filtered = switch (list.smartType) {
      SmartListType.myDay => tasks.where(
          (t) => t.isInMyDay || (showDueTodayInMyDay && _isDueToday(t.dueDate)),
        ),
      SmartListType.important => tasks.where((t) => t.isImportant),
      SmartListType.planned =>
        tasks.where((t) => t.dueDate != null || t.reminderAt != null),
      SmartListType.all => tasks,
      SmartListType.completed => tasks.where((t) => t.isCompleted),
      SmartListType.tasks => tasks.where((t) => t.listId == 'tasks'),
      null => tasks.where((t) => t.listId == list.id),
    };

    final result = filtered.toList();
    switch (sortOption) {
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
          return a.isImportant ? -1 : 1;
        });
      case TaskSortOption.dueDate:
        result.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
      case TaskSortOption.alphabetical:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
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

  String _nextId(String prefix) {
    _idCounter += 1;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  TodoLocalStorage get _storage => ref.read(todoLocalStorageProvider);

  @override
  TodoState build() {
    final snapshot = _storage.load();
    return TodoState(
      lists: snapshot.lists,
      groups: snapshot.groups,
      tasks: snapshot.tasks,
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

  void selectList(String listId) {
    state = state.copyWith(
      selectedListId: listId,
      clearSelectedTaskId: true,
    );
    _storage.saveSelectedListId(listId);
  }

  void selectTask(String? taskId) {
    state = state.copyWith(
      selectedTaskId: taskId,
      clearSelectedTaskId: taskId == null,
    );
  }

  void setSortOption(TaskSortOption option) {
    state = state.copyWith(sortOption: option);
    _storage.saveSortOption(option);
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _storage.saveThemeMode(mode);
  }

  void toggleShowCompleted(bool value) {
    state = state.copyWith(showCompleted: value);
    _storage.saveShowCompleted(value);
  }

  void setAddNewTasksOnTop(bool value) {
    state = state.copyWith(addNewTasksOnTop: value);
    _storage.saveAddNewTasksOnTop(value);
  }

  void setMoveStarredTasksToTop(bool value) {
    state = state.copyWith(moveStarredTasksToTop: value);
    _storage.saveMoveStarredTasksToTop(value);
  }

  void setConfirmBeforeDeleting(bool value) {
    state = state.copyWith(confirmBeforeDeleting: value);
    _storage.saveConfirmBeforeDeleting(value);
  }

  void setShowDueTodayInMyDay(bool value) {
    state = state.copyWith(showDueTodayInMyDay: value);
    _storage.saveShowDueTodayInMyDay(value);
  }

  void setStartOfWeek(WeekStart value) {
    state = state.copyWith(startOfWeek: value);
    _storage.saveStartOfWeek(value);
  }

  void setShowSmartListImportant(bool value) {
    state = state.copyWith(showSmartListImportant: value);
    _storage.saveShowSmartListImportant(value);
  }

  void setShowSmartListPlanned(bool value) {
    state = state.copyWith(showSmartListPlanned: value);
    _storage.saveShowSmartListPlanned(value);
  }

  void setShowSmartListAll(bool value) {
    state = state.copyWith(showSmartListAll: value);
    _storage.saveShowSmartListAll(value);
  }

  void setShowSmartListCompleted(bool value) {
    state = state.copyWith(showSmartListCompleted: value);
    _storage.saveShowSmartListCompleted(value);
  }

  void setAutoHideEmptySmartLists(bool value) {
    state = state.copyWith(autoHideEmptySmartLists: value);
    _storage.saveAutoHideEmptySmartLists(value);
  }

  void toggleGroupExpanded(String groupId) {
    final updated = [
      for (final group in state.groups)
        if (group.id == groupId)
          group.copyWith(isExpanded: !group.isExpanded)
        else
          group,
    ];
    state = state.copyWith(groups: updated);
    _storage.saveGroups(updated);
  }

  void addList(String title, ListThemeColor themeColor, {String? groupId}) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final newList = TodoList(
      id: _nextId('list'),
      title: trimmed,
      groupId: groupId,
      themeColor: themeColor,
      icon: Icons.format_list_bulleted,
    );
    final updated = [...state.lists, newList];
    state = state.copyWith(
      lists: updated,
      selectedListId: newList.id,
      clearSelectedTaskId: true,
    );
    _storage.saveLists(updated);
    _storage.saveSelectedListId(newList.id);
  }

  void renameList(String listId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      for (final list in state.lists)
        if (list.id == listId && !list.isSmartList)
          list.copyWith(title: trimmed)
        else
          list,
    ];
    state = state.copyWith(lists: updated);
    _storage.saveLists(updated);
  }

  void changeListTheme(String listId, ListThemeColor themeColor) {
    final updated = [
      for (final list in state.lists)
        if (list.id == listId)
          list.copyWith(themeColor: themeColor)
        else
          list,
    ];
    state = state.copyWith(lists: updated);
    _storage.saveLists(updated);
  }

  void moveListToGroup(String listId, String? groupId) {
    final updated = [
      for (final list in state.lists)
        if (list.id == listId && !list.isSmartList)
          list.copyWith(groupId: groupId, clearGroupId: groupId == null)
        else
          list,
    ];
    state = state.copyWith(lists: updated);
    _storage.saveLists(updated);
  }

  void setGroupLists(String groupId, Set<String> memberListIds) {
    final updated = [
      for (final list in state.lists)
        if (!list.isSmartList && memberListIds.contains(list.id))
          list.copyWith(groupId: groupId)
        else if (list.groupId == groupId && !memberListIds.contains(list.id))
          list.copyWith(clearGroupId: true)
        else
          list,
    ];
    state = state.copyWith(lists: updated);
    _storage.saveLists(updated);
  }

  void duplicateList(String listId) {
    final source = state.lists.where((l) => l.id == listId).firstOrNull;
    if (source == null || source.isSmartList) return;

    final newListId = _nextId('list');
    final duplicatedList = source.copyWith(
      id: newListId,
      title: '${source.title} (Copy)',
    );
    final copiedTasks = [
      for (final task in state.tasks.where((t) => t.listId == listId))
        task.copyWith(
          id: _nextId('task'),
          listId: newListId,
          createdAt: DateTime.now(),
          steps: [
            for (final step in task.steps)
              step.copyWith(id: _nextId('step')),
          ],
        ),
    ];

    final updatedLists = [...state.lists, duplicatedList];
    final updatedTasks = [...copiedTasks, ...state.tasks];
    state = state.copyWith(
      lists: updatedLists,
      tasks: updatedTasks,
      selectedListId: newListId,
      clearSelectedTaskId: true,
    );
    _storage.saveLists(updatedLists);
    _storage.saveTasks(updatedTasks);
    _storage.saveSelectedListId(newListId);
  }

  void deleteList(String listId) {
    final target = state.lists.where((l) => l.id == listId).firstOrNull;
    if (target == null || target.isSmartList) return;

    final updatedLists = state.lists.where((l) => l.id != listId).toList();
    final updatedTasks = state.tasks.where((t) => t.listId != listId).toList();
    final nextSelected =
        state.selectedListId == listId ? 'my_day' : state.selectedListId;

    state = state.copyWith(
      lists: updatedLists,
      tasks: updatedTasks,
      selectedListId: nextSelected,
      clearSelectedTaskId: true,
    );
    _storage.saveLists(updatedLists);
    _storage.saveTasks(updatedTasks);
    _storage.saveSelectedListId(nextSelected);
  }

  void addGroup(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final newGroup = ListGroup(
      id: _nextId('group'),
      title: trimmed,
      isExpanded: true,
    );
    final updated = [...state.groups, newGroup];
    state = state.copyWith(groups: updated);
    _storage.saveGroups(updated);
  }

  void renameGroup(String groupId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      for (final group in state.groups)
        if (group.id == groupId) group.copyWith(title: trimmed) else group,
    ];
    state = state.copyWith(groups: updated);
    _storage.saveGroups(updated);
  }

  void deleteGroup(String groupId) {
    final updatedGroups =
        state.groups.where((g) => g.id != groupId).toList();
    final updatedLists = [
      for (final list in state.lists)
        if (list.groupId == groupId)
          list.copyWith(clearGroupId: true)
        else
          list,
    ];
    state = state.copyWith(groups: updatedGroups, lists: updatedLists);
    _storage.saveGroups(updatedGroups);
    _storage.saveLists(updatedLists);
  }

  void addTask({
    required String title,
    String? targetListId,
    bool isInMyDay = false,
    bool isImportant = false,
    DateTime? dueDate,
    DateTime? reminderAt,
    RecurrenceType recurrence = RecurrenceType.none,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final currentList = state.selectedList;
    final resolvedListId = targetListId ??
        (currentList.isSmartList ? 'tasks' : currentList.id);

    final newTask = TaskItem(
      id: _nextId('task'),
      listId: resolvedListId,
      title: trimmed,
      createdAt: DateTime.now(),
      isInMyDay: isInMyDay || currentList.smartType == SmartListType.myDay,
      isImportant:
          isImportant || currentList.smartType == SmartListType.important,
      dueDate: dueDate ??
          (currentList.smartType == SmartListType.planned
              ? DateTime.now()
              : null),
      reminderAt: reminderAt,
      recurrence: recurrence,
    );

    final updated = state.addNewTasksOnTop
        ? [newTask, ...state.tasks]
        : [...state.tasks, newTask];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void reorderActiveTasks(
    List<TaskItem> visibleActiveTasks,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= visibleActiveTasks.length) return;
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 ||
        newIndex >= visibleActiveTasks.length ||
        oldIndex == newIndex) {
      return;
    }

    final reorderedVisible = [...visibleActiveTasks];
    final moved = reorderedVisible.removeAt(oldIndex);
    reorderedVisible.insert(newIndex, moved);

    // Replace the slots occupied by visibleActiveTasks in state.tasks
    final visibleIds = {for (final t in visibleActiveTasks) t.id};
    var visibleCursor = 0;
    final updated = [
      for (final task in state.tasks)
        if (visibleIds.contains(task.id))
          reorderedVisible[visibleCursor++]
        else
          task,
    ];

    state = state.copyWith(
      tasks: updated,
      sortOption: TaskSortOption.defaultOrder,
    );
    _storage.saveTasks(updated);
    _storage.saveSortOption(TaskSortOption.defaultOrder);
  }

  DateTime _nextDueDate(DateTime base, RecurrenceType recurrence) {
    switch (recurrence) {
      case RecurrenceType.none:
        return base;
      case RecurrenceType.daily:
        return base.add(const Duration(days: 1));
      case RecurrenceType.weekdays:
        var next = base.add(const Duration(days: 1));
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = next.add(const Duration(days: 1));
        }
        return next;
      case RecurrenceType.weekly:
        return base.add(const Duration(days: 7));
      case RecurrenceType.monthly:
        return DateTime(base.year, base.month + 1, base.day);
      case RecurrenceType.yearly:
        return DateTime(base.year + 1, base.month, base.day);
    }
  }

  void toggleTaskCompleted(String taskId) {
    TaskItem? nextOccurrence;
    final updated = <TaskItem>[];

    for (final task in state.tasks) {
      if (task.id == taskId) {
        final nowCompleted = !task.isCompleted;
        updated.add(task.copyWith(isCompleted: nowCompleted));
        if (nowCompleted && task.recurrence != RecurrenceType.none) {
          final now = DateTime.now();
          final baseDate =
              task.dueDate ?? DateTime(now.year, now.month, now.day);
          nextOccurrence = TaskItem(
            id: _nextId('task'),
            listId: task.listId,
            title: task.title,
            createdAt: DateTime.now(),
            isImportant: task.isImportant,
            isInMyDay: false,
            dueDate: _nextDueDate(baseDate, task.recurrence),
            recurrence: task.recurrence,
            note: task.note,
            steps: [
              for (final step in task.steps)
                TaskStep(id: _nextId('step'), title: step.title),
            ],
          );
        }
      } else {
        updated.add(task);
      }
    }

    if (nextOccurrence != null) {
      if (state.addNewTasksOnTop) {
        updated.insert(0, nextOccurrence);
      } else {
        updated.add(nextOccurrence);
      }
    }

    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void toggleTaskImportant(String taskId) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(isImportant: !task.isImportant)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void toggleTaskMyDay(String taskId) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(isInMyDay: !task.isInMyDay)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void updateTaskTitle(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId) task.copyWith(title: trimmed) else task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void updateTaskNote(String taskId, String note) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId) task.copyWith(note: note) else task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void moveTaskToList(String taskId, String targetListId) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId) task.copyWith(listId: targetListId) else task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void setTaskDueDate(String taskId, DateTime? dueDate) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(dueDate: dueDate, clearDueDate: dueDate == null)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void setTaskReminder(String taskId, DateTime? reminderAt) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(
            reminderAt: reminderAt,
            clearReminderAt: reminderAt == null,
          )
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void setTaskRecurrence(String taskId, RecurrenceType recurrence) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(recurrence: recurrence)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void deleteTask(String taskId) {
    final updated = state.tasks.where((t) => t.id != taskId).toList();
    state = state.copyWith(
      tasks: updated,
      clearSelectedTaskId: state.selectedTaskId == taskId,
    );
    _storage.saveTasks(updated);
  }

  void batchSetMyDay(Set<String> taskIds, bool value) {
    final updated = [
      for (final task in state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(isInMyDay: value)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void batchSetImportant(Set<String> taskIds, bool value) {
    final updated = [
      for (final task in state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(isImportant: value)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void batchSetDueDate(Set<String> taskIds, DateTime? dueDate) {
    final updated = [
      for (final task in state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(dueDate: dueDate, clearDueDate: dueDate == null)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void batchMoveToList(Set<String> taskIds, String targetListId) {
    final updated = [
      for (final task in state.tasks)
        if (taskIds.contains(task.id))
          task.copyWith(listId: targetListId)
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void batchDeleteTasks(Set<String> taskIds) {
    final updated =
        state.tasks.where((t) => !taskIds.contains(t.id)).toList();
    state = state.copyWith(
      tasks: updated,
      clearSelectedTaskId:
          state.selectedTaskId != null && taskIds.contains(state.selectedTaskId),
    );
    _storage.saveTasks(updated);
  }

  void addStep(String taskId, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final newStep = TaskStep(id: _nextId('step'), title: trimmed);
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(steps: [...task.steps, newStep])
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void toggleStepCompleted(String taskId, String stepId) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(
            steps: [
              for (final step in task.steps)
                if (step.id == stepId)
                  step.copyWith(isCompleted: !step.isCompleted)
                else
                  step,
            ],
          )
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }

  void deleteStep(String taskId, String stepId) {
    final updated = [
      for (final task in state.tasks)
        if (task.id == taskId)
          task.copyWith(
            steps: task.steps.where((s) => s.id != stepId).toList(),
          )
        else
          task,
    ];
    state = state.copyWith(tasks: updated);
    _storage.saveTasks(updated);
  }
}

final todoProvider = NotifierProvider<TodoNotifier, TodoState>(
  TodoNotifier.new,
);
