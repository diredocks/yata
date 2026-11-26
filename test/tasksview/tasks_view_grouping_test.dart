import 'package:flutter_test/flutter_test.dart';
import 'package:yata/data/todo_sorting.dart';
import 'package:yata/data/todo_state.dart';
import 'package:yata/l10n/app_localizations_en.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_dialogs.dart';
import 'package:yata/tasksview/tasks_view_grouping.dart';

TaskItem _task({
  required String id,
  String listId = 'tasks',
  String title = 'Task',
  bool isCompleted = false,
  DateTime? createdAt,
  DateTime? completedAt,
  DateTime? updatedAt,
  DateTime? dueDate,
  DateTime? reminderAt,
}) {
  return TaskItem(
    id: id,
    listId: listId,
    title: title,
    createdAt: createdAt ?? DateTime.utc(2026, 11, 20),
    isCompleted: isCompleted,
    completedAt: completedAt,
    updatedAt: updatedAt,
    dueDate: dueDate,
    reminderAt: reminderAt,
  );
}

void main() {
  final l10n = AppLocalizationsEn();

  test('splitTasksForDisplay handles Completed, Important, All, and custom lists', () {
    final older = _task(
      id: 't1',
      isCompleted: true,
      completedAt: DateTime(2026, 11, 19),
    );
    final newer = _task(
      id: 't2',
      isCompleted: true,
      completedAt: DateTime(2026, 11, 21),
    );
    final active = _task(id: 't3', isCompleted: false);

    // Completed smart list shows all tasks in active bucket without completed bucket
    final completedList = TodoList(
      id: 'completed',
      title: 'Completed',
      smartType: SmartListType.completed,
    );
    final completedSplit = splitTasksForDisplay([older, newer], completedList);
    expect(completedSplit.active.map((t) => t.id), ['t1', 't2']);
    expect(completedSplit.completed, isEmpty);

    // Important smart list respects showCompleted within active list
    final importantHidden = TodoList(
      id: 'important',
      title: 'Important',
      smartType: SmartListType.important,
      showCompleted: false,
    );
    final importantSplit = splitTasksForDisplay([
      older,
      active,
    ], importantHidden);
    expect(importantSplit.active.map((t) => t.id), ['t3']);
    expect(importantSplit.completed, isEmpty);

    // Custom list splits active and completed, sorting completed newest-first
    final customList = TodoList(
      id: 'custom',
      title: 'Work',
      showCompleted: true,
    );
    final customSplit = splitTasksForDisplay([
      older,
      active,
      newer,
    ], customList);
    expect(customSplit.active.map((t) => t.id), ['t3']);
    expect(customSplit.completed.map((t) => t.id), ['t2', 't1']);

    // Custom list & Tasks with showCompleted=false still expose completed tasks
    // for the collapsible Completed pill (showCompleted tracks expansion state)
    final customCollapsed = customList.copyWith(showCompleted: false);
    final collapsedSplit = splitTasksForDisplay([
      older,
      active,
      newer,
    ], customCollapsed);
    expect(collapsedSplit.active.map((t) => t.id), ['t3']);
    expect(collapsedSplit.completed.map((t) => t.id), ['t2', 't1']);

    const tasksCollapsed = TodoList(
      id: 'tasks',
      title: 'Tasks',
      smartType: SmartListType.tasks,
      showCompleted: false,
    );
    final tasksCollapsedSplit = splitTasksForDisplay([
      older,
      active,
      newer,
    ], tasksCollapsed);
    expect(tasksCollapsedSplit.active.map((t) => t.id), ['t3']);
    expect(tasksCollapsedSplit.completed.map((t) => t.id), ['t2', 't1']);

    // All smart list excludes completed tasks completely
    const allList = TodoList(
      id: 'all',
      title: 'All',
      smartType: SmartListType.all,
    );
    final allSplit = splitTasksForDisplay([older, active, newer], allList);
    expect(allSplit.active.map((t) => t.id), ['t3']);
    expect(allSplit.completed, isEmpty);

    // Planned smart list excludes completed tasks completely
    const plannedList = TodoList(
      id: 'planned',
      title: 'Planned',
      smartType: SmartListType.planned,
    );
    final plannedSplit = splitTasksForDisplay([
      older,
      active,
      newer,
    ], plannedList);
    expect(plannedSplit.active.map((t) => t.id), ['t3']);
    expect(plannedSplit.completed, isEmpty);
  });

  test('groupPlannedTasks classifies tasks into chronological buckets', () {
    // Tuesday 2026-11-24 (with WeekStart.monday, next week starts Mon 2026-11-30)
    final now = DateTime(2026, 11, 24, 10, 0);
    final earlier = _task(id: 'earlier', dueDate: DateTime(2026, 11, 23));
    final today = _task(id: 'today', dueDate: DateTime(2026, 11, 24));
    final tomorrow = _task(id: 'tomorrow', dueDate: DateTime(2026, 11, 25));
    final thisWeek = _task(id: 'week', dueDate: DateTime(2026, 11, 27));
    final later = _task(id: 'later', dueDate: DateTime(2026, 12, 5));
    final unscheduled = _task(id: 'none');

    final groups = groupPlannedTasks(
      [later, unscheduled, earlier, thisWeek, tomorrow, today],
      WeekStart.monday,
      now: now,
    );

    expect(groups.map((g) => g.bucket).toList(), [
      PlannedBucket.earlier,
      PlannedBucket.today,
      PlannedBucket.tomorrow,
      PlannedBucket.thisWeek,
      PlannedBucket.later,
    ]);
    expect(groups[0].tasks.map((t) => t.id), ['earlier']);
    expect(groups[1].tasks.map((t) => t.id), ['today']);
    expect(groups[2].tasks.map((t) => t.id), ['tomorrow']);
    expect(groups[3].tasks.map((t) => t.id), ['week']);
    expect(groups[4].tasks.map((t) => t.id), ['later', 'none']);
  });

  test('groupTasksByList groups tasks and resolves localized Tasks title', () {
    final lists = [
      TodoList(id: 'tasks', title: 'Tasks', smartType: SmartListType.tasks),
      TodoList(id: 'work', title: 'Work'),
    ];
    final tasks = [
      _task(id: '1', listId: 'work'),
      _task(id: '2', listId: 'tasks'),
      _task(id: '3', listId: 'work'),
      _task(id: '4', listId: 'missing'),
    ];

    final grouped = groupTasksByList(l10n, tasks, lists);
    expect(grouped.length, 3);
    expect(grouped[0].listId, 'work');
    expect(grouped[0].title, 'Work');
    expect(grouped[0].tasks.map((t) => t.id), ['1', '3']);
    expect(grouped[1].listId, 'tasks');
    expect(grouped[1].title, l10n.tasks);
    expect(grouped[2].listId, 'missing');
    expect(grouped[2].title, l10n.tasks);
  });

  test('plannedFilterMenuLabel appends parenthetical date info', () {
    final now = DateTime(2026, 11, 26, 10, 0); // Thursday
    expect(
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.today, now: now),
      'Today (Thu)',
    );
    expect(
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.tomorrow, now: now),
      'Tomorrow (Fri)',
    );
    expect(
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.thisWeek, now: now),
      'This week (26 - 2 Dec)',
    );
    expect(
      plannedFilterMenuLabel(l10n, PlannedDueDateFilter.all, now: now),
      'All planned',
    );
  });

  test('compareCompletedTasksDesc sorts by completion day DESC then updatedAt DESC', () {
    // Same-day remote midnight completedAt ties broken by updatedAt DESC,
    // even when createdAt is in the opposite order.
    final firstCompleted = _task(
      id: 't1',
      isCompleted: true,
      createdAt: DateTime.utc(2026, 11, 20, 9, 0),
      completedAt: DateTime.utc(2026, 11, 23, 0, 0),
      updatedAt: DateTime.utc(2026, 11, 23, 10, 0),
    );
    final secondCompleted = _task(
      id: 't2',
      isCompleted: true,
      createdAt: DateTime.utc(2026, 11, 20, 8, 0),
      completedAt: DateTime.utc(2026, 11, 23, 0, 0),
      updatedAt: DateTime.utc(2026, 11, 23, 11, 0),
    );
    // Local completion with full time precision on the same UTC day still
    // yields to a later remote completion on that day via updatedAt.
    final thirdCompleted = _task(
      id: 't3',
      isCompleted: true,
      createdAt: DateTime.utc(2026, 11, 20, 7, 0),
      completedAt: DateTime.utc(2026, 11, 23, 12, 0),
      updatedAt: DateTime.utc(2026, 11, 23, 12, 0),
    );
    final fourthRemoteLaterSameDay = _task(
      id: 't4',
      isCompleted: true,
      createdAt: DateTime.utc(2026, 11, 20, 6, 0),
      completedAt: DateTime.utc(2026, 11, 23, 0, 0),
      updatedAt: DateTime.utc(2026, 11, 23, 13, 0),
    );
    // Older completion day stays below newer completion day even if edited
    // more recently.
    final olderDayEditedLater = _task(
      id: 't0',
      isCompleted: true,
      createdAt: DateTime.utc(2026, 11, 20, 10, 0),
      completedAt: DateTime.utc(2026, 11, 22, 0, 0),
      updatedAt: DateTime.utc(2026, 11, 24, 15, 0),
    );

    final sorted = [
      olderDayEditedLater,
      firstCompleted,
      thirdCompleted,
      secondCompleted,
      fourthRemoteLaterSameDay,
    ]..sort(compareCompletedTasksDesc);

    expect(sorted.map((t) => t.id), ['t4', 't3', 't2', 't1', 't0']);

    // Completed smart list uses the same order for defaultOrder, and respects
    // custom sortOption (e.g. alphabetical) when selected.
    const completedDefault = TodoList(
      id: 'completed',
      title: 'Completed',
      smartType: SmartListType.completed,
    );
    final completedAlpha = completedDefault.copyWith(
      sortOption: TaskSortOption.alphabetical,
      sortAscending: true,
    );
    final alphaTasks = [
      firstCompleted.copyWith(title: 'Bravo'),
      secondCompleted.copyWith(title: 'Alpha'),
    ];
    final state = TodoState(
      lists: [completedDefault],
      groups: const [],
      tasks: alphaTasks,
      selectedListId: 'completed',
    );
    expect(state.tasksForList(completedDefault).map((t) => t.id), ['t2', 't1']);
    expect(state.tasksForList(completedAlpha).map((t) => t.id), ['t2', 't1']);

    final customListAlpha = const TodoList(
      id: 'tasks',
      title: 'Tasks',
      smartType: SmartListType.tasks,
      sortOption: TaskSortOption.alphabetical,
      sortAscending: true,
    );
    final customState = TodoState(
      lists: [customListAlpha],
      groups: const [],
      tasks: alphaTasks,
      selectedListId: 'tasks',
    );
    final splitAlpha = splitTasksForDisplay(
      customState.tasksForList(customListAlpha),
      customListAlpha,
    );
    expect(splitAlpha.completed.map((t) => t.id), ['t2', 't1']);
  });
}
