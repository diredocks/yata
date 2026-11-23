import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/richentry/task_entry_sheet.dart';

Widget _wrapSheet(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  final lists = [
    ...defaultSmartLists(),
    const TodoList(
      id: 'custom_1',
      title: 'Groceries',
      themeColor: ListThemeColor.green,
      icon: Icons.list,
    ),
  ];

  testWidgets('Tasks list and custom list hide list picker chip', (
    WidgetTester tester,
  ) async {
    final tasksList = lists.firstWhere(
      (l) => l.smartType == SmartListType.tasks,
    );

    await tester.pumpWidget(
      _wrapSheet(
        TaskEntrySheet(
          lists: lists,
          currentList: tasksList,
          onSubmit: ({
            required title,
            targetListId,
            dueDate,
            reminderAt,
            RecurrenceType recurrence = RecurrenceType.none,
          }) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('Add due date'), findsOneWidget);
  });

  testWidgets(
    'Planned list shows list picker chip and defaults due date to Today',
    (WidgetTester tester) async {
      final plannedList = lists.firstWhere(
        (l) => l.smartType == SmartListType.planned,
      );
      DateTime? submittedDueDate;

      await tester.pumpWidget(
        _wrapSheet(
          TaskEntrySheet(
            lists: lists,
            currentList: plannedList,
            onSubmit:
                ({
                  required title,
                  targetListId,
                  dueDate,
                  reminderAt,
                  RecurrenceType recurrence = RecurrenceType.none,
                }) {
                  submittedDueDate = dueDate;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // List picker chip is visible (defaults to Tasks)
      expect(find.byType(ActionChip), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      // Due date chip defaults to Today in Planned
      expect(find.text('Due Today'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Planned task');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      expect(submittedDueDate, DateTime(now.year, now.month, now.day));
      // Resets back to Due Today for the next entry in Planned
      expect(find.text('Due Today'), findsOneWidget);
    },
  );
}
