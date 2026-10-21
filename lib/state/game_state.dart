// lib/state/game_state.dart — shared match state.
//
// Three modes share one turn script (listen once, 5 s countdown, auto
// record, auto score) but not one round shape:
//   random — up to 5 surprise sounds, every player mimics the same sound
//   choice — the selector picks; everyone else goes first; selector last
//   host   — the host orders the sounds, then everyone plays each one
import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/game_sound.dart';
import '../models/player.dart';
import '../services/audio_io_service.dart';
import '../services/identity_store.dart';
import '../services/lan_socket_manager.dart';
import '../services/pitch_extractor.dart';
import '../services/sound_library_service.dart';
import 'coins.dart';

enum GameMode { random, choice, host }

enum TurnPhase { idle, listening, countdown, recording, scored }

enum MatchStage {
  idle,
  pick,
  pickQueue,
  handoff,
  turn,
  reveal,
  recap,
  finished,
}

class AttemptRecord {
  final String playerId;
  final String playerName;
  final String soundId;
  final String soundTitle;
  final int roundIndex;
  final double score;
  final double melody;
  final double rhythm;
  final bool pitched;
  final String? path;

  const AttemptRecord({
    required this.playerId,
    required this.playerName,
    required this.soundId,
    required this.soundTitle,
    required this.roundIndex,
    required this.score,
    required this.melody,
    required this.rhythm,
    required this.pitched,
    this.path,
  });
}

class GameData {
  final String playerName;
  final String roomName;
  final bool isHost;
  final bool isRoomLocked;
  final String connectionStatus;
  final GameMode mode;
  final List<Player> players;
  final List<GameSound> library;
  final GameSound? challenge;
  final int turnIndex;
  final TurnPhase phase;
  final double? lastScore;
  final double? lastMelody;
  final double? lastRhythm;
  final bool lastPitched;

  /// Per-axis grades of the last attempt (0–100; null = axis absent for
  /// this clip class) + clip kind 'tonal'/'speech'/'noise'/''. The reveal
  /// meters render from these, not from melody/rhythm alone.
  final double? lastPitch;
  final double? lastTimbre;
  final double? lastEnergy;
  final double? lastTiming;
  final String lastKind;

  /// True when the recorded total was boosted by the ×2 power-up — the
  /// reveal card shows a badge so nobody thinks the grade itself changed.
  final bool lastBoosted;
  final String? lastAttemptPath;
  final Map<String, double> scoreboard;
  final int roundIndex;
  final int roundsTotal;
  final int selectorIndex;
  final int turnInRound;
  final List<String> turnOrder;
  final List<GameSound> queue;
  final List<AttemptRecord> attempts;
  final MatchStage stage;

  const GameData({
    this.playerName = 'لاعب 1',
    this.roomName = 'غرفة التقليد',
    this.isHost = true,
    this.isRoomLocked = false,
    this.connectionStatus = 'فردي (بدون شبكة)',
    this.mode = GameMode.random,
    this.players = const [],
    this.library = const [],
    this.challenge,
    this.turnIndex = 0,
    this.phase = TurnPhase.idle,
    this.lastScore,
    this.lastMelody,
    this.lastRhythm,
    this.lastPitched = true,
    this.lastPitch,
    this.lastTimbre,
    this.lastEnergy,
    this.lastTiming,
    this.lastKind = '',
    this.lastBoosted = false,
    this.lastAttemptPath,
    this.scoreboard = const {},
    this.roundIndex = 0,
    this.roundsTotal = 0,
    this.selectorIndex = 0,
    this.turnInRound = 0,
    this.turnOrder = const [],
    this.queue = const [],
    this.attempts = const [],
    this.stage = MatchStage.idle,
  });

  Player get currentPlayer {
    if (players.isEmpty) {
      return Player(id: 'solo', name: playerName, ipAddress: 'local');
    }
    if (turnOrder.isNotEmpty) {
      final id = turnOrder[turnInRound.clamp(0, turnOrder.length - 1)];
      for (final p in players) {
        if (p.id == id) return p;
      }
    }
    return players[turnIndex.clamp(0, players.length - 1)];
  }

  Player? get selector {
    if (players.isEmpty) return null;
    return players[selectorIndex % players.length];
  }

  List<AttemptRecord> attemptsForRound(int round) =>
      [for (final a in attempts) if (a.roundIndex == round) a];

  AttemptRecord? get bestAttempt {
    if (attempts.isEmpty) return null;
    return attempts.reduce((a, b) => a.score >= b.score ? a : b);
  }

