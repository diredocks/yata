import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/theme/todo_theme.dart';
import 'package:yata/data/preferences.dart';

void main() {
  testWidgets('Header shadow is part of the overscroll transformed subtree', (
    WidgetTester tester,
  ) async {
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
    for (var i = 1; i <= 25; i++) {
      presenter.addTask(title: 'Scroll task $i', targetListId: 'tasks');
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    final shadow = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration == TodoColors.horizontalShadowDecoration,
    );
    expect(shadow, findsOneWidget);

    // Overscroll stretch applies only to the inner content CustomScrollView's
    // viewport, leaving the header and its bottom shadow stationary.
    final contentIndicator = find.descendant(
      of: find.byType(CustomScrollView).last,
      matching: find.byType(StretchingOverscrollIndicator),
    );
    final headerIndicator = find.ancestor(
      of: find.byType(SliverAppBar),
      matching: find.byType(StretchingOverscrollIndicator),
    );
    final shadowIndicator = find.ancestor(
      of: shadow,
      matching: find.byType(StretchingOverscrollIndicator),
    );
    expect(contentIndicator, findsOneWidget);
    expect(headerIndicator, findsNothing);
    expect(shadowIndicator, findsNothing);

    // Overscrolling past the end must not throw or detach the shadow.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView).last),
    );
    await gesture.moveBy(const Offset(0, -400));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(shadow, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('Header shadow is hidden in reorder mode even when scrolled', (
    WidgetTester tester,
  ) async {
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
    for (var i = 1; i <= 25; i++) {
      presenter.addTask(title: 'Scroll task $i', targetListId: 'tasks');
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    final shadow = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration == TodoColors.horizontalShadowDecoration,
    );
    final shadowOpacity = find.ancestor(
      of: shadow,
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(shadowOpacity).opacity, 1.0);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();

    expect(tester.widget<AnimatedOpacity>(shadowOpacity).opacity, 0.0);

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(shadowOpacity).opacity, 0.0);

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(shadowOpacity).opacity, 1.0);
  });
}
