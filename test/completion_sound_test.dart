import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/providers/todo_provider.dart';
import 'package:yata/services/completion_sound_service.dart';
import 'package:yata/settings/settings_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/view/task_checkbox.dart';

class _FakeCompletionSoundService extends CompletionSoundService {
  _FakeCompletionSoundService(super.ref);

  int playAttempts = 0;

  @override
  Future<void> playIfEnabled() async {
    playAttempts += 1;
  }
}

void main() {
  testWidgets(
      'Play completion sound setting defaults to true, persists, and triggers on task completion',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    late _FakeCompletionSoundService fakeSound;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          completionSoundServiceProvider.overrideWith((ref) {
            fakeSound = _FakeCompletionSoundService(ref);
            return fakeSound;
          }),
        ],
        child: const YataApp(),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(YataApp)),
    );
    expect(container.read(todoProvider).playCompletionSound, isTrue);

    container.read(tasksViewPresenterProvider).addTask(title: 'Sound task');
    await tester.pumpAndSettle();

    // Complete task in task list -> triggers sound once
    await tester.tap(find.byType(TaskCheckbox).first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(fakeSound.playAttempts, 1);

    // Uncomplete task -> does NOT trigger sound
    await tester.tap(find.byType(TaskCheckbox).first);
    await tester.pumpAndSettle();
    expect(fakeSound.playAttempts, 1);

    // Toggle setting off in SettingsScreen -> persists
    await tester.tap(find.text('Local Account'));
    await tester.pumpAndSettle();
    expect(find.text('Play completion sound'), findsOneWidget);
    await tester.tap(find.text('Play completion sound'));
    await tester.pumpAndSettle();

    expect(container.read(todoProvider).playCompletionSound, isFalse);
    expect(prefs.getBool('yata.play_completion_sound'), isFalse);

    // Re-enable via presenter and confirm persistence
    container.read(settingsPresenterProvider).setPlayCompletionSound(true);
    expect(prefs.getBool('yata.play_completion_sound'), isTrue);
  });
}
