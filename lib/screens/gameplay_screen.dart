// One turn script for every mode: listen once, 5 s countdown, auto-record,
// auto-score. The mode decides which sound, who goes, and how many rounds.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/game_sound.dart';
import '../services/attempt_scorer.dart';
import '../services/audio_io_service.dart';
import '../services/audio_scorer.dart';
import '../services/celebration.dart';
import '../services/lan_socket_manager.dart';
import '../services/funny_lines.dart';
import '../services/pitch_extractor.dart';
import '../services/sfx.dart';
import '../services/shop_catalog.dart';
import '../services/turn_runner.dart' show turnNoteLabel;

import '../i18n.dart';
import '../state/client_engine.dart';
import '../state/coins.dart';
import '../state/game_state.dart';
import '../state/host_engine.dart';
import '../state/shop_store.dart';
import '../widgets/avatar_view.dart';
import '../widgets/reveal_meters.dart';
import '../widgets/sound_picker.dart';
import '../widgets/ui_bits.dart';

class GameplayScreen extends ConsumerStatefulWidget {
  /// Solo couch game (from /party). LAN matches use /game without solo.
  final bool solo;
  const GameplayScreen({super.key, this.solo = false});

  @override
  ConsumerState<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends ConsumerState<GameplayScreen> {
  Timer? _progressTimer;
  StreamSubscription<double>? _ampSub;
  Completer<void>? _goGate;
  bool _awaitingGo = false;
  bool _bootInFlight = false;
  bool _booting = true;
  bool _noSounds = false;
  bool _micDenied = false;
  bool _running = false;
  bool _settled = false;
  bool _scoring = false;

  /// Solo ×2 power-up armed for the current turn (consumes shop stock at
  /// arm time; reset for every turn).
  bool _doubleArmed = false;
  int _gen = 0;
  int _countdown = 3;
  double _secondsLeft = 0;
  double _playProgress = 0;
  double _voicedPct = 0;
  String _status = t('نجهّز الحفلة…');
  List<double> _wave = const [];
  List<double> _live = const [];
  List<double> _attemptWave = const [];
  List<GameSound> _sounds = const [];
  List<String> _picked = [];
  // Saved in initState: ref is unsafe once the widget starts unmounting.
  LanSocketManager? _lan;
  AudioIoService? _audio;

  @override
  void initState() {
    super.initState();
    // Saved here: ref is unsafe once the widget starts unmounting.
    _lan = ref.read(lanProvider);
    _audio = ref.read(audioIoProvider);
    Future.microtask(_boot);
  }

  @override
  void dispose() {
    _gen++;
    _settled = true;
    final g = _goGate;
    _goGate = null;
    if (g != null && !g.isCompleted) {
      try {
        g.complete();
      } catch (_) {}
    }
    _progressTimer?.cancel();
    _ampSub?.cancel();
    _lan?.cancelTurnTimeout();
    unawaited(_audio?.cancelRecording() ?? Future.value());
    unawaited(_audio?.stopPlayback() ?? Future.value());
    super.dispose();
  }

  Future<void> _boot() async {
    if (!widget.solo) return; // LAN matches are driven by the host engine.
    if (_bootInFlight) return;
    _bootInFlight = true;
    if (mounted) {
      setState(() {
        _booting = true;
        _micDenied = false;
        _noSounds = false;
      });
    }
    try {
      final mic = await ref.read(audioIoProvider).ensureMicPermission();
      if (!mounted) return;
      if (!mic) {
        setState(() {
          _micDenied = true;
          _booting = false;
        });
        return;
      }
      final ctl = ref.read(gameProvider.notifier);
      await ctl.reloadLibrary(ref.read(libraryProvider));
      if (!mounted) return;
      final usable = <GameSound>[];
      for (final s in ref.read(gameProvider).library) {
        if (await File(s.filePath).exists()) usable.add(s);
      }
      if (!mounted) return;
      if (usable.isEmpty) {
        ctl.resetRound();
        setState(() {
          _noSounds = true;
          _booting = false;
          _status = t('لا توجد أصوات بعد — أضف صوتًا من المكتبة.');
        });
        return;
      }
      _sounds = usable;
      final game = ref.read(gameProvider);
      final known = usable.map((s) => s.id).toSet();
      final queued = [for (final s in game.queue) if (known.contains(s.id)) s];
      switch (game.mode) {
        case GameMode.random:
          ctl.startRandomMatch(usable);
        case GameMode.choice:
          ctl.startChoiceMatch(usable);
        case GameMode.host:
          if (queued.isNotEmpty) {
            ctl.startHostMatch(queued);
          } else {
            ctl.beginHostPicking();
          }
      }
      if (!mounted) return;
      setState(() => _booting = false);
      if (ref.read(gameProvider).stage == MatchStage.turn) {
        unawaited(_runTurn());
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _booting = false;
          _status = t('تعذّر بدء الحفلة. حاول مرة أخرى.');
        });
      }
    } finally {
      _bootInFlight = false;
    }
  }

  void _tapGo() {
    final g = _goGate;
    if (g != null && !g.isCompleted) {
      try {
        g.complete();
      } catch (_) {}
    }
  }

  Future<void> _runTurn() async {
    if (_running) return;
    if (ref.read(gameProvider).stage != MatchStage.turn) return;
    _running = true;
    if (mounted) setState(() => _doubleArmed = false);
    final gen = ++_gen;
    _settled = false;
    final serial = ref.read(gameProvider.notifier).openSubmission();
    final ctl = ref.read(gameProvider.notifier);
    bool alive() => mounted && gen == _gen && !_settled;

    try {
      final challenge = ref.read(gameProvider).challenge;
      if (challenge == null) {
        _finish(gen, serial, 0, 0, 0, false, status: t('لا يوجد صوت لهذا الدور'));
        return;
      }
      // Manual start: the player taps ابدأ الاستماع, then listen → 3 s
      // wait → auto-record → auto-score all run on their own.
      _goGate = Completer<void>();
      if (mounted) setState(() => _awaitingGo = true);
      try {
        await _goGate!.future;
      } catch (_) {
        _running = false;
        return;
      } finally {
        _goGate = null;
        if (mounted) setState(() => _awaitingGo = false);
      }
      if (!alive()) return;
      final game = ref.read(gameProvider);
      try {
        ref.read(lanProvider).broadcastJson(0x04, {
          'playerId': game.currentPlayer.id,
          'soundId': challenge.id,
        });
      } catch (_) {}

      final budget = Duration(
        seconds: (challenge.durationSeconds * 2).ceil() + 23,
      );
      ref.read(lanProvider).startTurn15SecTimeout(() {
        unawaited(ref.read(audioIoProvider).cancelRecording());
        unawaited(ref.read(audioIoProvider).stopPlayback());
        _finish(gen, serial, 0, 0, 0, false, status: t('انتهى الوقت — 0'));
      }, budget: budget);

      ctl.setPhase(TurnPhase.listening);
      if (mounted) {
        setState(() {
          _status = t('استمع… يُشغَّل مرة واحدة');
          _playProgress = 0;
          _scoring = false;
          _live = const [];
          _attemptWave = const [];
        });
      }
      unawaited(PitchExtractor.waveform(challenge.filePath).then((w) {
        if (alive()) setState(() => _wave = w);
      }));
      _startPlayProgress(challenge.durationSeconds);
      await ref.read(audioIoProvider).playOnce(challenge.filePath);
      _progressTimer?.cancel();
      if (!alive()) return;
      setState(() => _playProgress = 1);

      ctl.setPhase(TurnPhase.countdown);
      final sfxIo = ref.read(audioIoProvider);
      for (_countdown = 3; _countdown >= 1; _countdown--) {
        if (!alive()) return;
        setState(() => _status = _readyLine(_countdown));
        unawaited(Sfx.play(sfxIo, Sfx.beep));
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!alive()) return;
      unawaited(Sfx.play(sfxIo, Sfx.go));

      ctl.setPhase(TurnPhase.recording);
      final totalMs =
          (challenge.durationSeconds * 1000).round().clamp(2000, 6000);
      if (mounted) {
        setState(() {
          _status = t('قلّد الآن!');
          _live = const [];
          _secondsLeft = totalMs / 1000;
        });
      }
      final io = ref.read(audioIoProvider);
      _ampSub = io.micLevels().listen((level) {
        if (!alive()) return;
        setState(() {
          final next = [..._live, level];
          _live = next.length > 48 ? next.sublist(next.length - 48) : next;
        });
      });
      final started = DateTime.now();
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!alive()) {
          t.cancel();
          return;
        }
        final gone = DateTime.now().difference(started).inMilliseconds;
        setState(() => _secondsLeft = ((totalMs - gone) / 1000).clamp(0, 99));
      });
      final rawPath = await io.tempWavPath(
          'attempt_${DateTime.now().millisecondsSinceEpoch}');
      final stopped =
          await io.recordWav(rawPath, Duration(milliseconds: totalMs));
      _progressTimer?.cancel();
      await _ampSub?.cancel();
      _ampSub = null;
      if (!alive()) return;

      final attemptPath = stopped ?? rawPath;
      if (mounted) setState(() => _scoring = true);
      // Same function LAN turns use, so a solo take and a LAN take of the
      // same two files cannot disagree.
      final scored = await AttemptScorer.score(
        targetPath: challenge.filePath,
        playerPath: attemptPath,
        decodeToWav: (p) => ref.read(audioIoProvider).decodeToWav(p),
      );
      if (!alive()) return;
      final silentTake = scored.note == 'silent' || scored.note == 'empty-pitch';
      setState(() {
        _scoring = false;
        _voicedPct = scored.voicedPct;
        _attemptWave = scored.attemptWave;
        _status = silentTake
            ? t('لم نسمع شيئًا — 0')
            : '${scored.verdict.total.toStringAsFixed(0)}/100';
      });
      try {
        ref.read(lanProvider).broadcastJson(0x05, {
          'player': game.currentPlayer.name,
          'score': scored.verdict.total,
        });
      } catch (_) {}
      _finish(
        gen,
        serial,
        scored.verdict.total,
        scored.verdict.melody,
        scored.verdict.rhythm,
        scored.verdict.pitched,
        path: attemptPath,
        verdict: scored.verdict,
      );
    } catch (_) {
      _finish(gen, serial, 0, 0, 0, false,
          status: t('تعذّر إكمال الدور — النتيجة 0'));
    } finally {
      _running = false;
      _progressTimer?.cancel();
      await _ampSub?.cancel();
      _ampSub = null;
    }
  }

  void _finish(
    int gen,
    int serial,
    double score,
    double melody,
    double rhythm,
    bool pitched, {
    String? path,
    String? status,
    ScoreVerdict? verdict,
  }) {
    if (!mounted || gen != _gen || _settled) return;
    _settled = true;
    ref.read(lanProvider).cancelTurnTimeout();
    // The ×2 power-up is a totals change, not a grade change: it applies
    // only to a real take (a zero doubled is still zero).
    final boosted = _doubleArmed && score > 0;
    _doubleArmed = false;
    ref.read(gameProvider.notifier).completeTurn(
          serial: serial,
          score: score,
          melody: melody,
          rhythm: rhythm,
          pitched: pitched,
          boost: boosted ? 2 : 1,
          pitch: verdict?.pitch,
          timbre: verdict?.timbre,
          energy: verdict?.energy,
          timing: verdict?.timing,
          kind: verdict?.kind ?? '',
          attemptPath: path,
        );
    if (status != null && mounted) setState(() => _status = status);
  }

  void _startPlayProgress(double durationSeconds) {
    _progressTimer?.cancel();
    var elapsed = 0.0;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      elapsed += 0.1;
      final p = (elapsed / durationSeconds).clamp(0.0, 1.0);
      setState(() => _playProgress = p);
      if (p >= 1) t.cancel();
    });
  }

  String _readyLine(int seconds) => switch (seconds) {
        3 => t('جهّز صوتك'),
        2 => t('اقترب'),
        _ => t('هيّا!'),
      };

  void _togglePick(GameSound sound, {required bool multi}) {
    setState(() {
      if (_picked.contains(sound.id)) {
        _picked = [for (final id in _picked) if (id != sound.id) id];
      } else if (multi) {
        if (_picked.length >= 5) return;
        _picked = [..._picked, sound.id];
      } else {
        _picked = [sound.id];
      }
    });
  }

  void _confirmPick({required bool multi}) {
    final ctl = ref.read(gameProvider.notifier);
    if (multi) {
      final sounds = [
        for (final id in _picked) ..._sounds.where((s) => s.id == id),
      ];
      if (sounds.isEmpty) return;
      ctl.startHostMatch(sounds);
    } else {
      final matches = _sounds.where((s) => s.id == _picked.single);
      if (matches.isEmpty) return;
      ctl.chooseChallenge(matches.first);
    }
    setState(() => _picked = []);
  }

  // ---------------- LAN branch (host-driven, never local) ----------------

  Future<void> _confirmLeave() async {
    final match = ref.read(matchProvider);
    if (!match.active) {
      if (mounted) context.go('/home');
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('هل تريد المغادرة؟')),
        content: Text(match.iAmHost
            ? t('مغادرة المضيف تنهي الحفلة للجميع.')
            : t('ستغادر الغرفة وستكمل اللعبة بدونك.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('البقاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('مغادرة')),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    if (match.iAmHost) {
      await ref.read(hostEngineProvider).leave();
    } else {
      await ref.read(clientEngineProvider).leave();
    }
    if (mounted) context.go('/home');
  }

  Future<void> _confirmLanPick() async {
    if (_lanPicked.isEmpty) return;
    final game = ref.read(gameProvider);
    GameSound? found;
    for (final s in game.library) {
      if (s.id == _lanPicked) found = s;
    }
    if (found == null) return;
    setState(() => _lanPicked = '');
    final match = ref.read(matchProvider);
    if (match.iAmHost) {
      ref.read(hostEngineProvider).confirmLocalPick(found);
    } else {
      await ref.read(clientEngineProvider).confirmPick(found);
    }
  }

  String _lanPicked = '';

  Widget _lanTotals(LanMatchData match) {
    final round = match.roundsTotal > 0
        ? t('الجولة {a} من {b}',
            {'a': match.roundIndex + 1, 'b': match.roundsTotal})
        : t('نجهّز…');
    final inv = ref.watch(shopProvider).inventory;
    final waiting = match.activePlayerId != null &&
        match.activePlayerId != match.selfId;
    void fire(String kind) {
      if (match.iAmHost) {
        unawaited(ref.read(hostEngineProvider).usePowerUpLocal(kind));
      } else {
        unawaited(ref.read(clientEngineProvider).usePowerUp(kind));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Power-ups stay pinned at the top (visual right edge in RTL):
            // emoji + remaining stock, no verbose labels. The host is the
            // referee; wrong timing burns the unit per the shop hint.
            _headerPower(
              emoji: ShopCatalogPowerUps.byId('volt').emoji,
              stock: inv['volt'] ?? 0,
              enabled: waiting,
              tooltip: t('برق — يعيد دور اللاعب الحالي مرة واحدة'),
              onTap: () => fire('volt'),
            ),
            const SizedBox(width: 6),
            _headerPower(
              emoji: ShopCatalogPowerUps.byId('shield').emoji,
              stock: inv['shield'] ?? 0,
              enabled: true,
              tooltip: t('درع — يحذف أسوأ جولة من المجموع النهائي'),
              onTap: () => fire('shield'),
            ),
            const Spacer(),
            Text(round,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            const CoinChip(),
            const SizedBox(width: 8),
            if ((match.soundTitle ?? '').isNotEmpty)
              Flexible(
                child: Text(
                  t('“{n}”', {'n': t(match.soundTitle!)}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in match.order)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(end: 8),
                  child: Chip(
                    avatar: PlayerAvatar(
                        name: p.name, id: p.id, radius: 12),
                    label: Text(
                        '${p.name}  ${(match.totals[p.id] ?? 0).round()}'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        match.activePlayerId == p.id
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                            : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLan(
      BuildContext context, WidgetRef ref, LanMatchData match) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t(PartyModeView.of(match.mode).title)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _confirmLeave,
        ),
      ),
      body: SafeArea(
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _lanTotals(match),
                    const SizedBox(height: 12),
                    Expanded(child: _lanStage(match)),
                  ],
                ),
                Positioned.fill(
                  child: ReactionLayer(
                    reactions: match.reactions,
                    onDone: (k) => ref
                        .read(matchProvider.notifier)
                        .removeReaction(k),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Emoji taunts for waiting players. Visual only, one per 2 s.
  /// Every send costs coins — the price shows under each emoji.
  Widget _reactionBar() {
    final coins = ref.watch(coinsProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final e in ShopCatalog.emojis)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _ReactionButton(emoji: e, coins: coins),
          ),
      ],
    );
  }

  Widget _lanStage(LanMatchData match) {
    if (!match.active) {
      return _Blocked(
        icon: Icons.wifi_off,
        text: t('لا توجد مباراة نشطة.'),
        action: t('الرئيسية'),
        onPressed: () => context.go('/home'),
      );
    }
    switch (match.stage) {
      case 'choose':
        if (match.pickRequested) {
          final game = ref.watch(gameProvider);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('اختر التحدي'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  t('استمع قبل التثبيت. لن يسمع الباقون معاينتك.'),
                  style: const TextStyle(height: 1.35)),
              const SizedBox(height: 12),
              Expanded(
                child: SoundPicker(
                  sounds: game.library,
                  multi: false,
                  selectedIds:
                      _lanPicked.isEmpty ? const [] : [_lanPicked],
                  onTap: (s) => setState(() => _lanPicked = s.id),
                  onPreview: (s) async {
                    try {
                      await ref
                          .read(audioIoProvider)
                          .playOnce(s.filePath);
                    } catch (_) {}
                  },
                ),
              ),
              const SizedBox(height: 12),
              AppButton(
                label: _lanPicked.isEmpty
                    ? t('اختر صوتًا')
                    : t('هذا هو التحدي'),
                icon: Icons.play_arrow,
                onPressed:
                    _lanPicked.isEmpty ? null : _confirmLanPick,
              ),
            ],
          );
        }
        return _StageCard(children: [
          const Spacer(),
          Text(
              match.choosingName.isEmpty
                  ? t('…يختار الصوت')
                  : t('{n} يختار الصوت…', {'n': match.choosingName}),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 22)),
          const SizedBox(height: 8),
          Text(t('استعد، فدورك قادم بعده.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const Spacer(),
        ]);
      case 'turn':
        final mine = match.activePlayerId != null &&
            match.activePlayerId == match.selfId;
        if (mine) return _lanMyTurn(match);
        return _StageCard(children: [
          const Spacer(),
          Text(t('حان دور {n}', {'n': match.nameOf(match.activePlayerId)}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          AvatarView(
            avatarId: ShopData.avatarOf(match.activePlayerId == null
                ? null
                : match.gear[match.activePlayerId]),
            size: 140,
            height: 184,
            modelScale: 1.25,
          ),
          if ((match.soundTitle ?? '').isNotEmpty)
            Text(t('“{n}”', {'n': t(match.soundTitle!)}),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
          if (match.powerNote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(match.powerNote,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.amber, fontSize: 13, height: 1.35)),
          ],
          const SizedBox(height: 8),
          Text(t('ابقَ صامتًا — لا سماعة ولا ميكروفون لديك الآن.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          // Power-ups: waiting players only (⚡ forces one redo, 🛡️
          // drops their worst round at match end).
          // Waiting players may taunt; the active player gets none.
          _reactionBar(),
          const Spacer(),
        ]);
      case 'reveal':
        final revealScore = match.lastRevealScore ?? 0;
        var tickCount = 0;
        final mineNow = match.myLastScore != null &&
            match.activePlayerId == match.selfId;
        return LayoutBuilder(
          // Tall screens: card fills and content stays centered.
          // Short screens: the card grows and scrolls instead of striping.
          builder: (ctx, c) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: IntrinsicHeight(
                child: _StageCard(
                    align: MainAxisAlignment.center,
                    children: [
          Text(t('النتيجة القادمة من المضيف…'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          AvatarView(
            avatarId: ShopData.avatarOf(match.lastRevealId == null
                ? null
                : match.gear[match.lastRevealId]),
            celebration:
                CelebrationClip.forScore(revealScore),
            size: 120,
            height: 158,
            modelScale: 1.25,
          ),
          const SizedBox(height: 6),
          DramaticScore(
            score: revealScore,
            onTick: () {
              tickCount++;
              unawaited(Sfx.play(
                  ref.read(audioIoProvider), Sfx.tick));
              if (tickCount % 4 == 0) {
                HapticFeedback.lightImpact();
              }
            },
            onLand: () {
              HapticFeedback.heavyImpact();
              unawaited(Sfx.playLanding(
                  ref.read(audioIoProvider), revealScore));
            },
          ),
          if (mineNow)
            Text(
                t('نتيجتك {s}', {
                  's':
                      '${(match.myLastScore ?? 0).toStringAsFixed(0)}/100${match.myScoreLabel?.isNotEmpty == true ? ' · ${match.myScoreLabel}' : ''}'
                }),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.amber, fontSize: 16)),
          if (match.lastFunny.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(match.lastFunny,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15)),
          ],
          if (mineNow &&
              match.targetWave.isNotEmpty &&
              match.myAttemptWave.isNotEmpty) ...[
            const SizedBox(height: 6),
            OverlayWaves(
                target: match.targetWave,
                attempt: match.myAttemptWave,
                height: 56),
          ],
          if (mineNow &&
              turnNoteLabel(match.myNote).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('السبب: {n}', {'n': t(turnNoteLabel(match.myNote))}),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13),
              ),
            ),
          // Every phone sees the graded axes of the revealed take, chosen
          // by the clip class the host's scorer detected.
          RevealMeters(
            kind: match.lastRevealKind,
            pitch: match.lastRevealAxes['pitch'] ?? -1,
            timbre: match.lastRevealAxes['timbre'] ?? -1,
            energy: match.lastRevealAxes['energy'] ?? -1,
            timing: match.lastRevealAxes['timing'] ?? -1,
          ),
          if (match.powerNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(match.powerNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.amber, fontSize: 13, height: 1.35)),
            ),
          const SizedBox(height: 6),
                    ]),
              ),
            ),
          ),
        );
      case 'done':
        return Center(child: Text(t('انتهت الحفلة')));
      default:
        return _StageCard(children: [
          const Spacer(),
          Center(
              child: CircularProgressIndicator(color: Colors.white)),
          SizedBox(height: 12),
          Text(t('نجهّز الأصوات…'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18)),
          Spacer(),
        ]);
    }
  }

  /// Compact pinned power pill: emoji + remaining stock. Long-press shows
  /// what it does. Dimmed when dead (no stock, or ⚡ while it's your turn).
  Widget _headerPower({
    required String emoji,
    required int stock,
    required bool enabled,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final dead = !enabled || stock <= 0;
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.longPress,
      child: Material(
        color: dead ? Colors.white12 : Colors.white24,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: dead ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(emoji, style: const TextStyle(fontSize: 19)),
              const SizedBox(width: 3),
              Text('×$stock',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: dead ? Colors.white38 : Colors.white)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _lanMyTurn(LanMatchData match) {
    // Manual gate: this phone taps once, then listen → 3 s → record
    // → score all run on their own. Other phones stay on their wait card.
    if (match.goRequested) {
      return _StageCard(children: [
        const Spacer(),
        const Icon(Icons.hearing, color: Colors.white, size: 64),
        const SizedBox(height: 4),
        AvatarView(
          avatarId: ref.watch(shopProvider).avatar,
          size: 128,
          height: 168,
          modelScale: 1.25,
        ),
        const SizedBox(height: 8),
        Text(t('حان دورك يا {n}', {'n': match.nameOf(match.selfId)}),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800)),
        if ((match.soundTitle ?? '').isNotEmpty)
          Text(t('“{n}”', {'n': t(match.soundTitle!)}),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 8),
        Text(
          t('اضغط الزر: ستستمع إلى الصوت مرة واحدة، ثم تنتظر ٣ ثوانٍ، وبعدها يُسجَّل تقليدك تلقائيًا.'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        const SizedBox(height: 12),
        // ×2 must be armed BEFORE the take — it can never rewrite a grade
        // after seeing it. Consumes one unit of shop stock.
        _LanDoubleArm(match: match),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF4C1D95),
            minimumSize: const Size.fromHeight(60),
          ),
          onPressed: () {
            if (match.iAmHost) {
              ref.read(hostEngineProvider).tapGo();
            } else {
              ref.read(clientEngineProvider).tapGo();
            }
          },
          icon: const Icon(Icons.play_arrow, size: 28),
          label: Text(t('ابدأ الاستماع'),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
      ]);
    }
    final body = switch (match.myPhase) {
      TurnPhase.countdown => CountdownView(
          secondsLeft: match.countdown <= 0 ? 3 : match.countdown,
          caption: t('استعد…'),
        ),
      TurnPhase.recording => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, color: Colors.redAccent, size: 72),
            const SizedBox(height: 8),
            Text(t('قلّد الآن'),
                style: const TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 16),
            WaveformBars(
                values: match.myLevels, color: Colors.white, height: 64),
          ],
        ),
      TurnPhase.listening => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hearing, color: Colors.white, size: 64),
            SizedBox(height: 12),
            Text(t('استمع… مرة واحدة'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20)),
          ],
        ),
      _ => Text(t('دورك… جهّز نفسك'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 20)),
    };
    return _StageCard(children: [
      Text(t('حان دورك يا {n}', {'n': match.nameOf(match.selfId)}),
          style: const TextStyle(color: Colors.white70)),
      const Spacer(),
      body,
      const Spacer(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    ref.listen(gameProvider, (prev, next) {
      if (next.stage == MatchStage.finished &&
          prev?.stage != MatchStage.finished) {
        context.go('/results');
      }
      if (next.stage == MatchStage.turn && prev?.stage != MatchStage.turn) {
        unawaited(_runTurn());
      }
      if (next.stage == MatchStage.pick && prev?.stage != MatchStage.pick) {
        setState(() => _picked = []);
      }
    });
    ref.listen<LanMatchData>(matchProvider, (prev, next) {
      if (!widget.solo &&
          next.screen == 'results' &&
          prev?.screen != 'results' &&
          mounted) {
        context.go('/results');
      }
    });
    // Countdown beeps on my own LAN turn only (mic is closed otherwise).
    ref.listen<int>(
        matchProvider.select((m) => m.countdown), (prev, next) {
      if (widget.solo || !mounted || next == prev) return;
      final m = ref.read(matchProvider);
      if (m.stage != 'turn' ||
          m.activePlayerId != m.selfId ||
          m.myPhase != TurnPhase.countdown) {
        return;
      }
      final io = ref.read(audioIoProvider);
      if (next <= 1) {
        unawaited(Sfx.play(io, Sfx.go));
      } else {
        unawaited(Sfx.play(io, Sfx.beep));
      }
      HapticFeedback.lightImpact();
    });

    if (!widget.solo) {
      return _buildLan(context, ref, ref.watch(matchProvider));
    }

    // System back goes home instead of closing the app (LAN branch has
    // its own leave confirmation inside _buildLan).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/home');
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(t('اللعب بموبايل واحد')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: _booting && game.stage == MatchStage.idle
              ? const Center(child: CircularProgressIndicator())
              : _micDenied
                  ? _Blocked(
                      icon: Icons.mic_off,
                      text: t('يلزم إذن الميكروفون لسماع تقليدك.'),
                      action: t('اسمح للميكروفون'),
                      onPressed: _boot,
                    )
                  : _noSounds
                      ? _Blocked(
                          icon: Icons.music_off,
                          text: _status,
                          action: t('أضف صوتًا من المكتبة'),
                          onPressed: () => context.go('/library'),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _MatchHeader(game: game),
                            const SizedBox(height: 12),
                            Expanded(child: _stage(game)),
                          ],
                        ),
        ),
      ),
      ),
    );
  }

  Widget _stage(GameData game) {
    return switch (game.stage) {
      MatchStage.pick => _picker(
          game,
          multi: false,
          title: t('يا {n}، اختر التحدي',
              {'n': game.selector?.name ?? game.playerName}),
          subtitle: game.players.length > 1
              ? t('ليبتعد الباقون الآن. سيقلدون قبلك، وستلعب أخيرًا.')
              : t('اختر الصوت، وبعدها تسمعه مرة واحدة وتقلّده.'),
        ),
      MatchStage.pickQueue => _picker(
          game,
          multi: true,
          title: t('اختر أصوات الجولات'),
          subtitle: t('اضغط بالترتيب. سيقلد الجميع كل صوت قبل الانتقال إلى التالي.'),
        ),
      MatchStage.handoff => _Handoff(game: game),
      MatchStage.turn => _awaitingGo
          ? _ReadyCard(
              title: game.challenge?.title,
              onGo: _tapGo,
              doubleStock: ref.watch(shopProvider).inventory['double'] ?? 0,
              doubleArmed: _doubleArmed,
              onDouble: () async {
                final got =
                    await ref.read(shopProvider.notifier).usePowerUp('double');
                if (!got) return;
                if (mounted) setState(() => _doubleArmed = true);
              },
            )
          : _TurnStage(
              game: game,
              status: _status,
              countdown: _countdown,
              secondsLeft: _secondsLeft,
              playProgress: _playProgress,
              scoring: _scoring,
              wave: _wave,
              live: _live,
            ),
      MatchStage.reveal => _Reveal(
          game: game,
          voicedPct: _voicedPct,
          attemptWave: _attemptWave,
          targetWave: _wave,
        ),
      MatchStage.recap => _Recap(game: game),
      MatchStage.idle || MatchStage.finished => Center(child: Text(_status)),
    };
  }

  Widget _picker(
    GameData game, {
    required bool multi,
    required String title,
    required String subtitle,
  }) {
    final ready = _picked.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(height: 1.35)),
        const SizedBox(height: 12),
        Expanded(
          child: SoundPicker(
            sounds: _sounds,
            multi: multi,
            selectedIds: _picked,
            onTap: (s) => _togglePick(s, multi: multi),
            onPreview: (s) async {
              try {
                await ref.read(audioIoProvider).playOnce(s.filePath);
              } catch (_) {}
            },
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: multi
              ? (ready
                  ? t('ابدأ ({n})', {'n': _picked.length})
                  : t('اختر صوتًا'))
              : t('هذا هو التحدي'),
          icon: Icons.play_arrow,
          onPressed: ready ? () => _confirmPick(multi: multi) : null,
        ),
      ],
    );
  }
}

