// lib/state/host_engine.dart — the host phone is the referee.
// Runs the Random / Choice / Host state machines, owns totals, and speaks
// packets 0x01–0x0A. Clients never advance the match themselves.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/game_sound.dart';
import '../services/funny_lines.dart';
import '../services/lan_socket_manager.dart';
import '../services/pitch_extractor.dart';
import '../services/shop_catalog.dart';
import '../services/turn_runner.dart';
import 'coins.dart';
import 'game_state.dart';
import 'shop_store.dart';

class _OfferSound {
  final String ownerId;
  final String id;
  final String title;
  final double durationSeconds;
  final List<double> pitchMap;
  final int fileSize;
  _OfferSound({
    required this.ownerId,
    required this.id,
    required this.title,
    required this.durationSeconds,
    required this.pitchMap,
    required this.fileSize,
  });
}

class _ActiveTurn {
  final int roundIndex;
  final String playerId;
  _ActiveTurn(this.roundIndex, this.playerId);
}

class HostEngine {
  final Ref ref;
  HostEngine(this.ref);

  LanSocketManager get _lan => ref.read(lanProvider);
  MatchController get _match => ref.read(matchProvider.notifier);

  StreamSubscription<ReceivedPacket>? _sub;
  final Map<Socket, String> _peerIds = {};
  final Map<String, List<_OfferSound>> _offers = {};
  final Map<Socket, Map<String, dynamic>> _pendingManifest = {};

  Completer<Map<String, dynamic>>? _scoreWaiter;
  _ActiveTurn? _activeTurn;
  bool _turnDone = false;
  Timer? _watchdog;

  // Power-ups (0x0C). Host is the referee: it validates every use and
  // re-broadcasts an event line so every screen sees who did what.
  //   double — the active player arms it before their take lands
  //   volt   — a waiting player forces one redo of the current turn
  //   shield — armed before match end; worst round drops from the total
  bool _turnDouble = false;
  bool _voltQueued = false;
  bool _voltSpent = false;
  final Map<String, bool> _shields = {};

  Completer<String?>? _pickWaiter;
  Completer<void>? _goGate;
  Completer<({Map<String, dynamic> manifest, Uint8List bytes})>?
      _uploadWaiter;
  String? _expectedSoundId;

  GameMode? _lastMode;
  List<GameSound> _lastPlaylist = [];
  List<_OfferSound> _randomPool = [];
  bool _running = false;

  // ---------- room ----------

  Future<void> openRoom(String roomName) async {
    await dispose();
    _match.hostLobby(ref.read(gameProvider).playerName);
    final selfId = ref.read(matchProvider).selfId;
    if (selfId != null) {
      _match.setGear(selfId, ref.read(shopProvider).avatar);
    }
    _sub = _lan.packets.listen(_onPacket);
    await _lan.startHostRoom(roomName);
  }

  void syncLobby() => _broadcastLobby();

