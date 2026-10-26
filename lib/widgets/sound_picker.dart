// Pick one challenge or an ordered queue of them.
import 'package:flutter/material.dart';

import '../i18n.dart';
import '../models/game_sound.dart';
import 'sprite_button.dart';

class SoundPicker extends StatelessWidget {
  final List<GameSound> sounds;
  final List<String> selectedIds;
  final bool multi;
  final ValueChanged<GameSound> onTap;
  final Future<void> Function(GameSound sound)? onPreview;

  const SoundPicker({
    super.key,
    required this.sounds,
    required this.selectedIds,
    required this.onTap,
    this.multi = false,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (sounds.isEmpty) {
      return Center(child: Text(t('المكتبة فارغة.')));
    }
    return ListView.separated(
      itemCount: sounds.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final sound = sounds[i];
        final order = selectedIds.indexOf(sound.id);
        final selected = order >= 0;
        return Material(
          color: selected ? scheme.primaryContainer : Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTap(sound),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: selected
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    foregroundColor: selected ? Colors.white : scheme.primary,
                    child: Text(selected ? '${order + 1}' : '${i + 1}'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sound.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          t('{n} ثانية',
                              {'n': sound.durationSeconds.toStringAsFixed(1)}),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (onPreview != null)
                    SpriteButton(
                      seed: sound.id,
                      size: 42,
                      onTap: () => onPreview!(sound),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
