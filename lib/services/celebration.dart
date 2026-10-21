// lib/services/celebration.dart — which dance for which score.
// One map for solo + LAN reveals, the results podium, and shop previews.
class CelebrationClip {
  /// Death is reserved for a true 0. Everything else tiers up.
  static String forScore(double score) {
    if (score <= 0) return 'Death';
    if (score < 20) return 'Defeat';
    if (score < 50) return 'RecieveHit';
    if (score < 70) return 'Jump';
    return 'Victory';
  }

  /// Party-high: victory dance, fanfare, and confetti.
  static bool isHigh(double score) => score >= 70;
}
