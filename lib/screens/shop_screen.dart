// lib/screens/shop_screen.dart — spend coins on 3D characters, emoji and
// one-shot power-ups. Characters: buy once, equip one, synced to the room
// as your look. Emojis: pay-per-send, no free sends, no unlocks.
// Power-ups: buy stock once, every use consumes exactly one unit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../i18n.dart';
import '../services/shop_catalog.dart';
import '../state/coins.dart';
import '../state/shop_store.dart';
import '../widgets/avatar_view.dart';
import '../widgets/ui_bits.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  int _tab = 0;
  String? _previewId;

  @override
  Widget build(BuildContext context) {
    final coins = ref.watch(coinsProvider);
    final shop = ref.watch(shopProvider);
    final previewId = _previewId ?? shop.avatar;
    final preview = ShopCatalog.byId(previewId);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('المتجر')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        actions: const [CoinChip(), SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                    value: 0,
                    icon: const Icon(Icons.person),
                    label: Text(t('شخصيات'))),
                ButtonSegment(
                    value: 1,
                    icon: const Text('😂', style: TextStyle(fontSize: 18)),
                    label: Text(t('إيموجي'))),
                ButtonSegment(
                    value: 2,
                    icon: const Icon(Icons.bolt),
                    label: Text(t('قوى'))),
              ],
              selected: {_tab},
              onSelectionChanged: (s) =>
                  setState(() => _tab = s.first),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? _charactersTab(context, shop, coins, preview)
                : _tab == 1
                    ? _emojiTab(coins)
                    : _powerTab(coins, shop),
          ),
        ],
      ),
    );
  }

  Widget _charactersTab(BuildContext context, ShopData shop, int coins,
      AvatarDef preview) {
    final owned = shop.owned.contains(preview.id);
    final equipped = shop.avatar == preview.id;
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    AvatarView(
                      avatarId: preview.id,
                      size: 200,
                      height: 246,
                      interactive: true,
                    ),
                    const SizedBox(height: 4),
                    Text(t(preview.name),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _buyEquipButton(preview, owned, equipped, coins),
                    const SizedBox(height: 4),
                    Text(t('اسحب يمينًا فيدور الوجه مع إصبعك'),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.64,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final a = ShopCatalog.avatars[i];
                return _ShopAvatarTile(
                  avatar: a,
                  selected: a.id == preview.id,
                  equipped: shop.avatar == a.id,
                  onTap: () => setState(() => _previewId = a.id),
                );
              },
              childCount: ShopCatalog.avatars.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buyEquipButton(
      AvatarDef a, bool owned, bool equipped, int coins) {
    if (equipped) {
      return Chip(label: Text(t('شخصيتك الحالية')));
    }
    if (owned) {
      return FilledButton.icon(
        onPressed: () =>
            ref.read(shopProvider.notifier).equip(a.id),
        icon: const Icon(Icons.checkroom),
        label: Text(t('جهّز هذه الشخصية')),
      );
    }
    return FilledButton.icon(
      onPressed: coins >= a.price ? () => _buy(a) : null,
      icon: const Text('🪙'),
      label: Text(coins >= a.price
          ? t('اشترِ بـ {n}', {'n': a.price})
          : t('ينقصك {n} — العب لتجمع', {'n': a.price - coins})),
    );
  }

  Future<void> _buy(AvatarDef a) async {
    final ok = await ref.read(shopProvider.notifier).buy(a.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? t('أصبحت {n} لك! جهّزها لتظهر في الحفلة',
                {'n': t(a.name)})
            : t('عملاتك لا تكفي — العب واجمع المزيد')),
      ),
    );
    if (ok) {
      await ref.read(shopProvider.notifier).equip(a.id);
    }
  }

  Widget _emojiTab(int coins) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              t('لا يوجد إيموجي مجاني هنا. كل إرسال أثناء انتظار دور غيرك يسحب من رصيدك فورًا — الأوقح أغلى.'),
              style: const TextStyle(height: 1.4),
            ),
          ),
        ),
        for (final e in ShopCatalog.emojis)
          Card(
            child: ListTile(
              leading: Text(e, style: const TextStyle(fontSize: 32)),
              title: Text(t('🪙 {n} لكل إرسال',
                  {'n': ShopCatalog.emojiPrices[e]})),
              trailing: coins >= (ShopCatalog.emojiPrices[e] ?? 0)
                  ? const Icon(Icons.check, color: Colors.green)
                  : const Icon(Icons.lock_outline, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  /// One-shot power-ups: buying adds to the stock, every in-match use
  /// burns exactly one. All are host-enforced inside the match.
  Widget _powerTab(int coins, ShopData shop) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              t('قوى تُستخدم مرة واحدة أثناء الحفلة. الشراء يضيف للمخزون، وكل استخدام يستهلك وحدة — الحكم على التوقيت هو المضيف، والاستخدام الخاطئ لا يُسترَد.'),
              style: const TextStyle(height: 1.4),
            ),
          ),
        ),
        for (final p in ShopCatalogPowerUps.all)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(p.emoji,
                          style: const TextStyle(fontSize: 30)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(t(p.name),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text(
                          t('المخزون: {n}',
                              {'n': shop.inventory[p.id] ?? 0}),
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(t(p.hint),
                      style: const TextStyle(height: 1.35, fontSize: 13)),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: coins >= p.price
                        ? () => _buyPower(p)
                        : null,
                    icon: const Text('🪙'),
                    label: Text(coins >= p.price
                        ? t('اشترِ بـ {n}', {'n': p.price})
                        : t('ينقصك {n} — العب لتجمع',
                            {'n': p.price - coins})),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _buyPower(PowerUpDef p) async {
    final ok = await ref.read(shopProvider.notifier).buyPowerUp(p.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? t('وحدة {n} في مخزونك — استخدمها أثناء الحفلة',
                {'n': t(p.name)})
            : t('عملاتك لا تكفي — العب واجمع المزيد')),
      ),
    );
  }
}

class _ShopAvatarTile extends StatelessWidget {
  final AvatarDef avatar;
  final bool selected;
  final bool equipped;
  final VoidCallback onTap;
  const _ShopAvatarTile({
    required this.avatar,
    required this.selected,
    required this.equipped,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = equipped
        ? t('مجهز')
        : (avatar.price == 0 ? t('مجاني') : '🪙 ${avatar.price}');
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Column(
              children: [
                Expanded(
                  child: BakedAvatar(avatarId: avatar.id),
                ),
                const SizedBox(height: 2),
                Text(
                  t(avatar.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
