import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/storage/todo_repository.dart';
import 'package:yata/data/lists/todo_settings_store.dart';
import 'package:yata/detailview/detail_view_screen.dart';
import 'package:yata/detailview/details/detail_cards.dart';
import 'package:yata/detailview/note/note_card_view.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/settings/settings_screen.dart';
import 'package:yata/theme/todo_theme.dart';
import 'package:yata/data/storage/preferences.dart';

void main() {
  test('TodoTheme applies dynamicColorScheme when provided and falls back when null', () {
    final dynamicLight = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00897B),
      brightness: Brightness.light,
    );
    final dynamicDark = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00897B),
      brightness: Brightness.dark,
    );

    final themedLight = TodoTheme.light(dynamicColorScheme: dynamicLight);
    expect(themedLight.colorScheme.primary, dynamicLight.primary);
    expect(themedLight.scaffoldBackgroundColor, dynamicLight.surface);
    expect(themedLight.appBarTheme.backgroundColor, dynamicLight.surface);

    final themedDark = TodoTheme.dark(dynamicColorScheme: dynamicDark);
    expect(themedDark.colorScheme.primary, dynamicDark.primary);
    expect(themedDark.scaffoldBackgroundColor, dynamicDark.surface);

    final fallbackLight = TodoTheme.light();
    expect(fallbackLight.colorScheme.primary, TodoColors.attentionLight);
    expect(
      fallbackLight.scaffoldBackgroundColor,
      TodoColors.primaryBackgroundLight,
    );
  });

  testWidgets('SettingsScreen toggles and persists useDynamicColor', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Use system dynamic color'), 200);
    await tester.pumpAndSettle();

    final switchTile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Use system dynamic color'),
    );
    expect(switchTile.value, isTrue);

    await tester.tap(find.text('Use system dynamic color'));
    await tester.pumpAndSettle();

    final reloaded = TodoSettingsStore(prefs).load();
    expect(reloaded.useDynamicColor, isFalse);
  });

  testWidgets(
    'DetailViewScreen follows dynamic background and NoteCardView matches card width',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = TodoRepository.forAccount(prefs);
      final task = TaskItem(
        id: 't_detail',
        listId: 'tasks',
        title: 'Check detail layout',
        createdAt: DateTime(2026, 11, 22),
      );
      await repository.saveTasks([task]);

      final dynamicLight = ColorScheme.fromSeed(
        seedColor: const Color(0xFF00897B),
        brightness: Brightness.light,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: TodoTheme.light(dynamicColorScheme: dynamicLight),
            home: DetailViewScreen(taskId: task.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(scaffold.backgroundColor, dynamicLight.surface);

      final myDayWidth = tester.getSize(find.byType(MyDayCardView)).width;
      final scheduleWidth = tester
          .getSize(find.byType(TaskSchedulingCardView))
          .width;
      final noteWidth = tester.getSize(find.byType(NoteCardView)).width;
      expect(noteWidth, myDayWidth);
      expect(noteWidth, scheduleWidth);
    },
  );
}
