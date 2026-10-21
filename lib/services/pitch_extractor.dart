// lib/services/pitch_extractor.dart — PLAN §4 pitch pre-processing.
//
// NOTE: PLAN lists pitchupdart ^0.1.2 for YIN, but pub.dev only ships
// pitchupdart 0.0.6 (a guitar-note classifier, not a YIN detector), so pitch
// is extracted locally: WAV header (real sample rate + channels) → 50 ms
// windows → RMS silence gate → YIN F0 estimate → median-3 smoothing.
// Files that are not PCM WAV return an empty contour. Callers decode
// compressed audio to WAV first; a made-up contour would fake the score.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class _Wav {
  final List<double> mono; // -1..1
  final int sampleRate;
  _Wav(this.mono, this.sampleRate);
}

class PitchExtractor {
  static const int windowMs = 50;
  static const double silenceRmsThreshold = 0.02;
  // Generous on purpose: phone mics in real rooms are noisy, and a game
  // should measure a bad mimic with a low score rather than hear nothing.
  static const double yinThreshold = 0.20;
  static const double minFreq = 50.0;
  static const double maxFreq = 1000.0;

  /// F0 in Hz sampled every 50 ms. Returns [] on unreadable files.
  static Future<List<double>> extract(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const [];
      final bytes = await file.readAsBytes();
      final wav = _parseWav(bytes);
      if (wav == null || wav.mono.isEmpty) return const [];
      final windowSamples = (wav.sampleRate * windowMs / 1000).round();
      final raw = <double>[];
      for (var start = 0; start < wav.mono.length; start += windowSamples) {
        final end = min(start + windowSamples, wav.mono.length);
        raw.add(_yin(wav.mono.sublist(start, end), wav.sampleRate));
      }
      return _median3(raw);
    } catch (_) {
      return const [];
    }
  }

  /// RMS per 50 ms window, not peak-normalized. The scorer decides what
  /// counts as silence before it compares shapes.
  static Future<List<double>> energyEnvelope(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final wav = _parseWav(bytes);
      if (wav == null || wav.mono.isEmpty) return const [];
      final windowSamples = (wav.sampleRate * windowMs / 1000).round();
      if (windowSamples <= 0) return const [];
      final raw = <double>[];
      for (var start = 0; start < wav.mono.length; start += windowSamples) {
        final end = min(start + windowSamples, wav.mono.length);
        var sumSq = 0.0;
        for (var i = start; i < end; i++) {
          sumSq += wav.mono[i] * wav.mono[i];
        }
        raw.add(sqrt(sumSq / (end - start)));
      }
      return raw;
    } catch (_) {
      return const [];
    }
  }

  /// Peak-normalized waveform buckets (0..1) for drawing sound waves.
  /// Returns [] for non-decodable files (caller hides the visual).
  static Future<List<double>> waveform(String filePath,
      {int buckets = 64}) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final wav = _parseWav(bytes);
      if (wav == null || wav.mono.isEmpty) return const [];
      final perBucket = (wav.mono.length / buckets).ceil();
      var peak = 0.0;
      final rms = List<double>.filled(buckets, 0.0);
      for (var b = 0; b < buckets; b++) {
        final start = b * perBucket;
        if (start >= wav.mono.length) break;
        final end = min(start + perBucket, wav.mono.length);
        var sumSq = 0.0;
        for (var i = start; i < end; i++) {
          sumSq += wav.mono[i] * wav.mono[i];
        }
        rms[b] = sqrt(sumSq / (end - start));
        if (rms[b] > peak) peak = rms[b];
      }
      if (peak <= 0) return List<double>.filled(buckets, 0.0);
      return rms.map((v) => (v / peak).clamp(0.0, 1.0)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// YIN fundamental-frequency estimate for one window, 0.0 = unvoiced.
  static double _yin(List<double> window, int sampleRate) {
    final n = window.length;
    if (n < 64) return 0.0;
    var sumSq = 0.0;
    for (final s in window) {
      sumSq += s * s;
    }
    if (sqrt(sumSq / n) < silenceRmsThreshold) return 0.0;

    final maxLag = min(n - 2, (sampleRate / minFreq).round());
    final minLag = max(2, (sampleRate / maxFreq).round());
    if (maxLag <= minLag) return 0.0;

    // Step 1–2: difference function + cumulative mean normalized difference.
    final cmnd = List<double>.filled(maxLag + 1, 1.0);
    var runningSum = 0.0;
    for (var tau = 1; tau <= maxLag; tau++) {
      var d = 0.0;
      for (var j = 0; j < n - tau; j++) {
        final diff = window[j] - window[j + tau];
        d += diff * diff;
      }
      runningSum += d;
      cmnd[tau] = runningSum == 0 ? 1.0 : d * tau / runningSum;
    }

    // Step 3: first dip below threshold, then local minimum.
    // Fallback to the global minimum: a noisy-but-voiced frame still gets
    // a pitch instead of being marked silent.
    var tau = -1;
    for (var t = minLag; t <= maxLag; t++) {
      if (cmnd[t] < yinThreshold) {
        while (t + 1 <= maxLag && cmnd[t + 1] < cmnd[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      var best = minLag;
      for (var t = minLag + 1; t <= maxLag; t++) {
        if (cmnd[t] < cmnd[best]) best = t;
      }
      tau = best;
    }

    // Step 4: parabolic interpolation for sub-sample accuracy.
    var period = tau.toDouble();
    if (tau > 0 && tau < maxLag) {
      final s0 = cmnd[tau - 1], s1 = cmnd[tau], s2 = cmnd[tau + 1];
      final denom = s0 + s2 - 2 * s1;
      if (denom != 0) {
        period = tau + (s0 - s2) / (2 * denom);
      }
    }
    if (period < 1) return 0.0;
    final freq = sampleRate / period;
    if (freq < minFreq || freq > maxFreq) return 0.0;
    return freq;
  }

  static List<double> _median3(List<double> v) {
    if (v.length < 3) return v;
    final out = List<double>.from(v);
    for (var i = 1; i < v.length - 1; i++) {
      final a = v[i - 1], b = v[i], c = v[i + 1];
      out[i] = a < b
          ? (b < c ? b : (a < c ? c : a))
          : (b > c ? b : (a > c ? c : a));
    }
    return out;
  }

  /// Parses WAV bytes honoring the real header (sample rate, channels,
  /// 8/16-bit). Returns null when the file is not a WAV.
  static _Wav? _parseWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || // 'RI'
        bytes[2] != 0x46 || bytes[3] != 0x46) {
      // 'FF'
      return null;
    }
    final bd = ByteData.sublistView(bytes);
    final channels = bd.getUint16(22, Endian.little);
    final sampleRate = bd.getUint32(24, Endian.little);
    final bits = bd.getUint16(34, Endian.little);
    if (channels <= 0 || sampleRate <= 0 || (bits != 8 && bits != 16)) {
      return null;
    }
    // Find 'data' chunk.
    var dataStart = -1, dataLen = 0;
    for (var i = 12; i + 8 < bytes.length; i++) {
      if (bytes[i] == 0x64 && // 'd'
          bytes[i + 1] == 0x61 && // 'a'
          bytes[i + 2] == 0x74 && // 't'
          bytes[i + 3] == 0x61) {
        // 'a'
        dataStart = i + 8;
        dataLen = bd.getUint32(i + 4, Endian.little);
        break;
      }
    }
    if (dataStart < 0) return null;
    dataLen = min(dataLen, bytes.length - dataStart);
    final frameBytes = channels * (bits ~/ 8);
    final frames = dataLen ~/ frameBytes;
    if (frames == 0) return null;
    final mono = List<double>.filled(frames, 0.0);
    for (var f = 0; f < frames; f++) {
      var sum = 0.0;
      for (var ch = 0; ch < channels; ch++) {
        final off = dataStart + f * frameBytes + ch * (bits ~/ 8);
        if (bits == 16) {
          sum += bd.getInt16(off, Endian.little) / 32768.0;
        } else {
          sum += (bd.getUint8(off) - 128) / 128.0;
        }
      }
      mono[f] = sum / channels;
    }
    return _Wav(mono, sampleRate);
  }

  /// Peak absolute sample of a WAV file, 0 when unreadable.
  static Future<double> peakOf(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final wav = _parseWav(bytes);
      if (wav == null || wav.mono.isEmpty) return 0.0;
      var peak = 0.0;
      for (final s in wav.mono) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      return peak;
    } catch (_) {
      return 0.0;
    }
  }

  /// Scales a WAV file in place so its peak hits [target] (e.g. 0.89 for
  /// −1 dBFS library storage, 0.5 for attempts). Digital silence stays
  /// silent. Returns false when the file cannot be processed.
  static Future<bool> normalizeToPeak(String filePath, double target) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final wav = _parseWav(bytes);
      if (wav == null || wav.mono.isEmpty) return false;
      var peak = 0.0;
      for (final s in wav.mono) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      if (peak <= 0) return false;
      final gain = target / peak;
      if (gain > 0.99 && gain < 1.01) return true;
      final scaled = List<double>.generate(
        wav.mono.length,
        (i) => (wav.mono[i] * gain).clamp(-1.0, 1.0),
      );
      await File(filePath).writeAsBytes(
        _writeWav(scaled, wav.sampleRate),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Writes 16-bit PCM mono WAV bytes.
  static Uint8List _writeWav(List<double> mono, int sampleRate) {
    final dataLen = mono.length * 2;
    final out = Uint8List(44 + dataLen);
    final bd = ByteData.sublistView(out);
    void ascii(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        out[off + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    bd.setUint32(4, 36 + dataLen, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little);
    bd.setUint16(22, 1, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little);
    bd.setUint16(32, 2, Endian.little);
    bd.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bd.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < mono.length; i++) {
      bd.setInt16(
          44 + i * 2, (mono[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
    }
    return out;
  }

  // ------------------------------------------------------------------
  // MFCC timbre fingerprints (Gemini recipe): pre-emphasis → 20 ms
  // Hamming frames every 20 ms → FFT → 26 mel filters → log → DCT →
  // 13 cepstral coefficients → utterance-level cepstral mean
  // normalization. Near-silent frames become zero vectors so pauses
  // align with pauses. Used only for unpitched sounds (claps, laughs,
  // noises); pitched scoring ignores timbre so transposed melodies
  // keep scoring high.
  // ------------------------------------------------------------------

  /// MFCC frames for a WAV file. Empty list when undecodable.
  ///
  /// The signal is resampled to 44.1 kHz first: mel filter banks are
  /// built per sample rate, so comparing a 48 kHz library clip against
  /// a 44.1 kHz take without this measured pure filter mismatch.
  static const int mfccSampleRate = 44100;

  /// Linear resample of mono samples to [mfccSampleRate]. Cheap and
  /// plenty for 20 ms timbre frames.
  static List<double> resampleToMfccRate(List<double> mono, int sr) {
    if (sr == mfccSampleRate || mono.isEmpty) return mono;
    final n = (mono.length * mfccSampleRate / sr).round();
    if (n < 1) return const [];
    return List<double>.generate(n, (i) {
      final x = i * (mono.length - 1) / (n - 1);
      final j = x.floor();
      final t = x - j;
      final a = mono[j];
      final b = mono[min(j + 1, mono.length - 1)];
      return a + t * (b - a);
    });
  }

  static Future<List<List<double>>> extractMfcc(String filePath,
      {int coeffs = 13}) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final wav = _parseWav(bytes);
      if (wav == null || wav.mono.isEmpty) return const [];
      final mono44 = resampleToMfccRate(wav.mono, wav.sampleRate);
      if (mono44.isEmpty) return const [];
      const sr = mfccSampleRate;
      final frameLen = (sr * 20 / 1000).round();
      final hop = (sr * 20 / 1000).round();
      if (frameLen < 64 || hop <= 0) return const [];

      // Pre-emphasis over the whole signal.
      final mono = mono44;
      final emphasized = List<double>.filled(mono.length, 0.0);
      for (var i = 0; i < mono.length; i++) {
        emphasized[i] = mono[i] - (i > 0 ? 0.97 * mono[i - 1] : 0.0);
      }

      var n = 1;
      while (n < frameLen) {
        n <<= 1;
      }
      if (n > 2048) n = 2048;
      final filters = _melFilters(26, n, sr);
      final window = List<double>.generate(
          frameLen,
          (i) =>
              0.54 - 0.46 * cos(2 * pi * i / (frameLen - 1)));

      final frames = <List<double>>[];
      for (var start = 0; start < mono.length; start += hop) {
        final re = List<double>.filled(n, 0.0);
        final im = List<double>.filled(n, 0.0);
        var sumSq = 0.0;
        for (var i = 0; i < frameLen; i++) {
          final s = (start + i < emphasized.length)
              ? emphasized[start + i] * window[i]
              : 0.0;
          re[i] = s;
          sumSq += s * s;
        }
        final rms = sqrt(sumSq / frameLen);
        if (rms < 0.005) {
          frames.add(List<double>.filled(coeffs, 0.0));
          continue;
        }
        _fft(re, im);
        final mel = List<double>.filled(filters.length, 0.0);
        for (var m = 0; m < filters.length; m++) {
          var e = 0.0;
          final f = filters[m];
          for (var k = 0; k < f.length; k++) {
            final bin = f[k];
            e += bin * (re[k] * re[k] + im[k] * im[k]) / n;
          }
          mel[m] = log(max(e, 1e-10));
        }
        final cep = List<double>.filled(coeffs, 0.0);
        for (var k = 0; k < coeffs; k++) {
          var s = 0.0;
          for (var m = 0; m < mel.length; m++) {
            s += mel[m] * cos(pi * k * (2 * m + 1) / (2 * mel.length));
          }
          cep[k] = s;
        }
        frames.add(cep);
      }
      if (frames.isEmpty) return const [];

      // Cepstral mean normalization: subtract the per-coefficient mean
      // so mic/channel color stops mattering.
      final mean = List<double>.filled(coeffs, 0.0);
      for (final f in frames) {
        for (var k = 0; k < coeffs; k++) {
          mean[k] += f[k];
        }
      }
      for (var k = 0; k < coeffs; k++) {
        mean[k] /= frames.length;
      }
      return [
        for (final f in frames)
          List<double>.generate(coeffs, (k) => f[k] - mean[k]),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 26 triangular mel filters over FFT bins 0..n/2.
  static List<List<double>> _melFilters(int count, int n, int sr) {
    double hz2mel(double hz) => 2595 * (log(1 + hz / 700) / ln10);
    double mel2hz(double mel) => 700 * (pow(10, mel / 2595) - 1);
    final low = hz2mel(0);
    final high = hz2mel(sr / 2);
    final points = List<double>.generate(
        count + 2, (i) => mel2hz(low + i * (high - low) / (count + 1)));
    final bins = (n ~/ 2) + 1;
    return List<List<double>>.generate(count, (m) {
      final row = List<double>.filled(bins, 0.0);
      final left = points[m], center = points[m + 1], right = points[m + 2];
      for (var k = 0; k < bins; k++) {
        final hz = k * sr / n;
        if (hz >= left && hz <= center && center != left) {
          row[k] = (hz - left) / (center - left);
        } else if (hz >= center && hz <= right && right != center) {
          row[k] = (right - hz) / (right - center);
        }
      }
      return row;
    });
  }

  /// In-place radix-2 FFT.
  static void _fft(List<double> re, List<double> im) {
    final n = re.length;
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    var len = 2;
    while (len <= n) {
      final ang = -2 * pi / len;
      final wr = cos(ang), wi = sin(ang);
      var i = 0;
      while (i < n) {
        var cwr = 1.0, cwi = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final ur = re[i + k], ui = im[i + k];
          final vr = re[i + k + len ~/ 2] * cwr -
              im[i + k + len ~/ 2] * cwi;
          final vi = re[i + k + len ~/ 2] * cwi +
              im[i + k + len ~/ 2] * cwr;
          re[i + k] = ur + vr;
          im[i + k] = ui + vi;
          re[i + k + len ~/ 2] = ur - vr;
          im[i + k + len ~/ 2] = ui - vi;
          final nwr = cwr * wr - cwi * wi;
          cwi = cwr * wi + cwi * wr;
          cwr = nwr;
        }
        i += len;
      }
      len <<= 1;
    }
  }
}
