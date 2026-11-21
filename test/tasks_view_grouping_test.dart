import 'package:flutter_test/flutter_test.dart';
import 'package:yata/l10n/app_localizations_en.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_grouping.dart';

TaskItem _task({
  required String id,
  String listId = 'tasks',
  String title = 'Task',
  bool isCompleted = false,
  DateTime? createdAt,
  DateTime? completedAt,
  DateTime? dueDate,
  DateTime? reminderAt,
}) {
  return TaskItem(
    id: id,
    listId: listId,
    title: title,
    createdAt: createdAt ?? DateTime(2026, 11, 20),
    isCompleted: isCompleted,
    completedAt: completedAt,
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
    final importantSplit =
        splitTasksForDisplay([older, active], importantHidden);
    expect(importantSplit.active.map((t) => t.id), ['t3']);
    expect(importantSplit.completed, isEmpty);

    // Custom list splits active and completed, sorting completed newest-first
    final customList = TodoList(id: 'custom', title: 'Work', showCompleted: true);
    final customSplit =
        splitTasksForDisplay([older, active, newer], customList);
    expect(customSplit.active.map((t) => t.id), ['t3']);
    expect(customSplit.completed.map((t) => t.id), ['t2', 't1']);

    // Custom list with showCompleted=false hides completed bucket
    final customHidden = customList.copyWith(showCompleted: false);
    final hiddenSplit =
        splitTasksForDisplay([older, active, newer], customHidden);
    expect(hiddenSplit.active.map((t) => t.id), ['t3']);
    expect(hiddenSplit.completed, isEmpty);
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

    expect(
      groups.map((g) => g.bucket).toList(),
      [
        PlannedBucket.earlier,
        PlannedBucket.today,
        PlannedBucket.tomorrow,
        PlannedBucket.thisWeek,
        PlannedBucket.later,
      ],
    );
    expect(groups[0].tasks.map((t) => t.id), ['earlier']);
    expect(groups[1].tasks.map((t) => t.id), ['today']);
    expect(groups[2].tasks.map((t) => t.id), ['tomorrow']);
    expect(groups[3].tasks.map((t) => t.id), ['week']);
    expect(groups[4].tasks.map((t) => t.id), ['later', 'none']);
  });

  test('groupTasksByList groups tasks and resolves localized Tasks title', () {
    final lists = [
      TodoList(
        id: 'tasks',
        title: 'Tasks',
        smartType: SmartListType.tasks,
      ),
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
}
