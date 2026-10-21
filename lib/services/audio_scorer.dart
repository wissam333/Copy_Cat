// lib/services/audio_scorer.dart
//
// Party scoring. Solo and LAN both call judge() with features extracted
// from the WAV at score time (see AttemptScorer). The total is 0–100.
// Silence is 0. A perfect copy is 100. A different key still scores high
// because pitch is median-centered in cents, with a small penalty when an
// octave fold is needed.
//
// Four axes, weighted by the target clip:
//   tonal  — pitch 30, mfcc 20, energy 20, timing 30
//   speech — pitch 25, mfcc 35, energy 20, timing 20
//   noise  — pitch  0, mfcc 40, energy 35, timing 25
// A failed axis keeps its weight (0). A missing axis (no data) is dropped
// and the rest are renormalized. The raw mix then takes the static-vowel
// multiplier, a length multiplier, a noise burst multiplier, a weakest-link
// cap, and the piecewise game-feel curve.
import 'dart:math';

class ScoreVerdict {
  final double total;
  final double melody;
  final double rhythm;
  final bool pitched;

  /// What the target clip is: 'tonal' (sung), 'speech', 'noise' (claps,
  /// laughs), or '' (nothing was graded — silence / no data).
  final String kind;

  /// Per-axis grades 0–100. −1 = the axis carried no weight for this clip
  /// type (or no data). [melody]/[rhythm] stay for packet 0x05 compat.
  final double pitch;
  final double timbre;
  final double energy;
  final double timing;

  const ScoreVerdict({
    required this.total,
    required this.melody,
    required this.rhythm,
    required this.pitched,
    this.kind = '',
    this.pitch = -1,
    this.timbre = -1,
    this.energy = -1,
    this.timing = -1,
  });

  static const zero = ScoreVerdict(
    total: 0,
    melody: 0,
    rhythm: 0,
    pitched: false,
  );

  /// Zero total but the clip class is still known, so the reveal card can
  /// caption what was graded (or say why nothing was).
  static ScoreVerdict zeroKinded(_Kind kind) => ScoreVerdict(
        total: 0,
        melody: 0,
        rhythm: 0,
        pitched: kind != _Kind.noise,
        kind: kind.name,
      );
}

enum _Kind { tonal, speech, noise }

class _JudgeResult {
  final _Kind kind;
  final ScoreVerdict verdict;
  final double? sPitch;
  final double? sMfcc;
  final double? sEnergy;
  final double? sTiming;
  final double staticMul;
  final double lengthMul;
  final double burstMul;
  final bool weakestLink;
  final double raw;
  final bool silentGate;
  const _JudgeResult({
    required this.kind,
    required this.verdict,
    this.sPitch,
    this.sMfcc,
    this.sEnergy,
    this.sTiming,
    this.staticMul = 1,
    this.lengthMul = 1,
    this.burstMul = 1,
    this.weakestLink = false,
    this.raw = 0,
    this.silentGate = false,
  });
}

class AudioScorer {
  // Gap marker. Cents live near 0 after centering, so the sentinel must
  // sit far below any real pitch (a 10-semitone slip is only −1000 cents).
  static const double _gap = -1e6;
  static const double _voicedFloor = -1e5;
  // Average MFCC-frame distance that still feels like the same timbre.
  // 6.0 was calibrated on synthetic vectors; real mic-vs-library pairs
  // sit 2-3x farther apart (room, mic, mp3), which collapsed the whole
  // timbre axis to ~0 on genuine takes. Round-1 experiment: 12.0.
  static const double _mfccSigma = 12.0;
  // Peak RMS below this is "the mic heard nothing".
  static const double _silencePeak = 0.006;
  // Raw (pre-normalization) peak below this is background, not a try.
  // Players hold the mic to their mouth: real tries peak 0.1+, a
  // mouth-whisper 0.05+. Far sounds (traffic, a distant chicken) peak
  // ~0.01-0.02. Quieter than 0.04, the app says "speak up" instead of
  // grading the neighborhood.
  static const double _roomTonePeak = 0.04;
  // An envelope this flat is background hum, even when loud: 90th
  // percentile under 1.8x the 10th. A real try has attacks and gaps
  // (5-50x). Scale-invariant, so it survives peak normalization.
  static const double _flatRatio = 1.8;

  static const List<(double, double)> _curvePts = [
    (0.00, 0),
    (0.20, 10),
    (0.40, 40),
    (0.55, 70),
    (0.70, 88),
    (0.85, 97),
    (1.00, 100),
  ];

  /// True when raw mic audio is room tone: too quiet, or flat like a hum.
  /// Call BEFORE normalizeToPeak — afterwards every room sounds loud.
  static bool isRoomTone(List<double> energy) {
    if (energy.isEmpty) return true;
    var peak = 0.0;
    for (final v in energy) {
      if (v > peak) peak = v;
    }
    if (peak < _roomTonePeak) return true;
    return _isFlatLine(energy);
  }

