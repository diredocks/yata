import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';

void main() {
  testWidgets('TasksViewScreen respects bottom safe area padding', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"acct_a","displayName":"Alice","email":"alice@example.com","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'acct_a',
    });
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    final tasksScreenFinder = find.byType(TasksViewScreen);
    expect(tasksScreenFinder, findsOneWidget);

    final scrollViewFinder = find.descendant(
      of: tasksScreenFinder,
      matching: find.byType(NestedScrollView),
    );
    expect(scrollViewFinder, findsOneWidget);

    final scrollRect = tester.getRect(scrollViewFinder);
    expect(scrollRect.top, 0.0);
    expect(scrollRect.bottom, 800.0 - 34.0);
  });
}