  GameData copyWith({
    String? playerName,
    String? roomName,
    bool? isHost,
    bool? isRoomLocked,
    String? connectionStatus,
    GameMode? mode,
    List<Player>? players,
    List<GameSound>? library,
    GameSound? Function()? challenge,
    int? turnIndex,
    TurnPhase? phase,
    double? Function()? lastScore,
    double? Function()? lastMelody,
    double? Function()? lastRhythm,
    bool? lastPitched,
    double? Function()? lastPitch,
    double? Function()? lastTimbre,
    double? Function()? lastEnergy,
    double? Function()? lastTiming,
    String? lastKind,
    bool? lastBoosted,
    String? Function()? lastAttemptPath,
    Map<String, double>? scoreboard,
    int? roundIndex,
    int? roundsTotal,
    int? selectorIndex,
    int? turnInRound,
    List<String>? turnOrder,
    List<GameSound>? queue,
    List<AttemptRecord>? attempts,
    MatchStage? stage,
  }) =>
      GameData(
        playerName: playerName ?? this.playerName,
        roomName: roomName ?? this.roomName,
        isHost: isHost ?? this.isHost,
        isRoomLocked: isRoomLocked ?? this.isRoomLocked,
        connectionStatus: connectionStatus ?? this.connectionStatus,
        mode: mode ?? this.mode,
        players: players ?? this.players,
        library: library ?? this.library,
        challenge: challenge == null ? this.challenge : challenge(),
        turnIndex: turnIndex ?? this.turnIndex,
        phase: phase ?? this.phase,
        lastScore: lastScore == null ? this.lastScore : lastScore(),
        lastMelody: lastMelody == null ? this.lastMelody : lastMelody(),
        lastRhythm: lastRhythm == null ? this.lastRhythm : lastRhythm(),
        lastPitched: lastPitched ?? this.lastPitched,
        lastPitch: lastPitch == null ? this.lastPitch : lastPitch(),
        lastTimbre: lastTimbre == null ? this.lastTimbre : lastTimbre(),
        lastEnergy: lastEnergy == null ? this.lastEnergy : lastEnergy(),
        lastTiming: lastTiming == null ? this.lastTiming : lastTiming(),
        lastKind: lastKind ?? this.lastKind,
        lastBoosted: lastBoosted ?? this.lastBoosted,
        lastAttemptPath:
            lastAttemptPath == null ? this.lastAttemptPath : lastAttemptPath(),
        scoreboard: scoreboard ?? this.scoreboard,
        roundIndex: roundIndex ?? this.roundIndex,
        roundsTotal: roundsTotal ?? this.roundsTotal,
        selectorIndex: selectorIndex ?? this.selectorIndex,
        turnInRound: turnInRound ?? this.turnInRound,
        turnOrder: turnOrder ?? this.turnOrder,
        queue: queue ?? this.queue,
        attempts: attempts ?? this.attempts,
        stage: stage ?? this.stage,
      );
}

class GameController extends Notifier<GameData> {
  final _uuid = const Uuid();
  int _submitSerial = 0;

  @override
  GameData build() => GameData(
        playerName: IdentityStore.initialName ?? 'لاعب 1',
        roomName: IdentityStore.initialRoom ?? 'غرفة التقليد',
      );

  void setName(String v) {
    final name = v.trim().isEmpty ? 'لاعب 1' : _clip(v);
    unawaited(IdentityStore.saveName(name));
    if (state.players.isEmpty) {
      state = state.copyWith(playerName: name);
      return;
    }
    final idx = state.players.indexWhere((p) => p.isHost);
    final i = idx < 0 ? 0 : idx;
    state = state.copyWith(
      playerName: name,
      players: [
        for (var n = 0; n < state.players.length; n++)
          n == i ? state.players[n].copyWith(name: name) : state.players[n],
      ],
    );
  }

  void setRoom(String v) {
    final room = v.trim().isEmpty ? 'غرفة التقليد' : v.trim();
    unawaited(IdentityStore.saveRoom(room));
    state = state.copyWith(roomName: room);
  }

  void setMode(GameMode m) => state = state.copyWith(mode: m);

  void ensureSoloPlayer() {
    if (state.players.isEmpty) {
      state = state.copyWith(players: _solo());
    }
  }

  Future<void> reloadLibrary(SoundLibraryService lib) async {
    state = state.copyWith(library: await lib.loadAll());
  }

  void setChallenge(GameSound s) => state = state.copyWith(challenge: () => s);

  void setPhase(TurnPhase p) => state = state.copyWith(phase: p);

  void lockRoom() {
    final players = state.players.isEmpty ? _solo() : state.players;
    state = state.copyWith(
      players: players,
      isRoomLocked: true,
      connectionStatus: state.isHost
          ? 'يستضيف “${state.roomName}” — الغرفة مقفلة'
          : 'انضممت إلى الغرفة — بدأت اللعبة (مقفلة)',
    );
  }

