// Party-fun tests: funny lines stay in their tiers, coins persist.
import 'package:copy_cat/services/funny_lines.dart';
import 'package:copy_cat/state/coins.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('funny lines come from the right tier', () {
    for (var i = 0; i < 30; i++) {
      expect(FunnyLines.tier1, contains(FunnyLines.pickFor(5)));
      expect(FunnyLines.tier2, contains(FunnyLines.pickFor(25)));
      expect(FunnyLines.tier3, contains(FunnyLines.pickFor(55)));
      expect(FunnyLines.tier4, contains(FunnyLines.pickFor(75)));
      expect(FunnyLines.tier5, contains(FunnyLines.pickFor(95)));
    }
    expect(FunnyLines.pickFor(100), isNotEmpty);
    expect(FunnyLines.pickFor(0), isNotEmpty);
  });

  test('coins add up and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(coinsProvider), 0);
    await container.read(coinsProvider.notifier).add(7);
    expect(container.read(coinsProvider), 7);
    await container.read(coinsProvider.notifier).add(0);
    expect(container.read(coinsProvider), 7);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('copycat.coins'), 7);
  });
}
