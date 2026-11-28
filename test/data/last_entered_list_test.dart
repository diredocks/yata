import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';
import 'package:yata/homeview/home_view_screen.dart';
import 'package:yata/data/preferences.dart';

void main() {
  testWidgets(
    'Remembers last entered list across restarts and clears when returning to HomeView',
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

      // Initially on HomeViewScreen
      expect(find.byType(HomeViewScreen), findsOneWidget);
      expect(find.byType(TasksViewScreen), findsNothing);

      // Enter Important list
      await tester.tap(find.text('Important'));
      await tester.pumpAndSettle();
      expect(find.byType(TasksViewScreen), findsOneWidget);
      expect(
        prefs.getString('yata.acct.acct_a.last_entered_list_id'),
        'important',
      );

      // Restart app -> directly enters Important list
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TasksViewScreen), findsOneWidget);
      expect(find.text('Important'), findsOneWidget);

      // Press back to return to HomeViewScreen -> clears last entered list
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TasksViewScreen), findsNothing);
      expect(find.byType(HomeViewScreen), findsOneWidget);
      expect(prefs.getString('yata.acct.acct_a.last_entered_list_id'), isNull);

      // Restart app -> stays on HomeViewScreen
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeViewScreen), findsOneWidget);
      expect(find.byType(TasksViewScreen), findsNothing);
    },
  );

  testWidgets('Last entered list is isolated per account', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts': '[{"id":"acct_a","displayName":"Alice","email":"alice@example.com","createdAt":"2026-01-01T00:00:00.000"},{"id":"acct_b","displayName":"Bob","email":"bob@example.com","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'acct_a',
      'yata.acct.acct_a.last_entered_list_id': 'important',
      'yata.acct.acct_b.last_entered_list_id': 'tasks',
    });
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Launch with Account A active -> enters Important
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TasksViewScreen), findsOneWidget);
    expect(find.text('Important'), findsOneWidget);

    // Switch active account to B and restart -> enters Tasks
    await prefs.setString('yata.active_account_id', 'acct_b');
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TasksViewScreen), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
  });

  testWidgets('Clears stale last entered list ID if list no longer exists', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts': '[{"id":"acct_a","displayName":"Alice","email":"alice@example.com","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'acct_a',
      'yata.acct.acct_a.last_entered_list_id': 'deleted_list_id',
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

    expect(find.byType(HomeViewScreen), findsOneWidget);
    expect(find.byType(TasksViewScreen), findsNothing);
    expect(prefs.getString('yata.acct.acct_a.last_entered_list_id'), isNull);
  });
}
