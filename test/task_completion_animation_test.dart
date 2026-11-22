import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/main.dart';
import 'package:yata/providers/todo_provider.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/view/task_checkbox.dart';

void main() {
  testWidgets(
      'Task list completion plays checkbox + confetti animation during 300ms delay before committing',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1024, 800);
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
    final presenter = container.read(tasksViewPresenterProvider);
    presenter.addTask(title: 'Animated list task');
    await tester.pumpAndSettle();

    // Tap the checkbox in the task list
    final listCheckbox = find.byType(TaskCheckbox).first;
    await tester.tap(listCheckbox);
    await tester.pump();

    // Immediately: checkbox is checked and confetti Lottie is playing,
    // while provider state is not yet committed (300ms MEDIUM delay).
    expect(tester.widget<TaskCheckbox>(listCheckbox).isChecked, isTrue);
    expect(find.byType(Lottie), findsOneWidget);
    expect(container.read(todoProvider).tasks.first.isCompleted, isFalse);

    // After 300ms delay, completion is committed to provider.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(container.read(todoProvider).tasks.first.isCompleted, isTrue);
  });

  testWidgets(
      'Tapping task list checkbox again within 300ms cancels pending completion',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1024, 800);
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
    container.read(tasksViewPresenterProvider).addTask(title: 'Cancelable task');
    await tester.pumpAndSettle();

    final listCheckbox = find.byType(TaskCheckbox).first;
    await tester.tap(listCheckbox);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<TaskCheckbox>(listCheckbox).isChecked, isTrue);

    // Tap again before 300ms elapses -> cancels pending completion
    await tester.tap(listCheckbox);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(container.read(todoProvider).tasks.first.isCompleted, isFalse);
  });

  testWidgets('Completing a step in detail view does not play confetti',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1024, 800);
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
    final presenter = container.read(tasksViewPresenterProvider);
    presenter.addTask(title: 'Task with step');
    await tester.pumpAndSettle();

    final taskId = container.read(todoProvider).tasks.first.id;
    container.read(detailViewPresenterProvider).addStep(taskId, 'Step 1');
    await tester.pumpAndSettle();

    // Open detail panel
    await tester.tap(find.text('Task with step'));
    await tester.pumpAndSettle();

    // Find step checkbox (showConfetti: false)
    final stepCheckboxes = find.byWidgetPredicate(
      (w) => w is TaskCheckbox && !w.showConfetti,
    );
    expect(stepCheckboxes, findsOneWidget);

    await tester.tap(stepCheckboxes);
    await tester.pump();
    expect(find.byType(Lottie), findsNothing);
    await tester.pumpAndSettle();
    expect(
      container.read(todoProvider).tasks.first.steps.first.isCompleted,
      isTrue,
    );
  });
}
