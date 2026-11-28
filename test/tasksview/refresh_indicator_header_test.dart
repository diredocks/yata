import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/account/account_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/models/account.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

import 'package:yata/data/preferences.dart';

void main() {
  testWidgets(
    'Pulling down while header is collapsed expands header before dragging RefreshIndicator',
    (WidgetTester tester) async {
      final account = Account.microsoft(
        id: 'acct_ms',
        displayName: 'MS User',
        email: 'ms@example.com',
        microsoftUserId: 'cid1',
      );
      SharedPreferences.setMockInitialValues({
        'yata.accounts': jsonEncode([account.toJson()]),
        'yata.active_account_id': 'acct_ms',
      });
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(FakeSubstrateApi()),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      final presenter = container.read(tasksViewPresenterProvider);
      for (var i = 1; i <= 25; i++) {
        presenter.addTask(title: 'Task $i', targetListId: 'tasks');
      }
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      final nestedState = tester.state<NestedScrollViewState>(
        find.byType(NestedScrollView),
      );
      final maxOuter = nestedState.outerController.position.maxScrollExtent;
      expect(maxOuter, greaterThan(40));

      // Collapse header while keeping inner list at top.
      nestedState.outerController.jumpTo(maxOuter);
      await tester.pumpAndSettle();
      expect(nestedState.outerController.offset, closeTo(maxOuter, 0.5));
      expect(nestedState.innerController.offset, 0.0);

      // Start dragging down on the list, consuming only part of the header height.
      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(0, 20)); // exceed touch slop
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      // Header should have started expanding, but RefreshProgressIndicator must not appear yet.
      expect(nestedState.outerController.offset, lessThan(maxOuter));
      expect(nestedState.outerController.offset, greaterThan(0));
      final refreshIndicator = find.byType(RefreshIndicator);
      expect(refreshIndicator, findsOneWidget);
      final sizeTransitionWhileExpanding = find.descendant(
        of: refreshIndicator,
        matching: find.byType(SizeTransition),
      );
      if (sizeTransitionWhileExpanding.evaluate().isNotEmpty) {
        final st = tester.widget<SizeTransition>(sizeTransitionWhileExpanding);
        expect(st.sizeFactor.value, 0.0);
      }

      // Continue pulling down past the remaining header height to trigger overscroll drag.
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();

      expect(nestedState.outerController.offset, 0.0);
      final sizeTransitionAfterExpanded = find.descendant(
        of: refreshIndicator,
        matching: find.byType(SizeTransition),
      );
      expect(sizeTransitionAfterExpanded, findsOneWidget);
      expect(
        tester
            .widget<SizeTransition>(sizeTransitionAfterExpanded)
            .sizeFactor
            .value,
        greaterThan(0.0),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Pulling down from left or right screen edge does not trigger RefreshIndicator',
    (WidgetTester tester) async {
      final account = Account.microsoft(
        id: 'acct_ms',
        displayName: 'MS User',
        email: 'ms@example.com',
        microsoftUserId: 'cid1',
      );
      SharedPreferences.setMockInitialValues({
        'yata.accounts': jsonEncode([account.toJson()]),
        'yata.active_account_id': 'acct_ms',
      });
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(FakeAuthClient()),
            microsoftTodoApiProvider.overrideWithValue(FakeSubstrateApi()),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();

      final refreshIndicator = find.byType(RefreshIndicator);
      expect(refreshIndicator, findsOneWidget);

      // Drag diagonally down from the left edge (x = 16) -> must NOT pull out RefreshIndicator.
      final leftEdgeGesture = await tester.startGesture(const Offset(16, 300));
      await leftEdgeGesture.moveBy(const Offset(60, 200));
      await tester.pump();

      final sizeTransitionLeft = find.descendant(
        of: refreshIndicator,
        matching: find.byType(SizeTransition),
      );
      if (sizeTransitionLeft.evaluate().isNotEmpty) {
        expect(
          tester.widget<SizeTransition>(sizeTransitionLeft).sizeFactor.value,
          0.0,
        );
      }
      await leftEdgeGesture.up();
      await tester.pumpAndSettle();

      // Drag diagonally down from the right edge (x = 384) -> must NOT pull out RefreshIndicator.
      final rightEdgeGesture = await tester.startGesture(
        const Offset(384, 300),
      );
      await rightEdgeGesture.moveBy(const Offset(-60, 200));
      await tester.pump();

      final sizeTransitionRight = find.descendant(
        of: refreshIndicator,
        matching: find.byType(SizeTransition),
      );
      if (sizeTransitionRight.evaluate().isNotEmpty) {
        expect(
          tester.widget<SizeTransition>(sizeTransitionRight).sizeFactor.value,
          0.0,
        );
      }
      await rightEdgeGesture.up();
      await tester.pumpAndSettle();
    },
  );
}
