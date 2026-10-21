// Gemini-recipe scoring tests: MFCC timbre branch + signal normalization.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:copy_cat/services/attempt_scorer.dart';
import 'package:copy_cat/services/audio_scorer.dart';
import 'package:copy_cat/services/pitch_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> makeWav(String name, List<double> samples, int sr) async {
  final data = Uint8List(44 + samples.length * 2);
  final bd = ByteData.sublistView(data);
  void ascii(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      data[off + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  bd.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sr, Endian.little);
  bd.setUint32(28, sr * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bd.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 20000).round(),
        Endian.little);
  }
  final path = '${Directory.systemTemp.path}$Platform.pathSeparator$name';
  await File(path).writeAsBytes(data);
  return path;
}

Future<Map<String, dynamic>> feat(String path) async => {
      'pitch': await PitchExtractor.extract(path),
      'energy': await PitchExtractor.energyEnvelope(path),
      'mfcc': await PitchExtractor.extractMfcc(path),
    };

void main() {
  const sr = 44100;

  test('normalizeToPeak brings quiet audio to target, silence stays 0',
      () async {
    final quiet = List<double>.generate(
        sr * 2, (i) => 0.1 * sin(2 * pi * 300 * i / sr));
    final qp = await makeWav('norm_q.wav', quiet, sr);
    expect(await PitchExtractor.normalizeToPeak(qp, 0.5), isTrue);
    final peak = await PitchExtractor.peakOf(qp);
    expect(peak, inInclusiveRange(0.49, 0.51));

    final silent =
        await makeWav('norm_s.wav', List<double>.filled(sr, 0.0), sr);
    expect(await PitchExtractor.normalizeToPeak(silent, 0.5), isFalse);
    expect(await PitchExtractor.peakOf(silent), 0.0);
  });

  test('quiet mimic scores high after normalization', () async {
    final loud = List<double>.generate(
        sr * 4, (i) => 0.5 * sin(2 * pi * 300 * i / sr));
    final quiet = List<double>.generate(sr * 4, (i) {
      final t = i / sr;
      if (t < 0.4 || t > 3.6) return 0.0;
      return 0.07 * sin(2 * pi * 302 * i / sr);
    });
    final lp = await makeWav('fair_l.wav', loud, sr);
    final qp = await makeWav('fair_q.wav', quiet, sr);
    await PitchExtractor.normalizeToPeak(qp, 0.5);
    final lt = await PitchExtractor.extract(lp);
    final le = await PitchExtractor.energyEnvelope(lp);
    final at = await PitchExtractor.extract(qp);
    final ae = await PitchExtractor.energyEnvelope(qp);
    final verdict = AudioScorer.judge(lt, at,
        targetEnergy: le, playerEnergy: ae);
    expect(verdict.total, greaterThan(75));
  });

  test('identical noise scores 100 with MFCC, different noises score low',
      () async {
    List<double> bursts(int seed) {
      final r = Random(seed);
      return List<double>.generate(sr * 4, (i) {
        final burst = ((i / sr) % 0.7) < 0.12 ? 1.0 : 0.02;
        return burst * 0.5 * (r.nextDouble() * 2 - 1);
      });
    }

    List<double> rumble(int seed) {
      final r = Random(seed);
      var last = 0.0;
      return List<double>.generate(sr * 4, (i) {
        final t = i / sr;
        last = 0.92 * last + 0.08 * (r.nextDouble() * 2 - 1);
        return last * (0.4 + 0.3 * sin(2 * pi * 0.6 * t));
      });
    }

    final a = await feat(await makeWav('mf_a.wav', bursts(1), sr));
    final a2 = await feat(await makeWav('mf_a2.wav', bursts(1), sr));
    final b = await feat(await makeWav('mf_b.wav', rumble(2), sr));

    List<double> lp(List l) => l.map((e) => (e as num).toDouble()).toList();
    List<List<double>> lm(List l) => [
          for (final f in l)
            (f as List).map((e) => (e as num).toDouble()).toList()
        ];

    final same = AudioScorer.judge(
      lp(a['pitch'] as List), lp(a2['pitch'] as List),
      targetEnergy: lp(a['energy'] as List),
      playerEnergy: lp(a2['energy'] as List),
      targetMfcc: lm(a['mfcc'] as List),
      playerMfcc: lm(a2['mfcc'] as List),
    );
    expect(same.pitched, isFalse);
    expect(same.total, 100.0);

    final diff = AudioScorer.judge(
      lp(a['pitch'] as List), lp(b['pitch'] as List),
      targetEnergy: lp(a['energy'] as List),
      playerEnergy: lp(b['energy'] as List),
      targetMfcc: lm(a['mfcc'] as List),
      playerMfcc: lm(b['mfcc'] as List),
    );
    expect(diff.total, lessThan(60));
  });

  test('transposed tone ignores MFCC and still scores high', () async {
    double tone(double f, double amp, int i) =>
        amp * sin(2 * pi * f * i / sr);
    // Recordable takes have an onset and an offset: no human (and no
    // recording) starts and stops inside the same 50 ms window. A
    // mathematically flat envelope is room tone, which must score 0.
    double fade(int i, int n) {
      final edge = (sr * 0.15).round();
      final m = min(i, n - 1 - i);
      return m >= edge ? 1.0 : m / edge;
    }

    final n = sr * 3;
    final t = List<double>.generate(
        n, (i) => fade(i, n) * (tone(220, 0.5, i) + tone(330, 0.2, i)));
    final up = List<double>.generate(
        n, (i) => fade(i, n) * (tone(440, 0.5, i) + tone(660, 0.2, i)));
    final tp = await makeWav('mf_t.wav', t, sr);
    final upath = await makeWav('mf_u.wav', up, sr);
    final ft = await feat(tp);
    final fu = await feat(upath);

    List<double> lp(List l) => l.map((e) => (e as num).toDouble()).toList();
    List<List<double>> lm(List l) => [
          for (final f in l)
            (f as List).map((e) => (e as num).toDouble()).toList()
        ];
    final v = AudioScorer.judge(
      lp(ft['pitch'] as List), lp(fu['pitch'] as List),
      targetEnergy: lp(ft['energy'] as List),
      playerEnergy: lp(fu['energy'] as List),
      targetMfcc: lm(ft['mfcc'] as List),
      playerMfcc: lm(fu['mfcc'] as List),
    );
    expect(v.pitched, isTrue);
    expect(v.total, greaterThan(70));
  });

  test('scoreAttempt is deterministic for the same two wavs', () async {
    final n = sr * 2;
    // Pulses, not a flat tone: a steady sine is room tone and must score 0.
    double env(int i) {
      final t = i / sr;
      final burst = (t % 0.45) < 0.16;
      return burst ? 0.45 : 0.015;
    }

    final target = List<double>.generate(
        n, (i) => env(i) * sin(2 * pi * 220 * i / sr));
    final player = List<double>.generate(
        n, (i) => env(i) * 0.35 * sin(2 * pi * 330 * i / sr));
    final tp = await makeWav('att_t.wav', target, sr);
    final pp = await makeWav('att_p.wav', player, sr);
    final a = await AttemptScorer.score(targetPath: tp, playerPath: pp);
    final b = await AttemptScorer.score(targetPath: tp, playerPath: pp);
    expect(a.verdict.total, b.verdict.total);
    expect(a.verdict.melody, b.verdict.melody);
    expect(a.verdict.rhythm, b.verdict.rhythm);
    expect(a.verdict.pitched, b.verdict.pitched);
    expect(a.note, 'ok');
    expect(a.verdict.total, inInclusiveRange(0, 100));
  });
}
