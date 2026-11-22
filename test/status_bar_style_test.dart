import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

void main() {
  testWidgets(
      'Status bar icon brightness adapts to list theme colors and detail view',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
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
    container.read(settingsPresenterProvider).setUseDynamicColor(false);
    container.read(tasksViewPresenterProvider).addTask(title: 'Status bar task');
    await tester.pumpAndSettle();

    // HomeViewScreen (light surface) -> dark status bar icons.
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

    // Open My Day (default ListThemeColor.blue) -> light status bar icons.
    await tester.tap(find.text('My Day'));
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(
      SystemChrome.latestStyle?.statusBarIconBrightness,
      Brightness.light,
    );

    // Switch to light pastel color (lightBlue) -> dark status bar icons.
    final listId = container.read(todoProvider).selectedListId;
    container
        .read(tasksViewPresenterProvider)
        .changeListTheme(listId, ListThemeColor.lightBlue);
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

    // Switch to dark/saturated color (blue) -> light status bar icons.
    container
        .read(tasksViewPresenterProvider)
        .changeListTheme(listId, ListThemeColor.blue);
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(
      SystemChrome.latestStyle?.statusBarIconBrightness,
      Brightness.light,
    );

    // Switch to light pastel color (lightRose) -> dark status bar icons.
    container
        .read(tasksViewPresenterProvider)
        .changeListTheme(listId, ListThemeColor.lightRose);
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

    // Switch to photo theme -> light status bar icons.
    container.read(tasksViewPresenterProvider).changeListTheme(
          listId,
          ListThemeColor.blue,
          themePhoto: ListThemePhoto.beach,
        );
    await tester.pumpAndSettle();
    expect(
      SystemChrome.latestStyle?.statusBarIconBrightness,
      Brightness.light,
    );

    // Open DetailViewScreen in light mode -> dark status bar icons.
    await tester.tap(find.text('Status bar task'));
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarColor, Colors.transparent);
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);

    // Switch to dark mode while on DetailViewScreen -> light status bar icons.
    container.read(settingsPresenterProvider).setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      SystemChrome.latestStyle?.statusBarIconBrightness,
      Brightness.light,
    );
  });
}
