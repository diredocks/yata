import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/search/search_presenter.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/tasksview/task_batch_actions.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/preferences.dart';

Future<ProviderContainer> _createContainer() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('My Day separates explicit commit from due-today auto-population and postponedDay', () async {
    final container = await _createContainer();
    addTearDown(container.dispose);

    final tasksPresenter = container.read(tasksViewPresenterProvider);
    final detailPresenter = container.read(detailViewPresenterProvider);
    final settingsPresenter = container.read(settingsPresenterProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // Create a task in Tasks list due today -> auto-populated into My Day
    container.read(todoProvider.notifier).selectList('tasks');
    tasksPresenter.addTask(title: 'Due today auto', dueDate: today);
    final autoTask = container.read(todoProvider).tasks.first;
    expect(autoTask.isInMyDay, isTrue);
    expect(autoTask.myDayDate, isNull);

    // Removing from My Day sets postponedDay and keeps it out even if setting is toggled
    detailPresenter.toggleTaskMyDay(autoTask.id);
    var updated = container.read(todoProvider).tasks.first;
    expect(updated.isInMyDay, isFalse);
    expect(updated.postponedDay, isNotNull);

    settingsPresenter.setShowDueTodayInMyDay(false);
    settingsPresenter.setShowDueTodayInMyDay(true);
    updated = container.read(todoProvider).tasks.first;
    expect(updated.isInMyDay, isFalse);

    // Explicitly committed task due today stays in My Day when moved to tomorrow
    tasksPresenter.addTask(
      title: 'Explicit + due today',
      isInMyDay: true,
      dueDate: today,
    );
    final explicitTask = container
        .read(todoProvider)
        .tasks
        .firstWhere((t) => t.title == 'Explicit + due today');
    expect(explicitTask.myDayDate, isNotNull);

    detailPresenter.setTaskDueDate(explicitTask.id, tomorrow);
    final movedTask = container
        .read(todoProvider)
        .tasks
        .firstWhere((t) => t.id == explicitTask.id);
    expect(movedTask.isInMyDay, isTrue);
  });

  test('Recurrence clamps month-end and leap-day dates', () async {
    final container = await _createContainer();
    addTearDown(container.dispose);

    final tasksPresenter = container.read(tasksViewPresenterProvider);
    tasksPresenter.addTask(
      title: 'Month end',
      dueDate: DateTime(2026, 1, 31),
      recurrence: RecurrenceType.monthly,
    );
    final monthlyId = container.read(todoProvider).tasks.first.id;
    tasksPresenter.toggleTaskCompleted(monthlyId);

    final nextMonthly = container
        .read(todoProvider)
        .tasks
        .firstWhere((t) => !t.isCompleted && t.title == 'Month end');
    expect(nextMonthly.dueDate, DateTime(2026, 2, 28));

    tasksPresenter.addTask(
      title: 'Leap year',
      dueDate: DateTime(2024, 2, 29),
      recurrence: RecurrenceType.yearly,
    );
    final yearlyId = container
        .read(todoProvider)
        .tasks
        .firstWhere((t) => t.title == 'Leap year')
        .id;
    tasksPresenter.toggleTaskCompleted(yearlyId);

    final nextYearly = container
        .read(todoProvider)
        .tasks
        .firstWhere((t) => !t.isCompleted && t.title == 'Leap year');
    expect(nextYearly.dueDate, DateTime(2025, 2, 28));
  });

  test(
    'Sort defaults, toggle direction, and physical moveStarredTasksToTop',
    () async {
      final container = await _createContainer();
      addTearDown(container.dispose);

      final tasksPresenter = container.read(tasksViewPresenterProvider);
      container.read(todoProvider.notifier).selectList('tasks');

      tasksPresenter.addTask(title: 'Alpha');
      tasksPresenter.addTask(title: 'Beta');
      final alpha = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.title == 'Alpha');

      // Starring Alpha moves it to top physically when moveStarredTasksToTop is true
      tasksPresenter.toggleTaskImportant(alpha.id);
      final tasksList = container.read(todoProvider).selectedList;
      var ordered = container.read(todoProvider).tasksForList(tasksList);
      expect(ordered.first.title, 'Alpha');

      // Manual reorder can still move Alpha below Beta
      tasksPresenter.reorderActiveTasks(ordered, 0, 1);
      ordered = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(ordered.first.title, 'Beta');

      // Selecting importance defaults to descending (important first), clicking again flips
      tasksPresenter.setListSortOption('tasks', TaskSortOption.importance);
      expect(container.read(todoProvider).selectedList.sortAscending, isFalse);
      ordered = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(ordered.first.title, 'Alpha');

      tasksPresenter.setListSortOption('tasks', TaskSortOption.importance);
      expect(container.read(todoProvider).selectedList.sortAscending, isTrue);
    },
  );

  test('Smart lists filtering, Completed badge count, groups dedup, duplicate & delete list', () async {
    final container = await _createContainer();
    addTearDown(container.dispose);

    final homePresenter = container.read(homeViewPresenterProvider);
    final tasksPresenter = container.read(tasksViewPresenterProvider);

    // Group deduplication
    final g1 = homePresenter.addGroup('Work');
    final g2 = homePresenter.addGroup('Work');
    final g3 = homePresenter.addGroup('Work');
    expect(g1.title, 'Work');
    expect(g2.title, 'Work (1)');
    expect(g3.title, 'Work (2)');

    // Custom list creation, duplicate appends (1)/(2), delete falls back to previous list
    homePresenter.addList('Shopping', ListThemeColor.blue);
    final shoppingId = container.read(todoProvider).selectedListId;
    tasksPresenter.addTask(title: 'Eggs');
    tasksPresenter.duplicateList(shoppingId);
    final dupList = container.read(todoProvider).selectedList;
    expect(dupList.id, isNot(shoppingId));
    expect(dupList.title, 'Shopping (1)');

    tasksPresenter.duplicateList(shoppingId);
    final dupList2 = container.read(todoProvider).selectedList;
    expect(dupList2.title, 'Shopping (2)');
    tasksPresenter.deleteList(dupList2.id);
    expect(container.read(todoProvider).selectedListId, dupList.id);

    tasksPresenter.deleteList(dupList.id);
    expect(container.read(todoProvider).selectedListId, shoppingId);

    // All smart list excludes completed tasks; Completed badge count is always 0
    final eggId = container.read(todoProvider).tasks.first.id;
    tasksPresenter.toggleTaskCompleted(eggId);
    final state = container.read(todoProvider);
    final allList = state.lists.firstWhere(
      (l) => l.smartType == SmartListType.all,
    );
    final completedList = state.lists.firstWhere(
      (l) => l.smartType == SmartListType.completed,
    );
    expect(state.tasksForList(allList), isEmpty);
    expect(state.activeCountForList(completedList), 0);
  });

  test('duplicateList drops completed tasks when they are not kept', () async {
    final container = await _createContainer();
    addTearDown(container.dispose);

    final homePresenter = container.read(homeViewPresenterProvider);
    final tasksPresenter = container.read(tasksViewPresenterProvider);
    final detailPresenter = container.read(detailViewPresenterProvider);

    homePresenter.addList('Release', ListThemeColor.blue);
    final listId = container.read(todoProvider).selectedListId;

    tasksPresenter.addTask(title: 'Active');
    tasksPresenter.addTask(title: 'Done');
    tasksPresenter.addTask(title: 'Partial');

    TaskItem taskByTitle(String title) => container
        .read(todoProvider)
        .tasks
        .firstWhere((t) => t.title == title && t.listId == listId);

    tasksPresenter.setTaskCompleted(taskByTitle('Done').id, completed: true);
    detailPresenter.addStep(taskByTitle('Partial').id, 'Step A');
    detailPresenter.toggleStepCompleted(
      taskByTitle('Partial').id,
      taskByTitle('Partial').steps.first.id,
    );

    // Keeping completed tasks copies them with their completion state.
    tasksPresenter.duplicateList(listId, keepCompleted: true);
    final keptList = container.read(todoProvider).selectedList;
    final keptTasks = container.read(todoProvider).tasksForList(keptList);
    expect(
      keptTasks.map((t) => t.title),
      containsAll(['Active', 'Done', 'Partial']),
    );
    final keptDone = keptTasks.firstWhere((t) => t.title == 'Done');
    expect(keptDone.isCompleted, isTrue);
    expect(keptDone.completedAt, isNotNull);

    // Dropping completed tasks omits them entirely while leaving the other
    // tasks and their step completion state untouched.
    tasksPresenter.duplicateList(listId, keepCompleted: false);
    final droppedList = container.read(todoProvider).selectedList;
    final droppedTasks = container.read(todoProvider).tasksForList(droppedList);
    expect(
      droppedTasks.map((t) => t.title),
      unorderedEquals(['Active', 'Partial']),
    );
    final droppedPartial = droppedTasks.firstWhere((t) => t.title == 'Partial');
    expect(droppedPartial.isCompleted, isFalse);
    expect(droppedPartial.steps.single.isCompleted, isTrue);

    // The source list itself is untouched.
    final sourceTasks = container
        .read(todoProvider)
        .tasksForList(
          container.read(todoProvider).lists.firstWhere((l) => l.id == listId),
        );
    expect(
      sourceTasks.map((t) => t.title),
      unorderedEquals(['Active', 'Done', 'Partial']),
    );
  });

  test(
    'Steps promote/empty-rename, noteUpdatedAt guard, batchCopy & Search',
    () async {
      final container = await _createContainer();
      addTearDown(container.dispose);

      final tasksPresenter = container.read(tasksViewPresenterProvider);
      final actionPresenter = container.read(taskBatchActionsProvider);
      final detailPresenter = container.read(detailViewPresenterProvider);
      final searchPresenter = container.read(searchPresenterProvider);

      container.read(todoProvider.notifier).selectList('tasks');
      tasksPresenter.addTask(title: 'Parent task');
      final parent = container.read(todoProvider).tasks.first;

      // Empty rename deletes step
      detailPresenter.addStep(parent.id, 'Step 1');
      final step1Id = container.read(todoProvider).tasks.first.steps.first.id;
      detailPresenter.renameStep(parent.id, step1Id, '   ');
      expect(container.read(todoProvider).tasks.first.steps, isEmpty);

      // Completed step cannot be promoted
      detailPresenter.addStep(parent.id, 'Done step');
      final doneStepId = container
          .read(todoProvider)
          .tasks
          .first
          .steps
          .first
          .id;
      detailPresenter.toggleStepCompleted(parent.id, doneStepId);
      detailPresenter.promoteStepToTask(parent.id, doneStepId);
      expect(container.read(todoProvider).tasks.length, 1);

      // Note update with same text does not change noteUpdatedAt
      detailPresenter.updateTaskNote(parent.id, 'Hello world');
      final firstTime = container.read(todoProvider).tasks.first.noteUpdatedAt;
      detailPresenter.updateTaskNote(parent.id, 'Hello world');
      final secondTime = container.read(todoProvider).tasks.first.noteUpdatedAt;
      expect(secondTime, firstTime);

      // Batch copy preserves completed state
      tasksPresenter.toggleTaskCompleted(parent.id);
      actionPresenter.batchCopyToList({parent.id}, 'tasks');
      expect(
        container.read(todoProvider).tasks.where((t) => t.isCompleted).length,
        2,
      );

      // Search matches multi-word tokens across title/note/steps and respects showCompleted
      expect(
        searchPresenter.search('parent task', showCompleted: true).length,
        2,
      );
      expect(
        searchPresenter.search('parent task', showCompleted: false),
        isEmpty,
      );
    },
  );
}
