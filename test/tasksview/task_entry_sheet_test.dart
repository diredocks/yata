import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yata/data/tasks/recurrence.dart';
import 'package:yata/ui/widgets/task_pickers.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/l10n/app_localizations_en.dart';
import 'package:yata/models/default_lists.dart';
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
            rawRecurrence,
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
                  rawRecurrence,
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

  testWidgets('Repeat chip supports Custom recurrence dialog', (
    WidgetTester tester,
  ) async {
    final tasksList = lists.firstWhere(
      (l) => l.smartType == SmartListType.tasks,
    );
    Map<String, dynamic>? submittedRaw;

    await tester.pumpWidget(
      _wrapSheet(
        TaskEntrySheet(
          lists: lists,
          currentList: tasksList,
          onSubmit:
              ({
                required title,
                targetListId,
                dueDate,
                reminderAt,
                RecurrenceType recurrence = RecurrenceType.none,
                rawRecurrence,
              }) {
                submittedRaw = rawRecurrence;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    expect(find.text('Custom'), findsOneWidget);

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('Repeat every...'), findsOneWidget);

    // Enter interval = 2 in the dialog TextField (last TextField in tree).
    await tester.enterText(find.byType(TextField).last, '2');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Chip label reflects custom interval.
    expect(find.textContaining('Every 2 weeks'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Custom repeat task');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(submittedRaw?['RecurrenceType'], 'Custom');
    expect(submittedRaw?['IntervalType'], 'Weeks');
    expect(submittedRaw?['Interval'], 2);
  });

  testWidgets(
    'List picker menu separates smart lists and custom lists with a divider',
    (WidgetTester tester) async {
      final plannedList = lists.firstWhere(
        (l) => l.smartType == SmartListType.planned,
      );
      String? submittedTargetListId;

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
                  rawRecurrence,
                }) {
                  submittedTargetListId = targetListId;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();

      expect(find.byType(Divider), findsOneWidget);
      final tasksFinder = find.widgetWithText(ListTile, 'Tasks');
      final dividerFinder = find.byType(Divider);
      final groceriesFinder = find.widgetWithText(ListTile, 'Groceries');
      expect(tasksFinder, findsOneWidget);
      expect(groceriesFinder, findsOneWidget);
      expect(
        tester.getCenter(tasksFinder).dy,
        lessThan(tester.getCenter(dividerFinder).dy),
      );
      expect(
        tester.getCenter(dividerFinder).dy,
        lessThan(tester.getCenter(groceriesFinder).dy),
      );

      await tester.tap(groceriesFinder);
      await tester.pumpAndSettle();

      expect(find.text('Groceries'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Buy milk');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      expect(submittedTargetListId, 'custom_1');
    },
  );

  testWidgets(
    'List picker menu omits divider when no custom lists are present',
    (WidgetTester tester) async {
      final smartOnly = defaultSmartLists();
      final plannedList = smartOnly.firstWhere(
        (l) => l.smartType == SmartListType.planned,
      );

      await tester.pumpWidget(
        _wrapSheet(
          TaskEntrySheet(
            lists: smartOnly,
            currentList: plannedList,
            onSubmit: ({
              required title,
              targetListId,
              dueDate,
              reminderAt,
              RecurrenceType recurrence = RecurrenceType.none,
              rawRecurrence,
            }) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Tasks'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    },
  );

  test('formatRecurrenceLabel and computeNextDueDate handle custom rules', () {
    final l10n = AppLocalizationsEn();
    final every2Days = <String, dynamic>{
      'RecurrenceType': 'Custom',
      'IntervalType': 'Days',
      'Interval': 2,
    };
    expect(
      formatRecurrenceLabel(l10n, RecurrenceType.daily, every2Days),
      'Every 2 days',
    );
    expect(
      computeNextDueDate(
        DateTime(2026, 11, 26),
        RecurrenceType.daily,
        rawRecurrence: every2Days,
      ),
      DateTime(2026, 11, 28),
    );

    final monWedEvery2Weeks = <String, dynamic>{
      'RecurrenceType': 'Custom',
      'IntervalType': 'Weeks',
      'Interval': 2,
      'WeekDays': ['Monday', 'Wednesday'],
    };
    expect(
      formatRecurrenceLabel(l10n, RecurrenceType.weekly, monWedEvery2Weeks),
      'Every 2 weeks on Mon, Wed',
    );
    // Mon 2026-11-23 -> next in same week is Wed 2026-11-25
    expect(
      computeNextDueDate(
        DateTime(2026, 11, 23),
        RecurrenceType.weekly,
        rawRecurrence: monWedEvery2Weeks,
      ),
      DateTime(2026, 11, 25),
    );
    // Wed 2026-11-25 -> skip 1 week, next is Mon 2026-12-07
    expect(
      computeNextDueDate(
        DateTime(2026, 11, 25),
        RecurrenceType.weekly,
        rawRecurrence: monWedEvery2Weeks,
      ),
      DateTime(2026, 12, 7),
    );
  });
}
