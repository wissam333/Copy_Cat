// lib/services/audio_io_service.dart — record + playback wrapper.
// record v7 (proven in ../flutter_application_1): AudioRecorder +
// RecordConfig(encoder wav, 44.1 kHz mono). Playback/probe go through
// NativeAudio (framework MediaPlayer) so the APK builds fully offline.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../i18n.dart';

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
  /// With [onPitch], records through the PCM stream instead so a live
  /// zero-crossing pitch estimate (~20 Hz updates) can guide the mimic.
  /// Any stream failure falls back to the proven file recorder — the take
  /// still records and scores, just without the pitch needle.
  Future<String?> recordWav(String path, Duration recordFor,
      {void Function(double hz)? onPitch}) async {
    final ok = await ensureMicPermission();
    if (!ok) throw StateError(t('تم رفض إذن الميكروفون'));
    if (onPitch != null) {
      try {
        return await _recordWavStream(path, recordFor, onPitch);
      } catch (_) {
        await cancelRecording();
      }
    }
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 44100,
      numChannels: 1,
    );
    await _recorder.start(config, path: path);
    await Future<void>.delayed(recordFor);
    return _recorder.stop();
  }

  static const int _sampleRate = 44100;

  Future<String?> _recordWavStream(
      String path, Duration recordFor, void Function(double hz) onPitch) async {
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    );
    final stream = await _recorder.startStream(config);
    final pcm = BytesBuilder(copy: false);
    final window = <int>[]; // last ~93 ms of samples for the pitch estimate
    final sub = stream.listen((chunk) {
      pcm.add(chunk);
      final even = chunk.length & ~1;
      if (even < 2) return;
      final bytes = Uint8List.fromList(chunk.sublist(0, even));
      final samples =
          Int16List.view(bytes.buffer, 0, even ~/ 2);
      window.addAll(samples);
      if (window.length > 4096) {
        window.removeRange(0, window.length - 4096);
      }
      onPitch(_zcPitch(window));
    });
    await Future<void>.delayed(recordFor);
    await sub.cancel();
    await _recorder.stop();
    final data = pcm.toBytes();
    if (data.length < _sampleRate) throw StateError('stream too short');
    await File(path).writeAsBytes(_wavFromPcm16(data, _sampleRate),
        flush: true);
    return path;
  }

  /// Zero-crossing pitch of [samples] (int16, 44.1 kHz mono). 0 = no
  /// reliable pitch (silence, noise floor, or outside 40–2000 Hz). This
  /// only feeds the live meter — scoring still reads the finished WAV.
  static double _zcPitch(List<int> samples) {
    final n = samples.length;
    if (n < 512) return 0;
    var sumSq = 0.0;
    var crossings = 0;
    var prev = samples[0];
    for (final s in samples) {
      sumSq += s * s;
      if ((prev < 0) != (s < 0)) crossings++;
      prev = s;
    }
    final rms = sqrt(sumSq / n) / 32768;
    if (rms < 0.01) return 0;
    final hz = (crossings / 2) * (_sampleRate / n);
    return (hz > 40 && hz < 2000) ? hz : 0;
  }

  /// 44-byte mono 16-bit WAV header around raw PCM bytes.
  static Uint8List _wavFromPcm16(Uint8List pcm, int sampleRate) {
    final out = Uint8List(44 + pcm.length);
    final bd = ByteData.sublistView(out);
    void ascii(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        out[off + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    bd.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bd.setUint32(40, pcm.length, Endian.little);
    out.setRange(44, out.length, pcm);
    return out;
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
  /// 50 ms ticks + a light EMA: 20 Hz reads as a smooth curve instead of
  /// 10 Hz steps, and the EMA kills per-tick flicker without visible lag.
  static const int micTicksPerSecond = 20;
  Stream<double> micLevels() {
    var prev = 0.0;
    return _recorder
        .onAmplitudeChanged(
            const Duration(milliseconds: 1000 ~/ micTicksPerSecond))
        .map((a) {
      final raw = ((a.current + 60) / 60).clamp(0.0, 1.0);
      prev += (raw - prev) * 0.55;
      return prev;
    });
  }

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
