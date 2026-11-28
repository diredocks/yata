import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/todo_provider.dart';

/// Plays `assets/sounds/wl_completion_sound.mp3` when a task is completed
/// and `playCompletionSound` (`sound_checkoff_enabled`) is enabled, matching
/// `PlaySoundUseCase.java` (`yp/s1.java`).
class CompletionSoundService {
  CompletionSoundService(this._ref, {AudioPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? AudioPlayer.new;

  final Ref _ref;
  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;

  static final AudioContext _audioContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.assistanceSonification,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  Future<void> playIfEnabled() async {
    if (!_ref.read(todoProvider).playCompletionSound) return;
    try {
      final player = _player ??= _playerFactory();
      await player.stop();
      await player.play(
        AssetSource('sounds/wl_completion_sound.mp3'),
        ctx: _audioContext,
      );
    } on MissingPluginException {
      // Headless / widget test environments without platform audio plugin.
    } catch (_) {
      // Ignore audio backend errors so task completion never fails.
    }
  }
}

final completionSoundServiceProvider = Provider<CompletionSoundService>((ref) {
  return CompletionSoundService(ref);
});
