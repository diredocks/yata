import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/detailview/steps/steps_section.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/preferences.dart';

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
  test('DetailViewPresenter.reorderSteps updates step order and descending orderDateTime', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    // Trigger provider initialization.
    container.read(todoProvider);

    final tasksPresenter = container.read(tasksViewPresenterProvider);
    final detailPresenter = container.read(detailViewPresenterProvider);

    tasksPresenter.addTask(title: 'Task with steps');
    final taskId = container.read(todoProvider).tasks.single.id;

    detailPresenter.addStep(taskId, 'Step A');
    detailPresenter.addStep(taskId, 'Step B');
    detailPresenter.addStep(taskId, 'Step C');

    var steps = container.read(todoProvider).tasks.single.steps;
    expect(steps.map((s) => s.title).toList(), ['Step A', 'Step B', 'Step C']);
    expect(steps[0].orderDateTime!.isAfter(steps[1].orderDateTime!), isTrue);
    expect(steps[1].orderDateTime!.isAfter(steps[2].orderDateTime!), isTrue);

    // Move Step C (index 2) to top (index 0).
    detailPresenter.reorderSteps(taskId, 2, 0);
    steps = container.read(todoProvider).tasks.single.steps;
    expect(steps.map((s) => s.title).toList(), ['Step C', 'Step A', 'Step B']);
    expect(steps[0].orderDateTime!.isAfter(steps[1].orderDateTime!), isTrue);
    expect(steps[1].orderDateTime!.isAfter(steps[2].orderDateTime!), isTrue);

    // Move Step C (index 0) to middle (index 1).
    detailPresenter.reorderSteps(taskId, 0, 1);
    steps = container.read(todoProvider).tasks.single.steps;
    expect(steps.map((s) => s.title).toList(), ['Step A', 'Step C', 'Step B']);
    expect(steps[0].orderDateTime!.isAfter(steps[1].orderDateTime!), isTrue);
    expect(steps[1].orderDateTime!.isAfter(steps[2].orderDateTime!), isTrue);
  });

  testWidgets('Long-pressing and dragging a step reorders the list', (
    WidgetTester tester,
  ) async {
    var task = _makeTask('t1', const [
      TaskStep(id: 's1', title: 'First step'),
      TaskStep(id: 's2', title: 'Second step'),
      TaskStep(id: 's3', title: 'Third step'),
    ]);
    (int, int)? recordedMove;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ListView(
                children: [
                  StepsSection(
                    task: task,
                    backgroundColor: Colors.white,
                    onToggleStepCompleted: (_) {},
                    onRenameStep: (_, _) {},
                    onPromoteStepToTask: (_) {},
                    onDeleteStep: (_) {},
                    onAddStep: (_) {},
                    onReorderSteps: (oldIndex, newIndex) {
                      recordedMove = (oldIndex, newIndex);
                      setState(() {
                        final next = [...task.steps];
                        final moved = next.removeAt(oldIndex);
                        next.insert(newIndex, moved);
                        task = task.copyWith(steps: next);
                      });
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstCenter = tester.getCenter(find.text('First step'));
    final thirdCenter = tester.getCenter(find.text('Third step'));

    final gesture = await tester.startGesture(firstCenter);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    final totalDy = thirdCenter.dy + 20 - firstCenter.dy;
    const steps = 6;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, totalDy / steps));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recordedMove, (0, 2));
    expect(
      tester.getTopLeft(find.text('Second step')).dy,
      lessThan(tester.getTopLeft(find.text('First step')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Third step')).dy,
      lessThan(tester.getTopLeft(find.text('First step')).dy),
    );
  });

  testWidgets('Drag-and-drop is disabled while editing a step title', (
    WidgetTester tester,
  ) async {
    final task = _makeTask('t1', const [
      TaskStep(id: 's1', title: 'First step'),
      TaskStep(id: 's2', title: 'Second step'),
    ]);
    (int, int)? recordedMove;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListView(
            children: [
              StepsSection(
                task: task,
                backgroundColor: Colors.white,
                onToggleStepCompleted: (_) {},
                onRenameStep: (_, _) {},
                onPromoteStepToTask: (_) {},
                onDeleteStep: (_) {},
                onAddStep: (_) {},
                onReorderSteps: (oldIndex, newIndex) {
                  recordedMove = (oldIndex, newIndex);
                },
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap first step to enter inline edit mode.
    await tester.tap(find.text('First step'));
    await tester.pumpAndSettle();

    final listener = tester.widget<ReorderableDelayedDragStartListener>(
      find.byKey(const ValueKey('step_s1')),
    );
    expect(listener.enabled, isFalse);
    expect(recordedMove, isNull);
  });
}
