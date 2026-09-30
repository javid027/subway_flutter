import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// Centralizes every audio call so the rest of the game never touches
/// [FlameAudio] directly. If the background music asset hasn't been added
/// yet, calls fail silently instead of crashing gameplay.
class AudioManager {
  static const String backgroundMusicFile = 'background_music.mp3';

  bool _initialized = false;
  bool _musicAvailable = true;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await FlameAudio.bgm.initialize();
    } catch (e) {
      debugPrint('AudioManager: failed to initialize Bgm: $e');
    }
  }

  Future<void> playBackgroundMusic() async {
    if (!_musicAvailable) return;
    await _ensureInitialized();
    try {
      await FlameAudio.bgm.play(backgroundMusicFile, volume: 0.6);
    } catch (e) {
      _musicAvailable = false;
      debugPrint(
        'AudioManager: could not play "$backgroundMusicFile". '
        'Add the file to assets/audio/ to enable music. Error: $e',
      );
    }
  }

  Future<void> pauseBackgroundMusic() async {
    if (!_musicAvailable) return;
    try {
      await FlameAudio.bgm.pause();
    } catch (_) {}
  }

  Future<void> resumeBackgroundMusic() async {
    if (!_musicAvailable) return;
    try {
      await FlameAudio.bgm.resume();
    } catch (_) {}
  }

  Future<void> stopBackgroundMusic() async {
    if (!_musicAvailable) return;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }
}
