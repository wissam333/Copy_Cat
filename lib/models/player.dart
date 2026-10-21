// lib/models/player.dart — PLAN §3A
class Player {
  final String id;
  final String name;
  final String ipAddress;
  final bool isHost;
  final int score;

  const Player({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.isHost = false,
    this.score = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ipAddress': ipAddress,
        'isHost': isHost,
        'score': score,
      };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        name: json['name'] as String,
        ipAddress: json['ipAddress'] as String? ?? '',
        isHost: json['isHost'] as bool? ?? false,
        score: (json['score'] as num?)?.toInt() ?? 0,
      );

  Player copyWith({String? name, String? ipAddress, bool? isHost, int? score}) =>
      Player(
        id: id,
        name: name ?? this.name,
        ipAddress: ipAddress ?? this.ipAddress,
        isHost: isHost ?? this.isHost,
        score: score ?? this.score,
      );
}