  static bool _isFlatLine(List<double> energy) {
    if (energy.length < 8) return false;
    final sorted = [...energy]..sort();
    // Bottom 5%: a real take always has an onset (humans never start
    // within the first 50 ms of the window) or a breath between syllables.
    // Room tone and machine hum have none — every frame is the same.
    final lo =
        sorted[(sorted.length * 0.05).floor().clamp(0, sorted.length - 1)];
    final hi =
        sorted[(sorted.length * 0.9).floor().clamp(0, sorted.length - 1)];
    return hi < lo * _flatRatio + 1e-4;
  }

  static double calculateScore(
    List<double> targetPitch,
    List<double> playerPitch,
  ) {
    return judge(targetPitch, playerPitch).total;
  }

  static ScoreVerdict judge(
    List<double> targetPitch,
    List<double> playerPitch, {
    List<double>? targetEnergy,
    List<double>? playerEnergy,
    List<List<double>>? targetMfcc,
    List<List<double>>? playerMfcc,
  }) {
    return _judgeInternal(
      targetPitch,
      playerPitch,
      targetEnergy: targetEnergy,
      playerEnergy: playerEnergy,
      targetMfcc: targetMfcc,
      playerMfcc: playerMfcc,
    ).verdict;
  }

  /// Same pipeline as [judge] but with every intermediate exposed, so a
  /// real (target, attempt) pair can be dissected by tool/analyze_attempt.
  /// Pure computation, no I/O. Keys are documented in the tool.
  static Map<String, Object> diagnose(
    List<double> targetPitch,
    List<double> playerPitch, {
    List<double>? targetEnergy,
    List<double>? playerEnergy,
    List<List<double>>? targetMfcc,
    List<List<double>>? playerMfcc,
  }) {
    final r = _judgeInternal(
      targetPitch,
      playerPitch,
      targetEnergy: targetEnergy,
      playerEnergy: playerEnergy,
      targetMfcc: targetMfcc,
      playerMfcc: playerMfcc,
    );
    return {
      'kind': r.kind.name,
      'targetVoicedRatio': _voicedRatio(targetPitch),
      'targetVoicedCount': _voicedCount(targetPitch).toDouble(),
      'playerVoicedRatio': _voicedRatio(playerPitch),
      'playerVoicedCount': _voicedCount(playerPitch).toDouble(),
      'trimmedPlayerVoicedRatio':
          _voicedRatio(_trimSilence(playerPitch)),
      'targetOctaveSlipRate': _octaveSlipRate(targetPitch),
      'targetMedianJumpCents': _medianJumpCents(targetPitch),
      'activeRatio': (targetEnergy == null ||
              playerEnergy == null ||
              targetEnergy.isEmpty ||
              playerEnergy.isEmpty)
          ? -1
          : _activeRatio(targetEnergy, playerEnergy),
      'targetPeak': _peakOf(targetEnergy),
      'playerPeak': _peakOf(playerEnergy),
      'sPitch': r.sPitch ?? -1,
      'sMfcc': r.sMfcc ?? -1,
      'sEnergy': r.sEnergy ?? -1,
      'sTiming': r.sTiming ?? -1,
      'mfccErr': _mfccErr(targetMfcc, playerMfcc),
      'staticMul': r.staticMul,
      'lengthMul': r.lengthMul,
      'burstMul': r.burstMul,
      'weakestLink': r.weakestLink,
      'silentGate': r.silentGate,
      'rawPreFeel': r.raw,
      'total': r.verdict.total,
      'melody': r.verdict.melody,
      'rhythm': r.verdict.rhythm,
    };
  }

  static double _peakOf(List<double>? e) {
    if (e == null || e.isEmpty) return 0;
    var p = 0.0;
    for (final v in e) {
      if (v > p) p = v;
    }
    return p;
  }

  /// Fraction of adjacent voiced target frames jumping more than an
  /// octave (>1050 untouched cents — the unfold in _centered only fixes
  /// 1050..1350). Real melodies glide or step; a mistracked target
  /// teleports every few frames.
  static double _octaveSlipRate(List<double> hz) {
    final c = _centered(_trimSilence(hz));
    final v = [for (final x in c) if (x > _voicedFloor) x];
    if (v.length < 3) return 0;
    var slips = 0;
    for (var i = 1; i < v.length; i++) {
      if ((v[i] - v[i - 1]).abs() > 1050) slips++;
    }
    return slips / (v.length - 1);
  }

  /// Median adjacent voiced jump, cents. Real song/speech: 50-250.
  /// YIN garbage on distorted clips: 500+.
  static double _medianJumpCents(List<double> hz) {
    final c = _centered(_trimSilence(hz));
    final v = [for (final x in c) if (x > _voicedFloor) x];
    if (v.length < 3) return 0;
    final jumps = <double>[
      for (var i = 1; i < v.length; i++) (v[i] - v[i - 1]).abs()
    ]..sort();
    final mid = jumps.length ~/ 2;
    return jumps.length.isOdd
        ? jumps[mid]
        : (jumps[mid - 1] + jumps[mid]) / 2;
  }

