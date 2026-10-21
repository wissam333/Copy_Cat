// lib/services/identity_store.dart — remembers the player's name and
// room name between launches (shared_preferences, same version the
// sibling app already builds with, so no new native downloads).
import 'package:shared_preferences/shared_preferences.dart';

class IdentityStore {
  static const _nameKey = 'copycat.playerName';
  static const _roomKey = 'copycat.roomName';

  /// Filled in main() before runApp so providers start with saved values.
  static String? initialName;
  static String? initialRoom;

  static Future<(String?, String?)> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_nameKey), prefs.getString(_roomKey));
    } catch (_) {
      return (null, null);
    }
  }

  static Future<void> saveName(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, value);
    } catch (_) {}
  }

  static Future<void> saveRoom(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roomKey, value);
    } catch (_) {}
  }
}
