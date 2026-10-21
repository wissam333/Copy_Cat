// Who's holding the phone. Solo couch game: pass it around, no LAN,
// no modes — just names and turns.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/game_state.dart';
import '../widgets/ui_bits.dart';

class PartySetupScreen extends ConsumerStatefulWidget {
  const PartySetupScreen({super.key});

  @override
  ConsumerState<PartySetupScreen> createState() => _PartySetupScreenState();
}

class _PartySetupScreenState extends ConsumerState<PartySetupScreen> {
  String? _msg;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final ctl = ref.read(gameProvider.notifier);
      ctl.openParty(GameMode.random);
      await ctl.reloadLibrary(ref.read(libraryProvider));
    });
  }

  Future<void> _addPlayer() async {
    final game = ref.read(gameProvider);
    if (game.players.length >= 5) {
      setState(() => _msg = 'الحد الأقصى ٥ لاعبين على الهاتف نفسه');
      return;
    }
    final name = await _askName('اسم اللاعب', 'لاعب ${game.players.length + 1}');
    if (name == null) return;
    ref.read(gameProvider.notifier).addPlayer(name);
  }

  Future<void> _rename(String id, String current) async {
    final name = await _askName('تعديل الاسم', current);
    if (name == null || name.trim().isEmpty) return;
    ref.read(gameProvider.notifier).renamePlayer(id, name);
  }

  Future<String?> _askName(String title, String initial) {
    // The dialog owns its controller and disposes it in State.dispose —
    // disposing it right after showDialog returns races the close
    // animation (the TextField still rebuilds) and red-screens.
    return showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: title, initial: initial),
    );
  }

  Future<void> _start() async {
    final game = ref.read(gameProvider);
    if (game.library.isEmpty) {
      setState(() => _msg = 'أضف صوتًا من ٢–٦ ثوانٍ أولًا');
      return;
    }
    final mic = await ref.read(audioIoProvider).ensureMicPermission();
    if (!mic) {
      if (mounted) {
        setState(() => _msg = 'يلزم إذن الميكروفون لتقييم التقليد');
      }
      return;
    }
    if (!mounted) return;
    context.go('/game?solo=1');
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('اللعب بموبايل واحد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text('من سيلعب؟',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text(
              'تناوبوا على الهاتف؛ يمسكه كل لاعب عند دوره. '
              'تستمع إلى الصوت مرة واحدة، ثم تنتظر ٣ ثوانٍ، وتقلّد، وتحصل على نقاطك.',
              style: TextStyle(height: 1.4),
            ),
            const SizedBox(height: 8),
            Text('أصواتك الجاهزة: ${game.library.length}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            for (final p in game.players)
              Card(
                child: ListTile(
                  leading: PlayerAvatar(name: p.name, id: p.id, radius: 20),
                  title: Text(p.name),
                  subtitle: Text(p.isHost ? 'أنت' : 'مشارك'),
                  onTap: () => _rename(p.id, p.name),
                  trailing: game.players.length > 1
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => ref
                              .read(gameProvider.notifier)
                              .removePlayer(p.id),
                        )
                      : null,
                ),
              ),
            OutlinedButton.icon(
              onPressed: game.players.length >= 5 ? null : _addPlayer,
              icon: const Icon(Icons.person_add),
              label: const Text('أضف لاعب'),
            ),
            if (_msg != null) ...[
              const SizedBox(height: 12),
              Text(_msg!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 16),
            if (game.library.isEmpty)
              AppButton(
                label: 'أضف أصوات من المكتبة',
                icon: Icons.library_music,
                onPressed: () => context.go('/library'),
              )
            else
              AppButton(
                label: 'لنبدأ',
                icon: Icons.play_arrow,
                onPressed: _start,
              ),
          ],
        ),
      ),
    );
  }
}

/// Name dialog that owns its TextEditingController: it is disposed in
/// State.dispose, after the close animation is done and the TextField
/// is unmounted.
class _NameDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _NameDialog({required this.title, required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration:
            const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
