// lib/models/game_sound.dart — PLAN §3A
class GameSound {
  final String id;
  final String title;
  final String filePath;
  final double durationSeconds;
  final List<double> pitchMap; // F0 in Hz sampled every 50ms

  /// FNV-1a hash of the stored file bytes — stops the same voice being
  /// added twice. Empty for sounds saved before hashing existed.
  final String hash;

  /// Where it came from (e.g. an MP3 link). Empty when unknown.
  final String sourceUrl;

  const GameSound({
    required this.id,
    required this.title,
    required this.filePath,
    required this.durationSeconds,
    required this.pitchMap,
    this.hash = '',
    this.sourceUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'filePath': filePath,
        'durationSeconds': durationSeconds,
        'pitchMap': pitchMap,
        'hash': hash,
        'sourceUrl': sourceUrl,
      };

  factory GameSound.fromJson(Map<String, dynamic> json) => GameSound(
        id: json['id'] as String,
        title: json['title'] as String,
        filePath: json['filePath'] as String,
        durationSeconds: (json['durationSeconds'] as num).toDouble(),
        pitchMap: (json['pitchMap'] as List)
            .map((e) => (e as num).toDouble())
            .toList(),
        hash: (json['hash'] as String?) ?? '',
        sourceUrl: (json['sourceUrl'] as String?) ?? '',
      );

  GameSound copyWith({
    String? title,
    String? filePath,
    double? durationSeconds,
    List<double>? pitchMap,
    String? hash,
    String? sourceUrl,
  }) =>
      GameSound(
        id: id,
        title: title ?? this.title,
        filePath: filePath ?? this.filePath,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        pitchMap: pitchMap ?? this.pitchMap,
        hash: hash ?? this.hash,
        sourceUrl: sourceUrl ?? this.sourceUrl,
      );
}
