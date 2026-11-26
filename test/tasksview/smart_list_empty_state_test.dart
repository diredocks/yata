import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';
import 'package:yata/tasksview/tasks_view_widgets.dart';

void main() {
  Future<void> pumpList(
    WidgetTester tester, {
    required String listId,
    ListThemePhoto? photo,
  }) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'test',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              return TasksViewScreen(onOpenTask: (_) {});
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TasksViewScreen)),
    );
    final notifier = container.read(todoProvider.notifier);
    notifier.selectList(listId);
    if (photo != null) {
      final state = container.read(todoProvider);
      notifier.commit(
        state.copyWith(
          lists: [
            for (final l in state.lists)
              if (l.id == listId) l.copyWith(themePhoto: photo) else l,
          ],
        ),
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows illustration and prompt for important, planned, all, completed, tasks when empty',
    (tester) async {
      final expected = {
        'important': 'Try starring some tasks to see them here.',
        'planned': 'Tasks with due dates or reminders show up here.',
        'all': 'All your incomplete tasks show up here.',
        'completed': 'All your completed tasks show up here.',
        'tasks': 'Tasks show up here if they aren’t part of any lists you’ve created.',
      };

      for (final entry in expected.entries) {
        await pumpList(tester, listId: entry.key);
        expect(
          find.byKey(ValueKey('smart_list_empty_state_${entry.key}')),
          findsOneWidget,
        );
        expect(find.text(entry.value), findsOneWidget);
        expect(find.byType(TasksRuledLinesSliver), findsNothing);
      }
    },
  );

  testWidgets('does not show empty state for myDay and keeps ruled lines', (
    tester,
  ) async {
    await pumpList(tester, listId: 'my_day');
    expect(find.byType(SmartListEmptyState), findsNothing);
    expect(find.byType(TasksRuledLinesSliver), findsOneWidget);
  });

  testWidgets('uses scrim container on photo background', (tester) async {
    await pumpList(tester, listId: 'important', photo: ListThemePhoto.beach);
    final container = tester.widget<Container>(
      find.byKey(const ValueKey('smart_list_empty_state_important')),
    );
    final decoration = container.decoration as BoxDecoration?;
    expect(decoration?.color, const Color(0x99323232));
  });
}
