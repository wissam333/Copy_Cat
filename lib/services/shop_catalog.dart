// lib/services/shop_catalog.dart — what the shop sells.
// Characters: full 3D outfits (buy once, own forever, equip one).
// Everyone starts as the casual guy for free.
// Emojis: pay-per-send (no free sends). Sending deducts the price.
class AvatarDef {
  final String id;
  final String file; // assets/mascot3d/<file>.glb
  final String name;
  final int price; // 0 = free starter
  const AvatarDef({
    required this.id,
    required this.file,
    required this.name,
    required this.price,
  });

  String get asset => 'assets/mascot3d/$file.glb';
}

class ShopCatalog {
  static const String defaultAvatar = 'casual';

  /// Guard for the room gear string: a power-up id must never be
  /// mistaken for an avatar id (both travel as plain strings).
  static bool isPowerUp(String id) => ShopCatalogPowerUps.isPowerUp(id);

  static const List<AvatarDef> avatars = [
    AvatarDef(
        id: 'casual', file: 'Casual_Male', name: 'شاب عادي', price: 0),
    AvatarDef(
        id: 'casual_f',
        file: 'Casual_Female',
        name: 'بنت عادية',
        price: 200),
    AvatarDef(
        id: 'chef', file: 'Chef_Male', name: 'طباخ', price: 400),
    AvatarDef(id: 'elf', file: 'Elf', name: 'قزم', price: 500),
    AvatarDef(
        id: 'ninja', file: 'Ninja_Male', name: 'نينجا', price: 500),
    AvatarDef(
        id: 'zombie',
        file: 'Zombie_Male',
        name: 'زومبي',
        price: 600),
    AvatarDef(
        id: 'goblin',
        file: 'Goblin_Male',
        name: 'غول',
        price: 600),
    AvatarDef(id: 'cow', file: 'Cow', name: 'بقرة', price: 700),
    AvatarDef(id: 'pug', file: 'Pug', name: 'كلب', price: 700),
    AvatarDef(
        id: 'pirate',
        file: 'Pirate_Male',
        name: 'قرصان',
        price: 800),
    AvatarDef(
        id: 'viking',
        file: 'Viking_Male',
        name: 'فايكنج',
        price: 800),
    AvatarDef(
        id: 'wizard', file: 'Wizard', name: 'ساحر', price: 10000),
    AvatarDef(id: 'witch', file: 'Witch', name: 'ساحرة', price: 10000),
  ];

  static AvatarDef byId(String id) {
    for (final a in avatars) {
      if (a.id == id) return a;
    }
    return avatars.first;
  }

  static bool isAvatar(String id) {
    for (final a in avatars) {
      if (a.id == id) return true;
    }
    return false;
  }

  /// Price per send. No free emoji.
  static const Map<String, int> emojiPrices = {
    '😂': 10,
    '👏': 10,
    '😱': 15,
    '🍅': 30,
    '💩': 50,
  };

  static const List<String> emojis = ['😂', '👏', '😱', '🍅', '💩'];
}

/// One-shot consumables. Buying stores a stock count; using one consumes
/// exactly one (a failed use refunds nothing — aim before you spend).
class PowerUpDef {
  final String id;
  final String name;
  final String emoji;
  final int price;
  final String hint;

  /// When the room allows using it: 'myTurn' (×2), 'waiting' (⚡), or
  /// 'anytime' (🛡️).
  final String timing;
  const PowerUpDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.price,
    required this.hint,
    required this.timing,
  });
}

class ShopCatalogPowerUps {
  /// A ×2 armed before your turn doubles the recorded score (totals
  /// only — the base verdict stays 0–100).
  static const PowerUpDef double =
      PowerUpDef(
        id: 'double',
        name: 'مضاعفة',
        emoji: '✖️',
        price: 120,
        hint: 'قبل دورك: تتضاعف نقطة هذه الجولة في المجموع',
        timing: 'myTurn',
      );

  /// A 🛡️ removes the player's lowest round from their final total.
  static const PowerUpDef shield =
      PowerUpDef(
        id: 'shield',
        name: 'درع',
        emoji: '🛡️',
        price: 250,
        hint: 'أي وقت أثناء الحفلة: تُحذف أخفض جولة من مجموعك',
        timing: 'anytime',
      );

  /// A ⚡ forces the active player to redo their turn once (the second
  /// attempt replaces the first).
  static const PowerUpDef volt =
      PowerUpDef(
        id: 'volt',
        name: 'برق',
        emoji: '⚡',
        price: 80,
        hint: 'أثناء انتظار دور غيرك: أجبره على إعادة التقليد مرة',
        timing: 'waiting',
      );

  static const List<PowerUpDef> all = [double, shield, volt];

  static PowerUpDef byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return double;
  }

  static bool isPowerUp(String id) {
    for (final p in all) {
      if (p.id == id) return true;
    }
    return false;
  }
}
