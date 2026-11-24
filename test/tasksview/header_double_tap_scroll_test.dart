import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

void main() {
  testWidgets('Double tapping task list header scrolls back to top', (
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

    // Scroll down so the header collapses and top task is off-screen
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    final nestedScroll = tester.widget<NestedScrollView>(
      find.byType(NestedScrollView),
    );
    final nestedState = tester.state<NestedScrollViewState>(
      find.byType(NestedScrollView),
    );
    expect(nestedScroll.controller!.offset, greaterThan(0));
    expect(nestedState.innerController.offset, greaterThan(0));

    // Double-tap on the SliverAppBar header
    final appBarCenter = tester.getCenter(find.byType(FlexibleSpaceBar));
    await tester.tapAt(appBarCenter);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(appBarCenter);
    await tester.pumpAndSettle();

    expect(nestedScroll.controller!.offset, 0.0);
    expect(nestedState.innerController.offset, 0.0);
  });
}
