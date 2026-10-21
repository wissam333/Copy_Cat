// lib/services/sfx.dart — tiny UI sounds, generated locally (no downloads,
// no licensing issues). Played only on local events (taps, countdown,
// reveal) — never on a remote command, so an open mic stays clean.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_io_service.dart';

class Sfx {
  static const click = 'click';
  static const beep = 'beep';
  static const go = 'go';
  static const tick = 'tick';
  static const ding = 'ding';
  static const fanfare = 'fanfare';
  static const sad = 'sad';

  static final Map<String, String> _temps = {};

  /// Best-effort fire-and-forget playback. Never throws.
  static Future<void> play(AudioIoService io, String name) async {
    try {
      var path = _temps[name];
      if (path == null) {
        final data =
            await rootBundle.load('assets/sfx/$name.wav');
        final dir = await getTemporaryDirectory();
        path =
            '${dir.path}${Platform.pathSeparator}sfx_$name.wav';
        await File(path).writeAsBytes(
          data.buffer.asUint8List(),
          flush: true,
        );
        _temps[name] = path;
      }
      await io.playOnce(path);
    } catch (_) {}
  }

  /// Landing jingle for a score: fanfare high, sad low, ding between.
  static Future<void> playLanding(AudioIoService io, double score) {
    if (score >= 85) return play(io, fanfare);
    if (score < 20) return play(io, sad);
    return play(io, ding);
  }
}
