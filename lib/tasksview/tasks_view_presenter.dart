import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_date_time.dart';
import '../data/todo_provider.dart';
import '../detailview/recurrence/task_pickers.dart';
import '../homeview/home_view_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../sync/microsoft/substrate_time_codecs.dart';

/// Presenter for `tasksview/TasksViewFragment`, matching `tasksview/TasksViewPresenter`.
class TasksViewPresenter {
  TasksViewPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void selectTask(String? taskId) {
    _store.selectTask(taskId);
  }

  void setPlannedDueDateFilter(PlannedDueDateFilter filter) {
    if (_state.plannedDueDateFilter == filter) return;
    _store.commit(_state.copyWith(plannedDueDateFilter: filter));
    _store.settings.savePlannedDueDateFilter(filter);
  }

  void setPlannedGroupOption(PlannedGroupOption option) {
    if (_state.plannedGroupOption == option) return;
    _store.commit(_state.copyWith(plannedGroupOption: option));
    _store.settings.savePlannedGroupOption(option);
  }

  void _updateListById(
    String listId,
    TodoList Function(TodoList list) transform,
  ) {
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId) transform(list) else list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.repository.saveLists(_state.lists);
  }

  void _commitTasks(List<TaskItem> updated) {
    _store.commit(_state.copyWith(tasks: updated));
    _store.repository.saveTasks(_state.tasks);
  }

  void setListSortOption(
    String listId,
    TaskSortOption option, {
    bool? ascending,
  }) {
    _updateListById(
      listId,
      (list) => list.copyWith(
        sortOption: option,
        sortAscending:
            ascending ??
            (list.sortOption == option && option != TaskSortOption.defaultOrder
                ? !list.sortAscending
                : option.defaultAscending),
      ),
    );
  }

  void toggleListSortDirection(String listId) {
    _updateListById(
      listId,
      (list) => list.sortOption == TaskSortOption.defaultOrder
          ? list
          : list.copyWith(sortAscending: !list.sortAscending),
    );
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
    _updateListById(
      listId,
      (list) => list.isSmartList
          ? list
          : list.copyWith(
              title: trimmed,
              emoji: clearEmoji ? null : (emoji ?? list.emoji),
              themeColor: themeColor ?? list.themeColor,
              themePhoto: clearThemePhoto
                  ? null
                  : (themePhoto ?? list.themePhoto),
            ),
    );
  }

  void changeListTheme(
    String listId,
    ListThemeColor themeColor, {
    ListThemePhoto? themePhoto,
  }) {
    _updateListById(
      listId,
      (list) => list.copyWith(themeColor: themeColor, themePhoto: themePhoto),
    );
  }

  String _deduplicateListTitle(String title) {
    final existing = {
      for (final l in _state.lists)
        if (!l.isSmartList) l.title,
    };
    var candidate = title;
    var index = 1;
    while (existing.contains(candidate)) {
      candidate = '$title ($index)';
      index += 1;
    }
    return candidate;
  }

  void duplicateList(String listId, {bool keepCompleted = true}) {
    final source = _state.lists.where((l) => l.id == listId).firstOrNull;
    if (source == null || source.isSmartList) return;

    final now = DateTime.now();
    final newListId = _store.nextId('list');
    final siblingOrders = source.groupId != null
        ? _state.lists
              .where((l) => !l.isSmartList && l.groupId == source.groupId)
              .map((l) => l.orderDateTime)
        : [
            ..._state.lists
                .where((l) => !l.isSmartList && l.groupId == null)
                .map((l) => l.orderDateTime),
            ..._state.groups.map((g) => g.orderDateTime),
          ];
    final duplicatedList = TodoList(
      id: newListId,
      title: _deduplicateListTitle(source.title),
      groupId: source.groupId,
      emoji: source.emoji,
      sortAscending: false,
      orderDateTime: computeNewOrderDateTime(
        existingOrders: siblingOrders,
        addToTop: false,
        fallbackNow: now,
      ),
    );
    // Choosing not to keep completed tasks drops them from the copy entirely;
    // remaining tasks and their steps keep their completion state.
    final tasksToCopy = _state.tasks.where(
      (t) => t.listId == listId && (keepCompleted || !t.isCompleted),
    );
    var copyIndex = 0;
    final baseTaskOrder = now.toUtc();
    final copiedTasks = [
      for (final task in tasksToCopy)
        task.copyWith(
          id: _store.nextId('task'),
          listId: newListId,
          createdAt: now.toUtc(),
          remoteId: null,
          remoteParentFolderId: null,
          changeKey: null,
          orderDateTime: baseTaskOrder.subtract(Duration(seconds: copyIndex++)),
          committedOrder: null,
          steps: [
            for (final step in task.steps)
              step.copyWith(id: _store.nextId('step'), remoteId: null),
          ],
        ),
    ];

    final updatedLists = sortListsPreservingSmartLists([
      ..._state.lists,
      duplicatedList,
    ]);
    final updatedTasks = [...copiedTasks, ..._state.tasks];
    _store.commit(
      _state.copyWith(
        lists: updatedLists,
        tasks: updatedTasks,
        selectedListId: newListId,
        selectedTaskId: null,
      ),
    );
    _store.repository.saveLists(_state.lists);
    _store.repository.saveTasks(_state.tasks);
    _store.settings.saveSelectedListId(newListId);
    if (_store.settings.loadLastEnteredListId() != null) {
      _store.setLastEnteredListId(newListId);
    }
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
        selectedTaskId: null,
      ),
    );
    _store.repository.saveLists(_state.lists);
    _store.repository.saveTasks(_state.tasks);
    _store.settings.saveSelectedListId(nextSelected);
  }

  void addTask({
    required String title,
    String? targetListId,
    bool isInMyDay = false,
    bool isImportant = false,
    DateTime? dueDate,
    DateTime? reminderAt,
    RecurrenceType recurrence = RecurrenceType.none,
    Map<String, dynamic>? rawRecurrence,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final currentList = _state.selectedList;
    final resolvedListId =
        targetListId ?? (currentList.isSmartList ? 'tasks' : currentList.id);

    final now = DateTime.now();
    final effectiveDueDate =
        dueDate ??
        (currentList.smartType == SmartListType.planned ? now : null);
    final committedToMyDay =
        isInMyDay || currentList.smartType == SmartListType.myDay;
    final orderDateTime = computeNewOrderDateTime(
      existingOrders: _state.tasks
          .where((t) => t.listId == resolvedListId)
          .map((t) => t.orderDateTime),
      addToTop: _state.addNewTasksOnTop,
      fallbackNow: now,
    );
    final committedOrder = committedToMyDay
        ? computeNewOrderDateTime(
            existingOrders: _state.tasks
                .where((t) => t.isInMyDay)
                .map((t) => t.committedOrder),
            addToTop: _state.addNewTasksOnTop,
            fallbackNow: now,
          )
        : null;
    final newTask = TodoNotifier.syncMyDayFlag(
      TaskItem(
        id: _store.nextId('task'),
        listId: resolvedListId,
        title: trimmed,
        createdAt: now.toUtc(),
        isInMyDay: committedToMyDay,
        myDayDate: committedToMyDay ? now : null,
        orderDateTime: orderDateTime,
        committedOrder: committedOrder,
        isImportant:
            isImportant || currentList.smartType == SmartListType.important,
        dueDate: effectiveDueDate,
        reminderAt: reminderAt?.toUtc(),
        recurrence: recurrence,
        rawRecurrence: normalizeRawRecurrence(rawRecurrence),
      ),
      now: now,
      showDueTodayInMyDay: _state.showDueTodayInMyDay,
    );

    final updated = _state.addNewTasksOnTop
        ? [newTask, ..._state.tasks]
        : [..._state.tasks, newTask];
    _commitTasks(updated);
  }

  void restoreTask(TaskItem task, {int? index}) {
    if (_state.tasks.any((t) => t.id == task.id)) return;
    final updated = [..._state.tasks];
    if (index != null && index >= 0 && index <= updated.length) {
      updated.insert(index, task);
    } else {
      updated.add(task);
    }
    _commitTasks(updated);
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

    final isMyDayView = _state.selectedList.smartType == SmartListType.myDay;
    final currentOrders = [
      for (final t in reorderedVisible)
        isMyDayView ? t.committedOrder : t.orderDateTime,
    ];
    final newPositions = computeReorderedOrderDateTimes(
      currentOrders,
      newIndex,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final entry in newPositions.entries) {
      final current = reorderedVisible[entry.key];
      if (isMyDayView) {
        final needsMyDayDate =
            current.myDayDate == null ||
            !TodoNotifier.isSameDay(current.myDayDate!, now);
        reorderedVisible[entry.key] = current.copyWith(
          committedOrder: entry.value,
          myDayDate: needsMyDayDate ? today : current.myDayDate,
        );
      } else {
        reorderedVisible[entry.key] = current.copyWith(
          orderDateTime: entry.value,
        );
      }
    }

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
    _store.commit(_state.copyWith(lists: updatedLists, tasks: updated));
    _store.repository.saveLists(_state.lists);
    _store.repository.saveTasks(_state.tasks);
  }

  TaskItem _buildNextRecurringTask(TaskItem task, DateTime now) {
    final baseDate = task.dueDate ?? DateTime(now.year, now.month, now.day);
    final nextDue = computeNextDueDate(
      baseDate,
      task.recurrence,
      rawRecurrence: task.rawRecurrence,
    );
    DateTime? nextReminder;
    if (task.reminderAt case final reminderAt?) {
      final localReminder = reminderAt.toLocal();
      nextReminder = DateTime(
        nextDue.year,
        nextDue.month,
        nextDue.day,
        localReminder.hour,
        localReminder.minute,
      ).toUtc();
    }
    return TodoNotifier.syncMyDayFlag(
      TaskItem(
        id: _store.nextId('task'),
        listId: task.listId,
        title: task.title,
        createdAt: now.toUtc(),
        orderDateTime: computeNewOrderDateTime(
          existingOrders: _state.tasks
              .where((t) => t.listId == task.listId)
              .map((t) => t.orderDateTime),
          addToTop: _state.addNewTasksOnTop,
          fallbackNow: now,
        ),
        isImportant: task.isImportant,
        dueDate: nextDue,
        reminderAt: nextReminder,
        recurrence: task.recurrence,
        rawRecurrence: normalizeRawRecurrence(task.rawRecurrence),
        note: task.note,
        steps: [
          for (final step in task.steps)
            TaskStep(
              id: _store.nextId('step'),
              title: step.title,
              orderDateTime: step.orderDateTime,
            ),
        ],
      ),
      now: now,
      showDueTodayInMyDay: _state.showDueTodayInMyDay,
    );
  }

  void toggleTaskCompleted(String taskId) {
    final target = _state.tasks.where((t) => t.id == taskId).firstOrNull;
    if (target == null) return;
    setTaskCompleted(taskId, completed: !target.isCompleted);
  }

  void setTaskCompleted(String taskId, {required bool completed}) {
    TaskItem? nextOccurrence;
    final updated = <TaskItem>[];
    final now = DateTime.now();
    var changed = false;

    for (final task in _state.tasks) {
      if (task.id != taskId) {
        updated.add(task);
        continue;
      }
      if (task.isCompleted == completed) {
        updated.add(task);
        continue;
      }
      changed = true;
      updated.add(
        task.copyWith(
          isCompleted: completed,
          completedAt: completed ? now.toUtc() : null,
        ),
      );
      if (completed &&
          task.hasRecurrence &&
          _store.shouldSpawnRecurringLocally(task)) {
        nextOccurrence = _buildNextRecurringTask(task, now);
      }
    }

    if (!changed) return;

    if (nextOccurrence != null) {
      if (_state.addNewTasksOnTop) {
        updated.insert(0, nextOccurrence);
      } else {
        updated.add(nextOccurrence);
      }
    }

    _commitTasks(updated);
  }

  void toggleTaskImportant(String taskId) {
    TaskItem? movedToTop;
    final updated = <TaskItem>[];
    for (final task in _state.tasks) {
      if (task.id != taskId) {
        updated.add(task);
        continue;
      }
      final nextImportant = !task.isImportant;
      var nextTask = task.copyWith(isImportant: nextImportant);
      if (nextImportant && _state.moveStarredTasksToTop) {
        final topOrder = computeNewOrderDateTime(
          existingOrders: _state.tasks
              .where((t) => t.listId == task.listId && t.id != task.id)
              .map((t) => t.orderDateTime),
          addToTop: true,
        );
        final topCommitted = task.isInMyDay
            ? computeNewOrderDateTime(
                existingOrders: _state.tasks
                    .where((t) => t.isInMyDay && t.id != task.id)
                    .map((t) => t.committedOrder),
                addToTop: true,
              )
            : task.committedOrder;
        nextTask = nextTask.copyWith(
          orderDateTime: topOrder,
          committedOrder: topCommitted,
        );
        movedToTop = nextTask;
      } else {
        updated.add(nextTask);
      }
    }
    if (movedToTop != null) {
      updated.insert(0, movedToTop);
    }
    _commitTasks(updated);
  }
}

final tasksViewPresenterProvider = Provider<TasksViewPresenter>((ref) {
  return TasksViewPresenter(ref);
});