class _MatchHeader extends ConsumerWidget {
  final GameData game;
  const _MatchHeader({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final round = game.roundsTotal > 0
        ? t('الجولة {a} من {b}',
            {'a': game.roundIndex + 1, 'b': game.roundsTotal})
        : t('قبل البداية');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(round,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            const CoinChip(),
            const SizedBox(width: 8),
            if (game.challenge != null)
              Flexible(
                child: Text(
                  t(game.challenge!.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.primary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in game.players)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Chip(
                    avatar: PlayerAvatar(name: p.name, id: p.id, radius: 12),
                    label: Text('${p.name}  ${p.score}'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: game.currentPlayer.id == p.id &&
                            game.stage != MatchStage.pick &&
                            game.stage != MatchStage.pickQueue
                        ? scheme.primaryContainer
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Blocked extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onPressed;
  const _Blocked({
    required this.icon,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: Colors.grey),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          AppButton(label: action, icon: Icons.arrow_back, onPressed: onPressed),
        ],
      ),
    );
  }
}

class _Handoff extends ConsumerWidget {
  final GameData game;
  const _Handoff({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = game.currentPlayer;
    return _StageCard(
      children: [
        Text(t('مرّر الهاتف إلى'),
            style: const TextStyle(color: Colors.white70, fontSize: 18)),
        const SizedBox(height: 16),
        AvatarView(
          avatarId: ref.watch(shopProvider).avatar,
          size: 140,
          height: 184,
          modelScale: 1.25,
        ),
        const SizedBox(height: 12),
        Text(me.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          t('الجولة {a} من {b}',
              {'a': game.roundIndex + 1, 'b': game.roundsTotal}),
          style: const TextStyle(color: Colors.white70),
        ),
        if (game.challenge != null)
          Text(t('التحدي: {n}', {'n': t(game.challenge!.title)}),
              style: const TextStyle(color: Colors.white)),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF4C1D95),
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: () =>
              ref.read(gameProvider.notifier).acknowledgeHandoff(),
          icon: const Icon(Icons.play_arrow),
          label: Text(t('أنا {n} — ابدأ', {'n': me.name}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _TurnStage extends StatelessWidget {
  final GameData game;
  final String status;
  final int countdown;
  final double secondsLeft;
  final double playProgress;
  final bool scoring;
  final List<double> wave;
  final List<double> live;

  const _TurnStage({
    required this.game,
    required this.status,
    required this.countdown,
    required this.secondsLeft,
    required this.playProgress,
    required this.scoring,
    required this.wave,
    required this.live,
  });

  @override
  Widget build(BuildContext context) {
    final body = switch (game.phase) {
      TurnPhase.countdown => CountdownView(
          secondsLeft: countdown,
          caption: status,
        ),
      TurnPhase.recording => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mic, color: Colors.redAccent, size: 72),
            const SizedBox(height: 8),
            Text(
              secondsLeft.toStringAsFixed(1),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  height: 1),
            ),
            Text(t('قلّد الآن'),
                style: const TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 16),
            WaveformBars(values: live, color: Colors.white, height: 64),
          ],
        ),
      TurnPhase.listening => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hearing, color: Colors.white, size: 64),
            const SizedBox(height: 12),
            Text(status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20)),
            const SizedBox(height: 16),
            if (wave.isNotEmpty)
              WaveformBars(
                  values: wave, progress: playProgress, color: Colors.white),
          ],
        ),
      _ => scoring
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 12),
                Text(t('نحسب درجة التقليد…'),
                    style: const TextStyle(color: Colors.white, fontSize: 18)),
              ],
            )
          : Text(status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 20)),
    };
    return _StageCard(children: [
      Text(game.currentPlayer.name,
          style: const TextStyle(color: Colors.white70)),
      const Spacer(),
      body,
      const Spacer(),
    ]);
  }
}

