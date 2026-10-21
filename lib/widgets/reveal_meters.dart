// lib/widgets/reveal_meters.dart — the honest reveal: per-axis meters
// chosen by what the clip actually was (sung / spoken / noise), not one
// rhythm bar for everything.
//
// Axis grades arrive 0–100; −1 means the axis carried no weight (or no
// data). Deliberately minimal: the row is just the axis name and one
// bar — the fill is the grade, and its color tells the story
// (red < 50, amber 50–79, green ≥ 80). No numbers, no weights.
import 'package:flutter/material.dart';

class _AxisRow {
  final String label;
  final double value;
  const _AxisRow(this.label, this.value);
}

/// Small note above the meters naming the clip class and its judge axis.
String? revealKindCaption(String kind) {
  switch (kind) {
    case 'tonal':
      return 'صوت بنغمة — اللحن هو الحكم';
    case 'speech':
      return 'كلام — وضوح النطق هو الحكم';
    case 'noise':
      return 'بلا نغمة — النوع والإيقاع هما الحكم';
    default:
      return null; // nothing was graded — the reason line covers it
  }
}

List<_AxisRow> _rowsFor(
    String kind, double pitch, double timbre, double energy, double timing) {
  switch (kind) {
    case 'tonal':
      return [
        _AxisRow('اللحن', pitch),
        _AxisRow('الإيقاع', timing),
        _AxisRow('النبرة', timbre),
        _AxisRow('الطاقة', energy),
      ];
    case 'speech':
      return [
        _AxisRow('وضوح النطق', timbre),
        _AxisRow('الإيقاع', timing),
        _AxisRow('الطاقة', energy),
        _AxisRow('لحن الكلام', pitch),
      ];
    case 'noise':
      return [
        _AxisRow('نوع الصوت', timbre),
        _AxisRow('الإيقاع', timing),
        _AxisRow('الطاقة', energy),
      ];
    default:
      return const [];
  }
}

class RevealMeters extends StatelessWidget {
  final String kind;
  final double pitch;
  final double timbre;
  final double energy;
  final double timing;

  const RevealMeters({
    super.key,
    required this.kind,
    this.pitch = -1,
    this.timbre = -1,
    this.energy = -1,
    this.timing = -1,
  });

  @override
  Widget build(BuildContext context) {
    final caption = revealKindCaption(kind);
    final rows =
        _rowsFor(kind, pitch, timbre, energy, timing).where((r) => r.value >= 0);
    if (caption == null || !rows.any((r) => r.value >= 0)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(caption,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amber, fontSize: 12)),
          const SizedBox(height: 2),
          for (final r in rows) _MeterRow(row: r),
        ],
      ),
    );
  }
}

class _MeterRow extends StatelessWidget {
  final _AxisRow row;
  const _MeterRow({required this.row});

  static Color _gradeColor(double v) => v >= 80
      ? Colors.greenAccent
      : (v >= 50 ? Colors.amber : Colors.redAccent);

  @override
  Widget build(BuildContext context) {
    final value = row.value.clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(row.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: row.value < 0 ? 0 : value / 100,
                minHeight: 9,
                backgroundColor: Colors.white24,
                color: _gradeColor(value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
