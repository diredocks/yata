import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/ui/widgets/task_list_tile.dart';

Widget _wrapTile(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'Metadata hides past reminders, shows icon-only reminder when dueDate exists, and shows check when all steps complete',
    (WidgetTester tester) async {
      final now = DateTime.now();
      final futureReminder = now.add(const Duration(hours: 2));
      final taskWithDueAndReminder = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'With due and future reminder',
        createdAt: now,
        dueDate: DateTime(now.year, now.month, now.day),
        recurrence: RecurrenceType.daily,
        reminderAt: futureReminder,
        note: 'Some note',
        steps: const [
          TaskStep(id: 's1', title: 'Done step', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: _wrapTile(
            TaskListTile(
              task: taskWithDueAndReminder,
              showMyDayBadge: true,
              listName: 'Tasks',
              onTap: () {},
              onToggleCompleted: () {},
              onToggleImportant: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
      // Checkmark icon shown when all steps are completed
      expect(find.byIcon(Icons.check), findsOneWidget);
      // Repeat icon shown with due date
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      // Reminder icon shown, note icon shown
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
      // Dividers: Tasks • 1 of 1 • Today [repeat] • [bell][note] -> 3 dividers
      expect(find.text('•'), findsNWidgets(3));
    },
  );

  testWidgets('Past reminder is hidden from metadata bar', (
    WidgetTester tester,
  ) async {
    final now = DateTime.now();
    final pastReminderTask = TaskItem(
      id: 't2',
      listId: 'tasks',
      title: 'Past reminder task',
      createdAt: now,
      reminderAt: now.subtract(const Duration(hours: 1)),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: _wrapTile(
          TaskListTile(
            task: pastReminderTask,
            onTap: () {},
            onToggleCompleted: () {},
            onToggleImportant: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_none), findsNothing);
  });
}