class _Reveal extends ConsumerStatefulWidget {
  final GameData game;
  final double voicedPct;
  final List<double> attemptWave;
  final List<double> targetWave;
  const _Reveal({
    required this.game,
    required this.voicedPct,
    required this.attemptWave,
    required this.targetWave,
  });

  @override
  ConsumerState<_Reveal> createState() => _RevealState();
}

class _RevealState extends ConsumerState<_Reveal> {
  late final String _funny;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _funny = FunnyLines.pickFor(widget.game.lastScore ?? 0);
  }

  /// Plays the challenge then this device's take back to back. Only offered
  /// when the last attempt on this device is the one being revealed —
  /// remote LAN takes live on their recorder's phone (path is null here).
  Future<void> _compare() async {
    if (_comparing) return;
    _comparing = true;
    if (mounted) setState(() {});
    try {
      final io = ref.read(audioIoProvider);
      await io.playOnce(widget.game.challenge!.filePath);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await io.playOnce(widget.game.attempts.last.path!);
    } catch (_) {}
    if (mounted) setState(() => _comparing = false);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final score = game.lastScore ?? 0;
    final me = game.currentPlayer;
    final morePlayers = game.turnInRound + 1 < game.turnOrder.length;
    final moreRounds = game.roundIndex + 1 < game.roundsTotal;
    final nextLabel = morePlayers
        ? t('مرّر الهاتف للاعب التالي')
        : moreRounds
            ? (game.mode == GameMode.choice
                ? t('اختيار الصوت التالي')
                : t('الصوت التالي'))
            : t('النتائج');
    final roundAttempts = game.attemptsForRound(game.roundIndex);
    final best = roundAttempts.fold<double>(0, (m, a) => a.score > m ? a.score : m);
    final leading = game.players.length > 1 && score >= best && score > 0;
    final last = game.attempts.isEmpty ? null : game.attempts.last;
    final canCompare = game.challenge != null &&
        last != null &&
        (last.path?.isNotEmpty ?? false) &&
        last.playerId == game.currentPlayer.id;

    return Column(
      children: [
        Expanded(
          // The card scrolls instead of striping on short screens;
          // on tall screens everything fits and nothing moves.
          child: SingleChildScrollView(
          child: _StageCard(
            children: [
              if (_funny.isNotEmpty) ...[
                Text(_funny,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 4),
              ],
              if (game.lastBoosted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(t('✖️ ×2 مضاعفة'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ),
              AvatarView(
                avatarId: ref.watch(shopProvider).avatar,
                celebration: CelebrationClip.forScore(score),
                size: 110,
                height: 145,
                modelScale: 1.25,
              ),
              const SizedBox(height: 6),
              DramaticScore(
                score: score,
                onTick: () {
                  unawaited(Sfx.play(
                      ref.read(audioIoProvider), Sfx.tick));
                  HapticFeedback.lightImpact();
                },
                onLand: () {
                  HapticFeedback.heavyImpact();
                  unawaited(Sfx.playLanding(
                      ref.read(audioIoProvider), score));
                },
              ),
              if (leading)
                Text(t('أعلى تقليد لهذا الصوت حتى الآن'),
                    style: const TextStyle(color: Colors.amber)),
              const SizedBox(height: 8),
              RevealMeters(
                kind: game.lastKind,
                pitch: game.lastPitch ?? -1,
                timbre: game.lastTimbre ?? -1,
                energy: game.lastEnergy ?? -1,
                timing: game.lastTiming ?? -1,
              ),
              const SizedBox(height: 6),
              Text(t('مجموع {n}: {s}',
                  {'n': me.name, 's': me.score}),
                  style: const TextStyle(color: Colors.white, fontSize: 16)),
              if (score == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    t('لم نسمعك جيدًا — قرّب الهاتف وقلّد بصوت أوضح'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              if (widget.targetWave.isNotEmpty &&
                  widget.attemptWave.isNotEmpty) ...[
                const SizedBox(height: 6),
                OverlayWaves(
                    target: widget.targetWave,
                    attempt: widget.attemptWave,
                    height: 56),
              ] else if (widget.attemptWave.isNotEmpty) ...[
                const SizedBox(height: 6),
                WaveformBars(
                    values: widget.attemptWave, color: Colors.white, height: 42),
              ],
              if (canCompare) ...[
                const SizedBox(height: 10),
                AppButton(
                  label:
                      _comparing ? t('جارٍ التشغيل…') : t('اسمع الأصلي ثم صوتك'),
                  icon: Icons.play_arrow,
                  primary: false,
                  onPressed: _compare,
                ),
              ],
            ],
          ),
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: nextLabel,
          icon: Icons.arrow_forward,
          onPressed: () => ref.read(gameProvider.notifier).nextAfterReveal(),
        ),
        TextButton(
          onPressed: () => ref.read(gameProvider.notifier).finishMatch(),
          child: Text(t('إنهاء الحفلة')),
        ),
      ],
    );
  }
}

class _Recap extends ConsumerWidget {
  final GameData game;
  const _Recap({required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = [...game.attemptsForRound(game.roundIndex)]
      ..sort((a, b) => b.score.compareTo(a.score));
    final more = game.roundIndex + 1 < game.roundsTotal;
    final title = rows.isEmpty ? t('انتهت الجولة') : rows.first.soundTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('نتيجة “{n}”', {'n': t(title)}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < rows.length; i++)
                ScoreRow(
                  name: rows[i].playerName,
                  score: rows[i].score,
                  winner: i == 0 && rows[i].score > 0,
                ),
            ],
          ),
        ),
        AppButton(
          label: more ? t('الجولة التالية') : t('النتائج النهائية'),
          icon: Icons.skip_next,
          onPressed: () => ref.read(gameProvider.notifier).nextAfterRecap(),
        ),
      ],
    );
  }
}

