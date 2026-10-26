// lib/state/client_engine.dart — a joining phone. Renders what the host
// says (0x01/0x09/0x04), runs the turn script only on its own turn, and
// never advances the global match.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_sound.dart';
import '../services/lan_socket_manager.dart';
import '../services/pitch_extractor.dart';
import '../services/shop_catalog.dart';
import '../services/turn_runner.dart';
import '../i18n.dart';
import 'coins.dart';
import 'game_state.dart';
import 'shop_store.dart';
class ClientEngine {
  final Ref ref;
  ClientEngine(this.ref);

  LanSocketManager get _lan => ref.read(lanProvider);
  MatchController get _match => ref.read(matchProvider.notifier);

  StreamSubscription<ReceivedPacket>? _sub;
  Map<String, dynamic>? _pendingManifest;
  bool _turnRunning = false;
  Completer<void>? _goGate;
  bool _left = false;

  Future<void> connect(String ip, {int port = LanSocketManager.defaultPort}) async {
    await dispose();
    _left = false;
    _match.clientLobby();
    await ref.read(gameProvider.notifier).reloadLibrary(ref.read(libraryProvider));
    await _lan.connectToHost(ip, port: port);
    try {
      _lan.sendToHostJson({
        'join': true,
        'name': ref.read(gameProvider).playerName,
        'avatar': ref.read(shopProvider).avatar,
      }, PacketType.lobby);
    } catch (_) {}
    _sub = _lan.packets.listen(_onPacket);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _pendingManifest = null;
    final g = _goGate;
    _goGate = null;
    if (g != null && !g.isCompleted) {
      try {
        g.complete();
      } catch (_) {}
    }
  }

  /// Called by the UI tap on ابدأ الاستماع for this phone's turn.
  void tapGo() {
    final g = _goGate;
    if (g != null && !g.isCompleted) {
      try {
        g.complete();
      } catch (_) {}
    }
  }

