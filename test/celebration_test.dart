// Score tiers map to the kept animation clips, boundaries included.
import 'package:copy_cat/services/celebration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('celebration tiers', () {
    expect(CelebrationClip.forScore(0), 'Death');
    expect(CelebrationClip.forScore(-5), 'Death');
    expect(CelebrationClip.forScore(0.5), 'Defeat');
    expect(CelebrationClip.forScore(19.9), 'Defeat');
    expect(CelebrationClip.forScore(20), 'RecieveHit');
    expect(CelebrationClip.forScore(49.9), 'RecieveHit');
    expect(CelebrationClip.forScore(50), 'Jump');
    expect(CelebrationClip.forScore(69.9), 'Jump');
    expect(CelebrationClip.forScore(70), 'Victory');
    expect(CelebrationClip.forScore(100), 'Victory');
    expect(CelebrationClip.isHigh(69.9), isFalse);
    expect(CelebrationClip.isHigh(70), isTrue);
  });
}
