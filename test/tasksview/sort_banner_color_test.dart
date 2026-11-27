import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_bars.dart';
import 'package:yata/theme/todo_theme.dart';

void main() {
  TodoList buildList({
    required ListThemeColor themeColor,
    ListThemePhoto? themePhoto,
  }) {
    return TodoList(
      id: 'list-1',
      title: 'Test List',
      themeColor: themeColor,
      themePhoto: themePhoto,
      sortOption: TaskSortOption.dueDate,
    );
  }

  Future<Color?> pumpSortBannerAndGetBgColor(
    WidgetTester tester, {
    required Brightness brightness,
    required TodoList list,
  }) async {
    final headerFg = list.themePhoto != null
        ? Colors.white
        : TodoColors.headerForegroundFor(
            list.themeColor,
            brightness: brightness,
          );
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? TodoTheme.dark()
            : TodoTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return CustomScrollView(
                slivers: [
                  TasksSortBanner(
                    l10n: l10n,
                    currentList: list,
                    headerFg: headerFg,
                    onToggleSortDirection: () {},
                    onClearSort: () {},
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(TasksSortBanner),
        matching: find.byType(Container),
      ),
    );
    return (container.decoration as BoxDecoration?)?.color;
  }

  testWidgets(
    'TasksSortBanner uses dark translucent surface in dark mode even for light theme colors',
    (WidgetTester tester) async {
      final lightThemes = ListThemeColor.values.where(TodoColors.isLightTheme);
      for (final color in lightThemes) {
        final bgColor = await pumpSortBannerAndGetBgColor(
          tester,
          brightness: Brightness.dark,
          list: buildList(themeColor: color),
        );
        expect(
          bgColor,
          Colors.white.withValues(alpha: 0.10),
          reason:
              'Dark mode with $color should not use light-mode white 0.72 background',
        );
      }
    },
  );

  testWidgets(
    'TasksSortBanner uses dark translucent surface in dark mode for saturated theme colors',
    (WidgetTester tester) async {
      final bgColor = await pumpSortBannerAndGetBgColor(
        tester,
        brightness: Brightness.dark,
        list: buildList(themeColor: ListThemeColor.blue),
      );
      expect(bgColor, Colors.white.withValues(alpha: 0.10));
    },
  );

  testWidgets(
    'TasksSortBanner uses dark scrim for photo themes in both light and dark modes',
    (WidgetTester tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final bgColor = await pumpSortBannerAndGetBgColor(
          tester,
          brightness: brightness,
          list: buildList(
            themeColor: ListThemeColor.lightBlue,
            themePhoto: ListThemePhoto.beach,
          ),
        );
        expect(bgColor, Colors.black.withValues(alpha: 0.35));
      }
    },
  );

  testWidgets(
    'TasksSortBanner keeps light-mode background colors for solid color themes',
    (WidgetTester tester) async {
      final lightBg = await pumpSortBannerAndGetBgColor(
        tester,
        brightness: Brightness.light,
        list: buildList(themeColor: ListThemeColor.lightBlue),
      );
      expect(lightBg, Colors.white.withValues(alpha: 0.72));

      final saturatedBg = await pumpSortBannerAndGetBgColor(
        tester,
        brightness: Brightness.light,
        list: buildList(themeColor: ListThemeColor.blue),
      );
      expect(saturatedBg, Colors.black.withValues(alpha: 0.25));
    },
  );
}
