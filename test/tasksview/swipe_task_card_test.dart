import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/tasksview/recyclerview/swipeable_task_card.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/preferences.dart';

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

      // Right swipe past 40% -> waits for snap-back animation before triggering
      await tester.drag(find.text('Swipe target'), const Offset(220, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(rightCount, 0);
      await tester.pumpAndSettle();
      expect(rightCount, 1);
      expect(leftCount, 0);

      // Left swipe past 40% -> waits for snap-back animation before triggering
      await tester.drag(find.text('Swipe target'), const Offset(-220, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(leftCount, 0);
      await tester.pumpAndSettle();
      expect(rightCount, 1);
      expect(leftCount, 1);
    },
  );

  testWidgets(
    'Swiping right toggles My Day and swiping left deletes task in TasksViewScreen',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
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
    },
  );

  testWidgets(
    'SwipeableTaskCard ignores drags starting in left/right screen edge zones',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      var rightCount = 0;
      var leftCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              systemGestureInsets: EdgeInsets.only(left: 48, right: 20),
            ),
            child: Scaffold(
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
                    child: Text('Edge target'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Left edge (within systemGestureInsets.left = 48) -> ignored
      await tester.dragFrom(const Offset(40, 28), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(rightCount, 0);

      // Right edge (within minEdgeExclusion = 32, even though inset is 20) -> ignored
      await tester.dragFrom(const Offset(380, 28), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(leftCount, 0);

      // Center drag -> works normally
      await tester.dragFrom(const Offset(200, 28), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(rightCount, 1);
    },
  );

  testWidgets(
    'SwipeableTaskCard requires higher fling velocity/distance and same direction',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
                  child: Text('Fling target'),
                ),
              ),
            ),
          ),
        ),
      );

      // Moderate-speed short fling (~800 px/s, 80px = 20%) -> should NOT trigger
      await tester.fling(find.text('Fling target'), const Offset(80, 0), 800);
      await tester.pumpAndSettle();
      expect(rightCount, 0);

      // Drag right 120px (30%) then flick back left -> should NOT trigger
      final gesture = await tester.startGesture(const Offset(200, 28));
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rightCount, 0);
      expect(leftCount, 0);

      // Fast same-direction fling past 25% (120px = 30%, 1400 px/s) -> triggers
      await tester.fling(find.text('Fling target'), const Offset(120, 0), 1400);
      await tester.pumpAndSettle();
      expect(rightCount, 1);
    },
  );
}
