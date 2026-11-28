import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/storage/preferences.dart';

void main() {
  Future<ProviderContainer> pumpAppWithTasks(WidgetTester tester) async {
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
    final presenter = container.read(tasksViewPresenterProvider);
    presenter.addTask(title: 'First task');
    presenter.addTask(title: 'Second task');
    presenter.addTask(title: 'Third task');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Long-press enters multi-select first, and dragging to reorder automatically exits multi-select',
    (WidgetTester tester) async {
      final container = await pumpAppWithTasks(tester);

      final before = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(before.map((t) => t.title).toList(), [
        'Third task',
        'Second task',
        'First task',
      ]);

      final firstCenter = tester.getCenter(find.text('Third task'));
      final thirdCenter = tester.getCenter(find.text('First task'));
      final gesture = await tester.startGesture(firstCenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await tester.pump();

      // Long-press enters multi-select immediately before dragging and shows dot
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('selected_dot')), findsOneWidget);
      expect(find.byKey(const ValueKey('checked')), findsNothing);

      await gesture.moveTo(Offset(firstCenter.dx, thirdCenter.dy + 40));
      await tester.pump();

      // Dragging vertically exits multi-select immediately during the drag
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsNothing,
      );

      await gesture.up();
      await tester.pumpAndSettle();

      final after = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(after.map((t) => t.title).toList(), [
        'Second task',
        'Third task',
        'First task',
      ]);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Long-press without dragging enters multi-select mode without header height jump',
    (WidgetTester tester) async {
      await pumpAppWithTasks(tester);

      final headerTitleFinder = find.descendant(
        of: find.byType(NestedScrollView),
        matching: find.text('My Day'),
      );
      final beforeHeaderRect = tester.getRect(headerTitleFinder);
      final beforeTopY = tester.getTopLeft(find.text('Third task')).dy;

      await tester.longPress(find.text('Second task'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsOneWidget,
      );
      final afterTopY = tester.getTopLeft(find.text('Third task')).dy;
      expect(afterTopY, beforeTopY);
      expect(tester.getRect(headerTitleFinder), beforeHeaderRect);
    },
  );

  testWidgets(
    'Collapsed header stays collapsed when long-pressing to enter multi-select',
    (WidgetTester tester) async {
      await pumpAppWithTasks(tester);

      // Collapse the header by scrolling down
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      final collapsedTopY = tester.getTopLeft(find.text('Third task')).dy;

      await tester.longPress(find.text('Second task'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(find.text('Third task')).dy, collapsedTopY);

      // Partial scroll back in multi-select mode snaps header open
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();
      final nestedScroll = tester.widget<NestedScrollView>(
        find.byType(NestedScrollView),
      );
      expect(nestedScroll.controller!.offset, 0.0);
    },
  );

  testWidgets(
    'Non-default sort disables drag reordering and long-press enters multi-select',
    (WidgetTester tester) async {
      final container = await pumpAppWithTasks(tester);
      final presenter = container.read(tasksViewPresenterProvider);
      presenter.setListSortOption(
        container.read(todoProvider).selectedListId,
        TaskSortOption.alphabetical,
      );
      await tester.pumpAndSettle();

      final firstCenter = tester.getCenter(find.text('First task'));
      final thirdCenter = tester.getCenter(find.text('Third task'));
      final gesture = await tester.startGesture(firstCenter);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveTo(Offset(firstCenter.dx, thirdCenter.dy + 40));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final after = container
          .read(todoProvider)
          .tasksForList(container.read(todoProvider).selectedList);
      expect(after.map((t) => t.title).toList(), [
        'First task',
        'Second task',
        'Third task',
      ]);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Header photo image keeps full-screen height across browsing, multi-select, and reorder modes',
    (WidgetTester tester) async {
      final container = await pumpAppWithTasks(tester);
      final presenter = container.read(tasksViewPresenterProvider);
      presenter.changeListTheme(
        container.read(todoProvider).selectedListId,
        ListThemeColor.blue,
        themePhoto: ListThemePhoto.beach,
      );
      await tester.pumpAndSettle();

      final bgImageFinder = find.descendant(
        of: find.byKey(const ValueKey('bg_photo_beach')),
        matching: find.byType(Image),
      );
      final headerImageFinder = find.descendant(
        of: find.byKey(const ValueKey('header_photo_beach')),
        matching: find.byType(Image),
      );

      final expectedRect = tester.getRect(bgImageFinder);
      expect(expectedRect.height, 800.0);
      expect(tester.getRect(headerImageFinder), expectedRect);

      // Multi-select mode
      await tester.longPress(find.text('Second task'));
      await tester.pumpAndSettle();
      expect(tester.getRect(bgImageFinder), expectedRect);

      // Exit multi-select, enter reorder mode
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reorder'));
      await tester.pumpAndSettle();
      expect(tester.getRect(bgImageFinder), expectedRect);
    },
  );
}