  static _JudgeResult _judgeInternal(
    List<double> targetPitch,
    List<double> playerPitch, {
    List<double>? targetEnergy,
    List<double>? playerEnergy,
    List<List<double>>? targetMfcc,
    List<List<double>>? playerMfcc,
  }) {
    if (targetPitch.isEmpty &&
        (targetEnergy == null || targetEnergy.isEmpty)) {
      return const _JudgeResult(
          kind: _Kind.noise, verdict: ScoreVerdict.zero);
    }
    if (_isSilent(playerPitch, playerEnergy)) {
      return _JudgeResult(
          kind: _kind(targetPitch),
          verdict: ScoreVerdict.zeroKinded(_kind(targetPitch)),
          silentGate: true);
    }

    final kind = _kind(targetPitch);
    final w = _weights(kind);

    // A mistracked target teleports between octaves every few frames
    // (slipRate 0.10 on a distorted meme clip vs ~0.00 on real
    // melodies). No human can match detector noise, so pitch is dropped
    // and steadiness is not punished — timing, energy, and timbre carry
    // the take. An exact copy still scores 100 through those axes.
    final reliable = _octaveSlipRate(targetPitch) < 0.08;

    double? sPitch;
    if (w.pitch > 0 && reliable) {
      if (_voicedCount(targetPitch) >= 4) {
        // Round-3: gate on the ends-trimmed contour — the same content
        // _pitchScore actually grades. Gating the raw contour counted
        // leading/trailing silence against the take, so a short genuine
        // impression inside the record window scored exactly 0.
        sPitch = _voicedRatio(_trimSilence(playerPitch)) >= 0.45
            ? _pitchScore(targetPitch, playerPitch, kind)
            : 0.0;
      }
    }

    double? sMfcc;
    if (targetMfcc != null &&
        playerMfcc != null &&
        targetMfcc.isNotEmpty &&
        playerMfcc.isNotEmpty) {
      sMfcc = _mfccScore(targetMfcc, playerMfcc);
    }

    double? sEnergy;
    double? sTiming;
    var lengthMul = 1.0;
    var burstMul = 1.0;
    final hasEnergy = targetEnergy != null &&
        playerEnergy != null &&
        targetEnergy.isNotEmpty &&
        playerEnergy.isNotEmpty;
    if (hasEnergy) {
      sEnergy = _energyScore(targetEnergy, playerEnergy);
      sTiming = _timingScore(targetEnergy, playerEnergy);
      lengthMul = _lengthMul(_activeRatio(targetEnergy, playerEnergy));
      if (kind == _Kind.noise) {
        burstMul =
            0.5 + 0.5 * _burstSimilarity(targetEnergy, playerEnergy);
      }
    }

    var wp = sPitch == null ? 0.0 : w.pitch;
    var wm = sMfcc == null ? 0.0 : w.mfcc;
    var we = sEnergy == null ? 0.0 : w.energy;
    var wt = sTiming == null ? 0.0 : w.timing;
    final sumW = wp + wm + we + wt;
    if (sumW <= 0) {
      return _JudgeResult(
          kind: kind, verdict: ScoreVerdict.zeroKinded(kind));
    }
    wp /= sumW;
    wm /= sumW;
    we /= sumW;
    wt /= sumW;

    final used = <double>[
      ?sPitch,
      ?sMfcc,
      ?sEnergy,
      ?sTiming,
    ];
    var raw = wp * (sPitch ?? 0) +
        wm * (sMfcc ?? 0) +
        we * (sEnergy ?? 0) +
        wt * (sTiming ?? 0);
    final staticMul =
        reliable ? _staticMul(targetPitch, playerPitch) : 1.0;
    raw *= staticMul;
    raw *= lengthMul;
    raw *= burstMul;
    final weakestLink =
        _weakestLink(wp, sPitch, wm, sMfcc, we, sEnergy, wt, sTiming);
    if (weakestLink) {
      raw = min(raw, 0.45);
    }
    if (raw.isNaN || raw.isInfinite) raw = 0;

    final perfect = used.isNotEmpty && used.every((s) => s >= 0.995);
    final total = perfect ? 100.0 : _feel(raw);

    final rhythmDen = (sEnergy == null ? 0.0 : w.energy) +
        (sTiming == null ? 0.0 : w.timing);
    final rhythm = rhythmDen <= 0
        ? 0.0
        : 100.0 *
            (((sEnergy == null ? 0.0 : w.energy) * (sEnergy ?? 0)) +
                ((sTiming == null ? 0.0 : w.timing) * (sTiming ?? 0))) /
            rhythmDen;

    final verdict = ScoreVerdict(
      total: total.roundToDouble().clamp(0, 100),
      melody: ((sPitch ?? 0) * 100).roundToDouble().clamp(0, 100),
      rhythm: rhythm.roundToDouble().clamp(0, 100),
      pitched: kind != _Kind.noise,
      kind: kind.name,
      pitch: sPitch == null ? -1 : (sPitch * 100).roundToDouble().clamp(0, 100),
      timbre: sMfcc == null ? -1 : (sMfcc * 100).roundToDouble().clamp(0, 100),
      energy:
          sEnergy == null ? -1 : (sEnergy * 100).roundToDouble().clamp(0, 100),
      timing: sTiming == null ? -1 : (sTiming * 100).roundToDouble().clamp(0, 100),
    );
    return _JudgeResult(
      kind: kind,
      verdict: verdict,
      sPitch: sPitch,
      sMfcc: sMfcc,
      sEnergy: sEnergy,
      sTiming: sTiming,
      staticMul: staticMul,
      lengthMul: lengthMul,
      burstMul: burstMul,
      weakestLink: weakestLink,
      raw: raw,
    );
  }

