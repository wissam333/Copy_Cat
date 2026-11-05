// Award rules: zeros never win funniest, steady needs ≥2 takes.
import 'package:copy_cat/services/match_awards.dart';
import 'package:flutter_test/flutter_test.dart';

AwardEntry e(String id, int round, double score) =>
    AwardEntry(id, round, score);

void main() {
  test('best/funny/steady pick the right takes', () {
    final awards = matchAwards([
      e('a', 0, 88),
      e('a', 1, 82), // a: spread 6
      e('b', 0, 70),
      e('b', 1, 0), // zero — invisible to funny
      e('c', 0, 3), // funniest (lowest above zero)
    ]);
    expect(awards.map((w) => w.kind), ['best', 'funny', 'steady']);
    expect(awards[0].playerId, 'a');
    expect(awards[0].round, 0);
    expect(awards[1].playerId, 'c'); // not b, whose take was 0
    expect(awards[2].playerId, 'a'); // spread 6 beats b's 70
    expect(awards[2].round, 0); // steady shows the player's best take
  });

  test('all zeros → no best/funny; single take → no steady', () {
    final awards = matchAwards([e('a', 0, 0), e('b', 0, 0)]);
    expect(awards, isEmpty);
  });

  test('one positive take → best only, no funny duplicate', () {
    final awards = matchAwards([e('a', 0, 50)]);
    expect(awards.single.kind, 'best');
  });
}
