// lib/services/turn_runner.dart — the one automated turn script, run only
// on the phone whose turn it is: play synced challenge once → 3 s
// countdown → record for the challenge duration → judge locally.
// The result carries a `note` code so a 0 is always explainable.
import 'dart:async';

import '../state/game_state.dart';
import 'attempt_scorer.dart';
import 'audio_io_service.dart';
import 'audio_scorer.dart';

class TurnResult {
  final double score;
  final double melody;
  final double rhythm;
  final bool pitched;
  final String? attemptPath;
  final double voicedPct;
  final List<double> attemptWave;
  final String note;

  /// Full per-axis breakdown for the reveal meters (feature: real reveal
  /// shows the axes of the graded clip, not just melody/rhythm).
  final ScoreVerdict verdict;
  const TurnResult({
    required this.score,
    required this.melody,
    required this.rhythm,
    required this.pitched,
    required this.attemptPath,
    required this.voicedPct,
    required this.attemptWave,
    required this.verdict,
    this.note = '',
  });

  static TurnResult _zero({String note = ''}) => TurnResult(
        score: 0,
        melody: 0,
        rhythm: 0,
        pitched: false,
        attemptPath: null,
        voicedPct: 0,
        attemptWave: [],
        verdict: ScoreVerdict.zero,
        note: note,
      );

  TurnResult withNote(String n) => TurnResult(
        score: score,
        melody: melody,
        rhythm: rhythm,
        pitched: pitched,
        attemptPath: attemptPath,
        voicedPct: voicedPct,
        attemptWave: attemptWave,
        verdict: verdict,
        note: n,
      );
}

/// Formal Arabic explanation for a zero note code. Empty for `ok`.
String turnNoteLabel(String note) => switch (note) {
      'no-challenge' => 'لم يصل ملف التحدي إلى هاتفك',
      'play-failed' => 'تعذّر تشغيل صوت التحدي',
      'record-failed' => 'تعذّر التسجيل — تحقق من إذن الميكروفون',
      'empty-pitch' => 'التسجيل فارغ — لم يُلتقط أي صوت',
      'silent' => 'الصوت منخفض جدًا — قرّب الهاتف وتحدّث بصوت أعلى',
      'error' => 'خطأ غير متوقع أثناء الدور',
      _ => '',
    };

class TurnRunner {
  static Future<TurnResult> run({
    required AudioIoService io,
    required String challengePath,
    required double durationSeconds,
    void Function(TurnPhase phase)? onPhase,
    void Function(int secondsLeft)? onCountdown,
    void Function(double level)? onLevel,
  }) async {
    StreamSubscription<double>? ampSub;
    try {
      onPhase?.call(TurnPhase.listening);
      try {
        await io.playOnce(challengePath);
      } catch (_) {
        return TurnResult._zero(note: 'play-failed');
      }

      onPhase?.call(TurnPhase.countdown);
      for (var i = 3; i >= 1; i--) {
        try {
          onCountdown?.call(i);
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      onPhase?.call(TurnPhase.recording);
      ampSub = io.micLevels().listen((level) {
        try {
          onLevel?.call(level);
        } catch (_) {}
      });
      final rawPath = await io.tempWavPath(
          'attempt_${DateTime.now().millisecondsSinceEpoch}');
      final totalMs =
          (durationSeconds * 1000).round().clamp(2000, 6000);
      String? stopped;
      try {
        stopped =
            await io.recordWav(rawPath, Duration(milliseconds: totalMs));
      } catch (_) {
        final live = ampSub;
        ampSub = null;
        await live.cancel();
        return TurnResult._zero(note: 'record-failed');
      }
      final live = ampSub;
      ampSub = null;
      await live.cancel();
      final attemptPath = stopped ?? rawPath;
      // Same scorer solo uses. Target features come from the WAV, not
      // from the stored pitchMap, so a LAN take cannot stick at 18 just
      // because the library contour is wider than the live extract.
      final scored = await AttemptScorer.score(
        targetPath: challengePath,
        playerPath: attemptPath,
        decodeToWav: io.decodeToWav,
      );
      return TurnResult(
        score: scored.verdict.total,
        melody: scored.verdict.melody,
        rhythm: scored.verdict.rhythm,
        pitched: scored.verdict.pitched,
        attemptPath: attemptPath,
        voicedPct: scored.voicedPct,
        attemptWave: scored.attemptWave,
        verdict: scored.verdict,
        note: scored.note,
      );
    } catch (_) {
      final live = ampSub;
      ampSub = null;
      if (live != null) {
        try {
          await live.cancel();
        } catch (_) {}
      }
      return TurnResult._zero(note: 'error');
    }
  }
}
