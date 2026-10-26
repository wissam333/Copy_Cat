# voice-mimic-score

Score how closely one voice recording mimics another — **pitch, rhythm, timbre,
and loudness** — entirely in JavaScript. Browser and Node. **Zero runtime
dependencies.**

Give it a target clip and an attempt, get back a 0–100 score plus melody and
rhythm sub-scores, with every intermediate value exposed so you can see *why*.

```ts
import { scoreWavBytes } from 'voice-mimic-score';
import { readFileSync } from 'node:fs';

const target = readFileSync('target.wav');
const attempt = readFileSync('attempt.wav');

const result = scoreWavBytes(target, attempt);
console.log(result.verdict.total);  // 0..100
console.log(result.verdict.melody); // pitch match
console.log(result.verdict.rhythm); // loudness/pause match
```

In a browser:

```ts
import { scorePcm, decodeBlobToPcm } from 'voice-mimic-score';

const target = await decodeBlobToPcm(targetBlob);
const attempt = await decodeBlobToPcm(attemptBlob);

const result = scorePcm(
  target!.mono, target!.sampleRate,
  attempt!.mono, attempt!.sampleRate,
);
```

---

## Why

- **No dependencies, no WASM, no model download.** It is arithmetic over arrays,
  so it runs anywhere and the bundle is tiny (~9 kB gzipped for the whole demo).
- **Portable.** This is a 1:1 port of a Dart/Flutter engine; the two produce
  identical numbers, verified by an oracle test suite (see [Parity](#parity)).
- **Tunable.** Every constant — thresholds, weights, the perceptual curve — is
  exposed via a typed options object with the same defaults as the original.
- **Explainable.** `diagnose()` returns every intermediate value; nothing is a
  black box. The `docs/` folder teaches the whole pipeline from first
  principles, assuming no audio background.

## What "score" means

The engine compares four **axes**, each in `0..1`:

| Axis     | Meaning                                  | Technique |
|----------|------------------------------------------|-----------|
| `pitch`  | Same notes / melody?                     | YIN pitch tracking + DTW on the pitch contour |
| `mfcc`   | Does the voice *sound* like the target?  | MFCCs (FFT → mel → DCT) + DTW |
| `energy` | Same loudness shape?                     | RMS envelope + DTW + correlation |
| `timing` | Right length and rhythm?                 | Voiced/onset overlap (IoU) + duration |

The axes are **weighted by target type** (`tonal` singing, `speech`, `noise`),
missing/unreliable axes are dropped and the rest renormalized, then three
penalty multipliers (monotone singing, wrong length, choppy delivery) and a
**weakest-link cap** feed a perceptually-tuned `feel` curve to produce 0–100.

Full derivation in [`docs/concepts.md`](docs/concepts.md).

## Install

```sh
npm install voice-mimic-score
```

Works in any ESM environment. Node 18+. No peer dependencies.

## API

### `scorePcm(targetMono, targetSampleRate, playerMono, playerSampleRate, options?)`

The core entry point. Samples are `Float32Array | Float64Array | number[]`,
range `-1..1`; sample rates may differ. Runs the full pipeline:
room-tone gate → normalize attempt peak → extract features → judge.

### `scoreWavBytes(targetWav, playerWav, options?)`

Convenience for 8/16-bit PCM WAV files as `Uint8Array`.

### `scoreAudioBuffer(target, player, options?)`

Browser helper taking two decoded `AudioBuffer`s.

### `extractFeatures(mono, sampleRate, options?)`

Returns the raw `{ pitch, energy, mfcc, waveform }` for one clip — useful for
drawing graphs or building your own comparison.

### `decodeBlobToPcm(blob, audioCtx?)`

Browser helper: decode any audio the platform supports (MP3/OGG/WAV/Opus) to
`{ mono, sampleRate }` using the built-in `AudioContext`. Returns `null` on
failure.

### `judge(targetPitch, playerPitch, features?, options?)` / `diagnose(...)`

Score directly from pitch contours (`0` = unvoiced frame), optionally with
energy and MFCC features. `diagnose()` returns the full intermediate map.

### Result shape

```ts
interface ScoreResult {
  verdict: { total: number; melody: number; rhythm: number; pitched: boolean };
  kind: 'tonal' | 'speech' | 'noise';
  note: 'ok' | 'silent' | 'empty-pitch' | 'unreadable';
  voicedPct: number;         // fraction of the attempt that carried pitch
  waveform: number[];        // 48 normalized buckets, ready to draw
  targetPitch?: number[];    // pitch contours, when available
  playerPitch?: number[];
}
```

Other exports: `parseWav`, `writeWav`, `normalizePeak`, `resolveOptions`,
`DEFAULT_OPTIONS`, `classify`, `isRoomTone`, `looksPitched`, and the low-level
`extractPitch`, `energyEnvelope`, `extractMfcc`, `yin`, `median3`,
`waveformBuckets`, `resampleLinear`.

## Options

Every constant is overridable. The object is deep-merged over `DEFAULT_OPTIONS`,
so you pass only what you want to change:

```ts
scorePcm(target, sr, attempt, sr, {
  scoring: { mfccSigma: 6 },        // be stricter about timbre
  weights: { tonal: { pitch: 0.6 } },
});
```

Top-level groups: `preprocess`, `pitch`, `mfcc`, `scoring`, `gates`, `weights`,
`multipliers`. Call `resolveOptions(partial)` to get a fully-resolved object, or
read `DEFAULT_OPTIONS` for the complete list with defaults and documentation.

## Demo

```sh
npm install
npm run demo        # opens a recording + scoring playground with a live options panel
```

`demo/` is a small Vite app: record a target, record a mimic, score, and turn the
knobs to see the score change in real time. Nothing leaves your machine.

## Parity

This package is a faithful port of a Dart scoring engine. To prove it, a Dart
"oracle" emits the full feature set and verdict for a pair of WAV files, and the
TypeScript engine re-derives them from the same bytes:

```sh
npm test
```

The parity suite asserts every feature, every diagnostic, and the final integer
scores match, with a `1e-6` tolerance on floats and exact equality on integers.

## Scope

This measures **imitation** of pitch, rhythm, timbre, and loudness — not speaker
identity, and not whether the same *words* were said (that would require speech
recognition, which is intentionally out of scope). Pure noise targets (claps,
laughs) are scored on rhythm and timbre only; pitch is ignored.

## License

MIT
