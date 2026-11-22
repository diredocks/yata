import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/todo_provider.dart';

/// Plays `assets/sounds/wl_completion_sound.mp3` when a task is completed
/// and `playCompletionSound` (`sound_checkoff_enabled`) is enabled, matching
/// `PlaySoundUseCase.java` (`yp/s1.java`).
class CompletionSoundService {
  CompletionSoundService(this._ref);

  final Ref _ref;
  AudioPlayer? _player;

  Future<void> playIfEnabled() async {
    if (!_ref.read(todoProvider).playCompletionSound) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource('sounds/wl_completion_sound.mp3'));
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
