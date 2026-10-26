// lib/widgets/ui_bits.dart — small composable widgets (skill: one widget,
// one responsibility; const where possible).
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/celebration.dart';
import '../i18n.dart';
import '../services/sfx.dart';
import '../state/coins.dart';
import '../state/game_state.dart';
import 'avatar_view.dart';

/// How a round score should feel out loud.
String scoreLabel(double score) {
  if (score >= 95) return t('نسخة طبق الأصل!');
  if (score >= 85) return t('أسطورة التقليد');
  if (score >= 70) return t('تقليد قوي');
  if (score >= 55) return t('قريب نوعًا ما');
  if (score >= 35) return t('به شبه');
  if (score > 0) return t('بعيد… حاول الاقتراب أكثر');
  return t('لم نلتقط صوتك');
}

Color scoreColor(double score) {
  if (score >= 85) return const Color(0xFF059669);
  if (score >= 55) return const Color(0xFFD97706);
  if (score > 0) return const Color(0xFFDC2626);
  return const Color(0xFF6B7280);
}

Color playerColor(String id) {
  const colors = [
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF2563EB),
  ];
  return colors[id.hashCode.abs() % colors.length];
}

class PartyModeView {
  final GameMode mode;
  final String title;
  final String blurb;
  final IconData icon;
  const PartyModeView(this.mode, this.title, this.blurb, this.icon);

  static const all = [
    PartyModeView(
      GameMode.random,
      'حفلة عشوائية',
      'كل جولة صوت مفاجئ. الكل يقلّده بالدور، والنقاط تتراكم.',
      Icons.shuffle,
    ),
    PartyModeView(
      GameMode.choice,
      'اختيار اللاعب',
      'واحد يختار الصوت. الباقي يقلّدون قبله، وهو يلعب آخر واحد.',
      Icons.touch_app,
    ),
    PartyModeView(
      GameMode.host,
      'تحدي المضيف',
      'تختار قائمة الأصوات. الكل يقلّد كل صوت قبل الانتقال للي بعده.',
      Icons.star,
    ),
  ];

  static PartyModeView of(GameMode mode) =>
      all.firstWhere((m) => m.mode == mode);
}

