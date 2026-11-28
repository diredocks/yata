import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/preferences.dart';
import 'package:yata/homewidget/home_widget_service.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/richentry/task_entry_sheet.dart';
import 'package:yata/tasksview/tasks_view_screen.dart';

import '../helpers/home_widget_fakes.dart';

final _quickAddTasks = Uri.parse('yata://widget/add?listId=tasks');

Future<FakeHomeWidgetTransport> _pumpApp(
  WidgetTester tester, {
  Uri? initialLaunchUri,
}) async {
  SharedPreferences.setMockInitialValues({
    'yata.accounts': '[{"id":"acct_a","displayName":"Alice","email":"alice@example.com","createdAt":"2026-01-01T00:00:00.000"}]',
    'yata.active_account_id': 'acct_a',
    'yata.acct.acct_a.last_entered_list_id': 'tasks',
  });
  final prefs = await SharedPreferences.getInstance();
  final transport = FakeHomeWidgetTransport()
    ..initialLaunchUri = initialLaunchUri;
  addTearDown(transport.closeStreams);

  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeWidgetServiceProvider.overrideWithValue(
          HomeWidgetService(transport),
        ),
      ],
      child: const YataApp(),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(TasksViewScreen), findsOneWidget);
  return transport;
}

void main() {
  testWidgets('quickAdd at launch shows the sheet over the restored list', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester, initialLaunchUri: _quickAddTasks);

    expect(find.byType(TaskEntrySheet), findsOneWidget);
  });

  testWidgets('quickAdd while the list is already shown opens the sheet', (
    WidgetTester tester,
  ) async {
    final transport = await _pumpApp(tester);
    expect(find.byType(TaskEntrySheet), findsNothing);

    // Nothing navigates here and nothing else repaints either, so the sheet
    // only shows up if a frame is scheduled for it.
    transport.clickedController.add(_quickAddTasks);
    await tester.pumpAndSettle();

    expect(find.byType(TasksViewScreen), findsOneWidget);
    expect(find.byType(TaskEntrySheet), findsOneWidget);
  });
}
