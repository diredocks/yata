import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/tasksview/recyclerview/swipeable_task_card.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

void main() {
  testWidgets(
      'SwipeableTaskCard triggers right/left actions past 40% threshold and ignores small drags',
      (WidgetTester tester) async {
    var rightCount = 0;
    var leftCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: SwipeableTaskCard(
              enabled: true,
              isInMyDay: false,
              accentColor: Colors.blue,
              onSwipeRight: () => rightCount++,
              onSwipeLeft: () => leftCount++,
              child: const SizedBox(
                height: 56,
                width: 400,
                child: Text('Swipe target'),
              ),
            ),
          ),
        ),
      ),
    );

    // Small drag (< 40% of 400 = 160) -> should not trigger
    await tester.drag(find.text('Swipe target'), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(rightCount, 0);
    expect(leftCount, 0);

    // Right swipe past 40% -> triggers onSwipeRight
    await tester.drag(find.text('Swipe target'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(rightCount, 1);
    expect(leftCount, 0);

    // Left swipe past 40% -> triggers onSwipeLeft
    await tester.drag(find.text('Swipe target'), const Offset(-220, 0));
    await tester.pumpAndSettle();
    expect(rightCount, 1);
    expect(leftCount, 1);
  });

  testWidgets(
      'Swiping right toggles My Day and swiping left deletes task in TasksViewScreen',
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
    // Switch to Tasks list so task remains visible when toggling My Day
    container.read(todoProvider.notifier).selectList('tasks');
    await tester.pumpAndSettle();

    container.read(tasksViewPresenterProvider).addTask(title: 'Swipe me');
    await tester.pumpAndSettle();

    expect(container.read(todoProvider).tasks.first.isInMyDay, isFalse);

    // Swipe right -> adds to My Day
    await tester.drag(find.text('Swipe me'), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(container.read(todoProvider).tasks.first.isInMyDay, isTrue);

    // Swipe left -> deletes immediately and shows bottom Snackbar with Undo
    await tester.drag(find.text('Swipe me'), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(container.read(todoProvider).tasks, isEmpty);
    expect(find.text('Task deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // Snackbar is scoped to TasksViewScreen (not spanning sidebar) and above FAB
    final snackBarRect = tester.getRect(find.byType(SnackBar));
    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    expect(snackBarRect.left, greaterThanOrEqualTo(280));
    expect(snackBarRect.overlaps(fabRect), isFalse);
    expect(fabRect.bottom, lessThanOrEqualTo(snackBarRect.top));

    // Tapping Undo restores the task
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(container.read(todoProvider).tasks.length, 1);
    expect(container.read(todoProvider).tasks.first.title, 'Swipe me');

    // Swiping left again -> Snackbar auto-dismisses after 4 seconds
    await tester.drag(find.text('Swipe me'), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('Task deleted'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Task deleted'), findsNothing);
  });
}
