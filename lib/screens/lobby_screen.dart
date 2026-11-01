// lib/screens/lobby_screen.dart — LAN room lobby.
// Host: mode cards, connected phones, playlist for Host mode, Start rules.
// Client: same list, host's mode, leave. No match is started from here
// except the host's ابدأ اللعب.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n.dart';
import '../services/lan_socket_manager.dart';
import '../stage_theme.dart';
import '../state/client_engine.dart';
import '../state/game_state.dart';
import '../state/shop_store.dart';
import '../state/host_engine.dart';
import '../widgets/sound_picker.dart';
import '../widgets/ui_bits.dart';

const _modeMeanings = {
  GameMode.random: ('حفلة عشوائية', 'نجمع أصوات الجميع ونخلطها، ونلعب جولات مفاجئة.'),
  GameMode.choice: ('اختيار اللاعب', 'كل لاعب يختار صوتًا مرة. الباقي يقلّدون أول، والمختار آخر واحد.'),
  GameMode.host: ('تحدي المضيف', 'المضيف يرتّب أصواتًا من مكتبته والكل يقلّدها بالترتيب.'),
};

String modeTitle(GameMode m) => _modeMeanings[m]!.$1;

class LobbyScreen extends ConsumerStatefulWidget {
  final bool startAsHost;
  const LobbyScreen({super.key, required this.startAsHost});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final TextEditingController _ip = TextEditingController();
  final List<String> _queueIds = [];
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (widget.startAsHost) {
        await _openHostRoom();
      } else {
        await _startDiscovery();
      }
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _openHostRoom() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await [Permission.location, Permission.microphone].request();
      await ref
          .read(gameProvider.notifier)
          .reloadLibrary(ref.read(libraryProvider));
      await ref
          .read(hostEngineProvider)
          .openRoom(ref.read(gameProvider).roomName);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _msg = t('فشلت الاستضافة: {n}', {'n': e});
        });
      }
    }
  }

  Future<void> _startDiscovery() async {
    try {
      await Permission.location.request();
      await ref.read(lanProvider).startDiscovery();
      ref.read(gameProvider.notifier).setStatus(t('جارٍ اكتشاف الغرف…'));
    } catch (e) {
      if (mounted) setState(() => _msg = t('فشل الاكتشاف: {n}', {'n': e}));
    }
  }

  Future<void> _join(String ip, int port, String label) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      // Mic is needed later for your turns; ask while joining.
      await [Permission.location, Permission.microphone].request();
      await ref.read(clientEngineProvider).connect(ip, port: port);
      ref.read(gameProvider.notifier).setStatus(
          t('متصل بـ {n} — انتظر بدء المضيف للعبة', {'n': label}));
    } catch (e) {
      if (mounted) setState(() => _msg = t('فشل الاتصال: {n}', {'n': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startMatch() async {
    final match = ref.read(matchProvider);
    final engine = ref.read(hostEngineProvider);
    List queue = const [];
    if (match.mode == GameMode.host) {
      final game = ref.read(gameProvider);
      queue = [
        for (final id in _queueIds)
          ...game.library.where((s) => s.id == id),
      ];
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final err = await engine.startMatch(match.mode,
        playlist: List.from(queue));
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _msg = err);
      return;
    }
    context.go('/game');
  }

  Future<void> _leave() async {
    if (widget.startAsHost) {
      await ref.read(hostEngineProvider).leave();
    } else {
      await ref.read(clientEngineProvider).leave();
    }
    try {
      await ref.read(lanProvider).stopAll();
    } catch (_) {}
    ref.read(matchProvider.notifier).reset();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchProvider);
    final game = ref.watch(gameProvider);
    ref.listen<LanMatchData>(matchProvider, (prev, next) {
      if (next.screen == 'game' && prev?.screen != 'game' && mounted) {
        context.go('/game');
      }
    });
    final canStart = match.order.length >= 2 &&
        (match.mode != GameMode.host || _queueIds.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: StageBlack.appBarGlow(),
        title:
            Text(widget.startAsHost ? t('غرفتك') : t('الانضمام لغرفة')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leave,
        ),
      ),
      body: StageBlack.background(
        child: SafeArea(
          child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
            Card(
              color: match.locked
                  ? StageBlack.elev
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                        match.locked ? Icons.lock : Icons.meeting_room,
                        size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(game.roomName,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              match.locked
                                  ? t('الغرفة مقفلة — بدأت اللعبة')
                                  : match.order.length <= 1
                                      ? t('بانتظار انضمام أصدقائك…')
                                      : t('{n} هواتف في الغرفة',
                                          {'n': match.order.length}),
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SectionTitle(t('الهواتف في الغرفة')),
            if (match.order.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t('لا أحد بعد.'),
                      style: TextStyle(
                          color: StageBlack.muted, fontSize: 14)),
                ),
              )
            else
              for (final p in match.order)
                PlayerTile(
                    name:
                        '${p.name}${p.isHost ? t(' (مضيف)') : ''}',
                    subtitle: p.id == match.selfId
                        ? t('هذا أنت')
                        : t('متصل'),
                    avatarId: ShopData.avatarOf(match.gear[p.id])),
            if (widget.startAsHost) ...[
              SectionTitle(t('طريقة اللعب')),
              for (final m in GameMode.values)
                _ModeCard(
                  title: t(_modeMeanings[m]!.$1),
                  blurb: t(_modeMeanings[m]!.$2),
                  selected: match.mode == m,
                  onTap: () {
                    ref.read(matchProvider.notifier).setMode(m);
                    ref.read(hostEngineProvider).syncLobby();
                    setState(() => _queueIds.clear());
                  },
                ),
              // Rounds selector: the host sets the match length; random
              // rounds clamp to the sounds actually pooled at start.
              if (match.mode != GameMode.choice) ...[
                SectionTitle(t('عدد الجولات')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.format_list_numbered),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(t('عدد الجولات'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            if (GameData.maxSoundsPerRound > 1) {
                              GameData.maxSoundsPerRound--;
                            }
                          }),
                        ),
                        Text('${GameData.maxSoundsPerRound}',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ])),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() {
                            if (GameData.maxSoundsPerRound < 20) {
                              GameData.maxSoundsPerRound++;
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (match.mode == GameMode.host) ...[
                SectionTitle(t('أصوات التحدي (١–{n} بالترتيب)',
                    {'n': GameData.maxSoundsPerRound})),
                SizedBox(
                  height: 260,
                  child: SoundPicker(
                    sounds: game.library,
                    multi: true,
                    selectedIds: _queueIds,
                    onPreview: (s) async {
                      try {
                        await ref
                            .read(audioIoProvider)
                            .playOnce(s.filePath);
                      } catch (_) {}
                    },
                    onTap: (s) => setState(() {
                      if (_queueIds.contains(s.id)) {
                        _queueIds.remove(s.id);
                      } else if (_queueIds.length < GameData.maxSoundsPerRound) {
                        _queueIds.add(s.id);
                      } else {
                        _msg = t('{n} جولات كافية',
                            {'n': GameData.maxSoundsPerRound});
                      }
                    }),
                  ),
                ),
              ],
            ] else ...[
              SectionTitle(t('طريقة اللعب')),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.videogame_asset),
                  title: Text(t(modeTitle(match.mode))),
                  subtitle:
                      Text(t(_modeMeanings[match.mode]!.$2)),
                ),
              ),
              SectionTitle(t('غرف قريبة')),
              _JoinSection(
                busy: _busy,
                onJoin: _join,
                ipController: _ip,
              ),
            ],
            if (_msg != null)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(_msg!,
                    style:
                        TextStyle(fontSize: 12, color: StageBlack.bad)),
              ),
            const SizedBox(height: 16),
            if (!widget.startAsHost)
              OutlinedButton.icon(
                onPressed: _leave,
                icon: const Icon(Icons.logout),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child:
                      Text(t('غادر الغرفة'), style: const TextStyle(fontSize: 16)),
                ),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
              ],
            ),
            ),
            // Gold start pinned outside the list (spec): survives a long
            // player list, disabled stays visible with the reason as label.
            if (widget.startAsHost)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Builder(builder: (context) {
                  final enabled = canStart && !_busy;
                  final btn = FilledButton.icon(
                    onPressed: enabled ? _startMatch : null,
                    icon: const Icon(Icons.play_arrow, size: 26),
                    label: Text(
                        match.order.length < 2
                            ? t('ننتظر هاتفًا آخر… (اللعب بموبايل واحد من الرئيسية)')
                            : match.mode == GameMode.host &&
                                    _queueIds.isEmpty
                                ? t('اختر صوتًا أولًا')
                                : t('ابدأ اللعب'),
                        style: const TextStyle(fontSize: 18)),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(60)),
                  );
                  return enabled ? btn : Opacity(opacity: 0.4, child: btn);
                }),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String blurb;
  final bool selected;
  final VoidCallback onTap;
  const _ModeCard({
    required this.title,
    required this.blurb,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(
          selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : null,
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(blurb),
        onTap: onTap,
      ),
    );
  }
}

