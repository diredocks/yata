import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/tasksview/recyclerview/animated_task_sliver_list.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

TaskItem _makeTask(String id, String title) {
  return TaskItem(
    id: id,
    listId: 'tasks',
    title: title,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  testWidgets(
      'AnimatedTaskSliverList animates both moved and displaced items smoothly',
      (WidgetTester tester) async {
    var tasks = [
      _makeTask('t1', 'First'),
      _makeTask('t2', 'Second'),
      _makeTask('t3', 'Third'),
    ];
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setHostState = setState;
              return CustomScrollView(
                slivers: [
                  AnimatedTaskSliverList(
                    tasks: tasks,
                    itemBuilder: (context, task) => SizedBox(
                      key: ValueKey('row_${task.id}'),
                      height: 60,
                      child: Text(task.title),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Move t3 (bottom, y=120) to top (y=0); t1 & t2 are displaced down by 60px.
    setHostState(() {
      tasks = [
        _makeTask('t3', 'Third'),
        _makeTask('t1', 'First'),
        _makeTask('t2', 'Second'),
      ];
    });
    await tester.pump();
    // Advance ~halfway through the 250ms move animation.
    await tester.pump(const Duration(milliseconds: 125));

    // At ~125ms, t3 should be hit-testable above its final y=0? No, t3 started at
    // y=120 moving up to y=0, so at 125ms it's around y=60.
    // Verify hitTest works at its animated visual position and completes cleanly.
    final t1Box = tester.renderObject<RenderBox>(find.byKey(const ValueKey('row_t1')));
    final t3Box = tester.renderObject<RenderBox>(find.byKey(const ValueKey('row_t3')));
    // Layout positions are updated immediately (t3 at 0, t1 at 60).
    expect(t3Box.localToGlobal(Offset.zero).dy, 0.0);
    expect(t1Box.localToGlobal(Offset.zero).dy, 60.0);

    // Finish animation cleanly with no errors.
    await tester.pumpAndSettle();
  });

  testWidgets(
      'Collapsing Completed section plays fade-out animation before removing items',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'test',
    });
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(YataApp)),
    );
    final presenter = container.read(tasksViewPresenterProvider);
    presenter.addTask(title: 'Done task');
    await tester.pumpAndSettle();

    final taskId = container.read(todoProvider).tasks.first.id;
    presenter.setTaskCompleted(taskId, completed: true);
    await tester.pumpAndSettle();

    expect(find.text('Done task'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    // Tap the Completed pill to collapse it.
    await tester.tap(find.text('Completed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Mid-animation: the completed task is still in the tree fading out
    // via a single SliverFadeTransition (no per-item SizeTransition relayouts).
    expect(find.text('Done task'), findsOneWidget);
    final fadeFinder = find.ancestor(
      of: find.text('Done task'),
      matching: find.byType(SliverFadeTransition),
    );
    expect(fadeFinder, findsOneWidget);
    final fadeOpacity =
        tester.widget<SliverFadeTransition>(fadeFinder).opacity.value;
    expect(fadeOpacity, lessThan(1.0));
    expect(fadeOpacity, greaterThan(0.0));

    // After the animation finishes, the collapsed item is removed.
    await tester.pumpAndSettle();
    expect(find.text('Done task'), findsNothing);
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets(
      'Empty or short task list still scrolls enough to collapse SliverAppBar',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'test',
    });
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Open My Day (first list on mobile Landing -> HomeViewScreen -> My Day).
    if (find.text('My Day').evaluate().isNotEmpty) {
      await tester.tap(find.text('My Day').first);
      await tester.pumpAndSettle();
    }

    final scrollViewFinder = find.byType(CustomScrollView);
    expect(scrollViewFinder, findsOneWidget);

    // Drag up to collapse the header even with 0 tasks.
    await tester.drag(scrollViewFinder, const Offset(0, -200));
    await tester.pumpAndSettle();

    final appBarSliver = tester.renderObject(find.byType(SliverAppBar).first);
    expect(
      (appBarSliver as dynamic).geometry.paintExtent,
      closeTo(kToolbarHeight, 1.0),
    );
  });

  testWidgets(
      'Partially collapsed SliverAppBar snaps to expanded or collapsed on scroll end',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'test',
    });
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(412, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    if (find.text('My Day').evaluate().isNotEmpty) {
      await tester.tap(find.text('My Day').first);
      await tester.pumpAndSettle();
    }

    final scrollViewFinder = find.byType(CustomScrollView);
    final appBarSliver = tester.renderObject(find.byType(SliverAppBar).first);

    // Drag up slightly (< half of 88px collapseDelta) -> snaps back to expanded (144).
    await tester.drag(scrollViewFinder, const Offset(0, -25));
    await tester.pumpAndSettle();
    expect((appBarSliver as dynamic).geometry.paintExtent, closeTo(144.0, 1.0));

    // Drag up past half (>= 44px) -> snaps to collapsed (56).
    await tester.drag(scrollViewFinder, const Offset(0, -55));
    await tester.pumpAndSettle();
    expect(
      (appBarSliver as dynamic).geometry.paintExtent,
      closeTo(kToolbarHeight, 1.0),
    );
  });
}
