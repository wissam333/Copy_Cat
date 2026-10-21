// lib/state/shop_store.dart — owned characters + equipped avatar + the
// one-shot power-up stock. Persists offline. The equipped avatar syncs to
// the room as a plain id.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/shop_catalog.dart';
import 'coins.dart';

class ShopData {
  final Set<String> owned;
  final String avatar;

  /// Power-up stock, e.g. {'double': 1, 'shield': 2}.
  final Map<String, int> inventory;
  const ShopData({
    this.owned = const {'casual'},
    this.avatar = ShopCatalog.defaultAvatar,
    this.inventory = const {},
  });

  /// The gear string is just the avatar id (e.g. "pirate").
  String gearString() => avatar;

  /// Unknown/empty gear falls back to the free starter.
  static String avatarOf(String? gear) {
    final id = (gear ?? '').trim();
    return ShopCatalog.isAvatar(id) ? id : ShopCatalog.defaultAvatar;
  }
}

class ShopController extends Notifier<ShopData> {
  static const _ownedKey = 'copycat.shop.owned';
  static const _avatarKey = 'copycat.shop.avatar';
  static const _powerKey = 'copycat.powerups';

  @override
  ShopData build() {
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedOwned = prefs.getStringList(_ownedKey);
        final storedAvatar = prefs.getString(_avatarKey);
        final storedPower = prefs.getString(_powerKey);
        if (storedOwned != null ||
            storedAvatar != null ||
            storedPower != null) {
          state = ShopData(
            owned: {
              ShopCatalog.defaultAvatar,
              ...?storedOwned,
            },
            avatar: ShopData.avatarOf(storedAvatar),
            inventory: _decodePower(storedPower),
          );
        }
      } catch (_) {}
    });
    return const ShopData();
  }

  static Map<String, int> _decodePower(String? raw) {
    final out = <String, int>{};
    if (raw == null || raw.isEmpty) return out;
    try {
      final obj = jsonDecode(raw);
      if (obj is Map) {
        obj.forEach((k, v) {
          final id = k.toString();
          final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
          if (ShopCatalogPowerUps.isPowerUp(id) && n > 0) out[id] = n;
        });
      }
    } catch (_) {}
    return out;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_ownedKey, state.owned.toList());
      await prefs.setString(_avatarKey, state.avatar);
      await prefs.setString(
        _powerKey,
        jsonEncode({
          for (final e in state.inventory.entries) e.key: e.value,
        }),
      );
    } catch (_) {}
  }

  /// Buys a character once. False when already owned or coins too low.
  /// Free (price 0) characters are granted without touching coins.
  Future<bool> buy(String id) async {
    final def = ShopCatalog.byId(id);
    if (!ShopCatalog.isAvatar(id) || state.owned.contains(id)) {
      return false;
    }
    if (def.price > 0) {
      final paid =
          await ref.read(coinsProvider.notifier).spend(def.price);
      if (!paid) return false;
    }
    state = ShopData(
        owned: {...state.owned, id},
        avatar: state.avatar,
        inventory: state.inventory);
    await _save();
    return true;
  }

  /// Equips an owned character (tap the equipped one to go back to casual).
  Future<void> equip(String id) async {
    if (!state.owned.contains(id)) return;
    state = ShopData(
      owned: state.owned,
      avatar: state.avatar == id
          ? ShopCatalog.defaultAvatar
          : id,
      inventory: state.inventory,
    );
    await _save();
  }

  /// Adds one power-up to stock. False when coins fall short.
  Future<bool> buyPowerUp(String id) async {
    if (!ShopCatalogPowerUps.isPowerUp(id)) return false;
    final def = ShopCatalogPowerUps.byId(id);
    final paid = await ref.read(coinsProvider.notifier).spend(def.price);
    if (!paid) return false;
    state = ShopData(
      owned: state.owned,
      avatar: state.avatar,
      inventory: {
        ...state.inventory,
        id: (state.inventory[id] ?? 0) + 1,
      },
    );
    await _save();
    return true;
  }

  /// Consumes one unit from stock. Throwing units are spent by the caller
  /// right before the effect lands (×2 arm, ⚡ send, 🛡️ send) — refunds
  /// are deliberate none: a wasted arm is a lesson, not a bug report.
  Future<bool> usePowerUp(String id) async {
    if (!ShopCatalogPowerUps.isPowerUp(id)) return false;
    final have = state.inventory[id] ?? 0;
    if (have <= 0) return false;
    state = ShopData(
      owned: state.owned,
      avatar: state.avatar,
      inventory: {
        ...state.inventory,
        id: have - 1,
      },
    );
    await _save();
    return true;
  }

  String gearString() => state.gearString();
}

final shopProvider =
    NotifierProvider<ShopController, ShopData>(ShopController.new);