  void setStatus(String s) => state = state.copyWith(connectionStatus: s);

  void setLocked(bool v, {String? status}) => state = state.copyWith(
        isRoomLocked: v,
        connectionStatus: status ?? state.connectionStatus,
      );

  void openParty(GameMode mode) {
    if (state.players.isEmpty) {
      state = state.copyWith(players: _solo());
    }
    state = state.copyWith(
      mode: mode,
      stage: MatchStage.idle,
      queue: const [],
      attempts: const [],
      scoreboard: const {},
      players: [for (final p in state.players) p.copyWith(score: 0)],
      isRoomLocked: false,
      challenge: () => null,
      roundIndex: 0,
      roundsTotal: 0,
      selectorIndex: 0,
      turnInRound: 0,
      turnOrder: const [],
      phase: TurnPhase.idle,
      lastScore: () => null,
      lastMelody: () => null,
      lastRhythm: () => null,
      lastPitch: () => null,
      lastTimbre: () => null,
      lastEnergy: () => null,
      lastTiming: () => null,
      lastKind: '',
      lastBoosted: false,
      lastAttemptPath: () => null,
    );
  }

  void addPlayer(String name) {
    ensureSoloPlayer();
    if (state.players.length >= 5) return;
    final n = name.trim().isEmpty
        ? 'لاعب ${state.players.length + 1}'
        : _clip(name);
    state = state.copyWith(players: [
      ...state.players,
      Player(id: _uuid.v4(), name: n, ipAddress: 'local'),
    ]);
  }

  void renamePlayer(String id, String name) {
    final n = _clip(name);
    if (n.isEmpty) return;
    var renamedHost = false;
    final players = <Player>[];
    for (final p in state.players) {
      if (p.id != id) {
        players.add(p);
        continue;
      }
      renamedHost = p.isHost;
      players.add(p.copyWith(name: n));
    }
    state = state.copyWith(
      players: players,
      playerName: renamedHost ? n : state.playerName,
    );
    if (renamedHost) unawaited(IdentityStore.saveName(n));
  }

  void removePlayer(String id) {
    if (state.players.length <= 1) return;
    var next = state.players.where((p) => p.id != id).toList();
    if (!next.any((p) => p.isHost)) {
      next = [next.first.copyWith(isHost: true), ...next.skip(1)];
    }
    state = state.copyWith(players: next);
  }

  void armQueue(List<GameSound> sounds) {
    state = state.copyWith(queue: List<GameSound>.from(sounds));
  }

  /// Opens a submission window. The first [completeTurn] with this serial
  /// wins; a timeout and a real score cannot both land.
  int openSubmission() {
    _submitSerial += 1;
    return _submitSerial;
  }

  void completeTurn({
    required int serial,
    required double score,
    required double melody,
    required double rhythm,
    required bool pitched,
    double? pitch,
    double? timbre,
    double? energy,
    double? timing,
    String kind = '',
    double boost = 1,
    String? attemptPath,
  }) {
    if (serial != _submitSerial) return;
    _submitSerial = -1;
    final me = state.currentPlayer;
    final sound = state.challenge;
    // A power-up (×2) is a totals change, not a grade change: the base
    // verdict keeps 0–100, the board gets the boosted number.
    final safe = score.isNaN ? 0.0 : score.clamp(0, 100).toDouble();
    final finalScore = (boost == 1 ? safe : safe * boost).clamp(0, 200.0).toDouble();
    final board = Map<String, double>.from(state.scoreboard);
    board[me.id] = (board[me.id] ?? 0) + finalScore;
    // Solo pays half rate: LAN parties earn faster by design.
    unawaited(ref.read(coinsProvider.notifier).add(finalScore.round() ~/ 20));
    final attempt = AttemptRecord(
      playerId: me.id,
      playerName: me.name,
      soundId: sound?.id ?? '',
      soundTitle: sound?.title ?? 'تحدي',
      roundIndex: state.roundIndex,
      score: finalScore,
      melody: melody,
      rhythm: rhythm,
      pitched: pitched,
      path: attemptPath,
    );
    state = state.copyWith(
      attempts: [...state.attempts, attempt],
      scoreboard: board,
      players: [
        for (final p in state.players)
          p.id == me.id ? p.copyWith(score: board[me.id]!.round()) : p,
      ],
      lastScore: () => finalScore,
      lastMelody: () => melody,
      lastRhythm: () => rhythm,
      lastPitched: pitched,
      lastPitch: () => pitch,
      lastTimbre: () => timbre,
      lastEnergy: () => energy,
      lastTiming: () => timing,
      lastKind: kind,
      lastBoosted: boost != 1,
      lastAttemptPath: () => attemptPath,
      phase: TurnPhase.scored,
      stage: MatchStage.reveal,
    );
  }