  Map<String, dynamic> _json(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  void _onPacket(ReceivedPacket p) {
    if (!_lan.isClient) return;
    switch (p.type) {
      case PacketType.lobby:
        _applyLobby(_json(p.payload));
      case PacketType.phase:
        _applyPhase(_json(p.payload));
      case PacketType.manifest:
        _pendingManifest = _json(p.payload);
      case PacketType.soundBytes:
        _saveSyncedSound(p.payload);
      case PacketType.turnStart:
        _onTurnStart(_json(p.payload));
      case PacketType.score:
        _onScoreEcho(_json(p.payload));
      case PacketType.timeout:
        _onTimeout(_json(p.payload));
      case PacketType.pick:
        _onPickRequest(_json(p.payload));
      case PacketType.matchOver:
        _onMatchOver(_json(p.payload));
      case PacketType.reaction:
        _onReaction(_json(p.payload));
      case PacketType.power:
        _onPower(_json(p.payload));
    }
  }

  /// Waiting players only. Visual only, so an open mic can never
  /// record it. Every send costs coins (no free sends). Spam all you
  /// want — your balance is the only limit.
  Future<void> sendReaction(String emoji) async {
    final match = ref.read(matchProvider);
    if (match.activePlayerId == match.selfId) return;
    final price = ShopCatalog.emojiPrices[emoji] ?? 0;
    final paid =
        await ref.read(coinsProvider.notifier).spend(price);
    if (!paid) return;
    try {
      _lan.sendToHostJson({
        'fromId': match.selfId,
        'fromName': ref.read(gameProvider).playerName,
        'emoji': emoji,
      }, PacketType.reaction);
    } catch (_) {}
  }

  void _onReaction(Map<String, dynamic> json) {
    final emoji = json['emoji']?.toString() ?? '';
    if (emoji.isEmpty) return;
    var name = (json['fromName'] ?? '').toString();
    if (name.isEmpty) {
      name = ref.read(matchProvider).nameOf(
          json['fromId']?.toString());
    }
    _match.addReaction(emoji, name);
  }

  /// Host → all power event lines (×2 armed, ⚡ redo, 🛡️ shield).
  void _onPower(Map<String, dynamic> json) {
    if (json['kind']?.toString() != 'event') return;
    final note = (json['note'] ?? '').toString();
    if (note.isNotEmpty) _match.setPowerNote(note);
  }

  /// Uses one power-up from stock and asks the host to enforce it.
  /// Deducts the moment the request is sent; the host may still reject
  /// (wrong timing) — that is the cost of a slapped button, not a bug.
  Future<void> usePowerUp(String id) async {
    if (!ShopCatalogPowerUps.isPowerUp(id)) return;
    final match = ref.read(matchProvider);
    if (!match.active || match.stage == 'done') return;
    switch (ShopCatalogPowerUps.byId(id).timing) {
      case 'myTurn':
        if (match.activePlayerId != match.selfId) return;
      case 'waiting':
        if (match.activePlayerId == null ||
            match.activePlayerId == match.selfId) {
          return;
        }
    }
    final spent = await ref.read(shopProvider.notifier).usePowerUp(id);
    if (!spent) return;
    try {
      _lan.sendToHostJson({'kind': id}, PacketType.power);
    } catch (_) {}
  }

  void _applyLobby(Map<String, dynamic> json) {
    final players = json['players'];
    if (players is List) {
      _match.setOrder([
        for (final e in players)
          if (e is Map) LanPlayer.fromJson(Map<String, dynamic>.from(e)),
      ]);
    }
    final mode = json['mode']?.toString();
    if (mode != null) {
      final found = GameMode.values.asNameMap()[mode];
      if (found != null) _match.setMode(found);
    }
    if (json['youAre'] != null) {
      _match.setSelfId(json['youAre'].toString());
    }
    if (json['locked'] == true) {
      _match.setLocked(true);
      _match.setScreen('game');
    } else if (json.containsKey('locked')) {
      _match.setLocked(false);
    }
    _applyGear(json['gear']);
  }

  /// Avatar ids per player ("gear"). Unknown ids fall back to casual.
  void _applyGear(Object? raw) {
    if (raw is Map) {
      final gear = <String, String>{};
      raw.forEach((k, v) {
        gear[k.toString()] =
            ShopData.avatarOf(v?.toString());
      });
      _match.setGearMap(gear);
    }
  }

  void _applyPhase(Map<String, dynamic> json) {
    _match.remoteBegin();
    _match.applyPhase(json);
    _applyGear(json['gear']);
    final rawShields = json['shields'];
    if (rawShields is Map) {
      final sh = <String, bool>{};
      rawShields.forEach((k, v) {
        if (v == true) sh[k.toString()] = true;
      });
      _match.setShields(sh);
    }
    final stage = (json['stage'] ?? '').toString();
    final match = ref.read(matchProvider);
    if (stage == 'needLibraries') {
      unawaited(_sendOffer());
    } else if (stage == 'needFile') {
      _maybeUpload(json['soundId']?.toString());
    } else if (stage == 'choose') {
      final selector = json['selectorId']?.toString();
      _match.setPickRequested(selector != null && selector == match.selfId);
      if (match.screen != 'game') _match.setScreen('game');
    } else if (stage == 'turn' || stage == 'reveal') {
      if (match.screen != 'game') _match.setScreen('game');
    } else {
      // needLibraries / needFile / choose all mean the match is running.
      if (match.screen != 'game') _match.setScreen('game');
    }
  }

  Future<void> _sendOffer() async {
    final match = ref.read(matchProvider);
    final sounds = <Map<String, dynamic>>[];
    for (final s in ref.read(gameProvider).library) {
      int size = 0;
      try {
        size = await File(s.filePath).length();
      } catch (_) {}
      sounds.add({
        'id': s.id,
        'title': s.title,
        'durationSeconds': s.durationSeconds,
        'pitchMap': s.pitchMap,
        'fileSize': size,
      });
    }
    try {
      _lan.sendToHostJson({
        'playerId': match.selfId,
        'sounds': sounds,
      }, PacketType.libraryOffer);
    } catch (_) {}
  }

  Future<void> _maybeUpload(String? soundId) async {
    if (soundId == null || soundId.isEmpty) return;
    GameSound? found;
    for (final s in ref.read(gameProvider).library) {
      if (s.id == soundId) found = s;
    }
    if (found == null) return;
    try {
      final bytes = await File(found.filePath).readAsBytes();
      _lan.sendToHostJson({
        'soundId': found.id,
        'title': found.title,
        'durationSeconds': found.durationSeconds,
        'pitchMap': found.pitchMap,
        'fileSize': bytes.length,
      }, PacketType.manifest);
      _lan.sendToHostBytes(Uint8List.fromList(bytes), PacketType.soundBytes);
    } catch (_) {}
  }

  Future<void> _saveSyncedSound(Uint8List bytes) async {
    final manifest = _pendingManifest;
    _pendingManifest = null;
    if (manifest == null) return;
    try {
      final soundId = (manifest['soundId'] ?? 'sync').toString();
      final path =
          await ref.read(audioIoProvider).tempWavPath('sync_$soundId');
      await File(path).writeAsBytes(bytes);
      var pitch = [
        for (final f in ((manifest['pitchMap'] as List?) ?? const []))
          (f as num).toDouble()
      ];
      if (pitch.isEmpty) {
        pitch = await PitchExtractor.extract(path);
      }
      _match.setChallenge(
        path,
        GameSound(
          id: soundId,
          title: (manifest['title'] ?? t('تحدي')).toString(),
          filePath: path,
          durationSeconds:
              ((manifest['durationSeconds'] as num?) ?? 4).toDouble(),
          pitchMap: pitch,
        ),
      );
      unawaited(_match.loadTargetWave());
    } catch (_) {}
  }

  void _onTurnStart(Map<String, dynamic> json) {
    _match.remoteBegin();
    final match = ref.read(matchProvider);
    _match.applyPhase({
      'stage': 'turn',
      'roundIndex': (json['roundIndex'] as num?)?.toInt() ?? match.roundIndex,
      'activePlayerId': json['playerId']?.toString(),
    });
    if (match.screen != 'game') _match.setScreen('game');
    if (json['playerId']?.toString() == match.selfId && !_turnRunning) {
      unawaited(_runMyTurn(
        (json['soundId'] ?? '').toString(),
        (json['roundIndex'] as num?)?.toInt() ?? match.roundIndex,
      ));
    }
  }

  Future<void> _runMyTurn(String soundId, int roundIndex) async {
    _turnRunning = true;
    try {
      // Manual start: this phone taps ابدأ الاستماع, then everything is auto.
      _goGate = Completer<void>();
      _match.setGoRequested(true);
      _match.setMyPhase(TurnPhase.idle);
      _match.clearMyLevels();
      try {
        await _goGate!.future;
      } catch (_) {
        _match.setGoRequested(false);
        return;
      } finally {
        _goGate = null;
      }
      _match.setGoRequested(false);
      if (_left) return;
      final match = ref.read(matchProvider);
      final challenge = match.challenge;
      final path = match.challengePath;
      if (challenge == null || path == null) {
        _match.setMyResult(0, '', 0, 0, note: 'no-challenge');
        _sendScore(soundId, roundIndex, 0, 0, 0, false,
            note: 'no-challenge');
        return;
      }
      _match.setMyPhase(TurnPhase.listening);
      _match.clearMyLevels();
      final result = await TurnRunner.run(
        io: ref.read(audioIoProvider),
        challengePath: path,
        durationSeconds: challenge.durationSeconds,
        onPhase: (p) => _match.setMyPhase(p),
        onCountdown: (n) => _match.setCountdown(n),
        onLevel: (l) => _match.pushLevel(l),
      );
      _match.setMyResult(result.score, '', result.melody, result.rhythm,
          note: result.note);
      _match.setMyAxes({
        'pitch': result.verdict.pitch,
        'timbre': result.verdict.timbre,
        'energy': result.verdict.energy,
        'timing': result.verdict.timing,
      }, result.verdict.kind);
      _match.setMyWaves(attempt: result.attemptWave);
      _sendScore(soundId, roundIndex, result.score, result.melody,
          result.rhythm, result.pitched,
          note: result.note,
          kind: result.verdict.kind,
          pitch: result.verdict.pitch,
          timbre: result.verdict.timbre,
          energy: result.verdict.energy,
          timing: result.verdict.timing);
    } finally {
      _match.setMyPhase(TurnPhase.idle);
      _turnRunning = false;
    }
  }

  void _sendScore(String soundId, int roundIndex, double score,
      double melody, double rhythm, bool pitched,
      {String note = '',
      String kind = '',
      double? pitch,
      double? timbre,
      double? energy,
      double? timing}) {
    try {
      _lan.sendToHostJson({
        'playerId': ref.read(matchProvider).selfId,
        'soundId': soundId,
        'roundIndex': roundIndex,
        'score': score,
        'melody': melody,
        'rhythm': rhythm,
        'pitched': pitched,
        'note': note,
        'kind': kind,
        'pitch': pitch ?? -1,
        'timbre': timbre ?? -1,
        'energy': energy ?? -1,
        'timing': timing ?? -1,
      }, PacketType.score);
    } catch (_) {}
  }

  void _onScoreEcho(Map<String, dynamic> json) {
    final match = ref.read(matchProvider);
    final score = ((json['score'] as num?) ?? 0).toDouble();
    final name =
        (json['name'] ?? match.nameOf(json['playerId']?.toString())).toString();
    _match.setReveal(name, score,
        playerId: json['playerId']?.toString());
    final funny = (json['funny'] ?? '').toString();
    if (funny.isNotEmpty) _match.setFunny(funny);
    if (json['playerId']?.toString() == match.selfId) {
      _match.setMyResult(score, (json['scoreLabel'] ?? '').toString(),
          ((json['melody'] as num?) ?? 0).toDouble(),
          ((json['rhythm'] as num?) ?? 0).toDouble(),
          note: (json['note'] ?? '').toString());
      _match.setMyAxes({
        'pitch': ((json['pitch'] as num?) ?? -1).toDouble(),
        'timbre': ((json['timbre'] as num?) ?? -1).toDouble(),
        'energy': ((json['energy'] as num?) ?? -1).toDouble(),
        'timing': ((json['timing'] as num?) ?? -1).toDouble(),
      }, (json['kind'] ?? '').toString());
      // Our turn, our coins — same formula as solo and host.
      unawaited(ref
          .read(coinsProvider.notifier)
          .add(score.round() ~/ 10));
    }
    // Every phone paints the revealed player's meters from the echoed
    // axes, not just the take owner.
    _match.setRevealAxes({
      'pitch': ((json['pitch'] as num?) ?? -1).toDouble(),
      'timbre': ((json['timbre'] as num?) ?? -1).toDouble(),
      'energy': ((json['energy'] as num?) ?? -1).toDouble(),
      'timing': ((json['timing'] as num?) ?? -1).toDouble(),
    }, (json['kind'] ?? '').toString());
  }

  void _onTimeout(Map<String, dynamic> json) {
    final match = ref.read(matchProvider);
    final name =
        (json['name'] ?? match.nameOf(json['playerId']?.toString())).toString();
    if (name.isNotEmpty) {
      _match.setReveal(name, 0,
          playerId: json['playerId']?.toString());
    }
  }

  void _onPickRequest(Map<String, dynamic> json) {
    final match = ref.read(matchProvider);
    _match.setPickRequested(
        json['selectorId']?.toString() == match.selfId);
    if (match.screen != 'game') _match.setScreen('game');
  }

  void _onMatchOver(Map<String, dynamic> json) {
    _match.remoteBegin();
    final totals = <String, double>{};
    final rawTotals = json['scoreboard'];
    if (rawTotals is Map) {
      for (final e in rawTotals.entries) {
        totals[e.key.toString()] = (e.value as num).toDouble();
      }
    }
    final rounds = <String, List<double>>{};
    final rawRounds = json['rounds'];
    if (rawRounds is Map) {
      for (final e in rawRounds.entries) {
        rounds[e.key.toString()] = [
          for (final v in ((e.value as List?) ?? const []))
            (v as num).toDouble()
        ];
      }
    }
    final shields = <String, bool>{};
    final rawShields = json['shields'];
    if (rawShields is Map) {
      for (final e in rawShields.entries) {
        if (e.value == true) shields[e.key.toString()] = true;
      }
    }
    var players = ref.read(matchProvider).order;
    final rawPlayers = json['players'];
    if (rawPlayers is List && rawPlayers.isNotEmpty) {
      players = [
        for (final e in rawPlayers)
          if (e is Map) LanPlayer.fromJson(Map<String, dynamic>.from(e)),
      ];
    }
    _match.finishMatch(
        totals: totals, rounds: rounds, players: players, shields: shields);
  }

  /// Selector confirms one of their own sounds: pick, then file upload.
  Future<void> confirmPick(GameSound sound) async {
    _match.setPickRequested(false);
    try {
      final bytes = await File(sound.filePath).readAsBytes();
      _lan.sendToHostJson({'soundId': sound.id}, PacketType.pick);
      _lan.sendToHostJson({
        'soundId': sound.id,
        'title': sound.title,
        'durationSeconds': sound.durationSeconds,
        'pitchMap': sound.pitchMap,
        'fileSize': bytes.length,
      }, PacketType.manifest);
      _lan.sendToHostBytes(Uint8List.fromList(bytes), PacketType.soundBytes);
    } catch (_) {}
  }

  Future<void> leave() async {
    _left = true;
    await dispose();
    try {
      await _lan.stopAll();
    } catch (_) {}
    _match.reset();
  }
}

final clientEngineProvider = Provider<ClientEngine>((ref) {
  final engine = ClientEngine(ref);
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});
