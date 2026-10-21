// Final leaderboard. Points are the sum of each mimic, not a single try.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/game_state.dart';
import '../state/host_engine.dart';
import '../state/shop_store.dart';
import '../widgets/avatar_view.dart';
import '../widgets/ui_bits.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider);
    ref.listen<LanMatchData>(matchProvider, (prev, next) {
      if (next.screen == 'game' &&
          prev?.screen != 'game' &&
          context.mounted) {
        context.go('/game');
      }
    });
    if (match.active) {
      return _lanResults(context, ref, match);
    }
    return _soloResults(context, ref);
  }

  Widget _lanResults(
      BuildContext context, WidgetRef ref, LanMatchData match) {
    String nameOf(String id) => match.nameOf(id);
    final ranked = match.totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.isEmpty ? 0.0 : ranked.first.value;
    final winners =
        ranked.where((e) => top > 0 && e.value == top).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('نهاية الحفلة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: const [
          CoinChip(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(PartyModeView.of(match.mode).title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (ranked.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('لا نتائج بعد.'),
                ),
              )
            else ...[
              if (winners.length == 1)
                Center(
                  child: AvatarView(
                    avatarId: ShopData.avatarOf(
                        match.gear[winners.first.key]),
                    celebration: 'Victory',
                    size: 150,
                    height: 196,
                  ),
                )
              else if (ranked.length > 1)
                // Draw: the top two celebrate side by side.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final e in ranked.take(2))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8),
                        child: AvatarView(
                          avatarId: ShopData.avatarOf(
                              match.gear[e.key]),
                          celebration: 'Victory',
                          size: 96,
                          height: 126,
                        ),
                      ),
                  ],
                ),
              if (winners.length == 1 && ranked.length > 1)
                // Runner-up stands beside the champion.
                Center(
                  child: AvatarView(
                    avatarId: ShopData.avatarOf(
                        match.gear[ranked[1].key]),
                    size: 84,
                    height: 110,
                  ),
                ),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.emoji_events, size: 36),
                  title: Text(
                    winners.length == 1
                        ? 'الفائز: ${nameOf(winners.first.key)}'
                        : 'تعادل: ${winners.map((e) => nameOf(e.key)).join(' و ')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${top.round()} نقطة'),
                ),
              ),
            ],
            const SectionTitle('الترتيب'),
            const Text('عملاتك تفتح شخصيات المتجر — بالتوفيق',
                style: TextStyle(fontSize: 12)),
            for (final e in ranked)
              // 🛡️ badge: a shielded player's total already excludes their
              // worst round — named so the sum mismatch is explainable.
              ScoreRow(
                name: match.shields[e.key] == true
                    ? '🛡️ ${nameOf(e.key)}'
                    : nameOf(e.key),
                score: e.value,
                winner: top > 0 && e.value == top,
                points: true,
              ),
            if (match.roundsTotal > 0) const SectionTitle('الجولات'),
            for (var r = 0; r < match.roundsTotal; r++) ...[
              Text('الجولة ${r + 1}',
                  style:
                      const TextStyle(fontWeight: FontWeight.w700)),
              for (final p in match.order)
                ScoreRow(
                  name: p.name,
                  score: (r < (match.roundScores[p.id]?.length ?? 0))
                      ? match.roundScores[p.id]![r]
                      : 0,
                ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            if (match.iAmHost)
              AppButton(
                label: 'نفس الحفلة',
                icon: Icons.replay,
                onPressed: () async {
                  final err = await ref
                      .read(hostEngineProvider)
                      .rematch();
                  if (err != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)),
                    );
                  }
                },
              )
            else
              const Card(
                child: ListTile(
                  leading: Icon(Icons.hourglass_empty),
                  title: Text('انتظر حتى يبدأ المضيف حفلة جديدة'),
                ),
              ),
            const SizedBox(height: 8),
            AppButton(
              label: 'الرئيسية',
              icon: Icons.home,
              primary: false,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _soloResults(BuildContext context, WidgetRef ref) {
    final game = ref.watch(gameProvider);
    final ranked = [...game.players]
      ..sort((a, b) => b.score.compareTo(a.score));
    final top = ranked.isEmpty ? 0 : ranked.first.score;
    final winners =
        ranked.where((p) => top > 0 && p.score == top).toList();
    final best = game.bestAttempt;
    final rounds = <int>{for (final a in game.attempts) a.roundIndex}.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('نهاية الحفلة'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: const [
          CoinChip(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('اللعب بموبايل واحد',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (ranked.isEmpty || game.attempts.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('لا نتائج بعد — العب دورًا أولًا.'),
                ),
              )
            else ...[
              if (winners.length == 1)
                Center(
                  child: AvatarView(
                    avatarId: ref.watch(shopProvider).avatar,
                    celebration: 'Victory',
                    size: 150,
                    height: 196,
                  ),
                ),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.emoji_events, size: 36),
                  title: Text(
                    winners.length == 1
                        ? 'الفائز: ${winners.first.name}'
                        : 'تعادل: ${winners.map((p) => p.name).join(' و ')}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('$top نقطة'),
                ),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'تشغيل أفضل محاولة',
                icon: Icons.play_arrow,
                primary: false,
                onPressed: best?.path == null
                    ? null
                    : () async {
                        try {
                          await ref.read(audioIoProvider).playOnce(best!.path!);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('فشل التشغيل: $e')),
                            );
                          }
                        }
                      },
              ),
            ],
            const SectionTitle('الترتيب'),
            if (ranked.isEmpty)
              const Text('لا يوجد.')
            else ...[
              const Text('عملاتك تفتح شخصيات المتجر — بالتوفيق',
                  style: TextStyle(fontSize: 12)),
              for (final p in ranked)
                ScoreRow(
                  name: p.name,
                  score: p.score.toDouble(),
                  winner: top > 0 && p.score == top,
                  points: true,
                ),
            ],
            if (rounds.isNotEmpty) const SectionTitle('الجولات'),
            for (final round in rounds) ...[
              Text(
                'الجولة ${round + 1} · ${game.attemptsForRound(round).first.soundTitle}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final a in ([...game.attemptsForRound(round)]
                ..sort((x, y) => y.score.compareTo(x.score))))
                ScoreRow(name: a.playerName, score: a.score),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            AppButton(
              label: 'العب مجددًا',
              icon: Icons.replay,
              onPressed: () => context.go('/game?solo=1'),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'الرئيسية',
              icon: Icons.home,
              primary: false,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }
}
