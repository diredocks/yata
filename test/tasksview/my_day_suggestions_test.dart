import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/tasksview/my_day_suggestions.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';

Future<ProviderContainer> _pumpTasksView(
  WidgetTester tester, {
  GlobalKey<NavigatorState>? navigatorKey,
  ValueChanged<TaskItem>? onOpenTask,
  Size surfaceSize = const Size(800, 600),
  List<TaskItem> tasks = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
    'yata.active_account_id': 'test',
  });
  final prefs = await SharedPreferences.getInstance();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surfaceSize;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TasksViewScreen(onOpenTask: onOpenTask ?? (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(TasksViewScreen)),
  );
  if (tasks.isNotEmpty) {
    container
        .read(todoProvider.notifier)
        .commit(container.read(todoProvider).copyWith(tasks: tasks));
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  test('computeMyDaySuggestions groups eligible tasks into local buckets', () {
    final now = DateTime(2026, 11, 26, 10, 0);
    final tasks = [
      TaskItem(
        id: 't_in_my_day',
        listId: 'tasks',
        title: 'Already in My Day',
        isInMyDay: true,
        myDayDate: now,
        createdAt: now,
      ),
      TaskItem(
        id: 't_completed',
        listId: 'tasks',
        title: 'Completed task',
        isCompleted: true,
        dueDate: now,
        createdAt: now,
      ),
      TaskItem(
        id: 't_today',
        listId: 'tasks',
        title: 'Due today',
        dueDate: DateTime(2026, 11, 26),
        createdAt: now,
      ),
      TaskItem(
        id: 't_yesterday',
        listId: 'tasks',
        title: 'From yesterday',
        myDayDate: DateTime(2026, 11, 25),
        createdAt: now,
      ),
      TaskItem(
        id: 't_overdue',
        listId: 'tasks',
        title: 'Overdue task',
        dueDate: DateTime(2026, 11, 24),
        createdAt: now,
      ),
      TaskItem(
        id: 't_upcoming',
        listId: 'tasks',
        title: 'Upcoming task',
        dueDate: DateTime(2026, 11, 28),
        createdAt: now,
      ),
      TaskItem(
        id: 't_recent',
        listId: 'tasks',
        title: 'Recently added',
        createdAt: now,
      ),
    ];

    final buckets = computeMyDaySuggestions(tasks, now: now);
    expect(buckets.map((b) => b.type).toList(), [
      SuggestionBucketType.today,
      SuggestionBucketType.yesterday,
      SuggestionBucketType.overdue,
      SuggestionBucketType.upcoming,
      SuggestionBucketType.recentlyAdded,
    ]);
    expect(buckets[0].tasks.single.id, 't_today');
    expect(buckets[1].tasks.single.id, 't_yesterday');
    expect(buckets[2].tasks.single.id, 't_overdue');
    expect(buckets[3].tasks.single.id, 't_upcoming');
    expect(buckets[4].tasks.single.id, 't_recent');
  });

  testWidgets('My Day suggestions button opens sheet and adds task to My Day', (
    tester,
  ) async {
    final container = await _pumpTasksView(
      tester,
      tasks: [
        TaskItem(
          id: 'suggested_1',
          listId: 'tasks',
          title: 'Pick up groceries',
          createdAt: DateTime.now(),
        ),
      ],
    );
    final notifier = container.read(todoProvider.notifier);

    expect(
      find.byKey(const ValueKey('my_day_suggestions_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('my_day_suggestions_button')));
    await tester.pumpAndSettle();

    expect(find.text('Suggestions'), findsNWidgets(2));
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Pick up groceries'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_suggestion_suggested_1')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(todoProvider)
          .tasks
          .singleWhere((t) => t.id == 'suggested_1')
          .isInMyDay,
      isTrue,
    );
    expect(find.text('No suggestions for today'), findsOneWidget);

    // Non-My-Day list should not show the suggestions button.
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    notifier.selectList('tasks');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('my_day_suggestions_button')),
      findsNothing,
    );
  });

  testWidgets('suggestion rows animate out instead of disappearing', (
    tester,
  ) async {
    await _pumpTasksView(
      tester,
      tasks: [
        TaskItem(
          id: 'suggested_1',
          listId: 'tasks',
          title: 'Pick up groceries',
          createdAt: DateTime.now(),
        ),
        TaskItem(
          id: 'suggested_2',
          listId: 'tasks',
          title: 'Water the plants',
          createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('my_day_suggestions_button')));
    await tester.pumpAndSettle();

    expect(find.byType(SliverAnimatedList), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_suggestion_suggested_1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byKey(const ValueKey('removing_suggested_1')), findsOneWidget);
    expect(find.text('Water the plants'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('removing_suggested_1')), findsNothing);
    expect(find.text('Water the plants'), findsOneWidget);
    // Only the My Day list behind the sheet still shows the added task.
    expect(find.text('Pick up groceries'), findsOneWidget);
  });

  testWidgets('narrow layout keeps the sheet open behind the task detail', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pumpTasksView(
      tester,
      navigatorKey: navigatorKey,
      surfaceSize: const Size(400, 800),
      onOpenTask: (_) => navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Detail view'))),
        ),
      ),
      tasks: [
        TaskItem(
          id: 'suggested_1',
          listId: 'tasks',
          title: 'Pick up groceries',
          createdAt: DateTime.now(),
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('my_day_suggestions_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick up groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Detail view'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('Suggestions'), findsNWidgets(2));
    expect(find.text('Pick up groceries'), findsOneWidget);
  });

  testWidgets('wide layout dismisses the sheet when opening a task', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await _pumpTasksView(
      tester,
      navigatorKey: navigatorKey,
      surfaceSize: const Size(1024, 800),
      onOpenTask: (_) => navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: Center(child: Text('Detail view'))),
        ),
      ),
      tasks: [
        TaskItem(
          id: 'suggested_1',
          listId: 'tasks',
          title: 'Pick up groceries',
          createdAt: DateTime.now(),
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('my_day_suggestions_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick up groceries'));
    await tester.pumpAndSettle();

    expect(find.text('Detail view'), findsOneWidget);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.text('Suggestions'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('my_day_suggestions_button')),
      findsOneWidget,
    );
  });
}