  void acknowledgeHandoff() {
    if (state.stage != MatchStage.handoff) return;
    state = state.copyWith(stage: MatchStage.turn, phase: TurnPhase.idle);
  }

  void nextAfterReveal() {
    if (state.turnInRound + 1 < state.turnOrder.length) {
      state = state.copyWith(
        turnInRound: state.turnInRound + 1,
        stage: MatchStage.handoff,
        phase: TurnPhase.idle,
        lastScore: () => null,
        lastMelody: () => null,
        lastRhythm: () => null,
        lastPitch: () => null,
        lastTimbre: () => null,
        lastEnergy: () => null,
        lastTiming: () => null,
        lastKind: '',
        lastBoosted: false,
      );
      return;
    }
    if (state.players.length >= 2) {
      state = state.copyWith(stage: MatchStage.recap, phase: TurnPhase.idle);
      return;
    }
    _advanceRound();
  }

  void nextAfterRecap() => _advanceRound();

  void finishMatch() {
    state = state.copyWith(stage: MatchStage.finished, phase: TurnPhase.idle);
  }

  void startRandomMatch(List<GameSound> sounds) {
    if (sounds.isEmpty) return;
    final players = _roster();
    final rounds = min(5, sounds.length);
    final queue = [...sounds]..shuffle(Random());
    final picked = queue.take(rounds).toList();
    final order = [for (final p in players) p.id];
    state = _fresh(
      mode: GameMode.random,
      players: players,
      queue: picked,
      challenge: picked.first,
      roundsTotal: rounds,
      turnOrder: order,
      stage: players.length > 1 ? MatchStage.handoff : MatchStage.turn,
    );
  }

  void startChoiceMatch(List<GameSound> sounds) {
    if (sounds.isEmpty) return;
    final players = _roster();
    final rounds = players.length <= 1 ? min(3, sounds.length) : players.length;
    state = _fresh(
      mode: GameMode.choice,
      players: players,
      queue: const [],
      challenge: null,
      roundsTotal: max(1, rounds),
      turnOrder: const [],
      stage: MatchStage.pick,
    );
  }

  void beginHostPicking() {
    final players = _roster();
    state = _fresh(
      mode: GameMode.host,
      players: players,
      queue: const [],
      challenge: null,
      roundsTotal: 0,
      turnOrder: const [],
      stage: MatchStage.pickQueue,
    );
  }

  void startHostMatch(List<GameSound> queue) {
    if (queue.isEmpty) return;
    final players = _roster();
    final order = [for (final p in players) p.id];
    state = _fresh(
      mode: GameMode.host,
      players: players,
      queue: List<GameSound>.from(queue),
      challenge: queue.first,
      roundsTotal: queue.length,
      turnOrder: order,
      stage: players.length > 1 ? MatchStage.handoff : MatchStage.turn,
    );
  }

  void chooseChallenge(GameSound sound) {
    final players = state.players.isEmpty ? _roster() : state.players;
    final selector = players[state.selectorIndex % players.length];
    final order = [
      for (final p in players)
        if (p.id != selector.id) p.id,
      selector.id,
    ];
    state = state.copyWith(
      players: players,
      challenge: () => sound,
      turnOrder: order,
      turnInRound: 0,
      stage: players.length > 1 ? MatchStage.handoff : MatchStage.turn,
      phase: TurnPhase.idle,
    );
  }

  void resetRound() => state = state.copyWith(
        turnIndex: 0,
        turnInRound: 0,
        roundIndex: 0,
        roundsTotal: 0,
        phase: TurnPhase.idle,
        stage: MatchStage.idle,
        lastScore: () => null,
        lastMelody: () => null,
        lastRhythm: () => null,
        lastPitch: () => null,
        lastTimbre: () => null,
        lastEnergy: () => null,
        lastTiming: () => null,
        lastKind: '',
        lastBoosted: false,
        lastAttemptPath: () => null,
        scoreboard: const {},
        attempts: const [],
        challenge: () => null,
        turnOrder: const [],
        queue: const [],
      );

  List<Player> _solo() => [
        Player(
          id: _uuid.v4(),
          name: state.playerName,
          ipAddress: 'local',
          isHost: true,
        ),
      ];

  List<Player> _roster() {
    final raw = state.players.isEmpty ? _solo() : state.players;
    return [for (final p in raw) p.copyWith(score: 0)];
  }

