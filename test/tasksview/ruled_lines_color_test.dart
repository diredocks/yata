import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/tasksview/recyclerview/ruled_lines_painter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/theme/todo_theme.dart';
import 'package:yata/data/storage/preferences.dart';

void main() {
  RuledLinesPainter findRuledLinesPainter(WidgetTester tester) {
    final customPaints = tester.widgetList<CustomPaint>(
      find.byType(CustomPaint),
    );
    return customPaints
        .map((w) => w.painter)
        .whereType<RuledLinesPainter>()
        .single;
  }

  testWidgets(
    'Task list background ruled lines use dark color in light mode regardless of list theme',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
        'yata.active_account_id': 'test',
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
      container.read(settingsPresenterProvider).setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();

      // Open My Day (photo theme by default).
      await tester.tap(find.text('My Day'));
      await tester.pumpAndSettle();
      expect(
        findRuledLinesPainter(tester).lineColor,
        TodoColors.taskViewDividerLight,
      );

      // Switch to saturated color (blue) in light mode -> still dark lines.
      final listId = container.read(todoProvider).selectedListId;
      container
          .read(tasksViewPresenterProvider)
          .changeListTheme(listId, ListThemeColor.blue);
      await tester.pumpAndSettle();
      expect(
        findRuledLinesPainter(tester).lineColor,
        TodoColors.taskViewDividerLight,
      );

      // Switch to light pastel color (lightBlue) in light mode -> dark lines.
      container
          .read(tasksViewPresenterProvider)
          .changeListTheme(listId, ListThemeColor.lightBlue);
      await tester.pumpAndSettle();
      expect(
        findRuledLinesPainter(tester).lineColor,
        TodoColors.taskViewDividerLight,
      );

      // Switch app to dark mode -> light lines for dark background.
      container.read(settingsPresenterProvider).setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(
        findRuledLinesPainter(tester).lineColor,
        TodoColors.taskViewDividerDark,
      );
    },
  );
}