  static bool _isSilent(List<double> pitch, List<double>? energy) {
    if (energy != null && energy.isNotEmpty) {
      var peak = 0.0;
      for (final v in energy) {
        if (v > peak) peak = v;
      }
      if (peak < _silencePeak) return true;
      // Loud but flat (amplified room tone, mains hum): no performance.
      if (_isFlatLine(energy)) return true;
      return false;
    }
    if (pitch.isEmpty) return true;
    return _voicedRatio(pitch) < 0.30;
  }

  static double _voicedRatio(List<double> pitch) {
    if (pitch.isEmpty) return 0;
    return _voicedCount(pitch) / pitch.length;
  }

  static int _voicedCount(List<double> pitch) =>
      pitch.where((f) => f > 0).length;

  /// Same voiced test judge() used to gate timbre. Callers may still
  /// check this; scoring itself always accepts MFCC when it is passed.
  static bool looksPitched(List<double> pitch) =>
      _voicedRatio(pitch) >= 0.30 && _voicedCount(pitch) >= 4;

  static _Kind _kind(List<double> pitch) {
    final r = _voicedRatio(pitch);
    final n = _voicedCount(pitch);
    if (r >= 0.60 && n >= 4) return _Kind.tonal;
    // This YIN reports 15–30% voiced on claps and noise. Those stay noise,
    // same bar as looksPitched, so a burst is not graded as speech.
    if (r < 0.30 || n < 4) return _Kind.noise;
    return _Kind.speech;
  }

  static ({double pitch, double mfcc, double energy, double timing})
      _weights(_Kind kind) => switch (kind) {
            _Kind.tonal => (
                // 2026-10 rebalance: melody and rhythm weigh equally on sung
                // clips so a good beat feels worth points. Both stay at/above
                // the 0.25 weakest-link threshold, so a failed melody still
                // caps the take; timbre/energy (0.20) remain sub-guard.
                pitch: 0.30,
                mfcc: 0.20,
                energy: 0.20,
                timing: 0.30
              ),
            _Kind.speech => (
                pitch: 0.25,
                mfcc: 0.35,
                energy: 0.20,
                timing: 0.20
              ),
            _Kind.noise => (
                pitch: 0.00,
                mfcc: 0.40,
                energy: 0.35,
                timing: 0.25
              ),
          };

  static bool _weakestLink(
    double wp,
    double? sp,
    double wm,
    double? sm,
    double we,
    double? se,
    double wt,
    double? st,
  ) {
    bool bad(double w, double? s) => w >= 0.25 && s != null && s < 0.15;
    return bad(wp, sp) || bad(wm, sm) || bad(we, se) || bad(wt, st);
  }

  /// Graduated "aaaa" penalty. Only when the target itself moves
  /// (std > 200 cents). A flat beep matched by a flat note is free.
  static double _staticMul(List<double> targetHz, List<double> playerHz) {
    final t = _centered(_trimSilence(targetHz));
    final p = _centered(_trimSilence(playerHz));
    if (t.isEmpty || p.isEmpty) return 1;
    final tStd = _voicedStd(t);
    if (tStd <= 200) return 1;
    final r = _voicedStd(p) / tStd;
    if (r <= 0.15) return 0.30;
    if (r >= 0.50) return 1;
    return 0.30 + 0.70 * (r - 0.15) / 0.35;
  }

  static double _lengthMul(double ratio) {
    if (ratio >= 0.75 && ratio <= 1.35) return 1;
    if (ratio >= 0.5 && ratio < 0.75) {
      return 0.7 + 0.3 * (ratio - 0.5) / 0.25;
    }
    if (ratio > 1.35 && ratio <= 2.0) {
      return 1.0 - 0.3 * (ratio - 1.35) / 0.65;
    }
    return 0.5;
  }

  static double _activeRatio(List<double> target, List<double> player) {
    // Loose floor on purpose: this ratio only catches "way too much /
    // way too little" (droning on, one blip in a long window). The
    // strict peak-relative mask would let a single loud transient
    // shrink one side's count and halve genuine takes (Yare Yare:
    // true 25-vs-22 frames measured as 2.71).
    final ta = _activeCount(_maskLoose(target));
    final pa = _activeCount(_maskLoose(player));
    if (ta == 0) return pa == 0 ? 1 : 0;
    return pa / ta;
  }