  GameData _fresh({
    required GameMode mode,
    required List<Player> players,
    required List<GameSound> queue,
    required GameSound? challenge,
    required int roundsTotal,
    required List<String> turnOrder,
    required MatchStage stage,
  }) {
    return state.copyWith(
      mode: mode,
      players: players,
      isRoomLocked: true,
      queue: queue,
      challenge: () => challenge,
      roundIndex: 0,
      roundsTotal: roundsTotal,
      selectorIndex: 0,
      turnInRound: 0,
      turnIndex: 0,
      turnOrder: turnOrder,
      attempts: const [],
      scoreboard: const {},
      stage: stage,
      phase: TurnPhase.idle,
      lastScore: () => null,
      lastMelody: () => null,
      lastRhythm: () => null,
      lastPitch: () => null,
      lastTimbre: () => null,
      lastEnergy: () => null,
      lastTiming: () => null,
      lastPitched: true,
      lastKind: '',
      lastBoosted: false,
      lastAttemptPath: () => null,
    );
  }

  void _advanceRound() {
    final next = state.roundIndex + 1;
    if (next >= state.roundsTotal) {
      state = state.copyWith(stage: MatchStage.finished, phase: TurnPhase.idle);
      return;
    }
    if (state.mode == GameMode.choice) {
      final sel = state.players.isEmpty
          ? 0
          : (state.selectorIndex + 1) % state.players.length;
      state = state.copyWith(
        roundIndex: next,
        selectorIndex: sel,
        stage: MatchStage.pick,
        challenge: () => null,
        turnInRound: 0,
        turnOrder: const [],
        phase: TurnPhase.idle,
        lastScore: () => null,
        lastMelody: () => null,
        lastRhythm: () => null,
        lastPitch: () => null,
        lastTimbre: () => null,
        lastEnergy: () => null,
        lastTiming: () => null,
        lastKind: '',
        lastBoosted: false,
      );
      return;
    }
    if (next >= state.queue.length) {
      state = state.copyWith(stage: MatchStage.finished, phase: TurnPhase.idle);
      return;
    }
    final sound = state.queue[next];
    final order = [for (final p in state.players) p.id];
    state = state.copyWith(
      roundIndex: next,
      challenge: () => sound,
      turnOrder: order,
      turnInRound: 0,
      stage: state.players.length > 1 ? MatchStage.handoff : MatchStage.turn,
      phase: TurnPhase.idle,
      lastScore: () => null,
      lastMelody: () => null,
      lastRhythm: () => null,
      lastPitch: () => null,
      lastTimbre: () => null,
      lastEnergy: () => null,
      lastTiming: () => null,
      lastKind: '',
      lastBoosted: false,
    );
  }

  String _clip(String raw) {
    final n = raw.trim();
    if (n.length <= 18) return n;
    return n.substring(0, 18);
  }
}

final gameProvider =
    NotifierProvider<GameController, GameData>(GameController.new);

// ---------------------------------------------------------------------------
// LAN match state. The host is the referee: only the host engine mutates
// totals/rounds/order. Clients render what 0x01/0x09/0x04 tell them and never
// advance the global turn themselves.
// ---------------------------------------------------------------------------

class LanPlayer {
  final String id;
  final String name;
  final bool isHost;
  const LanPlayer({required this.id, required this.name, this.isHost = false});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'isHost': isHost};

  factory LanPlayer.fromJson(Map<String, dynamic> json) => LanPlayer(
        id: json['id'] as String,
        name: json['name'] as String,
        isHost: json['isHost'] as bool? ?? false,
      );
}

/// One flying emoji on every screen. Visual only — never a sound, so an
/// open mic never records it.
class LanReaction {
  final int key;
  final String emoji;
  final String fromName;
  const LanReaction(
      {required this.key, required this.emoji, required this.fromName});
}

class LanMatchData {
  final bool active;
  final bool inLobby;
  final bool iAmHost;
  final String? selfId;
  final GameMode mode;
  final List<LanPlayer> order;
  final bool locked;
  final int roundIndex;
  final int roundsTotal;
  final String stage;
  final String? activePlayerId;
  final String? soundTitle;
  final String? selectorId;
  final String choosingName;
  final String? challengePath;
  final GameSound? challenge;
  final double? myLastScore;
  final String? myScoreLabel;
  final String myNote;
  final double myMelody;
  final double myRhythm;
  final String? lastRevealName;
  final double? lastRevealScore;

  /// Who scored it (for their avatar + celebration on the reveal card).
  final String? lastRevealId;
  final Map<String, double> totals;

  /// Per-axis grades for the reveal card: keys 'pitch','timbre','energy',
  /// 'timing' → 0–100 (−1 = absent). [myKind]/[lastRevealKind] say what the
  /// clip was (tonal/speech/noise/'').
  final Map<String, double> myAxes;
  final String myKind;
  final Map<String, double> lastRevealAxes;
  final String lastRevealKind;

  /// Host-originated power-up event line (×2 armed, ⚡ redo, 🛡️ shield).
  final String powerNote;

