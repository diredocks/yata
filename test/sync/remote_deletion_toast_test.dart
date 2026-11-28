import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/detailview/detail_view_screen.dart';
import 'package:yata/homeview/home_view_presenter.dart';
import 'package:yata/homeview/home_view_screen.dart';
import 'package:yata/l10n/app_localizations_en.dart';
import 'package:yata/main.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';

final _l10n = AppLocalizationsEn();

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(400, 800),
}) async {
  SharedPreferences.setMockInitialValues({
    'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
    'yata.active_account_id': 'test',
  });
  final prefs = await SharedPreferences.getInstance();

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const YataApp(),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(YataApp)));
}

/// Mimics a pull/realtime patch that no longer contains [taskId].
Future<void> _dropTaskRemotely(
  ProviderContainer container,
  String taskId,
) async {
  final notifier = container.read(todoProvider.notifier);
  final remaining = [
    for (final task in container.read(todoProvider).tasks)
      if (task.id != taskId) task,
  ];
  await notifier.applyRemoteState(tasks: remaining);
}

/// Mimics a pull/realtime patch whose folder tombstone removed [listId] and
/// every task it held.
Future<void> _dropListRemotely(
  ProviderContainer container,
  String listId,
) async {
  final notifier = container.read(todoProvider.notifier);
  final state = container.read(todoProvider);
  await notifier.applyRemoteState(
    lists: [
      for (final list in state.lists)
        if (list.id != listId) list,
    ],
    tasks: [
      for (final task in state.tasks)
        if (task.listId != listId) task,
    ],
  );
}

/// Pumps past the toast fade-in and any auto-close transition without
/// waiting for the toast's auto-dismiss timer.
Future<void> _pumpToastIn(WidgetTester tester) async {
  await tester.pumpAndSettle();
}

void main() {
  group('remote deletion toast', () {
    testWidgets('task removed remotely closes its detail with a toast', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container.read(tasksViewPresenterProvider).addTask(title: 'Synced task');
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synced task'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailViewScreen), findsOneWidget);

      final taskId = container
          .read(todoProvider)
          .tasks
          .firstWhere((task) => task.title == 'Synced task')
          .id;
      await _dropTaskRemotely(container, taskId);
      await _pumpToastIn(tester);

      expect(find.byType(DetailViewScreen), findsNothing);
      expect(find.text(_l10n.taskNoLongerExists), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locally deleted task closes its detail without a toast', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container.read(tasksViewPresenterProvider).addTask(title: 'Local task');
      await tester.pumpAndSettle();

      await tester.tap(find.text('My Day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local task'));
      await tester.pumpAndSettle();

      final taskId = container
          .read(todoProvider)
          .tasks
          .firstWhere((task) => task.title == 'Local task')
          .id;
      container.read(detailViewPresenterProvider).deleteTask(taskId);
      await _pumpToastIn(tester);

      expect(find.byType(DetailViewScreen), findsNothing);
      expect(find.text(_l10n.taskNoLongerExists), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('list removed remotely pops its screen with a toast', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container
          .read(homeViewPresenterProvider)
          .addList('Groceries', ListThemeColor.teal);
      await tester.pumpAndSettle();
      final listId = container.read(todoProvider).selectedListId;

      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.byType(TasksViewScreen), findsOneWidget);

      await _dropListRemotely(container, listId);
      await _pumpToastIn(tester);

      expect(find.byType(TasksViewScreen), findsNothing);
      expect(find.byType(HomeViewScreen), findsOneWidget);
      expect(find.text(_l10n.listNoLongerExists), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'task removed remotely closes the wide detail pane with a toast',
      (tester) async {
        final container = await _pumpApp(tester, size: const Size(1300, 900));
        container
            .read(tasksViewPresenterProvider)
            .addTask(title: 'Pinned task');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Pinned task'));
        await tester.pumpAndSettle();
        expect(find.byType(DetailViewScreen), findsOneWidget);

        final taskId = container
            .read(todoProvider)
            .tasks
            .firstWhere((task) => task.title == 'Pinned task')
            .id;
        await _dropTaskRemotely(container, taskId);
        await _pumpToastIn(tester);

        expect(find.byType(DetailViewScreen), findsNothing);
        expect(find.text(_l10n.taskNoLongerExists), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('list removed remotely also closes the task detail above it', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container
          .read(homeViewPresenterProvider)
          .addList('Groceries', ListThemeColor.teal);
      await tester.pumpAndSettle();
      final listId = container.read(todoProvider).selectedListId;
      container.read(tasksViewPresenterProvider).addTask(title: 'Milk');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailViewScreen), findsOneWidget);

      await _dropListRemotely(container, listId);
      await _pumpToastIn(tester);

      expect(find.byType(DetailViewScreen), findsNothing);
      expect(find.byType(TasksViewScreen), findsNothing);
      expect(find.byType(HomeViewScreen), findsOneWidget);
      expect(find.text(_l10n.taskNoLongerExists), findsNothing);
      expect(find.text(_l10n.listNoLongerExists), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('locally deleted list pops its screen without a toast', (
      tester,
    ) async {
      final container = await _pumpApp(tester);
      container
          .read(homeViewPresenterProvider)
          .addList('Errands', ListThemeColor.blue);
      await tester.pumpAndSettle();
      final listId = container.read(todoProvider).selectedListId;

      await tester.tap(find.text('Errands'));
      await tester.pumpAndSettle();

      container
          .read(todoProvider.notifier)
          .mutateEntities(
            lists: [
              for (final list in container.read(todoProvider).lists)
                if (list.id != listId) list,
            ],
            deletedListIds: {listId},
            tasks: [
              for (final task in container.read(todoProvider).tasks)
                if (task.listId != listId) task,
            ],
          );
      await _pumpToastIn(tester);

      expect(find.text(_l10n.listNoLongerExists), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