  String? get selfId => ref.read(matchProvider).selfId;

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _watchdog?.cancel();
    _finishWaiting();
    final g = _goGate;
    _goGate = null;
    if (g != null && !g.isCompleted) {
      try {
        g.complete();
      } catch (_) {}
    }
    _peerIds.clear();
    _pendingManifest.clear();
    _finishWaiting();
  }

  void _finishWaiting() {
    try {
      _scoreWaiter?.completeError(StateError('done'));
    } catch (_) {}
    _scoreWaiter = null;
    try {
      _pickWaiter?.completeError(StateError('done'));
    } catch (_) {}
    _pickWaiter = null;
    try {
      _uploadWaiter?.completeError(StateError('done'));
    } catch (_) {}
    _uploadWaiter = null;
  }

  // ---------- packets in ----------

  Map<String, dynamic> _json(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  void _onPacket(ReceivedPacket p) {
    if (!_lan.isHosting) return;
    final sender = p.sender;
    switch (p.type) {
      case PacketType.lobby:
        if (sender != null) _handleJoin(sender, _json(p.payload));
      case PacketType.libraryOffer:
        _handleOffer(_json(p.payload));
      case PacketType.pick:
        _handlePick(_json(p.payload));
      case PacketType.manifest:
        if (sender != null) _pendingManifest[sender] = _json(p.payload);
      case PacketType.soundBytes:
        if (sender != null) _handleUpload(sender, p.payload);
      case PacketType.score:
        _handleScore(_json(p.payload));
      case PacketType.reaction:
        _handleReaction(_json(p.payload));
      case PacketType.power:
        if (sender != null) _handlePower(sender, _json(p.payload));
    }
  }

  /// A client spent a power-up and asks the referee to enforce it.
  void _handlePower(Socket sender, Map<String, dynamic> json) {
    final id = _peerIds[sender];
    if (id == null) return;
    final kind = json['kind']?.toString();
    final active = _activeTurn?.playerId;
    switch (kind) {
      case 'double':
        if (active != id || _turnDone) return;
        if (_turnDouble) return;
        _turnDouble = true;
        _announcePower('✖️ ${ref.read(matchProvider).nameOf(id)} مضاعفة نشطة لهذا الدور');
      case 'volt':
        if (active == null ||
            active == id ||
            _turnDone ||
            _voltQueued ||
            _voltSpent) {
          return;
        }
        _voltQueued = true;
        _announcePower(
            '⚡ ${ref.read(matchProvider).nameOf(id)} أعاد دور ${ref.read(matchProvider).nameOf(active)}');
      case 'shield':
        if (_shields[id] == true) return;
        _shields[id] = true;
        _broadcastPhase({'shields': _shields});
        _announcePower('🛡️ ${ref.read(matchProvider).nameOf(id)} درع نشط — أخفض جولة تُحذف');
    }
  }

  /// Host-side arming (its own ×2), same rules as the client path.
  void armDoubleForSelf() {
    final active = _activeTurn?.playerId;
    if (active != selfId || _turnDone || _turnDouble) return;
    _turnDouble = true;
    _announcePower('✖️ مضاعفة نشطة لهذا الدور');
  }

  void _announcePower(String note) {
    _match.setPowerNote(note);
    try {
      _lan.broadcastJson(PacketType.power, {'kind': 'event', 'note': note});
    } catch (_) {}
  }

  /// The host taunts like anyone else: waiting only, visual only.
  /// Every emoji send costs coins (no free sends). Spam all you want —
  /// your balance is the only limit.
  Future<void> sendReaction(String emoji) async {
    final match = ref.read(matchProvider);
    if (match.activePlayerId == match.selfId) return;
    final price = ShopCatalog.emojiPrices[emoji] ?? 0;
    final paid =
        await ref.read(coinsProvider.notifier).spend(price);
    if (!paid) return;
    _match.addReaction(emoji, match.nameOf(match.selfId));
    try {
      _lan.broadcastJson(PacketType.reaction, {
        'fromId': match.selfId,
        'fromName': match.nameOf(match.selfId),
        'emoji': emoji,
      });
    } catch (_) {}
  }

  /// Relays one waiting player's emoji to every screen. The active
  /// player's own reactions are dropped: only the waiting may taunt.
  void _handleReaction(Map<String, dynamic> json) {
    final fromId = json['fromId']?.toString() ?? '';
    final emoji = json['emoji']?.toString() ?? '';
    if (fromId.isEmpty || emoji.isEmpty) return;
    if (_activeTurn != null && _activeTurn!.playerId == fromId) return;
    var name = (json['fromName'] ?? '').toString();
    if (name.isEmpty) {
      name = ref.read(matchProvider).nameOf(fromId);
    }
    _match.addReaction(emoji, name);
    try {
      _lan.broadcastJson(PacketType.reaction, {
        'fromId': fromId,
        'fromName': name,
        'emoji': emoji,
      });
    } catch (_) {}
  }

  /// The host is a waiting player too: local volt/shield use goes through
  /// here instead of the packet path (0x0C is client → host only).
  Future<void> usePowerUpLocal(String id) async {
    if (!ShopCatalogPowerUps.isPowerUp(id)) return;
    final match = ref.read(matchProvider);
    if (!match.active || match.stage == 'done') return;
    switch (ShopCatalogPowerUps.byId(id).timing) {
      case 'waiting':
        if (match.activePlayerId == null ||
            match.activePlayerId == selfId) {
          return;
        }
      default:
        break;
    }
    final spent = await ref.read(shopProvider.notifier).usePowerUp(id);
    if (!spent) return;
    final active = _activeTurn?.playerId;
    switch (id) {
      case 'double':
        armDoubleForSelf();
      case 'volt':
        if (active == null ||
            active == selfId ||
            _turnDone ||
            _voltQueued ||
            _voltSpent) {
          return;
        }
        _voltQueued = true;
        _announcePower(
            '⚡ ${match.nameOf(selfId)} أعاد دور ${match.nameOf(active)}');
      case 'shield':
        if (_shields[selfId] == true) return;
        _shields[selfId!] = true;
        _broadcastPhase({'shields': _shields});
        _announcePower(
            '🛡️ ${match.nameOf(selfId)} درع نشط — أخفض جولة تُحذف');
    }
  }

  void _handleJoin(Socket sender, Map<String, dynamic> json) {
    if (json['join'] != true) return;
    final match = ref.read(matchProvider);
    if (_lan.isRoomLocked || match.order.length >= 5) {
      _lan.dropPeer(sender); // room full or already playing: ignore.
      return;
    }
    if (_peerIds.containsKey(sender)) return;
    final name = (json['name'] ?? 'لاعب').toString().trim();
    final id = const Uuid().v4();
    _peerIds[sender] = id;
    final order = [
      ...match.order,
      LanPlayer(id: id, name: name.isEmpty ? 'لاعب' : name),
    ];
    _match.setOrder(order);
    _match.setGear(
        id, ShopData.avatarOf(json['avatar']?.toString()));
    _lan.sendJson(sender, PacketType.lobby, {
      'youAre': id,
      ..._lobbyJson(),
    });
    _broadcastLobby();
  }

  void _handleOffer(Map<String, dynamic> json) {
    final playerId = json['playerId']?.toString();
    final sounds = json['sounds'];
    if (playerId == null || sounds is! List) return;
    _offers[playerId] = [
      for (final s in sounds)
        if (s is Map)
          _OfferSound(
            ownerId: playerId,
            id: (s['id'] ?? '').toString(),
            title: (s['title'] ?? 'صوت').toString(),
            durationSeconds: ((s['durationSeconds'] as num?) ?? 4).toDouble(),
            pitchMap: [
              for (final f in ((s['pitchMap'] as List?) ?? const []))
                (f as num).toDouble()
            ],
            fileSize: ((s['fileSize'] as num?) ?? 0).toInt(),
          ),
    ];
  }

  void _handlePick(Map<String, dynamic> json) {
    final soundId = json['soundId']?.toString();
    if (soundId == null || soundId.isEmpty) return;
    if (_pickWaiter != null && !_pickWaiter!.isCompleted) {
      _pickWaiter!.complete(soundId);
    }
  }

  void _handleUpload(Socket sender, Uint8List bytes) {
    final manifest = _pendingManifest.remove(sender);
    if (manifest == null) return;
    final w = _uploadWaiter;
    if (w != null &&
        !w.isCompleted &&
        manifest['soundId']?.toString() == _expectedSoundId) {
      w.complete((manifest: manifest, bytes: bytes));
    }
  }

  void _handleScore(Map<String, dynamic> json) {
    final turn = _activeTurn;
    if (turn == null || _turnDone) return;
    // A client's score must go through _recordScore like any other result:
    // totals, echo, reveal, and waking the turn loop. Just completing the
    // waiter here used to drop the score silently (client stuck at 0 and
    // the room derailed from the next sound on).
    if (json['playerId']?.toString() == turn.playerId &&
        (json['roundIndex'] as num?)?.toInt() == turn.roundIndex) {
      _recordScore(
        playerId: turn.playerId,
        soundId: (json['soundId'] ?? '').toString(),
        roundIndex: turn.roundIndex,
        score: ((json['score'] as num?) ?? 0).toDouble(),
        melody: ((json['melody'] as num?) ?? 0).toDouble(),
        rhythm: ((json['rhythm'] as num?) ?? 0).toDouble(),
        pitched: (json['pitched'] as bool?) ?? false,
        note: (json['note'] ?? '').toString(),
        kind: (json['kind'] ?? '').toString(),
        pitch: (json['pitch'] as num?)?.toDouble(),
        timbre: (json['timbre'] as num?)?.toDouble(),
        energy: (json['energy'] as num?)?.toDouble(),
        timing: (json['timing'] as num?)?.toDouble(),
      );
    }
  }

  Map<String, dynamic> _lobbyJson() {
    final match = ref.read(matchProvider);
    return {
      'players': [for (final p in match.order) p.toJson()],
      'mode': match.mode.name,
      'locked': match.locked,
      'gear': match.gear,
      'shields': _shields,
    };
  }

  void _broadcastLobby() {
    try {
      _lan.broadcastJson(PacketType.lobby, _lobbyJson());
    } catch (_) {}
  }

  // ---------- start ----------

  /// Gathers what Start needs, locks, and launches the run in background.
  /// Returns an Arabic error (stay in lobby) or null (match started).
  Future<String?> startMatch(GameMode mode, {List<GameSound> playlist = const []}) async {
    if (_running) return 'المباراة جارية';
    final match = ref.read(matchProvider);
    if (match.order.length < 2) {
      return 'لازم هاتفين على الأقل — للعب لوحدك استخدم اللعب بموبايل واحد';
    }
    _lastMode = mode;
    _lastPlaylist = List<GameSound>.from(playlist);
    if (mode == GameMode.host && playlist.isEmpty) {
      return 'اختر صوتًا واحدًا على الأقل';
    }
    if (mode == GameMode.random) {
      _match.setStatus('نجمع أصوات اللاعبين…');
      _offers.clear();
      _broadcastPhase({'stage': 'needLibraries'});
      await Future<void>.delayed(const Duration(seconds: 3));
      // The host's own sounds count too — a solo host library is enough.
      _randomPool = [...await _ownOffers(), ..._pool()];
      if (_randomPool.isEmpty) {
        _match.setStatus(
            'لا توجد أصوات — ليضف كل لاعب صوتًا من 2–6 ثوانٍ');
        return 'لا توجد أصوات — ليضف كل لاعب صوتًا من 2–6 ثوانٍ';
      }
    }
    _match.setMode(mode);
    _lockAndRun();
    return null;
  }

  Future<String?> rematch() async {
    final mode = _lastMode ?? GameMode.random;
    return startMatch(mode, playlist: _lastPlaylist);
  }

  List<_OfferSound> _pool() {
    final out = <_OfferSound>[];
    for (final entry in _offers.values) {
      out.addAll(entry);
    }
    return out;
  }

  void _lockAndRun() {
    final match = ref.read(matchProvider);
    _lan.isRoomLocked = true;
    _shields.clear();
    _turnDouble = false;
    _voltQueued = false;
    _voltSpent = false;
    _match.beginMatch(match.mode);
    _broadcastLobby();
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      final mode = ref.read(matchProvider).mode;
      if (mode == GameMode.random) {
        await _runRandom();
      } else if (mode == GameMode.choice) {
        await _runChoice();
      } else {
        await _runHostPlaylist(_lastPlaylist);
      }
      if (_running) await _finishMatch();
    } catch (_) {
      if (_running) {
        _running = false;
        await _finishMatch();
      }
    } finally {
      _running = false;
    }
  }

  // ---------- files ----------

  Future<List<_OfferSound>> _ownOffers() async {
    final game = ref.read(gameProvider);
    final id = selfId ?? '';
    final out = <_OfferSound>[];
    for (final s in game.library) {
      int size = 0;
      try {
        size = await File(s.filePath).length();
      } catch (_) {}
      out.add(_OfferSound(
        ownerId: id,
        id: s.id,
        title: s.title,
        durationSeconds: s.durationSeconds,
        pitchMap: s.pitchMap,
        fileSize: size,
      ));
    }
    return out;
  }

  Future<String?> _localWav(String path) async {
    if (path.toLowerCase().endsWith('.wav')) return path;
    try {
      return await ref.read(audioIoProvider).decodeToWav(path);
    } catch (_) {
      return null;
    }
  }

  Future<GameSound?> _prepareLocal(GameSound sound) async {
    final wav = await _localWav(sound.filePath);
    if (wav == null) return null;
    var pitch = sound.pitchMap;
    if (pitch.isEmpty) {
      pitch = await PitchExtractor.extract(wav);
    }
    return GameSound(
      id: sound.id,
      title: sound.title,
      filePath: wav,
      durationSeconds: sound.durationSeconds,
      pitchMap: pitch,
    );
  }

  Future<String> _tempFor(String soundId) =>
      ref.read(audioIoProvider).tempWavPath('sync_$soundId');

  /// Host reads its own file, or asks the owner's phone for 0x02+0x03.
  Future<({GameSound sound, Uint8List bytes})?> _obtainFile(
      _OfferSound entry) async {
    if (entry.ownerId == selfId) {
      final game = ref.read(gameProvider);
      GameSound? found;
      for (final s in game.library) {
        if (s.id == entry.id) found = s;
      }
      if (found == null) return null;
      final ready = await _prepareLocal(found);
      if (ready == null) return null;
      final bytes = await File(ready.filePath).readAsBytes();
      return (sound: ready, bytes: Uint8List.fromList(bytes));
    }
    _expectedSoundId = entry.id;
    _uploadWaiter = Completer();
    _broadcastPhase({'stage': 'needFile', 'soundId': entry.id});
    try {
      final got = await _uploadWaiter!.future
          .timeout(const Duration(seconds: 10));
      final path = await _tempFor(entry.id);
      await File(path).writeAsBytes(got.bytes);
      var pitch = [
        for (final f in ((got.manifest['pitchMap'] as List?) ?? const []))
          (f as num).toDouble()
      ];
      if (pitch.isEmpty) {
        pitch = await PitchExtractor.extract(path);
      }
      final sound = GameSound(
        id: entry.id,
        title: (got.manifest['title'] ?? entry.title).toString(),
        filePath: path,
        durationSeconds:
            ((got.manifest['durationSeconds'] as num?) ??
                    entry.durationSeconds)
                .toDouble(),
        pitchMap: pitch,
      );
      return (sound: sound, bytes: got.bytes);
    } catch (_) {
      return null; // owner never sent it: drop this sound, keep the room alive.
    } finally {
      _uploadWaiter = null;
      _expectedSoundId = null;
    }
  }

  void _broadcastPhase(Map<String, dynamic> extra) {
    final match = ref.read(matchProvider);
    try {
      _lan.broadcastJson(PacketType.phase, {
        'roundIndex': match.roundIndex,
        'roundsTotal': match.roundsTotal,
        'scoreboard': match.totals,
        'gear': match.gear,
        'shields': _shields,
        ...extra,
      });
    } catch (_) {}
  }

  // ---------- modes ----------

  Future<void> _runRandom() async {
    final pool = [..._randomPool];
    pool.shuffle(Random());
    final seen = <String>{};
    final picked = <_OfferSound>[];
    for (final o in pool) {
      if (seen.add(o.id)) picked.add(o);
      if (picked.length >= 5) break;
    }
    if (picked.isEmpty) return;
    _matchBeginRounds(picked.length);
    for (var i = 0; i < picked.length; i++) {
      if (!_running) return;
      final got = await _obtainFile(picked[i]);
      if (got == null) continue; // drop this sound, next one.
      await _playSound(got.sound, got.bytes, i, picked.length,
          [for (final p in ref.read(matchProvider).order) p.id]);
    }
  }

  Future<void> _runChoice() async {
    final order = [for (final p in ref.read(matchProvider).order) p.id];
    _matchBeginRounds(order.length);
    for (var r = 0; r < order.length; r++) {
      if (!_running) return;
      final selectorId = order[r % order.length];
      final choosingName = ref.read(matchProvider).nameOf(selectorId);
      _match.applyPhase({
        'stage': 'choose',
        'roundIndex': r,
        'roundsTotal': order.length,
        'selectorId': selectorId,
        'choosingName': choosingName,
      });
      _broadcastPhase({
        'stage': 'choose',
        'roundIndex': r,
        'roundsTotal': order.length,
        'selectorId': selectorId,
        'choosingName': choosingName,
      });
      GameSound? sound;
      if (selectorId == selfId) {
        sound = await _hostPicksSound();
      } else {
        final peer = _peerOf(selectorId);
        if (peer != null) {
          try {
            _lan.sendJson(peer, PacketType.pick,
                {'roundIndex': r, 'selectorId': selectorId});
          } catch (_) {}
        }
        final soundId = await _waitPick();
        if (soundId != null) {
          final got = await _waitUpload(soundId);
          if (got != null) sound = got;
        }
      }
      if (sound == null || !_running) continue; // selector stalled: drop round.
      final turnOrder = [
        for (final id in order)
          if (id != selectorId) id,
        selectorId,
      ];
      await _playSound(sound, null, r, order.length, turnOrder,
          forwardBytes: true);
    }
  }

  Future<void> _runHostPlaylist(List<GameSound> queue) async {
    final ready = <GameSound>[];
    for (final s in queue) {
      final r = await _prepareLocal(s);
      if (r != null) ready.add(r);
    }
    if (ready.isEmpty) return;
    _matchBeginRounds(ready.length);
    for (var i = 0; i < ready.length; i++) {
      if (!_running) return;
      final bytes = await File(ready[i].filePath).readAsBytes();
      await _playSound(ready[i], Uint8List.fromList(bytes), i,
          ready.length, [for (final p in ref.read(matchProvider).order) p.id]);
    }
  }

  void _matchBeginRounds(int total) {
    _match.applyPhase({
      'stage': 'turn',
      'roundIndex': 0,
      'roundsTotal': total,
    });
  }

  Future<GameSound?> _hostPicksSound() async {
    _match.setPickRequested(true);
    _localPickWaiter = Completer();
    try {
      return await _localPickWaiter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      _localPickWaiter = null;
      _match.setPickRequested(false);
    }
  }

  Completer<GameSound?>? _localPickWaiter;

  /// Called by the UI tap on ابدأ الاستماع for the host's own turn.
  void tapGo() {
    final g = _goGate;
    if (g != null && !g.isCompleted) {
      try {
        g.complete();
      } catch (_) {}
    }
  }

  /// Called by the host UI when the local selector confirms a sound.
  void confirmLocalPick(GameSound sound) {
    if (_localPickWaiter != null && !_localPickWaiter!.isCompleted) {
      _localPickWaiter!.complete(sound);
    }
  }

  Future<String?> _waitPick() async {
    final waiter = _pickWaiter = Completer<String?>();
    try {
      return await waiter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      _pickWaiter = null;
    }
  }

  Future<GameSound?> _waitUpload(String soundId) async {
    _expectedSoundId = soundId;
    _uploadWaiter = Completer();
    try {
      final got = await _uploadWaiter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('upload'),
      );
      final path = await _tempFor(soundId);
      await File(path).writeAsBytes(got.bytes);
      var pitch = [
        for (final f in ((got.manifest['pitchMap'] as List?) ?? const []))
          (f as num).toDouble()
      ];
      if (pitch.isEmpty) pitch = await PitchExtractor.extract(path);
      return GameSound(
        id: soundId,
        title: (got.manifest['title'] ?? 'تحدي').toString(),
        filePath: path,
        durationSeconds:
            ((got.manifest['durationSeconds'] as num?) ?? 4).toDouble(),
        pitchMap: pitch,
      );
    } catch (_) {
      return null;
    } finally {
      _uploadWaiter = null;
      _expectedSoundId = null;
    }
  }

  /// Shares one sound with the room, then runs every turn in [turnOrder].
  Future<void> _playSound(
    GameSound sound,
    Uint8List? bytes,
    int roundIndex,
    int roundsTotal,
    List<String> turnOrder, {
    bool forwardBytes = false,
  }) async {
    Uint8List? data = bytes;
    if (data == null || forwardBytes) {
      // Choice uploads arrive via _waitUpload; re-read for forwarding.
      try {
        data ??= Uint8List.fromList(
            await File(sound.filePath).readAsBytes());
      } catch (_) {
        return;
      }
    }
    _match.applyPhase({
      'stage': 'turn',
      'roundIndex': roundIndex,
      'roundsTotal': roundsTotal,
    });
    try {
      _lan.broadcastJson(PacketType.manifest, {
        'soundId': sound.id,
        'title': sound.title,
        'durationSeconds': sound.durationSeconds,
        'pitchMap': sound.pitchMap,
        'fileSize': data.length,
        'roundIndex': roundIndex,
      });
      _lan.broadcastBytes(PacketType.soundBytes, data);
    } catch (_) {}
    _match.setChallenge(sound.filePath, sound);
    unawaited(_match.loadTargetWave());
    for (var t = 0; t < turnOrder.length; t++) {
      if (!_running) return;
      await _doTurn(turnOrder[t], sound, roundIndex, t);
    }
  }

  Future<void> _doTurn(
      String playerId, GameSound sound, int roundIndex, int turnInRound) async {
    _turnDone = false;
    _turnDouble = false;
    _voltQueued = false;
    _voltSpent = false;
    _activeTurn = _ActiveTurn(roundIndex, playerId);
    final waiter = _scoreWaiter = Completer<Map<String, dynamic>>();
    try {
      _lan.broadcastJson(PacketType.turnStart, {
        'playerId': playerId,
        'soundId': sound.id,
        'roundIndex': roundIndex,
        'turnInRound': turnInRound,
      });
    } catch (_) {}
    _broadcastPhase({
      'stage': 'turn',
      'roundIndex': roundIndex,
      'activePlayerId': playerId,
      'soundTitle': sound.title,
    });
    // Same state locally: the host phone renders from its own match data,
    // otherwise it would show someone else's turn forever.
    _match.applyPhase({
      'stage': 'turn',
      'roundIndex': roundIndex,
      'activePlayerId': playerId,
      'soundTitle': sound.title,
    });
    final budget = Duration(
        seconds: (sound.durationSeconds * 2).ceil() + 3 + 20);
    if (playerId == selfId) {
      // The host mimics on its own mic, like everyone else.
      _match.setMyPhase(TurnPhase.listening);
      _match.clearMyLevels();
      unawaited(_hostSelfTurn(sound, roundIndex));
    } else {
      _lan.startTurn15SecTimeout(() {
        _recordScore(
          playerId: playerId,
          soundId: sound.id,
          roundIndex: roundIndex,
          score: 0,
          melody: 0,
          rhythm: 0,
          pitched: false,
          timeout: true,
        );
      }, budget: budget);
    }
    try {
      await waiter.future;
    } catch (_) {}
    _scoreWaiter = null;
    // Reveal pause: the count-up alone is 2.5 s. Without this the next
    // turn's phase overwrites 'reveal' instantly and nobody sees the score.
    for (var i = 0; i < 10; i++) {
      if (!_running) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    // ⚡ A waiting player paid to redo this turn: the second attempt
    // replaces the first (totals recompute from rounds). Once per turn.
    if (_voltQueued) {
      _voltQueued = false;
      _voltSpent = true;
      if (_running) {
        await _doTurn(playerId, sound, roundIndex, turnInRound);
        _activeTurn = null;
        return;
      }
    }
    _activeTurn = null;
  }

  Future<void> _hostSelfTurn(GameSound sound, int roundIndex) async {
    // Manual start: the host taps ابدأ الاستماع, then everything is auto.
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
    if (!_running) return;
    final result = await TurnRunner.run(
      io: ref.read(audioIoProvider),
      challengePath: sound.filePath,
      durationSeconds: sound.durationSeconds,
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
    _recordScore(
      playerId: selfId ?? '',
      soundId: sound.id,
      roundIndex: roundIndex,
      score: result.score,
      melody: result.melody,
      rhythm: result.rhythm,
      pitched: result.pitched,
      note: result.note,
      kind: result.verdict.kind,
      pitch: result.verdict.pitch,
      timbre: result.verdict.timbre,
      energy: result.verdict.energy,
      timing: result.verdict.timing,
    );
  }

  /// First result wins: a score and the watchdog cannot both land.
  /// Totals are recomputed from every round (not incremented), so a ⚡
  /// redo replaces the first attempt and a 🛡️ drops the worst round.
  void _recordScore({
    required String playerId,
    required String soundId,
    required int roundIndex,
    required double score,
    required double melody,
    required double rhythm,
    required bool pitched,
    String note = '',
    String kind = '',
    double? pitch,
    double? timbre,
    double? energy,
    double? timing,
    bool timeout = false,
  }) {
    if (!_running) return;
    if (_turnDone) return;
    _turnDone = true;
    _lan.cancelTurnTimeout();
    var safe = score.isNaN ? 0.0 : score.clamp(0, 100).toDouble();
    // Power-up: ×2 is a totals change, not a grade change.
    if (_turnDouble) {
      safe = (safe * 2).clamp(0, 200.0);
    }
    final match = ref.read(matchProvider);
    final rounds = <String, List<double>>{};
    for (final e in match.roundScores.entries) {
      rounds[e.key.toString()] = [...e.value];
    }
    (rounds[playerId] ??= []).add(0);
    while (rounds[playerId]!.length <= roundIndex) {
      rounds[playerId]!.add(0);
    }
    rounds[playerId]![roundIndex] = safe;
    final totals = {
      for (final p in match.order) p.id: _totalOf(p.id, rounds[p.id]),
    };
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rank = sorted.indexWhere((e) => e.key == playerId) + 1;
    final label = _turnDouble ? 'المركز $rank · ×2' : 'المركز $rank';
    final funny = FunnyLines.pickFor(score);
    ref.read(matchProvider.notifier).setTotals(totals, rounds);
    _match.setReveal(match.nameOf(playerId), safe, playerId: playerId);
    _match.setRevealAxes({
      'pitch': pitch ?? -1,
      'timbre': timbre ?? -1,
      'energy': energy ?? -1,
      'timing': timing ?? -1,
    }, kind);
    _match.setFunny(funny);
    // Same state locally: the host phone renders from its own match data,
    // otherwise the host screen would sit on the turn card forever.
    _match.applyPhase({'stage': 'reveal', 'roundIndex': roundIndex});
    // Coins live on each device: only credit the host's own turns here.
    // Clients credit themselves when they receive their score echo.
    if (playerId == match.selfId) {
      unawaited(ref.read(coinsProvider.notifier).add(safe.round() ~/ 10));
    }
    try {
      if (timeout) {
        _lan.broadcastJson(PacketType.timeout, {
          'playerId': playerId,
          'roundIndex': roundIndex,
          'score': 0,
          'name': match.nameOf(playerId),
        });
      }
      _lan.broadcastJson(PacketType.score, {
        'playerId': playerId,
        'soundId': soundId,
        'roundIndex': roundIndex,
        'score': safe,
        'melody': melody,
        'rhythm': rhythm,
        'pitched': pitched,
        'name': match.nameOf(playerId),
        'scoreLabel': label,
        'note': note,
        'funny': funny,
        'boosted': _turnDouble,
        'kind': kind,
        'pitch': pitch ?? -1,
        'timbre': timbre ?? -1,
        'energy': energy ?? -1,
        'timing': timing ?? -1,
      });
    } catch (_) {}
    _turnDouble = false;
    _broadcastPhase({'stage': 'reveal', 'roundIndex': roundIndex});
    try {
      _scoreWaiter?.complete({});
    } catch (_) {}
  }

  /// Sum of a player's rounds, minus their worst round when a 🛡️ is active.
  /// With a single round the shield does nothing (the one you keep).
  double _totalOf(String playerId, List<double>? rounds) {
    if (rounds == null || rounds.isEmpty) return 0;
    var sum = 0.0;
    for (final v in rounds) {
      sum += v;
    }
    if (_shields[playerId] == true && rounds.length >= 2) {
      var lo = rounds.first;
      for (final v in rounds) {
        if (v < lo) lo = v;
      }
      sum -= lo;
    }
    return sum;
  }

  Future<void> _finishMatch({bool aborted = false}) async {
    final match = ref.read(matchProvider);
    final payload = {
      'aborted': aborted,
      'scoreboard': match.totals,
      'rounds': match.roundScores,
      'players': [for (final p in match.order) p.toJson()],
      'shields': _shields,
    };
    try {
      _lan.broadcastJson(PacketType.matchOver, payload);
    } catch (_) {}
    ref.read(matchProvider.notifier).finishMatch(
          totals: Map<String, double>.from(match.totals),
          rounds: {
            for (final e in match.roundScores.entries)
              e.key: [...e.value]
          },
          players: [...match.order],
          shields: Map<String, bool>.from(_shields),
        );
  }

  Socket? _peerOf(String playerId) {
    for (final e in _peerIds.entries) {
      if (e.value == playerId) return e.key;
    }
    return null;
  }

  /// Host leaves: end the match with whatever scores exist.
  Future<void> leave() async {
    _running = false;
    _watchdog?.cancel();
    if (ref.read(matchProvider).active) {
      await _finishMatch(aborted: true);
    }
    await dispose();
    try {
      await _lan.stopAll();
    } catch (_) {}
    _match.reset();
  }
}

final hostEngineProvider = Provider<HostEngine>((ref) {
  final engine = HostEngine(ref);
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});
