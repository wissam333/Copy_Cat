// lib/widgets/sprite_button.dart — myinstants-style play button.
// Two exact frame files (normal | pressed) on a stable random-bright bg
// color. Press-and-hold swaps to the pressed frame, like the site's
// :active state; release fires the tap.
import 'package:flutter/material.dart';

class SpriteButton extends StatefulWidget {
  final VoidCallback? onTap;
  final double size;
  final String seed;

  /// Held down OR currently playing: shows the pressed frame.
  final bool playing;

  /// Stable "random" color per sound: same seed, same color, no flashing.
  static Color colorFor(String seed) {
    const palette = [
      Color(0xFFE53935), // red
      Color(0xFFFB8C00), // orange
      Color(0xFF43A047), // green
      Color(0xFF1E88E5), // blue
      Color(0xFF8E24AA), // purple
      Color(0xFFD81B60), // pink
      Color(0xFF00897B), // teal
      Color(0xFF6D4C41), // brown
    ];
    return palette[seed.hashCode.abs() % palette.length];
  }

  const SpriteButton({
    super.key,
    required this.onTap,
    required this.seed,
    this.size = 46,
    this.playing = false,
  });

  @override
  State<SpriteButton> createState() => _SpriteButtonState();
}

class _SpriteButtonState extends State<SpriteButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap!();
            }
          : null,
      onTapCancel: () => setState(() => _down = false),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: SpriteButton.colorFor(widget.seed),
            borderRadius:
                BorderRadius.circular(widget.size * 0.22),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(widget.size * 0.22),
            child: Image.asset(
              _down || widget.playing
                  ? 'assets/sprite_play_pressed.png'
                  : 'assets/sprite_play_normal.png',
              width: widget.size,
              height: widget.size,
              fit: BoxFit.fill,
            ),
          ),
        ),
      ),
    );
  }
}