  /// Inclusive activity mask (floor 15% of peak). _mask stays strict:
  /// onset overlap wants cores, duration wants spans.
  static List<bool> _maskLoose(List<double> energy) {
    var peak = 0.0;
    for (final v in energy) {
      if (v > peak) peak = v;
    }
    if (peak <= 0) return List<bool>.filled(energy.length, false);
    final floor = peak * 0.15;
    return [for (final v in energy) v >= floor];
  }

  static double _pitchScore(
    List<double> targetHz,
    List<double> playerHz,
    _Kind kind,
  ) {
    final tc = _centered(_trimSilence(targetHz));
    final pc = _centered(_trimSilence(playerHz));
    if (tc.isEmpty || pc.isEmpty) return 0;
    // PitchExtractor already median-filters. Smoothing again on these
    // 50 ms frames erases the melody and makes unrelated contours match.
    final pairs = _align(tc, pc, _pitchCost);
    if (pairs.isEmpty) return 0;
    final tol = kind == _Kind.tonal ? 100.0 : 200.0;
    final maxErr = kind == _Kind.tonal ? 450.0 : 600.0;
    var sum = 0.0;
    var n = 0;
    var voiced = 0;
    var overlap = 0;
    for (final pair in pairs) {
      final av = pair.$1 > _voicedFloor;
      final bv = pair.$2 > _voicedFloor;
      if (!av) continue;
      n++;
      voiced++;
      if (!bv) continue;
      overlap++;
      final oct = _octErr(pair.$1, pair.$2);
      var s = 0.0;
      if (oct.err <= tol) {
        s = 1;
      } else if (oct.err < maxErr) {
        s = pow((maxErr - oct.err) / (maxErr - tol), 1.5).toDouble();
      }
      if (oct.folded) s *= 0.85;
      sum += s;
    }
    if (n == 0 || voiced == 0) return 0;
    final frames = (sum / n) * (overlap / voiced);
    // Frame tolerance alone lets a different shape score high by
    // matching a few nearby notes. The contour itself has to agree —
    // measured along the DTW path (warp-tolerant), not on resampled
    // vectors: two takes of one phrase share phases, not frame indices.
    final ax = <double>[];
    final bx = <double>[];
    for (final pair in pairs) {
      if (pair.$1 > _voicedFloor && pair.$2 > _voicedFloor) {
        ax.add(pair.$1);
        bx.add(pair.$2);
      }
    }
    return (frames * _pathAgreement(ax, bx)).clamp(0.0, 1.0);
  }

  /// 1 when both aligned contours are flat (a beep) or they rise and
  /// fall together. 0 when one is flat or the shapes oppose each other.
  /// Rank correlation: direction agreement, outlier-proof — one
  /// falsetto spike must not veto an otherwise followed contour.
  /// Magnitude errors are already punished by the frame tolerance.
  static double _pathAgreement(List<double> a, List<double> b) {
    if (a.length < 3 || b.length < 3) return 1;
    final aStd = _voicedStd(a);
    final bStd = _voicedStd(b);
    if (aStd < 80 && bStd < 80) return 1;
    if (aStd < 80 || bStd < 80) return 0;
    final corr = _pearson(_ranks(a), _ranks(b));
    if (corr == null) return 1;
    return max(0.0, corr);
  }

  /// Fractional ranks with averaged ties.
  static List<double> _ranks(List<double> v) {
    final order = List<int>.generate(v.length, (i) => i)
      ..sort((i, j) => v[i].compareTo(v[j]));
    final ranks = List<double>.filled(v.length, 0);
    var i = 0;
    while (i < order.length) {
      var j = i;
      while (j + 1 < order.length && v[order[j + 1]] == v[order[i]]) {
        j++;
      }
      final avg = (i + j) / 2;
      for (var k = i; k <= j; k++) {
        ranks[order[k]] = avg;
      }
      i = j + 1;
    }
    return ranks;
  }

  static double _energyScore(List<double> targetRaw, List<double> playerRaw) {
    final t = _centerDb(_trimRelative(targetRaw));
    final p = _centerDb(_trimRelative(playerRaw));
    if (t.isEmpty || p.isEmpty) return 0;
    final n = max(t.length, p.length);
    final ta = _resample(t, n);
    final pa = _resample(p, n);
    final corr = _pearson(ta, pa);
    final madTerm = exp(-_mad(ta, pa) / 6.0);
    final base = corr == null ? madTerm : 0.5 * max(0.0, corr) + 0.5 * madTerm;
    final ra = _span(ta);
    final rb = _span(pa);
    final rangeSim =
        (ra + rb) < 1e-6 ? 1.0 : min(ra, rb) / max(ra, rb);
    return (0.85 * base + 0.15 * rangeSim).clamp(0.0, 1.0);
  }

  static double _timingScore(List<double> targetRaw, List<double> playerRaw) {
    final iou = _iou(_mask(targetRaw), _mask(playerRaw));
    final dur = _durationTerm(_activeRatio(targetRaw, playerRaw));
    final bursts = _burstSimilarity(targetRaw, playerRaw);
    return (0.5 * iou + 0.25 * dur + 0.25 * bursts).clamp(0.0, 1.0);
  }

