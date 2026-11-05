// Final leaderboard. Points are the sum of each mimic, not a single try.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../i18n.dart';
import '../services/match_awards.dart';
import '../stage_theme.dart';
import '../state/game_state.dart';
import '../state/host_engine.dart';
import '../state/shop_store.dart';
import '../widgets/avatar_view.dart';
import '../widgets/ui_bits.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  /// The three end-of-match awards with a replay button when this phone
  /// holds the attempt WAV (solo: always; LAN: after the owner's upload).
  Widget _awards(
      BuildContext context,
      WidgetRef ref,
      List<MatchAward> awards,
      String Function(MatchAward) nameOf,
      String? Function(MatchAward) pathOf) {
    if (awards.isEmpty) return const SizedBox.shrink();
    const emoji = {'best': '🏆', 'funny': '🤡', 'steady': '🎯'};
    const title = {
      'best': 'أفضل تقليد',
      'funny': 'أطرف محاولة',
      'steady': 'الأكثر ثباتًا',
    };
    return Column(
      children: [
        SectionTitle(t('جوائز الحفلة')),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final a in awards)
                  ListTile(
                    leading: Text(emoji[a.kind] ?? '🏅',
                        style: const TextStyle(fontSize: 26)),
                    title: Text(t(title[a.kind] ?? ''),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${nameOf(a)} · ${t('{n} نقطة', {'n': a.score.round()})}'),
                    trailing: pathOf(a) == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () async {
                              try {
                                await ref
                                    .read(audioIoProvider)
                                    .playOnce(pathOf(a)!);
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(t('فشل التشغيل: {n}',
                                            {'n': e}))),
                                  );
                                }
                              }
                            },
                          ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  AttemptRecord? _soloAttempt(GameData game, MatchAward a) {
    for (final attempt in game.attempts) {
      if (attempt.playerId == a.playerId &&
          attempt.roundIndex == a.round) {
        return attempt;
      }
    }
    return null;
  }

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
        flexibleSpace: StageBlack.appBarGlow(),
        title: Text(t('نهاية الحفلة')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: const [
          CoinChip(),
          SizedBox(width: 8),
        ],
      ),
      body: StageBlack.background(
        child: SafeArea(
          child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Text(t(PartyModeView.of(match.mode).title),
                style:
                    TextStyle(fontSize: 13, color: StageBlack.muted)),
            const SizedBox(height: 8),
            if (ranked.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(t('لا نتائج بعد.')),
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
                  leading: Icon(Icons.emoji_events,
                      size: 36, color: StageBlack.gold),
                  title: Text(
                    winners.length == 1
                        ? t('الفائز: {n}',
                            {'n': nameOf(winners.first.key)})
                        : t('تعادل: {n}', {
                            'n': winners
                                .map((e) => nameOf(e.key))
                                .join(t('و'))
                          }),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle:
                      Text(t('{n} نقطة', {'n': top.round()})),
                ),
              ),
              _awards(
                context,
                ref,
                match.awards,
                (a) => nameOf(a.playerId),
                (a) => match.awardAudio[a.kind],
              ),
            ],
            SectionTitle(t('الترتيب')),
            Text(t('عملاتك تفتح شخصيات المتجر — بالتوفيق'),
                style: const TextStyle(fontSize: 12)),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final e in ranked)
                      // 🛡️ badge: a shielded player's total already excludes
                      // their worst round — named so the sum mismatch is
                      // explainable.
                      ScoreRow(
                        name: match.shields[e.key] == true
                            ? '🛡️ ${nameOf(e.key)}'
                            : nameOf(e.key),
                        score: e.value,
                        winner: top > 0 && e.value == top,
                        points: true,
                      ),
                  ],
                ),
              ),
            ),
            if (match.roundsTotal > 0) SectionTitle(t('الجولات')),
            for (var r = 0; r < match.roundsTotal; r++) ...[
              Text(t('الجولة {n}', {'n': r + 1}),
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
                label: t('نفس الحفلة'),
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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.hourglass_empty),
                  title: Text(t('انتظر حتى يبدأ المضيف حفلة جديدة')),
                ),
              ),
            const SizedBox(height: 8),
            AppButton(
              label: t('الرئيسية'),
              icon: Icons.home,
              primary: false,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
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
    final rounds = <int>{for (final a in game.attempts) a.roundIndex}.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: StageBlack.appBarGlow(),
        title: Text(t('نهاية الحفلة')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: const [
          CoinChip(),
          SizedBox(width: 8),
        ],
      ),
      body: StageBlack.background(
        child: SafeArea(
          child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            Text(t('اللعب بموبايل واحد'),
                style:
                    TextStyle(fontSize: 13, color: StageBlack.muted)),
            const SizedBox(height: 8),
            if (ranked.isEmpty || game.attempts.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(t('لا نتائج بعد — العب دورًا أولًا.')),
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
                  leading: Icon(Icons.emoji_events,
                      size: 36, color: StageBlack.gold),
                  title: Text(
                    winners.length == 1
                        ? t('الفائز: {n}', {'n': winners.first.name})
                        : t('تعادل: {n}', {
                            'n': winners.map((p) => p.name).join(t('و'))
                          }),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(t('{n} نقطة', {'n': top})),
                ),
              ),
              const SizedBox(height: 8),
              _awards(
                context,
                ref,
                matchAwards([
                  for (final a in game.attempts)
                    AwardEntry(a.playerId, a.roundIndex, a.score),
                ]),
                (a) => _soloAttempt(game, a)?.playerName ?? a.playerId,
                (a) => _soloAttempt(game, a)?.path,
              ),
            ],
            SectionTitle(t('الترتيب')),
            if (ranked.isEmpty)
              Text(t('لا يوجد.'),
                  style: TextStyle(color: StageBlack.muted))
            else ...[
              Text(t('عملاتك تفتح شخصيات المتجر — بالتوفيق'),
                  style: const TextStyle(fontSize: 12)),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final p in ranked)
                        ScoreRow(
                          name: p.name,
                          score: p.score.toDouble(),
                          winner: top > 0 && p.score == top,
                          points: true,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (rounds.isNotEmpty) SectionTitle(t('الجولات')),
            for (final round in rounds) ...[
              Text(
                t('الجولة {n} · {title}', {
                  'n': round + 1,
                  'title': game.attemptsForRound(round).first.soundTitle,
                }),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final a in ([...game.attemptsForRound(round)]
                ..sort((x, y) => y.score.compareTo(x.score))))
                ScoreRow(name: a.playerName, score: a.score),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            AppButton(
              label: t('العب مجددًا'),
              icon: Icons.replay,
              onPressed: () => context.go('/game?solo=1'),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: t('الرئيسية'),
              icon: Icons.home,
              primary: false,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