  /// Players whose درع is armed: their worst round is dropped from the
  /// final total (results badge + host-side totals).
  final Map<String, bool> shields;
  final Map<String, List<double>> roundScores;
  final TurnPhase myPhase;
  final List<double> myLevels;
  final int countdown;
  final List<double> myAttemptWave;
  final List<double> targetWave;
  final String lastFunny;
  final List<LanReaction> reactions;

  /// Equipped look per player ("hat|glasses|hair"), synced over LAN.
  final Map<String, String> gear;
  final bool pickRequested;
  final bool goRequested;
  final String screen;
  final String? status;

  const LanMatchData({
    this.active = false,
    this.inLobby = false,
    this.iAmHost = false,
    this.selfId,
    this.mode = GameMode.random,
    this.order = const [],
    this.locked = false,
    this.roundIndex = 0,
    this.roundsTotal = 0,
    this.stage = 'lobby',
    this.activePlayerId,
    this.soundTitle,
    this.selectorId,
    this.choosingName = '',
    this.challengePath,
    this.challenge,
    this.myLastScore,
    this.myScoreLabel,
    this.myNote = '',
    this.myMelody = 0,
    this.myRhythm = 0,
    this.lastRevealName,
    this.lastRevealScore,
    this.lastRevealId,
    this.totals = const {},
    this.myAxes = const {},
    this.myKind = '',
    this.lastRevealAxes = const {},
    this.lastRevealKind = '',
    this.powerNote = '',
    this.shields = const {},
    this.roundScores = const {},
    this.myPhase = TurnPhase.idle,
    this.myLevels = const [],
    this.countdown = 3,
    this.myAttemptWave = const [],
    this.targetWave = const [],
    this.lastFunny = '',
    this.reactions = const [],
    this.gear = const {},
    this.pickRequested = false,
    this.goRequested = false,
    this.screen = 'lobby',
    this.status,
  });

  String nameOf(String? id) {
    if (id == null) return '';
    for (final p in order) {
      if (p.id == id) return p.name;
    }
    return '';
  }

  int rankOf(String id) {
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final idx = sorted.indexWhere((e) => e.key == id);
    return idx < 0 ? order.length : idx + 1;
  }

  LanMatchData copyWith({
    bool? active,
    bool? inLobby,
    bool? iAmHost,
    String? Function()? selfId,
    GameMode? mode,
    List<LanPlayer>? order,
    bool? locked,
    int? roundIndex,
    int? roundsTotal,
    String? stage,
    String? Function()? activePlayerId,
    String? Function()? soundTitle,
    String? Function()? selectorId,
    String? choosingName,
    String? Function()? challengePath,
    GameSound? Function()? challenge,
    double? Function()? myLastScore,
    String? Function()? myScoreLabel,
    String? myNote,
    double? myMelody,
    double? myRhythm,
    String? Function()? lastRevealName,
    double? Function()? lastRevealScore,
    String? Function()? lastRevealId,
    Map<String, double>? totals,
    Map<String, double>? myAxes,
    String? myKind,
    Map<String, double>? lastRevealAxes,
    String? lastRevealKind,
    String? powerNote,
    Map<String, bool>? shields,
    Map<String, List<double>>? roundScores,
    TurnPhase? myPhase,
    List<double>? myLevels,
    int? countdown,
    List<double>? myAttemptWave,
    List<double>? targetWave,
    String? lastFunny,
    List<LanReaction>? reactions,
    Map<String, String>? gear,
    bool? pickRequested,
    bool? goRequested,
    String? screen,
    String? Function()? status,
  }) =>
      LanMatchData(
        active: active ?? this.active,
        inLobby: inLobby ?? this.inLobby,
        iAmHost: iAmHost ?? this.iAmHost,
        selfId: selfId == null ? this.selfId : selfId(),
        mode: mode ?? this.mode,
        order: order ?? this.order,
        locked: locked ?? this.locked,
        roundIndex: roundIndex ?? this.roundIndex,
        roundsTotal: roundsTotal ?? this.roundsTotal,
        stage: stage ?? this.stage,
        activePlayerId:
            activePlayerId == null ? this.activePlayerId : activePlayerId(),
        soundTitle: soundTitle == null ? this.soundTitle : soundTitle(),
        selectorId: selectorId == null ? this.selectorId : selectorId(),
        choosingName: choosingName ?? this.choosingName,
        challengePath:
            challengePath == null ? this.challengePath : challengePath(),
        challenge: challenge == null ? this.challenge : challenge(),
        myLastScore:
            myLastScore == null ? this.myLastScore : myLastScore(),
        myScoreLabel:
            myScoreLabel == null ? this.myScoreLabel : myScoreLabel(),
        myNote: myNote ?? this.myNote,
        myMelody: myMelody ?? this.myMelody,
        myRhythm: myRhythm ?? this.myRhythm,
        lastRevealName: lastRevealName == null
            ? this.lastRevealName
            : lastRevealName(),
        lastRevealScore: lastRevealScore == null
            ? this.lastRevealScore
            : lastRevealScore(),
        lastRevealId:
            lastRevealId == null ? this.lastRevealId : lastRevealId(),
        totals: totals ?? this.totals,
        myAxes: myAxes ?? this.myAxes,
        myKind: myKind ?? this.myKind,
        lastRevealAxes: lastRevealAxes ?? this.lastRevealAxes,
        lastRevealKind: lastRevealKind ?? this.lastRevealKind,
        powerNote: powerNote ?? this.powerNote,
        shields: shields ?? this.shields,
        roundScores: roundScores ?? this.roundScores,
        myPhase: myPhase ?? this.myPhase,
        myLevels: myLevels ?? this.myLevels,
        countdown: countdown ?? this.countdown,
        myAttemptWave: myAttemptWave ?? this.myAttemptWave,
        targetWave: targetWave ?? this.targetWave,
        lastFunny: lastFunny ?? this.lastFunny,
        reactions: reactions ?? this.reactions,
        gear: gear ?? this.gear,
        pickRequested: pickRequested ?? this.pickRequested,
        goRequested: goRequested ?? this.goRequested,
        screen: screen ?? this.screen,
        status: status == null ? this.status : status(),
      );
}

