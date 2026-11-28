import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_date_time.dart';
import '../data/todo_provider.dart';
import '../data/task_mutations.dart';
import '../data/list_ordering.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

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
    _store.mutateSetting(
      _state.copyWith(plannedDueDateFilter: filter),
      persistLocal: () => _store.settings.savePlannedDueDateFilter(filter),
    );
  }

  void setPlannedGroupOption(PlannedGroupOption option) {
    if (_state.plannedGroupOption == option) return;
    _store.mutateSetting(
      _state.copyWith(plannedGroupOption: option),
      persistLocal: () => _store.settings.savePlannedGroupOption(option),
    );
  }

  void setListSortOption(
    String listId,
    TaskSortOption option, {
    bool? ascending,
  }) {
    _store.mutateList(
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
    _store.mutateList(
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
    String? customBackgroundPath,
    bool clearCustomBackgroundPath = false,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _store.mutateList(
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
              customBackgroundPath: clearCustomBackgroundPath
                  ? null
                  : (customBackgroundPath ?? list.customBackgroundPath),
            ),
    );
  }

  void changeListTheme(
    String listId,
    ListThemeColor themeColor, {
    ListThemePhoto? themePhoto,
    String? customBackgroundPath,
  }) {
    _store.mutateList(
      listId,
      (list) => list.copyWith(
        themeColor: themeColor,
        themePhoto: themePhoto,
        customBackgroundPath: customBackgroundPath,
      ),
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
    final source = _state.lists.firstWhereOrNull((l) => l.id == listId);
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
    _store.mutateEntities(
      lists: updatedLists,
      tasks: updatedTasks,
      touchedListIds: {newListId},
      touchedTaskIds: {for (final t in copiedTasks) t.id},
      selectedListId: newListId,
      clearSelectedTaskId: true,
    );
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

    _store.mutateEntities(
      lists: updatedLists,
      tasks: updatedTasks,
      deletedListIds: {listId},
      selectedListId: nextSelected,
      clearSelectedTaskId: true,
    );
    _store.settings.saveSelectedListId(nextSelected);
  }

  TaskMutations get _mutations => _ref.read(taskMutationsProvider);

  void addTask({
    required String title,
    String? targetListId,
    bool isInMyDay = false,
    bool isImportant = false,
    DateTime? dueDate,
    DateTime? reminderAt,
    RecurrenceType recurrence = RecurrenceType.none,
    Map<String, dynamic>? rawRecurrence,
  }) => _mutations.addTask(
    title: title,
    targetListId: targetListId,
    isInMyDay: isInMyDay,
    isImportant: isImportant,
    dueDate: dueDate,
    reminderAt: reminderAt,
    recurrence: recurrence,
    rawRecurrence: rawRecurrence,
  );
  void restoreTask(TaskItem task, {int? index}) {
    _store.restoreTask(task, insertAt: index);
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
    final touchedTaskIds = <String>{};
    for (final entry in newPositions.entries) {
      final current = reorderedVisible[entry.key];
      touchedTaskIds.add(current.id);
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
    _store.mutateEntities(
      lists: updatedLists,
      tasks: updated,
      touchedListIds: {_state.selectedListId},
      touchedTaskIds: touchedTaskIds,
    );
  }

  void toggleTaskCompleted(String taskId) =>
      _mutations.toggleTaskCompleted(taskId);

  void setTaskCompleted(String taskId, {required bool completed}) =>
      _mutations.setTaskCompleted(taskId, completed: completed);

  void toggleTaskImportant(String taskId) =>
      _mutations.toggleTaskImportant(taskId);
}

final tasksViewPresenterProvider = Provider<TasksViewPresenter>((ref) {
  return TasksViewPresenter(ref);
});
