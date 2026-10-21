// Shop tests: everyone starts casual, buys cost coins, gear is one id.
import 'package:copy_cat/services/shop_catalog.dart';
import 'package:copy_cat/state/coins.dart';
import 'package:copy_cat/state/shop_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('everyone starts as the free casual guy', () {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final shop = container.read(shopProvider);
    expect(shop.avatar, ShopCatalog.defaultAvatar);
    expect(shop.avatar, 'casual');
    expect(shop.owned, contains('casual'));
    expect(shop.gearString(), 'casual');
  });

  test('unknown gear falls back to casual', () {
    expect(ShopData.avatarOf(null), 'casual');
    expect(ShopData.avatarOf(''), 'casual');
    expect(ShopData.avatarOf('nope'), 'casual');
    expect(ShopData.avatarOf('pirate'), 'pirate');
  });

  test('emojis all cost coins, the rude one costs most', () {
    expect(ShopCatalog.emojis, hasLength(5));
    for (final e in ShopCatalog.emojis) {
      expect(ShopCatalog.emojiPrices[e] ?? 0, greaterThan(0));
    }
    final poop = ShopCatalog.emojiPrices['💩']!;
    for (final e in ShopCatalog.emojis) {
      expect(poop, greaterThanOrEqualTo(ShopCatalog.emojiPrices[e]!));
    }
  });

  test('buy deducts, equip switches, re-tap returns to casual',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(coinsProvider.notifier).add(1000);

    // Pirate costs 800.
    expect(await container.read(shopProvider.notifier).buy('pirate'),
        isTrue);
    expect(container.read(shopProvider).owned, contains('pirate'));
    expect(container.read(coinsProvider), 200);

    // Buying twice fails and costs nothing.
    expect(await container.read(shopProvider.notifier).buy('pirate'),
        isFalse);
    expect(container.read(coinsProvider), 200);

    // Witch costs 1000, we have 200: fails.
    expect(await container.read(shopProvider.notifier).buy('witch'),
        isFalse);
    expect(
        container.read(shopProvider).owned, isNot(contains('witch')));

    // Equip + unequip by tapping again.
    await container.read(shopProvider.notifier).equip('pirate');
    expect(container.read(shopProvider).avatar, 'pirate');
    expect(container.read(shopProvider).gearString(), 'pirate');
    await container.read(shopProvider.notifier).equip('pirate');
    expect(container.read(shopProvider).avatar, 'casual');

    // Cannot equip what we do not own.
    await container.read(shopProvider.notifier).equip('witch');
    expect(container.read(shopProvider).avatar, 'casual');
  });

  test('spend refuses more than the balance', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(coinsProvider.notifier).add(30);
    expect(
        await container.read(coinsProvider.notifier).spend(50),
        isFalse);
    expect(container.read(coinsProvider), 30);
    expect(
        await container.read(coinsProvider.notifier).spend(30),
        isTrue);
    expect(container.read(coinsProvider), 0);
  });

  test('power-up catalog: three one-shots, each priced and timed', () {
    expect(ShopCatalogPowerUps.all, hasLength(3));
    final ids = ShopCatalogPowerUps.all.map((p) => p.id).toSet();
    expect(ids, {'double', 'shield', 'volt'});
    for (final p in ShopCatalogPowerUps.all) {
      expect(p.price, greaterThan(0));
      expect(ShopCatalogPowerUps.isPowerUp(p.id), isTrue);
      expect(ShopCatalog.isAvatar(p.id), isFalse, reason: 'a power-up '
          'id must not collide with an avatar id (gear is a plain id)');
    }
    for (final a in ShopCatalog.avatars) {
      expect(ShopCatalogPowerUps.isPowerUp(a.id), isFalse,
          reason: 'avatar id collides with a power-up id: ${a.id}');
    }
    expect(ShopCatalogPowerUps.byId('double').timing, 'myTurn');
    expect(ShopCatalogPowerUps.byId('volt').timing, 'waiting');
    expect(ShopCatalogPowerUps.byId('shield').timing, 'anytime');
    // Errors degrade to a real def, never null.
    expect(ShopCatalogPowerUps.byId('nope').id, 'double');
    expect(ShopCatalogPowerUps.isPowerUp('nope'), isFalse);
  });

  test('buy adds stock and deducts coins, use burns one', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(coinsProvider.notifier).add(1000);
    final price = ShopCatalogPowerUps.byId('volt').price;

    expect(await container.read(shopProvider.notifier).buyPowerUp('volt'),
        isTrue);
    expect(container.read(coinsProvider), 1000 - price);
    expect(container.read(shopProvider).inventory['volt'], 1);

    expect(await container.read(shopProvider.notifier).buyPowerUp('bolt'),
        isFalse);
    expect(container.read(shopProvider).inventory['bolt'], isNull);

    // Each use consumes exactly one; four uses on one in stock fail.
    Future<bool> use() async => container
        .read(shopProvider.notifier)
        .usePowerUp('volt');
    expect(await use(), isTrue);
    expect(await use(), isFalse);
    expect(container.read(shopProvider).inventory['volt'] ?? 0, 0);

    // Buying more works again: stock can stack.
    await container.read(coinsProvider.notifier).add(price);
    expect(await container.read(shopProvider.notifier).buyPowerUp('volt'),
        isTrue);
    expect(await container.read(shopProvider.notifier).buyPowerUp('volt'),
        isTrue);
    expect(container.read(shopProvider).inventory['volt'], 2);
    expect(await use(), isTrue);
    expect(container.read(shopProvider).inventory['volt'], 1);
  });

  test('power-up stock persists across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    await first.read(coinsProvider.notifier).add(1000);
    await first.read(shopProvider.notifier).buyPowerUp('shield');
    await first.read(shopProvider.notifier).buyPowerUp('shield');
    first.dispose();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('copycat.powerups'), '{"shield":2}');

    // Same mock store: a fresh "app run" still owns two shields. The
    // first read instantiates the notifier and queues its load; the
    // read AFTER the delay sees the loaded state (same as the UI).
    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(shopProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(second.read(shopProvider).inventory, {'shield': 2});
  });
}