/// Compact emoji pill for arming the ×2 boost before a take. Sits at the
/// visual right edge (RTL start). Armed = amber chip; dead (no stock or
/// already armed) = dimmed. Explicit colors only — it must read clearly
/// on the dark gradient card and never fall back to a theme ink.
class _BoostPill extends StatelessWidget {
  final int stock;
  final bool armed;
  final VoidCallback? onArm;
  const _BoostPill(
      {required this.stock, required this.armed, required this.onArm});

  @override
  Widget build(BuildContext context) {
    final dead = armed || stock <= 0 || onArm == null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Tooltip(
        message: t('مضاعفة — نقاط هذا الدور ×2، تُجهّز قبل بدء الاستماع'),
        triggerMode: TooltipTriggerMode.longPress,
        child: Material(
          color: armed
              ? Colors.amber
              : (dead ? Colors.white12 : Colors.white24),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: dead ? null : onArm,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('✖️', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 5),
                Text(
                  armed ? t('مسلّحة لهذا الدور') : '×2',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color:
                          armed ? const Color(0xFF2E1065) : Colors.white),
                ),
                if (!armed) ...[
                  const SizedBox(width: 4),
                  Text(t('(المخزون {n})', {'n': stock}),
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white60)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Manual gate before the automated turn: tap once, then listen → 3 s
/// wait → auto-record → auto-score run on their own.
/// The ×2 pill pins the CARD's own top edge (its first row, right side
/// in RTL) and arms before the take — never mid-card, never buried.
class _ReadyCard extends ConsumerWidget {
  final String? title;
  final VoidCallback onGo;

  /// ×2 stock (inventory count) and whether one is already armed for this
  /// turn. [onDouble] consumes the stock and marks it armed.
  final int doubleStock;
  final bool doubleArmed;
  final VoidCallback? onDouble;
  const _ReadyCard({
    required this.title,
    required this.onGo,
    required this.doubleStock,
    required this.doubleArmed,
    required this.onDouble,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = title;
    return _StageCard(children: [
      // First row of the card: ✖️ pill pinned to the card's top (right
      // edge in RTL), before anything else.
      _BoostPill(
        stock: doubleStock,
        armed: doubleArmed,
        onArm: doubleArmed || doubleStock <= 0 ? null : onDouble,
      ),
      const Spacer(),
      const Icon(Icons.hearing, color: Colors.white, size: 64),
      const SizedBox(height: 12),
      if (shown != null && shown.isNotEmpty)
        Text(t('“{n}”', {'n': t(shown)}),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 22)),
      const SizedBox(height: 8),
      Text(
        t('اضغط الزر: تسمع الصوت مرة، تنتظر ٣ ثوانٍ، وبعدين يتسجل تقليدك تلقائيًا.'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
      const SizedBox(height: 12),
      const Spacer(),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF4C1D95),
          minimumSize: const Size.fromHeight(60),
        ),
        onPressed: onGo,
        icon: const Icon(Icons.play_arrow, size: 28),
        label: Text(t('ابدأ الاستماع'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
    ]);
  }
}

/// The ×2 arm row on the my-turn go card. StateLocal (armed flag) so the
/// button reads armed right away; the host confirms by event line.
class _LanDoubleArm extends ConsumerStatefulWidget {
  final LanMatchData match;
  const _LanDoubleArm({required this.match});

  @override
  ConsumerState<_LanDoubleArm> createState() => _LanDoubleArmState();
}

class _LanDoubleArmState extends ConsumerState<_LanDoubleArm> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final stock = ref.watch(shopProvider).inventory['double'] ?? 0;
    final dead = _armed || stock <= 0;
    return _BoostPill(
      stock: stock,
      armed: _armed,
      onArm: dead
          ? null
          : () async {
              final match = widget.match;
              if (match.iAmHost) {
                final got = await ref
                    .read(shopProvider.notifier)
                    .usePowerUp('double');
                if (!got) return;
                ref.read(hostEngineProvider).armDoubleForSelf();
              } else {
                // The consumable is spent by the client engine right
                // before the request goes out.
                unawaited(
                    ref.read(clientEngineProvider).usePowerUp('double'));
              }
              if (mounted) setState(() => _armed = true);
            },
    );
  }
}

class _StageCard extends StatelessWidget {
  final List<Widget> children;

  /// Tall screens center short content (replaces Spacer pairs, which
  /// cannot live inside a scroll view).
  final MainAxisAlignment align;
  const _StageCard({required this.children, this.align = MainAxisAlignment.start});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF6D28D9), Color(0xFF2E1065)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: align,
        children: children,
      ),
    );
  }
}

/// One priced emoji button. Disabled + dimmed when coins run short.
class _ReactionButton extends ConsumerWidget {
  final String emoji;
  final int coins;
  const _ReactionButton({required this.emoji, required this.coins});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = ShopCatalog.emojiPrices[emoji] ?? 0;
    final afford = coins >= price;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: afford
              ? () {
                  HapticFeedback.lightImpact();
                  final match = ref.read(matchProvider);
                  if (match.iAmHost) {
                    ref.read(hostEngineProvider).sendReaction(emoji);
                  } else {
                    ref.read(clientEngineProvider).sendReaction(emoji);
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(24),
          child: Opacity(
            opacity: afford ? 1 : 0.35,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(26),
              ),
              child:
                  Text(emoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text('🪙$price',
            style: const TextStyle(
                color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
