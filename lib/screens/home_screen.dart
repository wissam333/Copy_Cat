// lib/screens/home_screen.dart — one friendly hub: name, then play.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/cheat_codes.dart';
import '../state/coins.dart';
import '../state/game_state.dart';
import '../state/shop_store.dart';
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
      ctl.setLocked(false, status: 'فردي (بدون شبكة)');
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
            'شفرة مقبولة! +${CheatCodes.codes[code]} 🪙',
          CheatResult.alreadyUsed => 'استخدمت هذه الشفرة من قبل',
          CheatResult.invalid => 'شفرة غير صالحة',
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sounds = ref.watch(gameProvider).library.length;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.pets,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Copy Cat',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      Text('قلّد الصوت… واجمع النقاط!',
                          style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              sounds == 0
                  ? 'سجّل صوتًا من ٢–٦ ثوانٍ في أصواتي، ثم العب.'
                  : 'لديك $sounds أصوات. اختر:',
              style: const TextStyle(height: 1.35),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => context.go('/party'),
              icon: const Icon(Icons.smartphone, size: 26),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('اللعب بموبايل واحد',
                    style: TextStyle(fontSize: 20)),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MenuCard(
                    icon: Icons.add_home,
                    label: 'إنشاء غرفة',
                    onTap: () => context.go('/lobby?host=1'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MenuCard(
                    icon: Icons.group_add,
                    label: 'انضمام',
                    onTap: () => context.go('/lobby?host=0'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MenuCard(
                    icon: Icons.library_music,
                    label: 'أصواتي',
                    onTap: () => context.go('/library'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => context.go('/shop'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      AvatarView(
                        avatarId:
                            ref.watch(shopProvider).avatar,
                        size: 56,
                        height: 74,
                        lightweight: true,
                        maxFrameRate: 8,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('شخصيتك — اضغط للمتجر',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800)),
                            Text(
                                'رصيدك ${ref.watch(coinsProvider)} 🪙',
                                style: const TextStyle(
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'اسمك',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        if (CheatCodes.codes.containsKey(v)) {
                          _redeemCheat(v);
                          return;
                        }
                        ref
                            .read(gameProvider.notifier)
                            .setName(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _room,
                      decoration: const InputDecoration(
                        labelText: 'اسم الغرفة (للاستضافة)',
                        prefixIcon: Icon(Icons.meeting_room),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => ref
                          .read(gameProvider.notifier)
                          .setRoom(v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'العب مع أصدقائك على نفس شبكة الواي فاي',
                style:
                    TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'built by Wissam Najjom',
                style:
                    TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One big tappable menu tile.
class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
