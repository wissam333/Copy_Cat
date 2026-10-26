// lib/services/sound_library_service.dart — PLAN §4 sanitizer.
// WAV/M4A in, 2–6 s enforced, silence-trim note, pitchMap sidecar.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../i18n.dart';
import '../models/game_sound.dart';
import 'audio_io_service.dart';
import 'native_audio.dart';
import 'pitch_extractor.dart';

class LibraryResult {
  final GameSound? sound;
  final String? error;
  const LibraryResult.ok(this.sound) : error = null;
  const LibraryResult.fail(this.error) : sound = null;
}

class SoundLibraryService {
  static const double minSeconds = 2.0;
  static const double maxSeconds = 6.0;

  final AudioIoService audio;
  final _uuid = const Uuid();

  SoundLibraryService(this.audio);

  Future<Directory> _soundsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'mimic_sounds'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<GameSound>> loadAll() async {
    final dir = await _soundsDir();
    final out = <GameSound>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        try {
          final json =
              jsonDecode(await e.readAsString()) as Map<String, dynamic>;
          var sound = GameSound.fromJson(json);
          if (!await File(sound.filePath).exists()) continue;
          // Backfill for sounds saved before hashing/normalization:
          // bring quiet files to the same level, then hash.
          if (sound.hash.isEmpty) {
            try {
              final peak =
                  await PitchExtractor.peakOf(sound.filePath);
              if (peak > 0 && peak < 0.3) {
                await PitchExtractor.normalizeToPeak(
                    sound.filePath, 0.89);
              }
              final hash = await fileHash(sound.filePath);
              sound = sound.copyWith(hash: hash);
              await File('${sound.filePath}.json')
                  .writeAsString(jsonEncode(sound.toJson()));
            } catch (_) {}
          }
          out.add(sound);
        } catch (_) {}
      }
    }
    out.sort((a, b) => a.title.compareTo(b.title));
    return out;
  }

  /// FNV-1a 64-bit hash of a file's bytes (no dependency, fast enough
  /// for a few seconds of audio). Same bytes → same voice.
  static Future<String> fileHash(String path) async {
    final bytes = await File(path).readAsBytes();
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  Future<LibraryResult> importFromPicker() async {
    final path = await NativeAudio().pickAudio();
    if (path == null) {
      return LibraryResult.fail(t('لم يتم اختيار ملف'));
    }
    return ingest(path);
  }

  /// Validates duration, copies into app storage, extracts pitchMap.
  /// Same bytes (or same source link) as an existing sound → rejected.
  Future<LibraryResult> ingest(String srcPath,
      {String? title, String? sourceUrl}) async {
    final duration = await audio.probeDuration(srcPath);
    if (duration == null) {
      return LibraryResult.fail(t('تعذّر قراءة الملف الصوتي'));
    }
    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds < minSeconds || seconds > maxSeconds) {
      return LibraryResult.fail(t('يجب أن يكون الصوت 2–6 ثوانٍ (هذا {n} ث)', {
        'n': seconds.toStringAsFixed(1),
      }));
    }
    // Compressed imports become WAV here so the stored pitch map is a
    // real contour, not a placeholder.
    var source = srcPath;
    final decoded = await audio.decodeToWav(srcPath);
    if (decoded != null) source = decoded;

    final dir = await _soundsDir();
    final id = _uuid.v4();
    final ext = p.extension(source).toLowerCase();
    final safeExt =
        (ext == '.wav' || ext == '.m4a' || ext == '.mp3') ? ext : '.m4a';
    final dest = p.join(dir.path, '$id$safeExt');
    await File(source).copy(dest);
    if (decoded != null && decoded != srcPath) {
      try {
        await File(decoded).delete();
      } catch (_) {}
    }

    // Fairness (Gemini notes): one fixed loudness for every stored sound,
    // so mic distance stops costing points. Silence stays silent.
    await PitchExtractor.normalizeToPeak(dest, 0.89);

    // Same voice twice? Compare content hash (and source link) against
    // the library before accepting it.
    final hash = await fileHash(dest);
    final existing = await loadAll();
    final dup = existing.any((s) =>
        (hash.isNotEmpty && s.hash == hash) ||
        (sourceUrl != null &&
            sourceUrl.isNotEmpty &&
            s.sourceUrl == sourceUrl));
    if (dup) {
      try {
        await File(dest).delete();
      } catch (_) {}
      return LibraryResult.fail(
          t('هذا الصوت موجود في المكتبة مسبقًا'));
    }

    final isWav = safeExt == '.wav';
    final pitchMap =
        isWav ? await PitchExtractor.extract(dest) : const <double>[];

    final sound = GameSound(
      id: id,
      title: title ?? p.basenameWithoutExtension(srcPath),
      filePath: dest,
      durationSeconds: seconds,
      pitchMap: pitchMap,
      hash: hash,
      sourceUrl: sourceUrl ?? '',
    );
    await File('$dest.json')
        .writeAsString(jsonEncode(sound.toJson()));
    return LibraryResult.ok(sound);
  }

  Future<void> delete(GameSound sound) async {
    try {
      await File(sound.filePath).delete();
    } catch (_) {}
    try {
      await File('${sound.filePath}.json').delete();
    } catch (_) {}
  }
}
