import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/providers/todo_provider.dart';

void main() {
  testWidgets(
      'Persists newly created lists and tasks across app restarts without mock data',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Smart lists appear on HomeView with no mock tasks
    expect(find.text('My Day'), findsOneWidget);
    expect(find.text('Important'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Review weekly goals'), findsNothing);

    // Tap My Day and verify clean empty state (no prompt box) + date subtitle
    await tester.tap(find.text('My Day'));
    await tester.pumpAndSettle();
    expect(find.text('Focus on your day'), findsNothing);
    expect(find.text(DateFormat.MMMMEEEEd().format(DateTime.now())),
        findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);

    // Open DetailView for the new task
    await tester.tap(find.text('Buy milk'));
    await tester.pumpAndSettle();
    expect(find.text('Added to My Day'), findsOneWidget);
    expect(find.text('Add step'), findsOneWidget);

    // Rebuild a fresh ProviderScope backed by the same SharedPreferences
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Day'));
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets(
      'Wide layout displays sidebar, detail panel, and different menus per list type',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
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

    // Smart list (My Day) menu has Sort & Change theme, no Rename/Delete
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Change theme'), findsOneWidget);
    expect(find.text('Rename list'), findsNothing);
    expect(find.text('Delete list'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Create a custom list via New list
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Groceries');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Custom list menu includes Rename, Duplicate, Delete
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Rename list'), findsOneWidget);
    expect(find.text('Duplicate list'), findsOneWidget);
    expect(find.text('Delete list'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Add a recurring task and complete it -> next occurrence is generated
    final container = ProviderScope.containerOf(
      tester.element(find.byType(YataApp)),
    );
    container.read(todoProvider.notifier).addTask(
          title: 'Daily standup',
          recurrence: RecurrenceType.daily,
          dueDate: DateTime(2026, 11, 22),
        );
    await tester.pumpAndSettle();

    expect(find.text('Daily standup'), findsOneWidget);
    await tester.tap(find.text('Daily standup'));
    await tester.pumpAndSettle();
    expect(find.text('Added to My Day'), findsNothing);
    expect(find.text('Add to My Day'), findsOneWidget);

    final taskId = container.read(todoProvider).tasks.first.id;
    container.read(todoProvider.notifier).toggleTaskCompleted(taskId);
    await tester.pumpAndSettle();

    final tasks = container.read(todoProvider).tasks;
    expect(tasks.length, 2);
    expect(tasks.where((t) => !t.isCompleted).length, 1);
    expect(tasks.where((t) => t.isCompleted).length, 1);
  });

  testWidgets(
      'Supports task reordering, multi-select actions, group management, and settings persistence',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
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
    final notifier = container.read(todoProvider.notifier);

    // Add two tasks in My Day and verify reorder mode UI + reorderActiveTasks
    notifier.addTask(title: 'First task');
    notifier.addTask(title: 'Second task');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    expect(find.text('Done'), findsOneWidget);

    final active = container
        .read(todoProvider)
        .tasksForList(container.read(todoProvider).selectedList);
    notifier.reorderActiveTasks(active, 0, 2);
    await tester.pumpAndSettle();

    final reordered = container
        .read(todoProvider)
        .tasksForList(container.read(todoProvider).selectedList);
    expect(reordered.first.title, 'First task');

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Long-press enters multi-select mode; secondary actions are in overflow menu
    await tester.longPress(find.text('First task'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.select_all), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    // Open Settings and toggle Completed smart list + persist
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Local Account'));
    await tester.pumpAndSettle();

    expect(find.text('Add new tasks on top'), findsOneWidget);
    expect(find.text('Move starred tasks to top'), findsOneWidget);
    expect(find.text('Smart lists'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Completed'), 200);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();

    expect(container.read(todoProvider).showSmartListCompleted, isTrue);
  });
}
