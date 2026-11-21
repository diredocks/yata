import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';

/// Presenter for `tasksview/TasksViewFragment`, matching `tasksview/TasksViewPresenter`.
class TasksViewPresenter {
  TasksViewPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void selectTask(String? taskId) {
    _store.selectTask(taskId);
  }

  void setSortOption(TaskSortOption option) {
    setListSortOption(_state.selectedListId, option);
  }

  void setListSortOption(
    String listId,
    TaskSortOption option, {
    bool? ascending,
  }) {
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId)
          list.copyWith(
            sortOption: option,
            sortAscending: ascending ??
                (list.sortOption == option &&
                        option != TaskSortOption.defaultOrder
                    ? !list.sortAscending
                    : option.defaultAscending),
          )
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated, sortOption: option));
    _store.storage.saveLists(updated);
    _store.storage.saveSortOption(option);
  }

  void toggleListSortDirection(String listId) {
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId && list.sortOption != TaskSortOption.defaultOrder)
          list.copyWith(sortAscending: !list.sortAscending)
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.storage.saveLists(updated);
  }

  void toggleListShowCompleted(String listId) {
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId &&
            list.smartType != SmartListType.all &&
            list.smartType != SmartListType.completed)
          list.copyWith(showCompleted: !list.showCompleted)
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.storage.saveLists(updated);
  }

  void updateList(
    String listId, {
    required String title,
    String? emoji,
    bool clearEmoji = false,
    ListThemeColor? themeColor,
    ListThemePhoto? themePhoto,
    bool clearThemePhoto = false,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId && !list.isSmartList)
          list.copyWith(
            title: trimmed,
            emoji: emoji,
            clearEmoji: clearEmoji,
            themeColor: themeColor,
            themePhoto: themePhoto,
            clearThemePhoto: clearThemePhoto,
          )
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.storage.saveLists(updated);
  }

  void renameList(String listId, String newTitle) {
    updateList(listId, title: newTitle);
  }

  void changeListTheme(
    String listId,
    ListThemeColor themeColor, {
    ListThemePhoto? themePhoto,
  }) {
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId)
          list.copyWith(
            themeColor: themeColor,
            themePhoto: themePhoto,
            clearThemePhoto: themePhoto == null,
          )
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.storage.saveLists(updated);
  }

  void duplicateList(String listId, {bool keepCompleted = true}) {
    final source = _state.lists.where((l) => l.id == listId).firstOrNull;
    if (source == null || source.isSmartList) return;

    final newListId = _store.nextId('list');
    final duplicatedList = source.copyWith(
      id: newListId,
      title: source.title,
    );
    final copiedTasks = [
      for (final task in _state.tasks.where(
        (t) =>
            t.listId == listId && (source.showCompleted || !t.isCompleted),
      ))
        task.copyWith(
          id: _store.nextId('task'),
          listId: newListId,
          createdAt: DateTime.now(),
          isCompleted: keepCompleted ? task.isCompleted : false,
          clearCompletedAt: !keepCompleted,
          steps: [
            for (final step in task.steps)
              step.copyWith(
                id: _store.nextId('step'),
                isCompleted: keepCompleted ? step.isCompleted : false,
              ),
          ],
        ),
    ];

    final updatedLists = [..._state.lists, duplicatedList];
    final updatedTasks = [...copiedTasks, ..._state.tasks];
    _store.commit(
      _state.copyWith(
        lists: updatedLists,
        tasks: updatedTasks,
        selectedListId: newListId,
        clearSelectedTaskId: true,
      ),
    );
    _store.storage.saveLists(updatedLists);
    _store.storage.saveTasks(updatedTasks);
    _store.storage.saveSelectedListId(newListId);
  }

  void deleteList(String listId) {
    final targetIndex = _state.lists.indexWhere((l) => l.id == listId);
    if (targetIndex < 0) return;
    final target = _state.lists[targetIndex];
    if (target.isSmartList) return;

    final updatedLists = _state.lists.where((l) => l.id != listId).toList();
    final updatedTasks = _state.tasks.where((t) => t.listId != listId).toList();
    var nextSelected = _state.selectedListId;
    if (_state.selectedListId == listId) {
      nextSelected = targetIndex > 0
          ? _state.lists[targetIndex - 1].id
          : 'my_day';
    }

    _store.commit(
      _state.copyWith(
        lists: updatedLists,
        tasks: updatedTasks,
        selectedListId: nextSelected,
        clearSelectedTaskId: true,
      ),
    );
    _store.storage.saveLists(updatedLists);
    _store.storage.saveTasks(updatedTasks);
    _store.storage.saveSelectedListId(nextSelected);
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

    final currentList = _state.selectedList;
    final resolvedListId = targetListId ??
        (currentList.isSmartList ? 'tasks' : currentList.id);

    final now = DateTime.now();
    final effectiveDueDate = dueDate ??
        (currentList.smartType == SmartListType.planned ? now : null);
    final committedToMyDay =
        isInMyDay || currentList.smartType == SmartListType.myDay;
    final newTask = TodoNotifier.syncMyDayFlag(
      TaskItem(
        id: _store.nextId('task'),
        listId: resolvedListId,
        title: trimmed,
        createdAt: now,
        isInMyDay: committedToMyDay,
        myDayDate: committedToMyDay ? now : null,
        isImportant:
            isImportant || currentList.smartType == SmartListType.important,
        dueDate: effectiveDueDate,
        reminderAt: reminderAt,
        recurrence: recurrence,
      ),
      now: now,
      showDueTodayInMyDay: _state.showDueTodayInMyDay,
    );

    final updated = _state.addNewTasksOnTop
        ? [newTask, ..._state.tasks]
        : [..._state.tasks, newTask];
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void reorderActiveTasks(
    List<TaskItem> visibleActiveTasks,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= visibleActiveTasks.length) return;
    if (newIndex < 0 ||
        newIndex >= visibleActiveTasks.length ||
        oldIndex == newIndex) {
      return;
    }

    final reorderedVisible = [...visibleActiveTasks];
    final moved = reorderedVisible.removeAt(oldIndex);
    reorderedVisible.insert(newIndex, moved);

    final visibleIds = {for (final t in visibleActiveTasks) t.id};
    var visibleCursor = 0;
    final updated = [
      for (final task in _state.tasks)
        if (visibleIds.contains(task.id))
          reorderedVisible[visibleCursor++]
        else
          task,
    ];

    final updatedLists = [
      for (final list in _state.lists)
        if (list.id == _state.selectedListId)
          list.copyWith(sortOption: TaskSortOption.defaultOrder)
        else
          list,
    ];
    _store.commit(
      _state.copyWith(
        lists: updatedLists,
        tasks: updated,
        sortOption: TaskSortOption.defaultOrder,
      ),
    );
    _store.storage.saveLists(updatedLists);
    _store.storage.saveTasks(updated);
    _store.storage.saveSortOption(TaskSortOption.defaultOrder);
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
        final totalMonths = base.year * 12 + (base.month - 1) + 1;
        final targetYear = totalMonths ~/ 12;
        final targetMonth = (totalMonths % 12) + 1;
        final lastDay = DateTime(targetYear, targetMonth + 1, 0).day;
        return DateTime(
          targetYear,
          targetMonth,
          base.day > lastDay ? lastDay : base.day,
        );
      case RecurrenceType.yearly:
        final targetYear = base.year + 1;
        final lastDay = DateTime(targetYear, base.month + 1, 0).day;
        return DateTime(
          targetYear,
          base.month,
          base.day > lastDay ? lastDay : base.day,
        );
    }
  }

  void toggleTaskCompleted(String taskId) {
    TaskItem? nextOccurrence;
    final updated = <TaskItem>[];

    for (final task in _state.tasks) {
      if (task.id == taskId) {
        final nowCompleted = !task.isCompleted;
        final now = DateTime.now();
        updated.add(
          task.copyWith(
            isCompleted: nowCompleted,
            completedAt: nowCompleted ? now : null,
            clearCompletedAt: !nowCompleted,
          ),
        );
        if (nowCompleted && task.recurrence != RecurrenceType.none) {
          final baseDate =
              task.dueDate ?? DateTime(now.year, now.month, now.day);
          final nextDue = _nextDueDate(baseDate, task.recurrence);
          DateTime? nextReminder;
          if (task.reminderAt != null) {
            nextReminder = DateTime(
              nextDue.year,
              nextDue.month,
              nextDue.day,
              task.reminderAt!.hour,
              task.reminderAt!.minute,
            );
          }
          nextOccurrence = TodoNotifier.syncMyDayFlag(
            TaskItem(
              id: _store.nextId('task'),
              listId: task.listId,
              title: task.title,
              createdAt: now,
              isImportant: task.isImportant,
              dueDate: nextDue,
              reminderAt: nextReminder,
              recurrence: task.recurrence,
              note: task.note,
              steps: [
                for (final step in task.steps)
                  TaskStep(id: _store.nextId('step'), title: step.title),
              ],
            ),
            now: now,
            showDueTodayInMyDay: _state.showDueTodayInMyDay,
          );
        }
      } else {
        updated.add(task);
      }
    }

    if (nextOccurrence != null) {
      if (_state.addNewTasksOnTop) {
        updated.insert(0, nextOccurrence);
      } else {
        updated.add(nextOccurrence);
      }
    }

    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }

  void toggleTaskImportant(String taskId) {
    TaskItem? movedToTop;
    final updated = <TaskItem>[];
    for (final task in _state.tasks) {
      if (task.id == taskId) {
        final nextImportant = !task.isImportant;
        final nextTask = task.copyWith(isImportant: nextImportant);
        if (nextImportant && _state.moveStarredTasksToTop) {
          movedToTop = nextTask;
        } else {
          updated.add(nextTask);
        }
      } else {
        updated.add(task);
      }
    }
    if (movedToTop != null) {
      updated.insert(0, movedToTop);
    }
    _store.commit(_state.copyWith(tasks: updated));
    _store.storage.saveTasks(updated);
  }
}

final tasksViewPresenterProvider = Provider<TasksViewPresenter>((ref) {
  return TasksViewPresenter(ref);
});