class MatchController extends Notifier<LanMatchData> {
  @override
  LanMatchData build() => const LanMatchData();

  void reset() => state = const LanMatchData();

  void hostLobby(String selfName) {
    final id = const Uuid().v4();
    state = LanMatchData(
      inLobby: true,
      iAmHost: true,
      selfId: id,
      order: [LanPlayer(id: id, name: selfName, isHost: true)],
      screen: 'lobby',
    );
  }

  void clientLobby() {
    state = const LanMatchData(inLobby: true, screen: 'lobby');
  }

  void setMode(GameMode m) => state = state.copyWith(mode: m);

  void setOrder(List<LanPlayer> order) =>
      state = state.copyWith(order: order);

  void setSelfId(String id) => state = state.copyWith(selfId: () => id);

  void setLocked(bool v) => state = state.copyWith(locked: v);

  void setScreen(String s) => state = state.copyWith(screen: s);

  void setStatus(String? s) => state = state.copyWith(status: () => s);

  void beginMatch(GameMode mode) {
    state = state.copyWith(
      active: true,
      inLobby: false,
      mode: mode,
      locked: true,
      roundIndex: 0,
      roundsTotal: 0,
      stage: 'lobby',
      totals: {},
      myAxes: const {},
      myKind: '',
      lastRevealAxes: const {},
      lastRevealKind: '',
      powerNote: '',
      roundScores: {},
      myLastScore: () => null,
      myScoreLabel: () => null,
      myNote: '',
      countdown: 3,
      myAttemptWave: const [],
      targetWave: const [],
      lastFunny: '',
      reactions: const [],
      lastRevealName: () => null,
      lastRevealScore: () => null,
      lastRevealId: () => null,
      challengePath: () => null,
      challenge: () => null,
      screen: 'game',
      status: () => null,
    );
  }

  void applyPhase(Map<String, dynamic> json) {
    Map<String, double> totals = state.totals;
    final rawTotals = json['scoreboard'];
    if (rawTotals is Map) {
      totals = {
        for (final e in rawTotals.entries)
          e.key.toString(): (e.value as num).toDouble(),
      };
    }
    state = state.copyWith(
      stage: (json['stage'] ?? state.stage).toString(),
      roundIndex: (json['roundIndex'] as num?)?.toInt() ?? state.roundIndex,
      roundsTotal:
          (json['roundsTotal'] as num?)?.toInt() ?? state.roundsTotal,
      selectorId: () => json['selectorId']?.toString(),
      activePlayerId: () => json['activePlayerId']?.toString(),
      soundTitle: () => json['soundTitle']?.toString(),
      choosingName: (json['choosingName'] ?? '').toString(),
      totals: totals,
    );
  }

  void setChallenge(String path, GameSound sound) {
    state = state.copyWith(
      challengePath: () => path,
      challenge: () => sound,
    );
  }

  void setMyPhase(TurnPhase p) => state = state.copyWith(myPhase: p);

  void setCountdown(int n) => state = state.copyWith(countdown: n);

  void setMyWaves({List<double>? attempt, List<double>? target}) {
    state = state.copyWith(
      myAttemptWave: attempt ?? state.myAttemptWave,
      targetWave: target ?? state.targetWave,
    );
  }

  void setFunny(String line) => state = state.copyWith(lastFunny: line);

