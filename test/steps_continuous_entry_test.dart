import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/main.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

void main() {
  testWidgets(
      'Submitting a step keeps focus on the add-step input for continuous entry',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
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
    container.read(tasksViewPresenterProvider).addTask(title: 'Parent task');
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Day'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Parent task'));
    await tester.pumpAndSettle();

    final addStepFieldFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.textInputAction == TextInputAction.next,
    );
    expect(addStepFieldFinder, findsOneWidget);

    // Tap add-step input, enter first step, and submit.
    await tester.tap(addStepFieldFinder);
    await tester.pumpAndSettle();
    await tester.enterText(addStepFieldFinder, 'First step');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(find.text('First step'), findsOneWidget);
    final fieldAfterFirst = tester.widget<TextField>(addStepFieldFinder);
    expect(fieldAfterFirst.controller?.text, isEmpty);
    expect(fieldAfterFirst.focusNode?.hasFocus, isTrue);

    // Immediately enter second step without re-tapping.
    await tester.enterText(addStepFieldFinder, 'Second step');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(find.text('Second step'), findsOneWidget);
    final fieldAfterSecond = tester.widget<TextField>(addStepFieldFinder);
    expect(fieldAfterSecond.controller?.text, isEmpty);
    expect(fieldAfterSecond.focusNode?.hasFocus, isTrue);

    // Submitting empty input unfocuses the field.
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(fieldAfterSecond.focusNode?.hasFocus, isFalse);

    // Focus Add Step again, enter a step, then tap Repeat:
    // Add Step must unfocus and must NOT regain focus after Repeat closes.
    await tester.tap(addStepFieldFinder);
    await tester.pumpAndSettle();
    await tester.enterText(addStepFieldFinder, 'Third step');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(fieldAfterSecond.focusNode?.hasFocus, isTrue);

    await tester.tap(find.text('Repeat'));
    await tester.pumpAndSettle();
    expect(fieldAfterSecond.focusNode?.hasFocus, isFalse);

    // Dismiss Repeat sheet by tapping Daily.
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(fieldAfterSecond.focusNode?.hasFocus, isFalse);
  });
}
