// tool/score_json.dart — parity oracle for voice-mimic-score.
//
// Runs the REAL game pipeline on two WAV files (room-tone gate, peak
// normalization of a copy, feature extraction, judge) and dumps everything
// to JSON so the TypeScript port can prove it produces identical numbers.
//
// usage:
//   dart run tool/score_json.dart TARGET.WAV PLAYER.WAV [--out OUT.json]
// With no --out the JSON is printed to stdout.

import 'dart:convert';
import 'dart:io';

import 'package:copy_cat/services/audio_scorer.dart';
import 'package:copy_cat/services/pitch_extractor.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  String? outPath;
  final flag = args.indexOf('--out');
  if (flag >= 0 && flag + 1 < args.length) outPath = args[flag + 1];

  if (positional.length < 2) {
    stderr.writeln('usage: dart run tool/score_json.dart TARGET PLAYER [--out OUT.json]');
    exit(1);
  }
  final target = positional[0];
  final player = positional[1];

  final result = <String, Object?>{
    'features': await rawFeatures(target, player),
    'diagnose': await rawDiagnose(target, player),
    'e2e': await endToEnd(target, player),
    'fixtures': {'targetPath': target, 'playerPath': player},
  };

  final json = jsonEncode(result);
  if (outPath != null) {
    await File(outPath).writeAsString(json, flush: true);
  } else {
    stdout.writeln(json);
  }
}

/// Features extracted from the ORIGINAL files — the exact byte inputs the
/// TypeScript port must re-extract and re-judge identically.
Future<Map<String, Object?>> rawFeatures(String target, String player) async {
  return {
    'targetPitch': await PitchExtractor.extract(target),
    'playerPitch': await PitchExtractor.extract(player),
    'targetEnergy': await PitchExtractor.energyEnvelope(target),
    'playerEnergy': await PitchExtractor.energyEnvelope(player),
    'targetMfcc': await PitchExtractor.extractMfcc(target),
    'playerMfcc': await PitchExtractor.extractMfcc(player),
  };
}

Future<Map<String, Object>> rawDiagnose(String target, String player) async {
  final tPitch = await PitchExtractor.extract(target);
  final pPitch = await PitchExtractor.extract(player);
  final tE = await PitchExtractor.energyEnvelope(target);
  final pE = await PitchExtractor.energyEnvelope(player);
  final tM = await PitchExtractor.extractMfcc(target);
  final pM = await PitchExtractor.extractMfcc(player);
  return AudioScorer.diagnose(
    tPitch,
    pPitch,
    targetEnergy: tE,
    playerEnergy: pE,
    targetMfcc: tM,
    playerMfcc: pM,
  );
}

/// Replicates AttemptScorer on a COPY of the player file (so we never mutate
/// the fixtures): raw room-tone gate → normalize copy to 0.5 → features →
/// judge → verdict + voicedPct.
Future<Map<String, Object?>> endToEnd(String target, String player) async {
  final dir = await Directory.systemTemp.createTemp('parity_');
  try {
    final playerCopy = '${dir.path}/player.wav';
    await File(player).copy(playerCopy);

    final rawEnergy = await PitchExtractor.energyEnvelope(playerCopy);
    if (AudioScorer.isRoomTone(rawEnergy)) {
      return {'total': 0, 'melody': 0, 'rhythm': 0, 'pitched': false, 'voicedPct': 0, 'note': 'silent'};
    }

    await PitchExtractor.normalizeToPeak(playerCopy, 0.5);
    final pPitch = await PitchExtractor.extract(playerCopy);
    if (pPitch.isEmpty) {
      return {'total': 0, 'melody': 0, 'rhythm': 0, 'pitched': false, 'voicedPct': 0, 'note': 'empty-pitch'};
    }

    final tPitch = await PitchExtractor.extract(target);
    final tE = await PitchExtractor.energyEnvelope(target);
    final pE = await PitchExtractor.energyEnvelope(playerCopy);
    final tM = await PitchExtractor.extractMfcc(target);
    final pM = await PitchExtractor.extractMfcc(playerCopy);
    final verdict = AudioScorer.judge(
      tPitch,
      pPitch,
      targetEnergy: tE,
      playerEnergy: pE,
      targetMfcc: tM,
      playerMfcc: pM,
    );
    final voiced = pPitch.where((f) => f > 0).length;
    return {
      'total': verdict.total,
      'melody': verdict.melody,
      'rhythm': verdict.rhythm,
      'pitched': verdict.pitched,
      'voicedPct': pPitch.isEmpty ? 0.0 : voiced / pPitch.length,
      'note': 'ok',
    };
  } finally {
    await dir.delete(recursive: true);
  }
}