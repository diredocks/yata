import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/data/account/account_provider.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/data/attachments/attachment_service.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/storage/preferences.dart';

void main() {
  testWidgets(
    'Shows LandingScreen when no accounts exist, creates isolated local storage per account, supports switching and signing out',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = Directory.systemTemp.createTempSync('yata_ma_att_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            attachmentServiceProvider.overrideWith(
              (ref) => AttachmentService(
                ref,
                storageRootProvider: () async => tempDir,
              ),
            ),
          ],
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
      expect(find.text('Bob'), findsWidgets);
      expect(find.text('bob@example.com'), findsWidgets);
      expect(container.read(todoProvider).tasks, isEmpty);

      container.read(tasksViewPresenterProvider).addTask(title: 'Bob task');
      await tester.pumpAndSettle();
      expect(container.read(todoProvider).tasks.single.title, 'Bob task');

      // 4. Switch back to Alice via HomeView account switcher (menu stays open)
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

  testWidgets(
    'HomeView preserves account-opened state when navigating to other pages and back',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tempDir = Directory.systemTemp.createTempSync('yata_ma_att_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            attachmentServiceProvider.overrideWith(
              (ref) => AttachmentService(
                ref,
                storageRootProvider: () async => tempDir,
              ),
            ),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alice@example.com');
      await tester.tap(find.text('Use a local account'));
      await tester.pumpAndSettle();

      // Open account menu on HomeView
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('homeview_accounts')), findsOneWidget);

      // Navigate to Settings and back
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('homeview_accounts')), findsOneWidget);

      // Navigate to Manage accounts and back
      await tester.tap(find.text('Manage accounts'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('homeview_accounts')), findsOneWidget);

      // Navigate to Add account and cancel (back)
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('homeview_accounts')), findsOneWidget);
    },
  );
}
