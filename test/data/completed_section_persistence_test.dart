import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/storage/preferences.dart';

void main() {
  testWidgets(
    'List menu omits Hide completed tasks and Completed expansion state persists per list',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': '[{"id":"acct_a","displayName":"Alice","email":"alice@example.com","createdAt":"2026-01-01T00:00:00.000"}]',
        'yata.active_account_id': 'acct_a',
      });
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

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      final presenter = container.read(tasksViewPresenterProvider);
      presenter.addTask(title: 'Done in My Day', targetListId: 'my_day');
      presenter.addTask(title: 'Done in Tasks', targetListId: 'tasks');
      await tester.pumpAndSettle();

      final myDayTask = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.title == 'Done in My Day');
      final tasksListTask = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.title == 'Done in Tasks');
      presenter.setTaskCompleted(myDayTask.id, completed: true);
      presenter.setTaskCompleted(tasksListTask.id, completed: true);
      await tester.pumpAndSettle();

      // Enter My Day
      await tester.tap(find.text('My Day'));
      await tester.pumpAndSettle();

      // Open menu: Hide completed tasks should not be present
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Hide completed tasks'), findsNothing);
      expect(find.text('Show completed tasks'), findsNothing);
      expect(find.text('Change theme'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Completed section is initially expanded
      expect(find.text('Done in My Day'), findsOneWidget);

      // Collapse Completed in My Day
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(find.text('Done in My Day'), findsNothing);

      // Return to HomeView and open Tasks: Tasks' Completed section is still expanded
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      expect(find.text('Done in Tasks'), findsOneWidget);

      // Return to HomeView, restart app, and open My Day: still collapsed
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
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
      expect(find.text('Done in My Day'), findsNothing);
    },
  );
}
