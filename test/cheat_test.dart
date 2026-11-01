// Cheat codes pay once, then never again.
import 'package:copy_cat/services/cheat_codes.dart';
import 'package:copy_cat/state/coins.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('wissam333! grants coins exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var granted = 0;
    Future<void> grant(int n) async {
      granted += n;
      await container.read(coinsProvider.notifier).add(n);
    }

    final amount = CheatCodes.codes['wissam333!']!;
    expect(await CheatCodes.redeem('wissam333!', grant),
        CheatResult.granted);
    expect(granted, amount);
    expect(container.read(coinsProvider), amount);

    // Second try: nothing.
    expect(await CheatCodes.redeem('wissam333!', grant),
        CheatResult.alreadyUsed);
    expect(granted, amount);
    expect(container.read(coinsProvider), amount);

    // Wrong code: nothing.
    expect(await CheatCodes.redeem('nope', grant), CheatResult.invalid);
    expect(granted, amount);
  });

  test('wissammagic grants coins exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var granted = 0;
    Future<void> grant(int n) async {
      granted += n;
      await container.read(coinsProvider.notifier).add(n);
    }

    final amount = CheatCodes.codes['wissammagic']!;
    expect(await CheatCodes.redeem('wissammagic', grant),
        CheatResult.granted);
    expect(granted, amount);
    expect(await CheatCodes.redeem('wissammagic', grant),
        CheatResult.alreadyUsed);
    expect(granted, amount);
  });
}