  void setGear(String playerId, String gear) {
    final next = Map<String, String>.from(state.gear);
    next[playerId] = gear;
    state = state.copyWith(gear: next);
  }

  void setGearMap(Map<String, String> gear) {
    state = state.copyWith(gear: Map<String, String>.from(gear));
  }

  /// Shields currently armed (host-enforced). Display-only on clients.
  void setShields(Map<String, bool> shields) {
    state = state.copyWith(shields: Map<String, bool>.from(shields));
  }

  /// Adds a flying reaction, dropping the oldest past 12.
  void addReaction(String emoji, String fromName) {
    final next = [...state.reactions];
    if (next.length >= 12) next.removeAt(0);
    next.add(LanReaction(
      key: DateTime.now().microsecondsSinceEpoch,
      emoji: emoji,
      fromName: fromName,
    ));
    state = state.copyWith(reactions: next);
  }

  void removeReaction(int key) {
    state = state.copyWith(
      reactions: [
        for (final r in state.reactions)
          if (r.key != key) r,
      ],
    );
  }

  /// Loads the challenge's own waveform once (for the overlay view).
  Future<void> loadTargetWave() async {
    final path = state.challengePath;
    if (path == null || state.targetWave.isNotEmpty) return;
    try {
      final wave =
          await PitchExtractor.waveform(path, buckets: 48);
      if (wave.isNotEmpty) {
        state = state.copyWith(targetWave: wave);
      }
    } catch (_) {}
  }

  void pushLevel(double level) {
    final next = [...state.myLevels, level];
    state = state.copyWith(
        myLevels: next.length > 48
            ? next.sublist(next.length - 48)
            : next);
  }

  void clearMyLevels() => state = state.copyWith(myLevels: const []);

  void setMyResult(
      double score, String label, double melody, double rhythm,
      {String note = ''}) {
    state = state.copyWith(
      myLastScore: () => score,
      myScoreLabel: () => label,
      myMelody: melody,
      myRhythm: rhythm,
      myNote: note,
    );
  }

  void setMyAxes(Map<String, double> axes, String kind) {
    state = state.copyWith(myAxes: axes, myKind: kind);
  }

  void setRevealAxes(Map<String, double> axes, String kind) {
    state = state.copyWith(lastRevealAxes: axes, lastRevealKind: kind);
  }

  void setPowerNote(String note) =>
      state = state.copyWith(powerNote: note);

  void setReveal(String name, double score, {String? playerId}) {
    state = state.copyWith(
      lastRevealName: () => name,
      lastRevealScore: () => score,
      lastRevealId: () => playerId,
    );
  }

  void setPickRequested(bool v) =>
      state = state.copyWith(pickRequested: v);

  void setGoRequested(bool v) =>
      state = state.copyWith(goRequested: v);

  /// A client joins a match already running on the host: mark it active
  /// without wiping the roster, totals, or its own id.
  void remoteBegin() {
    if (state.active) return;
    state = state.copyWith(
      active: true,
      inLobby: false,
      locked: true,
      totals: {},
      roundScores: {},
      myAxes: const {},
      myKind: '',
      lastRevealAxes: const {},
      lastRevealKind: '',
      myLastScore: () => null,
      myScoreLabel: () => null,
      myNote: '',
      countdown: 3,
      myAttemptWave: const [],
      targetWave: const [],
      lastFunny: '',
      reactions: const [],
      gear: {},
      lastRevealName: () => null,
      lastRevealScore: () => null,
      lastRevealId: () => null,
      myPhase: TurnPhase.idle,
      myLevels: const [],
      pickRequested: false,
      goRequested: false,
      screen: 'game',
      status: () => null,
    );
  }

  void setTotals(
      Map<String, double> totals, Map<String, List<double>> rounds) {
    state = state.copyWith(totals: totals, roundScores: rounds);
  }

  void finishMatch({
    required Map<String, double> totals,
    required Map<String, List<double>> rounds,
    required List<LanPlayer> players,
    Map<String, bool> shields = const {},
  }) {
    state = state.copyWith(
      totals: totals,
      roundScores: rounds,
      order: players,
      shields: shields,
      stage: 'done',
      screen: 'results',
      myPhase: TurnPhase.idle,
      pickRequested: false,
    );
  }
}

final matchProvider =
    NotifierProvider<MatchController, LanMatchData>(MatchController.new);

final lanProvider = Provider<LanSocketManager>((ref) {
  final lan = LanSocketManager();
  ref.onDispose(lan.dispose);
  return lan;
});

final audioIoProvider = Provider<AudioIoService>((ref) {
  final io = AudioIoService();
  ref.onDispose(() => io.dispose());
  return io;
});

final libraryProvider = Provider<SoundLibraryService>((ref) {
  return SoundLibraryService(ref.watch(audioIoProvider));
});
