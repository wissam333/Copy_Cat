// lib/services/match_awards.dart — end-of-match awards.
// Computed from per-round scores only, so no extra LAN traffic is needed
// to decide them. kind: 'best' | 'funny' | 'steady'.

/// One scored take: who, which round, what grade.
class AwardEntry {
  final String playerId;
  final int round;
  final double score;
  const AwardEntry(this.playerId, this.round, this.score);
}

/// An award points at one showcased attempt (for 'steady' that is the
/// winner's best take — their most representative listen).
class MatchAward {
  final String kind;
  final String playerId;
  final int round;
  final double score;
  const MatchAward({
    required this.kind,
    required this.playerId,
    required this.round,
    required this.score,
  });

  factory MatchAward.fromJson(Map<String, dynamic> json) => MatchAward(
        kind: (json['kind'] ?? '').toString(),
        playerId: (json['playerId'] ?? '').toString(),
        round: (json['round'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'playerId': playerId,
        'round': round,
        'score': score,
      };
}

/// 🏆 best — highest single take. 🤡 funny — lowest single take above
/// zero (a zero is a broken recording, not a joke, and never wins).
/// 🎯 steady — smallest best−worst spread among players with ≥2 takes;
/// ties go to the higher average. First entry wins ties elsewhere.
List<MatchAward> matchAwards(List<AwardEntry> entries) {
  if (entries.isEmpty) return const [];
  final awards = <MatchAward>[];
  final positive = [for (final e in entries) if (e.score > 0) e];
  if (positive.isNotEmpty) {
    var best = positive.first;
    var funny = positive.first;
    for (final e in positive) {
      if (e.score > best.score) best = e;
      if (e.score < funny.score) funny = e;
    }
    awards.add(MatchAward(
        kind: 'best',
        playerId: best.playerId,
        round: best.round,
        score: best.score));
    if (!identical(funny, best)) {
      awards.add(MatchAward(
          kind: 'funny',
          playerId: funny.playerId,
          round: funny.round,
          score: funny.score));
    }
  }
  final byPlayer = <String, List<AwardEntry>>{};
  for (final e in entries) {
    (byPlayer[e.playerId] ??= []).add(e);
  }
  String? steadyId;
  var bestSpread = double.infinity;
  var bestAvg = -1.0;
  byPlayer.forEach((id, takes) {
    if (takes.length < 2) return;
    var lo = takes.first.score;
    var hi = lo;
    var sum = 0.0;
    for (final e in takes) {
      if (e.score < lo) lo = e.score;
      if (e.score > hi) hi = e.score;
      sum += e.score;
    }
    final spread = hi - lo;
    final avg = sum / takes.length;
    if (spread < bestSpread || (spread == bestSpread && avg > bestAvg)) {
      bestSpread = spread;
      bestAvg = avg;
      steadyId = id;
    }
  });
  if (steadyId != null) {
    final takes = byPlayer[steadyId]!;
    var top = takes.first;
    for (final e in takes) {
      if (e.score > top.score) top = e;
    }
    awards.add(MatchAward(
        kind: 'steady',
        playerId: top.playerId,
        round: top.round,
        score: top.score));
  }
  return awards;
}
