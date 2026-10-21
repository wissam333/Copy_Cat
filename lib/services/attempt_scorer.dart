// Shared post-record scoring for solo and LAN.
//
// Play / countdown / record stay in the caller. After a file exists, both
// modes must go through this function so the same two WAVs cannot produce
// two different totals.
import 'audio_scorer.dart';
import 'pitch_extractor.dart';

class AttemptScore {
  final ScoreVerdict verdict;
  final double voicedPct;
  final List<double> attemptWave;
  final String note;
  final String wavPath;

  const AttemptScore({
    required this.verdict,
    required this.voicedPct,
    required this.attemptWave,
    required this.note,
    required this.wavPath,
  });

  static const silent = AttemptScore(
    verdict: ScoreVerdict.zero,
    voicedPct: 0,
    attemptWave: [],
    note: 'silent',
    wavPath: '',
  );

  static const emptyPitch = AttemptScore(
    verdict: ScoreVerdict.zero,
    voicedPct: 0,
    attemptWave: [],
    note: 'empty-pitch',
    wavPath: '',
  );
}

class AttemptScorer {
  /// Decode if needed, gate room tone on the RAW envelope, peak-normalize
  /// the attempt, extract pitch + energy + MFCC on both files, judge.
  static Future<AttemptScore> score({
    required String targetPath,
    required String playerPath,
    Future<String?> Function(String path)? decodeToWav,
  }) async {
    Future<String> wavOf(String path) async {
      if (path.toLowerCase().endsWith('.wav')) return path;
      if (decodeToWav == null) return path;
      return (await decodeToWav(path)) ?? path;
    }

    final targetWav = await wavOf(targetPath);
    final playerWav = await wavOf(playerPath);

    final rawEnergy = await PitchExtractor.energyEnvelope(playerWav);
    if (AudioScorer.isRoomTone(rawEnergy)) {
      return AttemptScore(
        verdict: ScoreVerdict.zero,
        voicedPct: 0,
        attemptWave: const [],
        note: 'silent',
        wavPath: playerWav,
      );
    }

    await PitchExtractor.normalizeToPeak(playerWav, 0.5);

    final targetPitch = await PitchExtractor.extract(targetWav);
    final playerPitch = await PitchExtractor.extract(playerWav);
    if (playerPitch.isEmpty) {
      return AttemptScore(
        verdict: ScoreVerdict.zero,
        voicedPct: 0,
        attemptWave: const [],
        note: 'empty-pitch',
        wavPath: playerWav,
      );
    }

    final targetEnergy = await PitchExtractor.energyEnvelope(targetWav);
    final playerEnergy = await PitchExtractor.energyEnvelope(playerWav);
    final targetMfcc = await PitchExtractor.extractMfcc(targetWav);
    final playerMfcc = await PitchExtractor.extractMfcc(playerWav);

    final verdict = AudioScorer.judge(
      targetPitch,
      playerPitch,
      targetEnergy: targetEnergy,
      playerEnergy: playerEnergy,
      targetMfcc: targetMfcc,
      playerMfcc: playerMfcc,
    );

    final voiced = playerPitch.where((f) => f > 0).length;
    final voicedPct =
        playerPitch.isEmpty ? 0.0 : voiced / playerPitch.length;
    final attemptWave =
        await PitchExtractor.waveform(playerWav, buckets: 48);

    // Unpitched clips (claps, laughs) are allowed to have a low voiced
    // ratio. "silent" is only the room-tone / empty-mic case above.
    return AttemptScore(
      verdict: verdict,
      voicedPct: voicedPct,
      attemptWave: attemptWave,
      note: 'ok',
      wavPath: playerWav,
    );
  }
}
