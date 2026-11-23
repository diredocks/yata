import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yata/detailview/steps/steps_section.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';

TaskItem _makeTask(String id, List<TaskStep> steps) {
  return TaskItem(
    id: id,
    listId: 'tasks',
    title: 'Parent',
    createdAt: DateTime(2026, 1, 1),
    steps: steps,
  );
}

void main() {
  testWidgets(
    'Adding a step animates height and opacity smoothly instead of snapping',
    (WidgetTester tester) async {
      var task = _makeTask('t1', const []);
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return StepsSection(
                  task: task,
                  backgroundColor: Colors.white,
                  onToggleStepCompleted: (_) {},
                  onRenameStep: (_, _) {},
                  onPromoteStepToTask: (_) {},
                  onDeleteStep: (_) {},
                  onAddStep: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final addStepRowFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.textInputAction == TextInputAction.next,
      );
      final initialAddStepY = tester
          .getTopLeft(addStepRowFinder)
          .dy;

      // Add a new step.
      setHostState(() {
        task = _makeTask('t1', const [
          TaskStep(id: 's1', title: 'Animated step'),
        ]);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final stepFinder = find.byKey(const ValueKey('step_s1'));
      expect(stepFinder, findsOneWidget);

      // Mid-animation: the step is expanding, so add-step row is between
      // initialAddStepY and its final settled Y.
      final midAddStepY = tester.getTopLeft(addStepRowFinder).dy;
      expect(midAddStepY, greaterThan(initialAddStepY));

      await tester.pumpAndSettle();
      final finalAddStepY = tester.getTopLeft(addStepRowFinder).dy;
      expect(finalAddStepY, greaterThan(midAddStepY));
    },
  );

  testWidgets(
    'Removing a step plays exit animation before disappearing',
    (WidgetTester tester) async {
      var task = _makeTask('t1', const [
        TaskStep(id: 's1', title: 'Step to delete'),
      ]);
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return StepsSection(
                  task: task,
                  backgroundColor: Colors.white,
                  onToggleStepCompleted: (_) {},
                  onRenameStep: (_, _) {},
                  onPromoteStepToTask: (_) {},
                  onDeleteStep: (_) {},
                  onAddStep: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      setHostState(() {
        task = _makeTask('t1', const []);
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      // Still visible while animating out.
      expect(find.byKey(const ValueKey('removing_step_s1')), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('removing_step_s1')), findsNothing);
      expect(find.text('Step to delete'), findsNothing);
    },
  );

  testWidgets(
    'Switching to a different task updates steps without cross-task animation',
    (WidgetTester tester) async {
      var task = _makeTask('t1', const [
        TaskStep(id: 's1', title: 'Task 1 step'),
      ]);
      late StateSetter setHostState;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return StepsSection(
                  task: task,
                  backgroundColor: Colors.white,
                  onToggleStepCompleted: (_) {},
                  onRenameStep: (_, _) {},
                  onPromoteStepToTask: (_) {},
                  onDeleteStep: (_) {},
                  onAddStep: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      setHostState(() {
        task = _makeTask('t2', const [
          TaskStep(id: 's2', title: 'Task 2 step'),
        ]);
      });
      await tester.pump();

      expect(find.byKey(const ValueKey('removing_step_s1')), findsNothing);
      expect(find.text('Task 2 step'), findsOneWidget);
    },
  );
}