  /// 1 inside 0.75–1.35, down to 0.7 at the 0.5 / 2.0 edges, else 0.5.
  static double _durationTerm(double ratio) => _lengthMul(ratio);

  /// Raw DTW cost per frame behind _mfccScore (before the Gaussian).
  /// Same voice + same phrase should sit well under _mfccSigma.
  static double _mfccErr(
      List<List<double>>? target, List<List<double>>? player) {
    if (target == null ||
        player == null ||
        target.isEmpty ||
        player.isEmpty) {
      return -1;
    }
    final t = _dropC0(_trimVecEnds(target));
    final p = _dropC0(_trimVecEnds(player));
    if (t.isEmpty || p.isEmpty) return -1;
    final err = _dtwVec(t, p) / max(t.length, p.length);
    if (err.isNaN || err.isInfinite) return -1;
    return err;
  }

  static double _mfccScore(
      List<List<double>> target, List<List<double>> player) {
    final t = _dropC0(_trimVecEnds(target));
    final p = _dropC0(_trimVecEnds(player));
    if (t.isEmpty || p.isEmpty) return 0;
    if (t.first.isEmpty || p.first.isEmpty) return 0;
    final err = _dtwVec(t, p) / max(t.length, p.length);
    if (err.isNaN || err.isInfinite) return 0;
    return exp(-err * err / (2 * _mfccSigma * _mfccSigma)).clamp(0.0, 1.0);
  }

  static List<List<double>> _dropC0(List<List<double>> frames) {
    return [
      for (final f in frames) f.length > 1 ? f.sublist(1) : List<double>.from(f),
    ];
  }

  static double _feel(double raw) {
    if (raw.isNaN || raw.isInfinite || raw <= 0) return 0;
    final x = raw > 1 ? 1.0 : raw;
    for (var i = 1; i < _curvePts.length; i++) {
      final x1 = _curvePts[i].$1;
      if (x <= x1) {
        final x0 = _curvePts[i - 1].$1;
        final y0 = _curvePts[i - 1].$2;
        final y1 = _curvePts[i].$2;
        final span = x1 - x0;
        final t = span == 0 ? 0.0 : (x - x0) / span;
        return y0 + t * (y1 - y0);
      }
    }
    return 100;
  }

  static List<double> _centerDb(List<double> rms) {
    if (rms.isEmpty) return const [];
    final db = <double>[
      for (final v in rms) 20.0 * (log(max(v, 1e-8)) / ln10),
    ];
    final mid = _median(db);
    return [for (final v in db) v - mid];
  }

  static List<double> _trimRelative(List<double> rms) {
    if (rms.isEmpty) return rms;
    var peak = 0.0;
    for (final v in rms) {
      if (v > peak) peak = v;
    }
    if (peak < _silencePeak) return const [];
    return _trimEnds(rms, floor: peak * 0.08);
  }

