// lib/widgets/pitch_meter.dart — live "too high / too low" guidance while
// recording. Log-scale needle: one octave off target = full deflection.
// Hidden entirely when the target clip has no pitch map (noise/speech).
import 'dart:math';

import 'package:flutter/material.dart';

import '../stage_theme.dart';

class PitchMeter extends StatelessWidget {
  /// Median of the challenge's pitch map — the note to aim for. 0 hides.
  final double targetHz;

  /// Live estimate from the recorder; 0 = no signal (dim needle).
  final double liveHz;

  const PitchMeter(
      {super.key, required this.targetHz, required this.liveHz});

  /// Median pitch of a pitch map, or 0 when absent (meter stays hidden).
  static double targetOf(List<double> pitchMap) {
    if (pitchMap.isEmpty) return 0;
    final sorted = [...pitchMap]..sort();
    final mid = sorted[sorted.length ~/ 2];
    return mid > 40 ? mid : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (targetHz <= 0) return const SizedBox.shrink();
    final octaves = liveHz > 0
        ? (log(liveHz / targetHz) / ln2).clamp(-1.0, 1.0)
        : 0.0;
    final inTune = liveHz > 0 && octaves.abs() < 0.12; // ~±12% pitch
    final color = liveHz == 0
        ? StageBlack.muted
        : (inTune ? Colors.greenAccent : StageBlack.bad);
    return Column(
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            final x = w / 2 + octaves * (w / 2 - 10);
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: StageBlack.muted.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Positioned(
                  left: w / 2 - 1,
                  child: Container(
                      width: 2,
                      height: 18,
                      color: StageBlack.text.withValues(alpha: 0.7)),
                ),
                Positioned(
                  left: (x - 8).clamp(0.0, w - 16),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}