class AppButton extends ConsumerWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  const AppButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tap = onPressed;
    final wrapped = tap == null
        ? null
        : () {
            unawaited(Sfx.play(
                ref.read(audioIoProvider), Sfx.click));
            tap();
          };
    final btn = primary
        ? FilledButton.icon(
            onPressed: wrapped,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: wrapped,
            icon: Icon(icon),
            label: Text(label),
          );
    return SizedBox(width: double.infinity, child: btn);
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class PlayerTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool highlight;

  /// Equipped character id; shows a small 3D look instead of the icon.
  final String? avatarId;
  const PlayerTile({
    super.key,
    required this.name,
    required this.subtitle,
    this.highlight = false,
    this.avatarId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: highlight
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: ListTile(
        leading: avatarId == null
            ? const Icon(Icons.person)
            : SizedBox(
                width: 44,
                height: 58,
                child: AvatarView(
                  avatarId: avatarId!,
                  expand: true,
                  lightweight: true,
                  maxFrameRate: 8,
                ),
              ),
        title: Text(name),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class CountdownView extends StatelessWidget {
  final int secondsLeft;
  final String caption;
  final Color color;
  const CountdownView({
    super.key,
    required this.secondsLeft,
    this.caption = 'استعد! يبدأ التسجيل خلال…',
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(t(caption),
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 18)),
        const SizedBox(height: 16),
        Text(
          '$secondsLeft',
          style: TextStyle(
            fontSize: 84,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class PlayerAvatar extends StatelessWidget {
  final String name;
  final String id;
  final double radius;
  const PlayerAvatar({
    super.key,
    required this.name,
    required this.id,
    this.radius = 28,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first);
    return CircleAvatar(
      radius: radius,
      backgroundColor: playerColor(id),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.85,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class ModeCard extends StatelessWidget {
  final PartyModeView mode;
  final bool selected;
  final VoidCallback onTap;
  const ModeCard({
    super.key,
    required this.mode,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Icon(mode.icon, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t(mode.title),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(t(mode.blurb),
                        style: const TextStyle(fontSize: 13, height: 1.35)),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle : Icons.chevron_left,
                  color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class ScoreRow extends StatelessWidget {
  final String name;
  final double score;
  final bool winner;
  final bool points;
  const ScoreRow({
    super.key,
    required this.name,
    required this.score,
    this.winner = false,
    this.points = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = points
        ? t('{n} نقطة', {'n': score.toStringAsFixed(0)})
        : '${score.toStringAsFixed(0)}/100';
    return ListTile(
      leading: Icon(winner ? Icons.emoji_events : Icons.person,
          color: winner ? Colors.amber[700] : null),
      title: Text(name,
          style: winner
              ? const TextStyle(fontWeight: FontWeight.bold)
              : null),
      trailing: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String text;
  const StatusChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.info_outline, size: 18),
      label: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

/// Sound-wave bars. [values] are 0..1 levels; [progress] 0..1 highlights
/// the played portion (null = no progress highlight).
class WaveformBars extends StatelessWidget {
  final List<double> values;
  final double? progress;
  final double height;
  final Color? color;
  const WaveformBars({
    super.key,
    required this.values,
    this.progress,
    this.height = 72,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final played = color ?? scheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePainter(
          values: values,
          progress: progress,
          played: played,
          rest: played.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> values;
  final double? progress;
  final Color played;
  final Color rest;
  _WavePainter({
    required this.values,
    required this.progress,
    required this.played,
    required this.rest,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final barW = size.width / values.length;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final h = (v * (size.height - 8)).clamp(3.0, size.height);
      final x = i * barW + barW / 2;
      final isPlayed =
          progress != null && (i / values.length) <= progress!;
      paint
        ..color = isPlayed ? played : rest
        ..strokeWidth = (barW * 0.6).clamp(1.0, 6.0);
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.values != values || old.progress != progress;
}

/// Two waveforms on top of each other: the original in blue, the
/// player's attempt in orange. Both resampled to the same bucket count
/// so different lengths still line up.
class OverlayWaves extends StatelessWidget {
  final List<double> target;
  final List<double> attempt;
  final double height;
  const OverlayWaves({
    super.key,
    required this.target,
    required this.attempt,
    this.height = 72,
  });

  static List<double> _resample(List<double> v, int n) {
    if (v.isEmpty) return List<double>.filled(n, 0.0);
    if (v.length == 1) return List<double>.filled(n, v.first);
    return List<double>.generate(n, (i) {
      final pos = i * (v.length - 1) / (n - 1);
      final lo = pos.floor().clamp(0, v.length - 1);
      final hi = pos.ceil().clamp(0, v.length - 1);
      final frac = pos - lo;
      return v[lo] * (1 - frac) + v[hi] * frac;
    });
  }

  @override
  Widget build(BuildContext context) {
    const buckets = 48;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _OverlayPainter(
          target: _resample(target, buckets),
          attempt: _resample(attempt, buckets),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final List<double> target;
  final List<double> attempt;
  _OverlayPainter({required this.target, required this.attempt});

  @override
  void paint(Canvas canvas, Size size) {
    if (target.isEmpty || attempt.isEmpty) return;
    const targetColor = Color(0xFF38BDF8);
    const attemptColor = Color(0xFFFB923C);
    final barW = size.width / target.length;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (barW * 0.42).clamp(1.0, 5.0);
    // Blue first (behind), orange on top.
    for (final entry in [
      (target, targetColor),
      (attempt, attemptColor),
    ]) {
      paint.color = entry.$2;
      final values = entry.$1;
      for (var i = 0; i < values.length; i++) {
        final v = values[i].clamp(0.0, 1.0);
        final h = (v * (size.height - 8)).clamp(3.0, size.height);
        final x = i * barW + barW / 2;
        canvas.drawLine(
          Offset(x, (size.height - h) / 2),
          Offset(x, (size.height + h) / 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.target != target || old.attempt != attempt;
}

/// Flying emojis layer. Watches a reactions list; each entry floats up
/// and fades, then removes itself. Visual only, always silent.
class ReactionLayer extends StatelessWidget {
  final List<LanReaction> reactions;
  final void Function(int key) onDone;
  const ReactionLayer({
    super.key,
    required this.reactions,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final r in reactions)
            _FlyingEmoji(
              key: ValueKey(r.key),
              emoji: r.emoji,
              seed: r.key,
              onDone: () => onDone(r.key),
            ),
        ],
      ),
    );
  }
}

class _FlyingEmoji extends StatefulWidget {
  final String emoji;
  final int seed;
  final VoidCallback onDone;
  const _FlyingEmoji({
    super.key,
    required this.emoji,
    required this.seed,
    required this.onDone,
  });

  @override
  State<_FlyingEmoji> createState() => _FlyingEmojiState();
}

class _FlyingEmojiState extends State<_FlyingEmoji>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alignX = ((widget.seed % 80) / 80) * 1.4 - 0.7;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Align(
          alignment: Alignment(alignX, 0.9 - t * 1.6),
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Text(
              widget.emoji,
              style: TextStyle(fontSize: 28 + t * 20),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen paper burst. Used when a mimic lands in the high tier.
class _ConfettiBit {
  final double x0;
  final double vx;
  final double vy;
  final double spin0;
  final double spinV;
  final double w;
  final double h;
  final double delay;
  final Color color;
  final bool circle;
  const _ConfettiBit({
    required this.x0,
    required this.vx,
    required this.vy,
    required this.spin0,
    required this.spinV,
    required this.w,
    required this.h,
    required this.delay,
    required this.color,
    required this.circle,
  });
}

class _ConfettiField extends StatefulWidget {
  final int density;
  final VoidCallback onDone;
  const _ConfettiField({required this.density, required this.onDone});

  @override
  State<_ConfettiField> createState() => _ConfettiFieldState();
}

class _ConfettiFieldState extends State<_ConfettiField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_ConfettiBit> _bits;
  static const _palette = <Color>[
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFFC4B5FD),
    Color(0xFF34D399),
    Color(0xFF60A5FA),
    Color(0xFFFDE68A),
    Color(0xFFF9FAFB),
  ];

  @override
  void initState() {
    super.initState();
    final count = widget.density == 3
        ? 110
        : widget.density == 2
            ? 78
            : 48;
    final rng = Random(widget.density * 97 + count);
    _bits = [
      for (var i = 0; i < count; i++)
        _ConfettiBit(
          x0: rng.nextDouble(),
          vx: (rng.nextDouble() - 0.5) * 0.55,
          vy: 0.15 + rng.nextDouble() * 0.45,
          spin0: rng.nextDouble() * pi * 2,
          spinV: (rng.nextDouble() - 0.5) * 14,
          w: 6 + rng.nextDouble() * 8,
          h: 8 + rng.nextDouble() * 12,
          delay: rng.nextDouble() * 0.12,
          color: _palette[rng.nextInt(_palette.length)],
          circle: rng.nextBool(),
        ),
    ];
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) widget.onDone();
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _ConfettiPainter(bits: _bits, t: _ctrl.value),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiBit> bits;
  final double t;
  _ConfettiPainter({required this.bits, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final flash = (1 - (t / 0.18)).clamp(0.0, 1.0);
    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFFF7D6).withValues(alpha: 0.22 * flash),
      );
    }
    for (final bit in bits) {
      if (t < bit.delay) continue;
      final u = ((t - bit.delay) / (1 - bit.delay)).clamp(0.0, 1.0);
      final x = (bit.x0 + bit.vx * u) * size.width;
      final y = -20 + bit.vy * u * size.height + u * u * size.height * 0.85;
      final fade = u < 0.72 ? 1.0 : (1 - (u - 0.72) / 0.28).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(bit.spin0 + bit.spinV * u);
      final paint = Paint()..color = bit.color.withValues(alpha: fade);
      if (bit.circle) {
        canvas.drawCircle(Offset.zero, bit.w * 0.45, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: bit.w, height: bit.h),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Dramatic score reveal: ~1.5 s of spinning numbers with ticks, then an
/// overshoot pop onto the real score plus the shout line. A high score
/// throws confetti over the whole screen. Callers play sounds + haptics
/// via onTick/onLand so this widget stays silent about policy.
class DramaticScore extends StatefulWidget {
  final double score;
  final VoidCallback? onTick;
  final VoidCallback? onLand;
  const DramaticScore({
    super.key,
    required this.score,
    this.onTick,
    this.onLand,
  });

  @override
  State<DramaticScore> createState() => _DramaticScoreState();
}

class _DramaticScoreState extends State<DramaticScore>
    with SingleTickerProviderStateMixin {
  final _random = Random();
  late final AnimationController _pop;
  Timer? _spin;
  OverlayEntry? _confetti;
  double _display = 0;
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    var ticks = 0;
    _spin = Timer.periodic(const Duration(milliseconds: 90), (t) {
      if (!mounted) return;
      ticks++;
      if (ticks >= 16) {
        t.cancel();
        setState(() {
          _display = widget.score;
          _landed = true;
        });
        _pop.forward();
        _throwConfetti();
        try {
          widget.onLand?.call();
        } catch (_) {}
        return;
      }
      setState(() => _display = _random.nextDouble() * 100);
      try {
        widget.onTick?.call();
      } catch (_) {}
    });
  }

  @override
  void didUpdateWidget(covariant DramaticScore old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score && _landed) {
      setState(() => _display = widget.score);
    }
  }

  void _throwConfetti() {
    if (!CelebrationClip.isHigh(widget.score)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final density = widget.score >= 95
        ? 3
        : widget.score >= 85
            ? 2
            : 1;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _ConfettiField(
          density: density,
          onDone: () {
            if (_confetti != entry) return;
            _confetti = null;
            entry.remove();
          },
        ),
      ),
    );
    _confetti = entry;
    overlay.insert(entry);
  }

  void _dropConfetti() {
    final entry = _confetti;
    _confetti = null;
    entry?.remove();
  }

  @override
  void dispose() {
    _spin?.cancel();
    _dropConfetti();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _landed ? scoreColor(widget.score) : Colors.white;
    final number = Text(
      '${_display.round()}/100',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: _landed ? 88 : 72,
        fontWeight: FontWeight.w900,
        height: 1,
        shadows: _landed
            ? [
                Shadow(
                  color: color.withValues(alpha: 0.85),
                  blurRadius: 28,
                ),
              ]
            : const [],
      ),
    );
    final shout = AnimatedOpacity(
      opacity: _landed ? 1 : 0,
      duration: const Duration(milliseconds: 280),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          scoreLabel(widget.score),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [number, shout],
    );
    if (!_landed) return column;
    return ScaleTransition(
      scale: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
      ),
      child: column,
    );
  }
}

/// Coin balance chip (offline progression; nothing to spend on yet).
class CoinChip extends ConsumerWidget {
  const CoinChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(coinsProvider);
    return Chip(
      avatar: const Icon(Icons.monetization_on,
          size: 18, color: Colors.amber),
      label: Text('$coins',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      visualDensity: VisualDensity.compact,
    );
  }
}