  static double? _pearson(List<double> x, List<double> y) {
    final n = min(x.length, y.length);
    if (n < 3) return null;
    var mx = 0.0;
    var my = 0.0;
    for (var i = 0; i < n; i++) {
      mx += x[i];
      my += y[i];
    }
    mx /= n;
    my /= n;
    var num = 0.0;
    var vx = 0.0;
    var vy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = x[i] - mx;
      final dy = y[i] - my;
      num += dx * dy;
      vx += dx * dx;
      vy += dy * dy;
    }
    if (vx < 1e-8 || vy < 1e-8) return null;
    return (num / sqrt(vx * vy)).clamp(-1.0, 1.0);
  }

  static double _mad(List<double> x, List<double> y) {
    final n = min(x.length, y.length);
    if (n == 0) return 99;
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += (x[i] - y[i]).abs();
    }
    return s / n;
  }

  static double _span(List<double> v) {
    if (v.length < 2) return 0;
    final s = [...v]..sort();
    final lo = s[(s.length * 0.1).floor().clamp(0, s.length - 1)];
    final hi = s[(s.length * 0.9).floor().clamp(0, s.length - 1)];
    return hi - lo;
  }

  static List<double> _resample(List<double> v, int n) {
    if (v.isEmpty || n <= 0) return const [];
    if (v.length == n) return v;
    if (n == 1) return [v.first];
    return [
      for (var i = 0; i < n; i++)
        () {
          final x = i * (v.length - 1) / (n - 1);
          final j = x.floor();
          final t = x - j;
          final a = v[j];
          final b = v[min(j + 1, v.length - 1)];
          return a + t * (b - a);
        }(),
    ];
  }

  static List<bool> _mask(List<double> energy) {
    var peak = 0.0;
    for (final v in energy) {
      if (v > peak) peak = v;
    }
    if (peak <= 0) return List<bool>.filled(energy.length, false);
    final floor = peak * 0.4;
    return [for (final v in energy) v >= floor];
  }

  static int _activeCount(List<bool> mask) {
    var n = 0;
    for (final v in mask) {
      if (v) n++;
    }
    return n;
  }

  static List<bool> _resampleBool(List<bool> v, int n) {
    if (v.isEmpty || n <= 0) return const [];
    if (v.length == n) return v;
    return [
      for (var i = 0; i < n; i++)
        v[((i * v.length) / n).floor().clamp(0, v.length - 1)],
    ];
  }

  static List<bool> _dilate(List<bool> mask, int radius) {
    final out = List<bool>.from(mask);
    for (var i = 0; i < mask.length; i++) {
      if (!mask[i]) continue;
      final a = max(0, i - radius);
      final b = min(mask.length - 1, i + radius);
      for (var k = a; k <= b; k++) {
        out[k] = true;
      }
    }
    return out;
  }

  static double _iou(List<bool> a, List<bool> b) {
    final n = max(a.length, b.length);
    if (n == 0) return 1;
    final aa = _dilate(_resampleBool(a, n), 2);
    final bb = _dilate(_resampleBool(b, n), 2);
    var inter = 0;
    var union = 0;
    for (var i = 0; i < n; i++) {
      if (aa[i] || bb[i]) union++;
      if (aa[i] && bb[i]) inter++;
    }
    if (union == 0) return 1;
    return inter / union;
  }

  /// Drops leading/trailing all-silent (zero-vector) frames.
  static List<List<double>> _trimVecEnds(List<List<double>> frames) {
    var start = 0;
    var end = frames.length;
    bool silent(List<double> f) {
      for (final v in f) {
        if (v != 0.0) return false;
      }
      return true;
    }

    while (start < end && silent(frames[start])) {
      start++;
    }
    while (end > start && silent(frames[end - 1])) {
      end--;
    }
    if (start >= end) return frames;
    return frames.sublist(start, end);
  }

  /// 0..1: do both envelopes have a similar number of loud bursts?
  /// Connected frames above 40% of peak count as one burst.
  static double _burstSimilarity(List<double> a, List<double> b) {
    int bursts(List<double> env) {
      var peak = 0.0;
      for (final v in env) {
        if (v > peak) peak = v;
      }
      if (peak <= 0) return 0;
      final floor = peak * 0.4;
      var count = 0;
      var inside = false;
      for (final v in env) {
        if (v >= floor) {
          if (!inside) {
            inside = true;
            count++;
          }
        } else {
          inside = false;
        }
      }
      return count;
    }

    final x = bursts(a);
    final y = bursts(b);
    if (x == 0 && y == 0) return 1;
    final hi = max(x, y);
    if (hi == 0) return 1;
    return min(x, y) / hi;
  }

  static double _vecCost(List<double> a, List<double> b) {
    final n = min(a.length, b.length);
    if (n == 0) return 1e9;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sqrt(sum);
  }

  static double _dtwVec(List<List<double>> a, List<List<double>> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return 1e9;
    final longer = n > m ? n : m;
    final slack = (longer * 0.35).round();
    final band = (n - m).abs() + (slack < 2 ? 2 : slack);
    final dtw = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.infinity),
    );
    dtw[0][0] = 0;
    for (var i = 1; i <= n; i++) {
      final j0 = i - band < 1 ? 1 : i - band;
      final j1 = i + band > m ? m : i + band;
      for (var j = j0; j <= j1; j++) {
        final up = dtw[i - 1][j];
        final left = dtw[i][j - 1];
        final diag = dtw[i - 1][j - 1];
        final best = up < left ? (up < diag ? up : diag) : (left < diag ? left : diag);
        dtw[i][j] = _vecCost(a[i - 1], b[j - 1]) + best;
      }
    }
    final v = dtw[n][m];
    if (v.isInfinite) return _dtwVecFull(a, b);
    return v;
  }

  static double _dtwVecFull(List<List<double>> a, List<List<double>> b) {
    final n = a.length;
    final m = b.length;
    final dtw = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.infinity),
    );
    dtw[0][0] = 0;
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final up = dtw[i - 1][j];
        final left = dtw[i][j - 1];
        final diag = dtw[i - 1][j - 1];
        final best = up < left ? (up < diag ? up : diag) : (left < diag ? left : diag);
        dtw[i][j] = _vecCost(a[i - 1], b[j - 1]) + best;
      }
    }
    return dtw[n][m];
  }

  static List<double> _trimEnds(List<double> env, {double floor = 0.08}) {
    if (env.isEmpty) return env;
    var start = 0;
    var end = env.length;
    while (start < end && env[start] < floor) {
      start++;
    }
    while (end > start && env[end - 1] < floor) {
      end--;
    }
    if (start >= end) return env;
    return env.sublist(start, end);
  }

  static List<double> _trimSilence(List<double> pitch) {
    var start = 0;
    var end = pitch.length;
    while (start < end && pitch[start] <= 0) {
      start++;
    }
    while (end > start && pitch[end - 1] <= 0) {
      end--;
    }
    return pitch.sublist(start, end);
  }

  static List<double> _centered(List<double> hz) {
    if (hz.isEmpty) return const [];
    final cents = <double>[];
    double? prev;
    for (final f in hz) {
      if (f <= 0) {
        cents.add(_gap);
        continue;
      }
      var s = 1200.0 * (log(f / 440.0) / ln2);
      if (prev != null) {
        final delta = s - prev;
        // Only a near-octave jump is a detector slip. A real leap (a
        // fifth, a shout) must stay in the contour.
        if (delta.abs() > 1050 && delta.abs() < 1350) {
          s -= 1200.0 * delta.sign;
        }
      }
      cents.add(s);
      prev = s;
    }
    final voiced = [for (final s in cents) if (s > _voicedFloor) s];
    if (voiced.isEmpty) return cents;
    final mid = _median(voiced);
    return [for (final s in cents) s > _voicedFloor ? s - mid : _gap];
  }

  static double _median(List<double> values) {
    final s = [...values]..sort();
    final mid = s.length ~/ 2;
    if (s.length.isOdd) return s[mid];
    return (s[mid - 1] + s[mid]) / 2;
  }

  static ({double err, bool folded}) _octErr(double a, double b) {
    final d = (a - b).abs();
    final down = (a - b - 1200).abs();
    final up = (a - b + 1200).abs();
    if (down < d && down <= up) return (err: down, folded: true);
    if (up < d && up < down) return (err: up, folded: true);
    return (err: d, folded: false);
  }

  static double _pitchCost(double a, double b) {
    final av = a > _voicedFloor;
    final bv = b > _voicedFloor;
    if (!av && !bv) return 0;
    if (av != bv) return 400;
    return _octErr(a, b).err;
  }

  /// Variance over voiced frames only (gaps are _gap, not data).
  static double _voicedVariance(List<double> v) {
    var n = 0;
    var mean = 0.0;
    for (final x in v) {
      if (x < _voicedFloor) continue;
      n++;
      mean += x;
    }
    if (n < 2) return 0;
    mean /= n;
    var s = 0.0;
    for (final x in v) {
      if (x < _voicedFloor) continue;
      s += (x - mean) * (x - mean);
    }
    return s / n;
  }

  static double _voicedStd(List<double> v) {
    final variance = _voicedVariance(v);
    return variance <= 0 ? 0 : sqrt(variance);
  }

  static List<(double, double)> _align(
    List<double> a,
    List<double> b,
    double Function(double, double) costOf,
  ) {
    final pairs = _alignBand(a, b, costOf);
    if (pairs != null) return pairs;
    return _alignFull(a, b, costOf);
  }

  static List<(double, double)>? _alignBand(
    List<double> a,
    List<double> b,
    double Function(double, double) costOf,
  ) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return const [];
    final longer = n > m ? n : m;
    // 20% Sakoe-Chiba band. Wider than that lets a short contour match
    // by repeating a few lucky frames.
    final slack = (longer * 0.20).round();
    final band = (n - m).abs() + (slack < 2 ? 2 : slack);
    final dtw = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.infinity),
    );
    final ptr = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    dtw[0][0] = 0;
    for (var i = 1; i <= n; i++) {
      final j0 = i - band < 1 ? 1 : i - band;
      final j1 = i + band > m ? m : i + band;
      for (var j = j0; j <= j1; j++) {
        _step(dtw, ptr, i, j, costOf(a[i - 1], b[j - 1]));
      }
    }
    if (dtw[n][m].isInfinite) return null;
    return _backtrack(a, b, ptr);
  }

  static List<(double, double)> _alignFull(
    List<double> a,
    List<double> b,
    double Function(double, double) costOf,
  ) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return const [];
    final dtw = List.generate(
      n + 1,
      (_) => List<double>.filled(m + 1, double.infinity),
    );
    final ptr = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    dtw[0][0] = 0;
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        _step(dtw, ptr, i, j, costOf(a[i - 1], b[j - 1]));
      }
    }
    if (dtw[n][m].isInfinite) return const [];
    return _backtrack(a, b, ptr);
  }

  static void _step(
    List<List<double>> dtw,
    List<List<int>> ptr,
    int i,
    int j,
    double cost,
  ) {
    final diag = dtw[i - 1][j - 1];
    final up = dtw[i - 1][j];
    final left = dtw[i][j - 1];
    var best = diag;
    var dir = 0;
    if (up < best) {
      best = up;
      dir = 1;
    }
    if (left < best) {
      best = left;
      dir = 2;
    }
    dtw[i][j] = cost + best;
    ptr[i][j] = dir;
  }

  static List<(double, double)> _backtrack(
    List<double> a,
    List<double> b,
    List<List<int>> ptr,
  ) {
    final pairs = <(double, double)>[];
    var i = a.length;
    var j = b.length;
    while (i > 0 && j > 0) {
      pairs.add((a[i - 1], b[j - 1]));
      final dir = ptr[i][j];
      if (dir == 1) {
        i--;
      } else if (dir == 2) {
        j--;
      } else {
        i--;
        j--;
      }
    }
    return pairs.reversed.toList();
  }
}
