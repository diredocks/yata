import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/tasksview/completion_sound_service.dart';
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

class _RecordingAudioPlayer extends Fake implements AudioPlayer {
  int stopCalls = 0;
  final List<(Source, AudioContext?)> playCalls = [];

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playCalls.add((source, ctx));
  }
}

void main() {
  test(
    'CompletionSoundService plays with AndroidAudioFocus.none so other music is not paused',
    () async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts':
            '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
        'yata.active_account_id': 'test',
      });
      final prefs = await SharedPreferences.getInstance();
      final recordingPlayer = _RecordingAudioPlayer();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          completionSoundServiceProvider.overrideWith(
            (ref) => CompletionSoundService(
              ref,
              playerFactory: () => recordingPlayer,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(completionSoundServiceProvider).playIfEnabled();

      expect(recordingPlayer.stopCalls, 1);
      expect(recordingPlayer.playCalls, hasLength(1));
      final (source, ctx) = recordingPlayer.playCalls.single;
      expect(source, isA<AssetSource>());
      expect((source as AssetSource).path, 'sounds/wl_completion_sound.mp3');
      expect(ctx, isNotNull);
      expect(ctx!.android.audioFocus, AndroidAudioFocus.none);
      expect(ctx.android.contentType, AndroidContentType.sonification);
      expect(ctx.android.usageType, AndroidUsageType.assistanceSonification);
    },
  );

  testWidgets(
    'Play completion sound setting defaults to true, persists, and triggers on task completion',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
        'yata.active_account_id': 'test',
      });
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
      await tester.tap(find.text('Local User'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Play completion sound'), findsOneWidget);
      await tester.tap(find.text('Play completion sound'));
      await tester.pumpAndSettle();

      expect(container.read(todoProvider).playCompletionSound, isFalse);
      expect(prefs.getBool('yata.acct.test.play_completion_sound'), isFalse);

      // Re-enable via presenter and confirm persistence
      container.read(settingsPresenterProvider).setPlayCompletionSound(true);
      expect(prefs.getBool('yata.acct.test.play_completion_sound'), isTrue);
    },
  );
}
