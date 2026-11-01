// lib/screens/home_screen.dart — one friendly hub: name, then play.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../i18n.dart';
import '../services/cheat_codes.dart';
import '../stage_theme.dart';
import '../state/coins.dart';
import '../state/game_state.dart';
import '../state/language.dart';
import '../state/shop_store.dart';
import '../state/theme_mode.dart';
import '../widgets/avatar_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _name;
  late final TextEditingController _room;

  @override
  void initState() {
    super.initState();
    final g = ref.read(gameProvider);
    _name = TextEditingController(text: g.playerName);
    _room = TextEditingController(text: g.roomName);
    // Fresh start: drop any previous LAN session so a new room never
    // shows the old LOCKED state.
    Future.microtask(() async {
      await ref.read(lanProvider).stopAll();
      final ctl = ref.read(gameProvider.notifier);
      ctl.setLocked(false, status: t('فردي (بدون شبكة)'));
      ref.read(matchProvider.notifier).reset();
      await ctl.reloadLibrary(ref.read(libraryProvider));
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    super.dispose();
  }

  /// Secret codes typed as the name: pay once, clear the field so the
  /// code never becomes the player's room name.
  Future<void> _redeemCheat(String code) async {
    final result = await CheatCodes.redeem(
      code,
      (amount) => ref.read(coinsProvider.notifier).add(amount),
    );
    _name.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          CheatResult.granted =>
            t('شفرة مقبولة! +{n} 🪙', {'n': CheatCodes.codes[code]}),
          CheatResult.alreadyUsed => t('استخدمت هذه الشفرة من قبل'),
          CheatResult.invalid => t('شفرة غير صالحة'),
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sounds = ref.watch(gameProvider).library.length;
    return Scaffold(
      body: StageBlack.background(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Wordmark row: gold-ring paw, title, tagline, theme + language.
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: StageBlack.panel,
                      shape: BoxShape.circle,
                      border: Border.all(color: StageBlack.gold, width: 1.5),
                    ),
                    child: Icon(Icons.pets,
                        size: 22, color: StageBlack.gold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Copy Cat',
                            style: TextStyle(
                                fontFamily: StageBlack.displayFont,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: StageBlack.text)),
                        Text(t('قلّد الصوت… واجمع النقاط!'),
                            style: TextStyle(
                                fontSize: 13, color: StageBlack.muted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Theme toggle: icon shows the mode you'll switch to.
                  IconButton(
                    onPressed: () =>
                        ref.read(themeProvider.notifier).set(!StageBlack.isLight),
                    icon: Icon(StageBlack.isLight
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined),
                    color: StageBlack.text,
                  ),
                  // Language pill: label always names the OTHER language.
                  InkWell(
                    onTap: () => ref
                        .read(languageProvider.notifier)
                        .set(currentLanguage == AppLanguage.english
                            ? AppLanguage.arabic
                            : AppLanguage.english),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: StageBlack.lineStrong),
                      ),
                      child: Text(
                          currentLanguage == AppLanguage.english
                              ? 'عربي'
                              : 'EN',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: StageBlack.text)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                t(sounds == 0
                    ? 'سجّل صوتًا من ٢–٦ ثوانٍ في أصواتي، ثم العب.'
                    : 'لديك {n} أصوات. اختر:',
                    {'n': sounds}),
                style: TextStyle(
                    fontSize: 14, height: 1.35, color: StageBlack.muted),
              ),
              const SizedBox(height: 10),
              // Way 1: this phone, passed around.
              _PlayPanel(
                title: t('هذا الموبايل'),
                line: t('مرّر الموبايل — كل لاعب يقلّد في دوره.'),
                child: FilledButton.icon(
                  onPressed: () => context.go('/party'),
                  icon: const Icon(Icons.smartphone, size: 24),
                  label: Text(t('اللعب بموبايل واحد'),
                      style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 10),
              // Way 2: same Wi-Fi, equal weight, two outlined actions.
              _PlayPanel(
                title: t('نفس الواي فاي'),
                line: t('كل لاعب على موبايله.'),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/lobby?host=1'),
                        icon: const Icon(Icons.add_home),
                        label: Text(t('إنشاء غرفة')),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/lobby?host=0'),
                        icon: const Icon(Icons.group_add),
                        label: Text(t('انضمام')),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                      ),
                    ),
                  ],
                ),
              ),
              // My sounds: a quiet row, not a third tile.
              TextButton.icon(
                onPressed: () => context.go('/library'),
                icon: const Icon(Icons.library_music, size: 20),
                label: Text(t('أصواتي')),
              ),
              const SizedBox(height: 4),
              // Character + coin balance row.
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.go('/shop'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        AvatarView(
                          avatarId: ref.watch(shopProvider).avatar,
                          size: 56,
                          height: 74,
                          lightweight: true,
                          maxFrameRate: 8,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t('شخصيتك — اضغط للمتجر'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  t('رصيدك {n} 🪙', {
                                    'n': ref.watch(coinsProvider)
                                  }),
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: StageBlack.muted)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 18, color: StageBlack.muted),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Name + room fields on one row (cheat codes included).
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _name,
                          decoration: InputDecoration(
                            labelText: t('اسمك'),
                            prefixIcon: const Icon(Icons.person),
                          ),
                          onChanged: (v) {
                            if (CheatCodes.codes.containsKey(v)) {
                              _redeemCheat(v);
                              return;
                            }
                            ref.read(gameProvider.notifier).setName(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _room,
                          decoration: InputDecoration(
                            labelText: t('اسم الغرفة'),
                            prefixIcon: const Icon(Icons.meeting_room),
                          ),
                          onChanged: (v) =>
                              ref.read(gameProvider.notifier).setRoom(v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'built by Wissam Najjom',
                  style: TextStyle(fontSize: 11, color: StageBlack.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the two "ways to play" panels: title, muted line, action(s).
class _PlayPanel extends StatelessWidget {
  final String title;
  final String line;
  final Widget child;
  const _PlayPanel(
      {required this.title, required this.line, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(line,
                style: TextStyle(
                    fontSize: 13, height: 1.35, color: StageBlack.muted)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
