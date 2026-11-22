import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

void main() {
  testWidgets(
    'Shows LandingScreen when no accounts exist, creates isolated local storage per account, supports switching and signing out',
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

      // 1. Fresh install shows LandingScreen
      expect(find.text('Welcome to Yata'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Use a local account'), findsOneWidget);

      // 2. Sign in as Alice via "Use a local account" -> creates local account & enters MainShellScreen
      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.tap(find.text('Use a local account'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('My Day'), findsOneWidget);

      // Add a task in Alice's account
      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      container.read(tasksViewPresenterProvider).addTask(title: 'Alice task');
      await tester.pumpAndSettle();
      expect(container.read(todoProvider).tasks.length, 1);

      // 3. Open HomeView account switcher -> Add account (Bob)
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('Add account'), findsOneWidget);
      expect(find.text('Manage accounts'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Yata'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'bob@example.com');
      await tester.tap(find.text('Use a local account'));
      await tester.pumpAndSettle();

      // Bob has his own empty local storage (Alice's task is isolated)
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('bob@example.com'), findsOneWidget);
      expect(container.read(todoProvider).tasks, isEmpty);

      container.read(tasksViewPresenterProvider).addTask(title: 'Bob task');
      await tester.pumpAndSettle();
      expect(container.read(todoProvider).tasks.single.title, 'Bob task');

      // 4. Switch back to Alice via HomeView account switcher
      await tester.tap(find.text('Bob'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(container.read(todoProvider).tasks.single.title, 'Alice task');

      // 5. Open Manage accounts and sign out of Bob, then Alice
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage accounts'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Sign out'), findsNWidgets(2));

      // Sign out of Bob (second Sign out button)
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);

      // Sign out of Alice (last account) -> returns to LandingScreen
      await tester.tap(find.text('Sign out').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to Yata'), findsOneWidget);
      expect(container.read(accountProvider).accounts, isEmpty);
    },
  );
}
