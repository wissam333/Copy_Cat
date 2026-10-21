// tool/analyze_attempt.dart — forensics for a real (target, attempt) pair.
//
// Usage: dart run tool/analyze_attempt.dart target.wav attempt.wav
//
// Runs the exact AttemptScorer feature path (room-tone gate on the raw
// envelope, in-place peak normalize of a COPY, pitch + energy + MFCC on
// both files) and prints every axis, gate, and multiplier via
// AudioScorer.diagnose. -1 means "axis missing, weight renormalized".
import 'dart:io';
import 'dart:math';

import 'package:copy_cat/services/audio_scorer.dart';
import 'package:copy_cat/services/pitch_extractor.dart';

String _contour(List<double> hz) {
  final shown = hz.take(52).map((f) => f <= 0 ? '.' : f.round().toString());
  return '[${shown.join(' ')}]${hz.length > 52 ? '…(${hz.length})' : ''}';
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: dart run tool/analyze_attempt.dart '
        '<target.wav> <attempt.wav>');
    exit(1);
  }
  final targetPath = args[0];
  var playerPath = args[1];

  final rawEnergy = await PitchExtractor.energyEnvelope(playerPath);
  if (rawEnergy.isEmpty) {
    print('EMPTY attempt energy envelope');
    exit(2);
  }
  final sorted = [...rawEnergy]..sort();
  final peak = sorted.last;
  final p05 = sorted[(sorted.length * 0.05).floor()];
  final p90 = sorted[(sorted.length * 0.9).floor()];
  print('attempt raw: frames=${rawEnergy.length} peak=${peak.toStringAsFixed(4)} '
      'p05=${p05.toStringAsFixed(4)} p90=${p90.toStringAsFixed(4)} '
      'flatRatio=${(p90 / max(p05, 1e-9)).toStringAsFixed(2)}');
  print('isRoomTone=${AudioScorer.isRoomTone(rawEnergy)}');

  // The app normalizes the attempt file in place: work on a copy.
  final work =
      await File(playerPath).copy('${playerPath}.forensics-tmp.wav');
  playerPath = work.path;
  try {
    await PitchExtractor.normalizeToPeak(playerPath, 0.5);

    final targetPitch = await PitchExtractor.extract(targetPath);
    final playerPitch = await PitchExtractor.extract(playerPath);
    final targetEnergy = await PitchExtractor.energyEnvelope(targetPath);
    final playerEnergy = await PitchExtractor.energyEnvelope(playerPath);
    final targetMfcc = await PitchExtractor.extractMfcc(targetPath);
    final playerMfcc = await PitchExtractor.extractMfcc(playerPath);

    print('target pitch : ${_contour(targetPitch)}');
    print('player pitch : ${_contour(playerPitch)}');
    print('mfcc frames  : target=${targetMfcc.length} '
        'player=${playerMfcc.length}');

    final d = AudioScorer.diagnose(
      targetPitch,
      playerPitch,
      targetEnergy: targetEnergy,
      playerEnergy: playerEnergy,
      targetMfcc: targetMfcc,
      playerMfcc: playerMfcc,
    );
    for (final e in d.entries) {
      final v = e.value;
      print('${e.key}=${v is double ? v.toStringAsFixed(4) : v}');
    }
  } finally {
    try {
      await work.delete();
    } catch (_) {}
  }
}
