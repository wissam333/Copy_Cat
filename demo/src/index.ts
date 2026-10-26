/**
 * index.ts — the public API. Everything else is internal.
 *
 * The highest-level entry point is `scorePcm()`: give it the PCM of a
 * target clip and a player attempt, get a 0–100 verdict. It runs the exact
 * pipeline the original Dart app runs after recording:
 *
 *   1. gate room tone on the raw attempt envelope ("nobody at the mic")
 *   2. peak-normalize the attempt to 0.5
 *   3. extract pitch + energy + MFCC from both
 *   4. judge() → verdict
 *
 * For the browser, `scoreAudioBuffer()`/`decodeBlobToPcm()` decode any audio
 * with the platform's own decoder. In Node use `scoreWavBytes()` or feed
 * `parseWav()` output into `scorePcm()`.
 */

import type { Kind, ScoreVerdict, JudgeFeatures, JudgeResult } from './core.js';
import { judge, diagnose, isRoomTone, looksPitched, classify, ZERO_VERDICT } from './core.js';
import type { DeepPartial, ScorerOptions } from './options.js';
import { DEFAULT_OPTIONS, resolveOptions } from './options.js';
import type { WavData, Pcm } from './pcm.js';
import { parseWav, writeWav, normalizePeak, decodeBlobToPcm } from './pcm.js';
import { extractPitch, energyEnvelope, waveformBuckets, resampleLinear, median3, yin } from './pitch.js';
import { extractMfcc, MFCC_SAMPLE_RATE } from './mfcc.js';

// Types and values re-exported so consumers only import from this module.
export type {
  Kind,
  ScoreVerdict,
  JudgeFeatures,
  JudgeResult,
  ScorerOptions,
  DeepPartial,
  WavData,
  Pcm,
};
export {
  judge,
  diagnose,
  isRoomTone,
  looksPitched,
  classify,
  ZERO_VERDICT,
  DEFAULT_OPTIONS,
  resolveOptions,
  parseWav,
  writeWav,
  normalizePeak,
  decodeBlobToPcm,
  extractPitch,
  energyEnvelope,
  waveformBuckets,
  resampleLinear,
  median3,
  yin,
  extractMfcc,
  MFCC_SAMPLE_RATE,
};

export type ScoreNote = 'ok' | 'silent' | 'empty-pitch' | 'unreadable';

export interface ScoreResult {
  verdict: ScoreVerdict;
  /** What kind of sound the target is: 'tonal' | 'speech' | 'noise'. */
  kind: Kind;
  /** 'silent' / 'empty-pitch' / 'unreadable' are zero-score early exits. */
  note: ScoreNote;
  /** Fraction of attempt windows that carried pitch (0..1). */
  voicedPct: number;
  /** 48 peak-normalized RMS buckets of the attempt — easy to draw. */
  waveform: number[];
  /** The target pitch contour when it could be extracted (for graphs). */
  targetPitch?: number[];
  /** The player pitch contour when it could be extracted (for graphs). */
  playerPitch?: number[];
}

export interface ExtractedFeatures {
  pitch: number[];
  energy: number[];
  mfcc: number[][];
  waveform: number[];
}

/**
 * Score a target clip against a player attempt; both given as raw PCM
 * samples (any sample rate) plus their sample rate. Synchronous, pure math.
 */
export function scorePcm(
  targetMono: Pcm,
  targetSampleRate: number,
  playerMono: Pcm,
  playerSampleRate: number,
  options?: DeepPartial<ScorerOptions>,
): ScoreResult {
  const o = resolveOptions(options);

  // Gate room tone on the RAW envelope — before normalization, otherwise
  // every room would sound loud after scaling.
  const rawEnergy = energyEnvelope(playerMono, playerSampleRate, o);
  if (isRoomTone(rawEnergy, o)) {
    return { verdict: ZERO_VERDICT, kind: 'noise', note: 'silent', voicedPct: 0, waveform: [] };
  }

  const player =
    o.preprocess.normalizePlayerPeak > 0
      ? normalizePeak(playerMono, o.preprocess.normalizePlayerPeak)
      : playerMono;
  const target =
    o.preprocess.normalizeTargetPeak > 0
      ? normalizePeak(targetMono, o.preprocess.normalizeTargetPeak)
      : targetMono;

  const targetPitch = extractPitch(target, targetSampleRate, o);
  const playerPitch = extractPitch(player, playerSampleRate, o);
  if (playerPitch.length === 0) {
    return {
      verdict: ZERO_VERDICT,
      kind: classify(targetPitch),
      note: 'empty-pitch',
      voicedPct: 0,
      waveform: [],
      targetPitch,
      playerPitch,
    };
  }

  const targetEnergy = energyEnvelope(target, targetSampleRate, o);
  const playerEnergy = energyEnvelope(player, playerSampleRate, o);
  const targetMfcc = extractMfcc(target, targetSampleRate, o);
  const playerMfcc = extractMfcc(player, playerSampleRate, o);

  const verdict = judge(
    targetPitch,
    playerPitch,
    { targetEnergy, playerEnergy, targetMfcc, playerMfcc },
    o,
  );

  const voiced = playerPitch.filter((f) => f > 0).length;
  const voicedPct = playerPitch.length === 0 ? 0 : voiced / playerPitch.length;
  const waveform = waveformBuckets(player, playerSampleRate, o, 48);

  return { verdict, kind: classify(targetPitch), note: 'ok', voicedPct, waveform, targetPitch, playerPitch };
}

/** Score two WAV files (8/16-bit PCM) given as bytes. */
export function scoreWavBytes(
  targetWav: Uint8Array,
  playerWav: Uint8Array,
  options?: DeepPartial<ScorerOptions>,
): ScoreResult {
  const t = parseWav(targetWav);
  const p = parseWav(playerWav);
  if (!t || !p) {
    return { verdict: ZERO_VERDICT, kind: 'noise', note: 'unreadable', voicedPct: 0, waveform: [] };
  }
  return scorePcm(t.mono, t.sampleRate, p.mono, p.sampleRate, options);
}

/** Browser convenience: score two decoded AudioBuffers directly. */
export function scoreAudioBuffer(
  target: AudioBuffer,
  player: AudioBuffer,
  options?: DeepPartial<ScorerOptions>,
): ScoreResult {
  return scorePcm(
    target.getChannelData(0),
    target.sampleRate,
    player.getChannelData(0),
    player.sampleRate,
    options,
  );
}

/** Extract everything the scorer needs from one PCM clip (demo / graphs). */
export function extractFeatures(
  mono: Pcm,
  sampleRate: number,
  options?: DeepPartial<ScorerOptions>,
): ExtractedFeatures {
  const o = resolveOptions(options);
  return {
    pitch: extractPitch(mono, sampleRate, o),
    energy: energyEnvelope(mono, sampleRate, o),
    mfcc: extractMfcc(mono, sampleRate, o),
    waveform: waveformBuckets(mono, sampleRate, o, 48),
  };
}