class _JoinSection extends ConsumerWidget {
  final bool busy;
  final Future<void> Function(String ip, int port, String label) onJoin;
  final TextEditingController ipController;
  const _JoinSection({
    required this.busy,
    required this.onJoin,
    required this.ipController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lan = ref.watch(lanProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StreamBuilder<List<DiscoveredRoom>>(
          stream: lan.rooms,
          initialData: lan.foundRooms,
          builder: (context, snap) {
            final rooms = snap.data ?? const [];
            if (rooms.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                        child: Text(
                            t('لا توجد غرف بعد — تأكدوا من الاتصال بنفس شبكة الواي فاي.')),
                ),
              );
            }
            return Column(
              children: [
                for (final r in rooms)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_find),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              r.name,
                              softWrap: true,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: busy
                                ? null
                                : () => onJoin(r.ip, r.port, r.name),
                            child: Text(t('انضم')),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        ExpansionTile(
          leading: const Icon(Icons.edit),
                title: Text(t('لديك عنوان IP المضيف؟')),
                subtitle: Text(t('يُستخدم غالبًا مع نقطة الاتصال')),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ipController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: '192.168.43.1',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: busy
                          ? null
                          : () => onJoin(ipController.text.trim(),
                              LanSocketManager.defaultPort,
                              ipController.text.trim()),
                      child: Text(t('اتصال'))),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
