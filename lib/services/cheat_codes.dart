// lib/services/cheat_codes.dart — secret coin codes, one-time each.
// Type the code into the home name field: coins drop, the field clears,
// and the code never pays twice (flag persists offline).
import 'package:shared_preferences/shared_preferences.dart';

enum CheatResult { granted, alreadyUsed, invalid }

class CheatCodes {
  static const Map<String, int> codes = {
    'wissam333!': 1000,
    'wissammagic': 20000,
  };

  static String _key(String code) =>
      'copycat.cheat.${code.hashCode}';

  static Future<CheatResult> redeem(
    String input,
    Future<void> Function(int amount) grant,
  ) async {
    final amount = codes[input];
    if (amount == null) return CheatResult.invalid;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_key(input)) == true) {
        return CheatResult.alreadyUsed;
      }
      await grant(amount);
      await prefs.setBool(_key(input), true);
      return CheatResult.granted;
    } catch (_) {
      return CheatResult.invalid;
    }
  }
}
