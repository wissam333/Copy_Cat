// lib/services/native_audio.dart — framework-only audio I/O over the
// "mimic_party/audio" channel (SAF picker + MediaPlayer).
//
// Used instead of file_picker / just_audio: their Android Gradle artifacts
// (AGP 8.5.x, ExoPlayer) are unreachable on this network, while the app's
// own AGP 9.1.0/Kotlin 2.4.0 toolchain is cached. Same behavior for the game.
import 'package:flutter/services.dart';

class NativeAudio {
  static const _ch = MethodChannel('mimic_party/audio');

  /// Opens the system audio picker, copies the file into app cache.
  /// Returns the cached path, or null when the user cancels.
  Future<String?> pickAudio() =>
      _ch.invokeMethod<String>('pickAudio');

  /// Plays [path] once, completing when playback finishes.
  Future<void> playOnce(String path) =>
      _ch.invokeMethod('playOnce', {'path': path});

  Future<void> stopPlayback() async {
    try {
      await _ch.invokeMethod('stopPlayback');
    } catch (_) {}
  }

  /// Decodes compressed audio to a cache WAV so pitch scoring sees real
  /// samples. Returns [path] unchanged when it is already WAV, or null
  /// when this platform cannot decode it.
  Future<String?> decodeToWav(String path) async {
    try {
      final out = await _ch.invokeMethod<String>('decodeToWav', {'path': path});
      if (out == null || out.isEmpty) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<Duration?> probeDuration(String path) async {
    try {
      final ms =
          await _ch.invokeMethod<int>('probeDurationMs', {'path': path});
      if (ms == null || ms <= 0) return null;
      return Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  /// Opens a URL in the phone's browser (e.g. myinstants trending page).
  Future<void> openUrl(String url) =>
      _ch.invokeMethod('openUrl', {'url': url});
}
