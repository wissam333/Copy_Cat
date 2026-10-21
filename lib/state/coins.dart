// lib/state/coins.dart — offline game coins. Earned per attempt, stored
// on-device. Nothing to spend them on yet (shop comes later).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoinsController extends Notifier<int> {
  static const _key = 'copycat.coins';

  @override
  int build() {
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final v = prefs.getInt(_key) ?? 0;
        // Only fill the fresh default: never clobber coins earned
        // after startup.
        if (state == 0 && v != 0) state = v;
      } catch (_) {}
    });
    return 0;
  }

  Future<void> add(int n) async {
    if (n <= 0) return;
    state = state + n;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, state);
    } catch (_) {}
  }

  /// Spends coins for shop buys and paid emoji sends.
  /// Returns false (and spends nothing) when the balance is too low.
  Future<bool> spend(int n) async {
    if (n <= 0) return true;
    if (state < n) return false;
    state = state - n;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, state);
    } catch (_) {}
    return true;
  }
}

final coinsProvider =
    NotifierProvider<CoinsController, int>(CoinsController.new);
