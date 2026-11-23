import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/theme/todo_theme.dart';

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

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final shadow = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration == TodoColors.horizontalShadowDecoration,
    );
    expect(shadow, findsOneWidget);

    // The stretch overscroll effect wraps the scroll view and the shadow
    // together, so the shadow stays glued to the header while overscrolling.
    final scrollViewIndicator = find.ancestor(
      of: find.byType(CustomScrollView),
      matching: find.byType(StretchingOverscrollIndicator),
    );
    final shadowIndicator = find.ancestor(
      of: shadow,
      matching: find.byType(StretchingOverscrollIndicator),
    );
    expect(scrollViewIndicator, findsOneWidget);
    expect(shadowIndicator, findsOneWidget);
    expect(
      identical(
        tester.widget(scrollViewIndicator),
        tester.widget(shadowIndicator),
      ),
      isTrue,
    );

    // Overscrolling past the end must not detach the shadow from the header.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -400));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(shadow, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
