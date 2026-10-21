import 'dart:io';
import 'dart:math';

import 'package:copy_cat/services/audio_scorer.dart';
import 'package:copy_cat/services/pitch_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical pitch maps score 100', () {
    final pitch = [220.0, 247.0, 262.0, 0.0, 330.0];
    expect(AudioScorer.calculateScore(pitch, List.of(pitch)), 100);
  });

  test('silence scores 0', () {
    expect(
      AudioScorer.calculateScore(
        <double>[220, 247, 262, 294, 330, 294],
        <double>[0, 0, 0, 0, 0, 0],
      ),
      0,
    );
  });

  test('same melody in another key scores high', () {
    final target = <double>[196, 220, 247, 262, 294, 330, 294, 262];
    final shifted = target.map((f) => f * pow(2, 7 / 12)).toList();
    expect(AudioScorer.calculateScore(target, shifted), greaterThan(90));
  });

  test('a close copy beats an inverted contour', () {
    final target = <double>[200, 230, 280, 320, 360, 320, 280];
    final close = <double>[198, 233, 276, 325, 355, 318, 284];
    final inverted = <double>[360, 320, 280, 230, 200, 230, 280];
    final closeScore = AudioScorer.calculateScore(target, close);
    final farScore = AudioScorer.calculateScore(target, inverted);
    expect(closeScore, greaterThan(farScore));
    expect(closeScore, greaterThan(80));
    expect(farScore, lessThan(70));
  });

  test('unpitched sounds score on energy, quiet attempts stay 0', () {
    final energy = [0.0, 0.05, 0.2, 0.05, 0.0, 0.25, 0.1, 0.0];
    final shifted = [0.0, 0.06, 0.18, 0.07, 0.0, 0.22, 0.09, 0.01];
    final clap = AudioScorer.judge(
      const [0, 0, 0, 0, 0, 0, 0, 0],
      const [0, 0, 0, 0, 0, 0, 0, 0],
      targetEnergy: energy,
      playerEnergy: shifted,
    );
    expect(clap.pitched, isFalse);
    expect(clap.total, greaterThan(70));

    final quiet = AudioScorer.judge(
      const [220, 247, 262, 294, 330],
      const [0, 0, 0, 0, 0],
      targetEnergy: const [0.2, 0.5, 0.4, 0.3, 0.2],
      playerEnergy: const [0.0, 0.001, 0.0, 0.002, 0.0],
    );
    expect(quiet.total, 0);
  });

  test('amplified room tone scores 0 even when YIN hallucinates pitch',
      () {
    // normalizeToPeak turns an empty room into peak-0.5 flat noise, and
    // YIN locks onto mains hum ~half the frames. That must still be 0.
    final noise = List<double>.filled(40, 0.5);
    final humPitch = [for (var i = 0; i < 40; i++) i.isEven ? 52.0 : 0.0];
    final v = AudioScorer.judge(
      [for (var i = 0; i < 40; i++) 200.0 + (i % 8) * 15.0],
      humPitch,
      targetEnergy: [for (var i = 0; i < 40; i++) (i % 10) / 10],
      playerEnergy: noise,
    );
    expect(v.total, 0);
  });

  test('flat noise against an unpitched meme sound scores 0', () {
    final meme = [for (var i = 0; i < 40; i++) (i % 7) / 7];
    final memeMfcc = [
      for (var i = 0; i < 40; i++) [1.0 + (i % 3), 0.5, -0.3]
    ];
    final v = AudioScorer.judge(
      List<double>.filled(40, 0),
      List<double>.filled(40, 0),
      targetEnergy: meme,
      playerEnergy: List<double>.filled(40, 0.5),
      targetMfcc: memeMfcc,
      playerMfcc: [
        for (var i = 0; i < 40; i++) [0.4, 0.4, 0.4]
      ],
    );
    expect(v.total, 0);
  });

  test('flat aaaa against varied speech scores low', () {
    // "say wallahi bro" contour vs one held vowel.
    final speech = <double>[180, 205, 168, 225, 190, 150, 212, 176];
    final flatAaa = List<double>.filled(8, 110.0);
    final v = AudioScorer.calculateScore(speech, flatAaa);
    expect(v, lessThanOrEqualTo(30));
    // The old contour cap glued every LAN take at exactly 18.
    expect(v, isNot(18));
  });

  test('a compressed but shaped contour is not glued to 18', () {
    final target = <double>[
      180, 205, 168, 225, 190, 150, 212, 176, 200, 160,
    ];
    final mean = target.reduce((a, b) => a + b) / target.length;
    // Half the range: a real, quieter contour. The old variance cap
    // glued this (and almost every LAN take) to exactly 18.
    final timid = [for (final f in target) mean + (f - mean) * 0.5];
    final v = AudioScorer.calculateScore(target, timid);
    expect(v, isNot(18));
    expect(v, greaterThan(40));
  });

  test('same melody an octave up stays high', () {
    final target = <double>[196, 220, 247, 262, 294, 330, 294, 262];
    final up = target.map((f) => f * 2).toList();
    expect(AudioScorer.calculateScore(target, up), greaterThanOrEqualTo(85));
  });

  test('unrelated contour scores low', () {
    final target = <double>[180, 205, 168, 225, 190, 150, 212, 176];
    // Same register, opposite shape. An octave-scrambled copy is a
    // different case (fold is supposed to forgive that).
    final other = <double>[240, 230, 220, 210, 200, 190, 175, 160];
    expect(AudioScorer.calculateScore(target, other), lessThanOrEqualTo(40));
    // A ramp played backwards has correlation -1. This phrase's own
    // reverse still shares its notes, so it is a weak fixture.
    final rising = <double>[140, 160, 180, 200, 230, 270, 320, 380];
    expect(
      AudioScorer.calculateScore(rising, rising.reversed.toList()),
      lessThanOrEqualTo(25),
    );
  });

  test('scores stay in 0..100 and are deterministic', () {
    final a = <double>[180, 220, 260, 200, 240, 180, 300, 160];
    final b = <double>[200, 190, 210, 400, 120, 180, 90, 250];
    final first = AudioScorer.calculateScore(a, b);
    final second = AudioScorer.calculateScore(a, b);
    expect(first, second);
    expect(first, inInclusiveRange(0, 100));
    expect(first.isNaN, isFalse);
  });

  test('narrow but shaped singing is not punished', () {
    final speech = <double>[180, 205, 168, 225, 190, 150, 212, 176];
    final mean = speech.reduce((a, b) => a + b) / speech.length;
    // Same contour at half range: a shy but real try.
    final narrow = [for (final f in speech) mean + (f - mean) * 0.5];
    expect(AudioScorer.calculateScore(speech, narrow), greaterThan(30));
  });

  test('flat voice still matches a flat beep in any key', () {
    final beep = List<double>.filled(8, 440.0);
    final otherKey = List<double>.filled(8, 330.0);
    expect(AudioScorer.calculateScore(beep, otherKey), greaterThan(90));
  });

  test('footsteps during a song score almost nothing', () {
    // Two dull thumps while the song plays: 10% voiced, sparse bursts.
    final song = <double>[180, 205, 168, 225, 190, 150, 212, 176];
    final songEnergy = <double>[0.3, 0.5, 0.4, 0.6, 0.5, 0.4, 0.5, 0.3];
    final thumps = List<double>.filled(40, 0.0);
    thumps[8] = 70.0;
    thumps[9] = 65.0;
    thumps[28] = 72.0;
    thumps[29] = 68.0;
    final thumpEnergy = List<double>.filled(40, 0.02);
    for (var i = 6; i < 12; i++) {
      thumpEnergy[i] = 0.4;
    }
    for (var i = 26; i < 32; i++) {
      thumpEnergy[i] = 0.45;
    }
    final v = AudioScorer.judge(
      [for (var i = 0; i < 5; i++) ...song],
      thumps,
      targetEnergy: [for (var i = 0; i < 5; i++) ...songEnergy],
      playerEnergy: thumpEnergy,
    );
    expect(v.total, lessThan(20));
  });

  test('one thump is not four claps', () {
    List<double> bursts(List<int> at, int n) {
      final e = List<double>.filled(n, 0.0);
      for (final i in at) {
        e[i] = 1.0;
        if (i + 1 < n) e[i + 1] = 0.9;
      }
      return e;
    }

    final n = 40;
    final mfcc = [
      for (var i = 0; i < n; i++) [0.8, 0.2, -0.1]
    ];
    final v = AudioScorer.judge(
      List<double>.filled(n, 0),
      List<double>.filled(n, 0),
      targetEnergy: bursts([5, 15, 25, 35], n),
      playerEnergy: bursts([13, 14, 15, 16, 17, 18], n),
      targetMfcc: mfcc,
      playerMfcc: mfcc,
    );
    // Identical timbre, decent shape — but 1 sustained burst vs 4 claps.
    expect(v.total, lessThan(55));
  });

  test('isRoomTone separates room tone from whispers', () {
    expect(AudioScorer.isRoomTone([]), isTrue);
    // Quiet room and loud flat hum: both tone.
    expect(AudioScorer.isRoomTone(List.filled(60, 0.004)), isTrue);
    expect(AudioScorer.isRoomTone(List.filled(60, 0.05)), isTrue);
    // Mouth-whisper: quiet but dynamic with syllable gaps.
    final whisper = [
      for (var i = 0; i < 60; i++) i % 12 < 4 ? 0.05 : 0.006
    ];
    expect(AudioScorer.isRoomTone(whisper), isFalse);
    // Held note with onset/offset: dynamic, a real try.
    final held = [
      for (var i = 0; i < 60; i++) (i < 5 || i > 54) ? 0.01 : 0.2
    ];
    expect(AudioScorer.isRoomTone(held), isFalse);
  });

  test('teleporting target grades timing not pitch', () async {
    // Real regression pair: the distorted "ogre" clip scored 3 before
    // the reliability guard (pitch graded against detector noise).
    // Same files the forensics tool measured: total 47, melody 0.
    final tmp = await Directory.systemTemp.createTemp('ogre');
    try {
      final target = await File('test/fixtures/ogre_target.wav')
          .copy('${tmp.path}/target.wav');
      final attempt = await File('test/fixtures/ogre_attempt.wav')
          .copy('${tmp.path}/attempt.wav');
      final rawEnergy =
          await PitchExtractor.energyEnvelope(attempt.path);
      expect(AudioScorer.isRoomTone(rawEnergy), isFalse);
      await PitchExtractor.normalizeToPeak(attempt.path, 0.5);
      final targetPitch = await PitchExtractor.extract(target.path);
      final playerPitch = await PitchExtractor.extract(attempt.path);
      final v = AudioScorer.judge(
        targetPitch,
        playerPitch,
        targetEnergy: await PitchExtractor.energyEnvelope(target.path),
        playerEnergy: await PitchExtractor.energyEnvelope(attempt.path),
        targetMfcc: await PitchExtractor.extractMfcc(target.path),
        playerMfcc: await PitchExtractor.extractMfcc(attempt.path),
      );
      // Fair band for a good-effort take on an unmatchable clip:
      // far from the broken ~3, far from a freebie handout.
      expect(v.total, inInclusiveRange(40, 55));
      expect(v.melody, 0);
      final d = AudioScorer.diagnose(
        targetPitch,
        playerPitch,
        targetEnergy: await PitchExtractor.energyEnvelope(target.path),
        playerEnergy: await PitchExtractor.energyEnvelope(attempt.path),
        targetMfcc: await PitchExtractor.extractMfcc(target.path),
        playerMfcc: await PitchExtractor.extractMfcc(attempt.path),
      );
      expect(d['kind'], 'tonal');
      expect(d['sPitch'], -1); // pitch dropped: unjudgeable target
      expect(d['staticMul'], 1.0); // steadiness not punished vs chaos
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('same shape with shifted timing still matches', () {
    // A dip one frame later is warp, not a different melody.
    // Resample-correlation scored this ~7; path-rank must stay high.
    final a = <double>[200, 200, 120, 200, 200, 220, 220, 220];
    final b = <double>[200, 200, 200, 120, 200, 200, 220, 220];
    expect(AudioScorer.calculateScore(a, b), greaterThan(70));
  });

  test('exact copy of a teleporting target still scores 100', () {    final chaos = <double>[
      for (var i = 0; i < 24; i++) i.isEven ? 120.0 : 240.0
    ];
    final env = <double>[
      0.02, 0.02, 0.50, 0.60, 0.40, 0.03, 0.02, 0.55, 0.50, 0.03, 0.02, 0.02,
      0.45, 0.60, 0.35, 0.02, 0.50, 0.55, 0.03, 0.02, 0.40, 0.50, 0.03, 0.02,
    ];
    final mfcc = [
      for (var i = 0; i < 24; i++) [1.0, 0.5, -0.3]
    ];
    final v = AudioScorer.judge(
      chaos,
      List<double>.of(chaos),
      targetEnergy: env,
      playerEnergy: List<double>.of(env),
      targetMfcc: mfcc,
      playerMfcc: mfcc.map(List<double>.of).toList(),
    );
    expect(v.total, 100);
  });

  test('verdict carries per-axis grades for the reveal meters', () {
    // Tonal: every frame voiced → pitch axis graded and present.
    final target = [220.0, 247.0, 262.0, 294.0, 330.0, 294.0, 262.0];
    final v = AudioScorer.judge(List.of(target), List.of(target));
    expect(v.kind, 'tonal');
    expect(v.pitched, isTrue);
    expect(v.pitch, greaterThanOrEqualTo(60));
    // No energy data → no timing axis: it is "missing" (−1), and the
    // reveal only shows axes that carried weight.
    expect(v.timing, -1);
    expect(v.total, greaterThan(80));
    expect(v.timbre, -1);
    expect(v.energy, -1);

    // A clap: noise class. Pitch carried no weight — the axis slot shows
    // the computed 0 (all frames unvoiced), still never shown for noise.
    final clap = AudioScorer.judge(
      const [0, 0, 0, 0, 0, 0, 0, 0],
      const [0, 0, 0, 0, 0, 0, 0, 0],
      targetEnergy: const [0.0, 0.5, 0.2, 0.4, 0.1, 0.3, 0.2, 0.0],
      playerEnergy: const [0.0, 0.45, 0.2, 0.4, 0.1, 0.3, 0.2, 0.0],
    );
    expect(clap.kind, 'noise');
    expect(clap.pitched, isFalse);
    expect(clap.energy, greaterThanOrEqualTo(0));
    expect(clap.energy, lessThanOrEqualTo(100));
    expect(clap.timing, greaterThanOrEqualTo(0));
    expect(clap.timbre, -1);

    // Silence: nothing was graded — every axis is missing, but the clip
    // class is still known so the reveal can caption it.
    final silent = AudioScorer.judge(
      target,
      const [0, 0, 0, 0, 0, 0, 0],
      targetEnergy: const [0.2, 0.5, 0.4, 0.3, 0.2, 0.1, 0.2],
      playerEnergy: const [0.0, 0.001, 0.0, 0.002, 0.0, 0.0, 0.0],
    );
    expect(silent.total, 0);
    expect(silent.kind, 'tonal');
    expect(silent.pitch, -1);
    expect(silent.timing, -1);
    expect(silent.melody, 0);
    expect(silent.rhythm, 0);
  });

  test('an empty noise target still captions its class on a zero', () {
    // No energy, no MFCC → every axis is missing. The zeroKinded path
    // keeps the clip class so the reveal knows what was attempted.
    final v = AudioScorer.judge(
      const [0, 0, 0, 0, 0],
      const [0, 0, 0, 0, 0],
    );
    expect(v.total, 0);
    expect(v.kind, 'noise');
    expect(v.pitched, isFalse);
    expect(v.pitch, -1);
    expect(v.timbre, -1);
  });
}
