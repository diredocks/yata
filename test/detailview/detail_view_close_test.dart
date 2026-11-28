import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/detailview/detail_view_screen.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';
import 'package:yata/data/preferences.dart';

Future<ProviderContainer> _openTaskDetail(
  WidgetTester tester, {
  required String title,
}) async {
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
  container.read(tasksViewPresenterProvider).addTask(title: title);
  await tester.pumpAndSettle();

  await tester.tap(find.text('My Day'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.byType(DetailViewScreen), findsOneWidget);

  return container;
}

void main() {
  testWidgets('Task detail closes when its task disappears from state', (
    WidgetTester tester,
  ) async {
    final container = await _openTaskDetail(tester, title: 'Synced task');

    final taskId = container
        .read(todoProvider)
        .tasks
        .firstWhere((task) => task.title == 'Synced task')
        .id;
    container.read(detailViewPresenterProvider).deleteTask(taskId);
    await tester.pumpAndSettle();

    expect(find.byType(DetailViewScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Task removal during the closing transition keeps the list', (
    WidgetTester tester,
  ) async {
    final container = await _openTaskDetail(tester, title: 'Closing task');
    final taskId = container
        .read(todoProvider)
        .tasks
        .firstWhere((task) => task.title == 'Closing task')
        .id;

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    container.read(detailViewPresenterProvider).deleteTask(taskId);
    await tester.pumpAndSettle();

    expect(find.byType(TasksViewScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Task removal closes the detail view and any sheet above it', (
    WidgetTester tester,
  ) async {
    final container = await _openTaskDetail(tester, title: 'Sheet task');

    await tester.tap(find.byIcon(Icons.calendar_today_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    final taskId = container
        .read(todoProvider)
        .tasks
        .firstWhere((task) => task.title == 'Sheet task')
        .id;
    container.read(detailViewPresenterProvider).deleteTask(taskId);
    await tester.pumpAndSettle();

    expect(find.byType(DetailViewScreen), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(TasksViewScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Footer delete closes only the task detail', (
    WidgetTester tester,
  ) async {
    await _openTaskDetail(tester, title: 'Footer task');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.byType(DetailViewScreen), findsNothing);
    expect(find.byType(TasksViewScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
