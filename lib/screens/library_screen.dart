// lib/screens/library_screen.dart — PLAN §4 + §8.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/pitch_extractor.dart';
import '../state/game_state.dart';
import '../widgets/sprite_button.dart';
import '../widgets/ui_bits.dart';
import '../widgets/wave_pitch.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _busy = false;
  bool _recording = false;
  int _recordSeconds = 5;
  String? _msg;
  String? _playingId;
  List<double> _live = const [];
  StreamSubscription<double>? _ampSub;
  final Map<String, List<double>> _waves = {};

  /// Pitch contour per sound id: the stored pitchMap when it was saved
  /// with the file, else extracted from the WAV once and cached here.
  final Map<String, List<double>> _pitches = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref
          .read(gameProvider.notifier)
          .reloadLibrary(ref.read(libraryProvider));
      _loadWaves();
    });
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    super.dispose();
  }

  Future<void> _loadWaves() async {
    final lib = ref.read(gameProvider).library;
    for (final s in lib) {
      if (!mounted) return;
      if (!_waves.containsKey(s.id)) {
        final w = await PitchExtractor.waveform(s.filePath, buckets: 48);
        if (!mounted) return;
        if (w.isNotEmpty) setState(() => _waves[s.id] = w);
      }
      // Stored pitchMap (50 ms cadence) is free; only rerun extraction
      // for old library entries saved before pitch hashing existed.
      if (!_pitches.containsKey(s.id)) {
        final p = s.pitchMap.length >= 8
            ? s.pitchMap
            : await PitchExtractor.extract(s.filePath);
        if (!mounted) return;
        if (p.isNotEmpty && p.any((f) => f > 0)) {
          setState(() => _pitches[s.id] = p);
        }
      }
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final res = await ref.read(libraryProvider).importFromPicker();
      if (res.sound != null) {
        await ref
            .read(gameProvider.notifier)
            .reloadLibrary(ref.read(libraryProvider));
        _loadWaves();
        setState(() => _msg = 'تمت الإضافة: “${res.sound!.title}”');
      } else {
        setState(() => _msg = res.error);
      }
    } catch (e) {
      setState(() => _msg = 'فشل الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _record() async {
    if (_recording) return;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      setState(() => _msg = 'يلزم إذن الميكروفون');
      return;
    }
    setState(() {
      _recording = true;
      _live = const [];
      _msg = 'جارٍ التسجيل… غنِّ أو قلّد لمدة $_recordSeconds ثوانٍ';
    });
    try {
      final io = ref.read(audioIoProvider);
      _ampSub = io.micLevels().listen((level) {
        if (!mounted) return;
        setState(() {
          final next = [..._live, level];
          _live = next.length > 48 ? next.sublist(next.length - 48) : next;
        });
      });
      final path = await io.tempWavPath(
          'mimic_${DateTime.now().millisecondsSinceEpoch}');
      final stopped = await io.recordWav(
          path, Duration(seconds: _recordSeconds));
      await _ampSub?.cancel();
      _ampSub = null;
      if (stopped == null) {
        setState(() => _msg = 'التسجيل لم يُنتج ملفًا');
        return;
      }
      final res = await ref.read(libraryProvider).ingest(stopped,
          title:
              'مقطع ${DateTime.now().hour}:${DateTime.now().minute}');
      if (res.sound != null) {
        await ref
            .read(gameProvider.notifier)
            .reloadLibrary(ref.read(libraryProvider));
        _loadWaves();
        setState(() => _msg = 'تمت الإضافة: “${res.sound!.title}”');
      } else {
        setState(() => _msg = res.error);
      }
    } catch (e) {
      await _ampSub?.cancel();
      _ampSub = null;
      setState(() => _msg = 'فشل التسجيل: $e');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مكتبة الأصوات'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('استيراد (2–6 ثوانٍ)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_busy || _recording) ? null : _record,
                      icon: Icon(
                          _recording ? Icons.stop : Icons.mic),
                      label: Text(_recording
                          ? 'جارٍ التسجيل…'
                          : 'تسجيل $_recordSeconds ث'),
                    ),
                  ),
                ],
              ),
              if (!_recording) ...[
                Row(
                  children: [
                    const Text('المدة',
                        style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Slider(
                        value: _recordSeconds.toDouble(),
                        min: 2,
                        max: 6,
                        divisions: 4,
                        label: '$_recordSeconds ث',
                        onChanged: _busy
                            ? null
                            : (v) => setState(
                                () => _recordSeconds = v.round()),
                      ),
                    ),
                    Text('$_recordSeconds ث',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: (_busy || _recording)
                      ? null
                      : () => context.go('/download'),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('تحميل أصوات من الإنترنت'),
                ),
              ),
              if (_recording) ...[
                const SizedBox(height: 12),
                WaveformBars(values: _live),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_msg!,
                      style: const TextStyle(fontSize: 12)),
                ),
              const SectionTitle('أصوات التحدي'),
              Expanded(
                child: game.library.isEmpty
                    ? const Center(
                        child: Text(
                            'فارغة. استورد أو سجّل صوتًا من 2–6 ثوانٍ للّعب.'))
                    : ListView.builder(
                        itemCount: game.library.length,
                        itemBuilder: (context, i) {
                          final s = game.library[i];
                          final wave = _waves[s.id];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: const Icon(
                                        Icons.audio_file_outlined),
                                    title: Text(s.title),
                                    subtitle: Text(
                                        '${s.durationSeconds.toStringAsFixed(1)} ث · ${s.pitchMap.length} عينة نغمية'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SpriteButton(
                                          seed: s.id,
                                          playing: _playingId == s.id,
                                          onTap: () async {
                                            // Tap the playing sound again:
                                            // stop it.
                                            if (_playingId == s.id) {
                                              try {
                                                await ref
                                                    .read(audioIoProvider)
                                                    .stopPlayback();
                                              } catch (_) {}
                                              if (context.mounted) {
                                                setState(() =>
                                                    _playingId = null);
                                              }
                                              return;
                                            }
                                            final io = ref.read(
                                                audioIoProvider);
                                            try {
                                              await io.stopPlayback();
                                            } catch (_) {}
                                            if (!context.mounted) return;
                                            setState(
                                                () => _playingId = s.id);
                                            try {
                                              await io.playOnce(
                                                  s.filePath);
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                        content: Text(
                                                            'فشل التشغيل: $e')));
                                              }
                                            } finally {
                                              if (context.mounted &&
                                                  _playingId == s.id) {
                                                setState(() =>
                                                    _playingId = null);
                                              }
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline),
                                          onPressed: () async {
                                            if (_playingId == s.id) {
                                              try {
                                                await ref
                                                    .read(audioIoProvider)
                                                    .stopPlayback();
                                              } catch (_) {}
                                              if (mounted) {
                                                setState(() =>
                                                    _playingId = null);
                                              }
                                            }
                                            await ref
                                                .read(libraryProvider)
                                                .delete(s);
                                            await ref
                                                .read(gameProvider.notifier)
                                                .reloadLibrary(ref.read(
                                                    libraryProvider));
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (wave != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(
                                              16, 0, 16, 8),
                                      child: WavePitchPreview(
                                        wave: wave,
                                        pitch: _pitches[s.id],
                                        height: 64,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
