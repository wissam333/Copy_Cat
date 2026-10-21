// lib/widgets/wave_pitch.dart — the library card preview: the sound's
// energy envelope plus its pitch contour (F0 from the stored pitchMap or
// a fresh extraction). One glance answers two questions: how loud it is
// over time, and whether it has a melody to mimic.
import 'dart:math';

import 'package:flutter/material.dart';

class WavePitchPreview extends StatelessWidget {
  final List<double> wave;

  /// F0 in Hz sampled on a fixed cadence (50 ms). 0 or negative = unvoiced.
  final List<double>? pitch;
  final double height;

  const WavePitchPreview({
    super.key,
    required this.wave,
    this.pitch,
    this.height = 64,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (wave.isEmpty && (pitch == null || pitch!.isEmpty)) {
      return SizedBox(height: height);
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePitchPainter(
          wave: wave,
          pitch: pitch ?? const [],
          waveColor: scheme.primary,
          pitchColor: scheme.tertiary,
        ),
      ),
    );
  }
}

class _WavePitchPainter extends CustomPainter {
  final List<double> wave;
  final List<double> pitch;
  final Color waveColor;
  final Color pitchColor;

  _WavePitchPainter({
    required this.wave,
    required this.pitch,
    required this.waveColor,
    required this.pitchColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Pitch band on top (60%), waveform band below — score over groove.
    final hasPitch = pitch.any((f) => f > 0);
    final pitchH = hasPitch ? size.height * 0.60 : 0.0;
    final waveTop = hasPitch ? pitchH + 3 : 0.0;
    final waveH = size.height - waveTop;

    // --- Waveform: mirrored bars around the band's center. ---
    if (wave.isNotEmpty && waveH > 4) {
      final barColor = Paint()
        ..color = waveColor.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      final n = wave.length;
      final barW = size.width / n;
      final maxAmp = wave.fold<double>(0.0001, (m, v) => v > m ? v : m);
      final cy = waveTop + waveH / 2;
      final halfH = waveH / 2 - 1;
      for (var i = 0; i < n; i++) {
        final a = (wave[i] / maxAmp).clamp(0.0, 1.0);
        final h = max(1.0, a * halfH);
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i * barW + barW / 2, cy),
            width: max(1.0, barW * 0.62),
            height: h * 2,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(r, barColor);
      }
    }

    // --- Pitch contour: segments over voiced frames, gaps on unvoiced. ---
    double lo = double.infinity;
    double hi = 0;
    for (final f in pitch) {
      if (f > 0) {
        if (f < lo) lo = f;
        if (f > hi) hi = f;
      }
    }
    if (!hasPitch) return;
    if (hi <= lo) {
      // Monotone (or one voiced frame): a flat line in the band's middle.
      final y = size.height * 0.30;
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()
            ..color = pitchColor
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round);
      return;
    }
    final linePaint = Paint()
      ..color = pitchColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()..color = pitchColor;
    const pad = 4.0;
    final usableH = max(1.0, pitchH - pad * 2 - 2);
    final stepX = size.width / max(1, pitch.length - 1);
    var last = Offset.zero;
    var inRun = false;
    for (var i = 0; i < pitch.length; i++) {
      final f = pitch[i];
      if (f <= 0) {
        inRun = false;
        continue;
      }
      // Log scale: melody perception is octave-relative, so a fifth looks
      // equally high regardless of the key it sits in.
      final t = ((log(f / lo) / log(hi / lo)) * 1.0).clamp(0.0, 1.0);
      final pt = Offset(
          (i * stepX).clamp(0.0, size.width), pad + (1 - t) * usableH);
      if (inRun) {
        canvas.drawLine(last, pt, linePaint);
      } else {
        canvas.drawCircle(pt, 2.0, dotPaint);
      }
      last = pt;
      inRun = true;
    }
  }

  @override
  bool shouldRepaint(covariant _WavePitchPainter old) =>
      old.wave.length != wave.length ||
      old.pitch.length != pitch.length ||
      old.waveColor != waveColor ||
      old.pitchColor != pitchColor;
}
