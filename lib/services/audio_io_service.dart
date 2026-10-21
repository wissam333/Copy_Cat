// lib/services/audio_io_service.dart — record + playback wrapper.
// record v7 (proven in ../flutter_application_1): AudioRecorder +
// RecordConfig(encoder wav, 44.1 kHz mono). Playback/probe go through
// NativeAudio (framework MediaPlayer) so the APK builds fully offline.
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'native_audio.dart';

class AudioIoService {
  final AudioRecorder _recorder = AudioRecorder();
  final NativeAudio _native = NativeAudio();

  Future<bool> ensureMicPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Records a WAV file at [path] for [recordFor]; returns stopped path.
  Future<String?> recordWav(String path, Duration recordFor) async {
    final ok = await ensureMicPermission();
    if (!ok) throw StateError('تم رفض إذن الميكروفون');
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 44100,
      numChannels: 1,
    );
    await _recorder.start(config, path: path);
    await Future<void>.delayed(recordFor);
    return _recorder.stop();
  }

  Future<void> cancelRecording() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  /// Plays [path] exactly once and completes when done.
  Future<void> playOnce(String path) => _native.playOnce(path);

  /// Live mic levels 0..1 (dBFS mapped) for drawing sound waves while
  /// recording. Emits only while the recorder is running.
  Stream<double> micLevels() =>
      _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .map((a) => ((a.current + 60) / 60).clamp(0.0, 1.0));

  Future<void> stopPlayback() => _native.stopPlayback();

  Future<String?> decodeToWav(String path) async {
    if (path.toLowerCase().endsWith('.wav')) return path;
    final out = await _native.decodeToWav(path);
    if (out == null || out.isEmpty) return null;
    if (!await File(out).exists()) return null;
    return out;
  }

  Future<Duration?> probeDuration(String path) =>
      _native.probeDuration(path);

  Future<String> tempWavPath(String name) async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}${Platform.pathSeparator}$name.wav';
  }

  Future<void> dispose() async {
    try {
      _recorder.dispose();
    } catch (_) {}
  }
}
