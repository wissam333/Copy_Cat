/**
 * options.ts — every knob the scoring engine has, with the defaults that
 * make the JavaScript output identical to the original Dart engine.
 *
 * Pass a partial override to `resolveOptions()` to tune any of them; the
 * helper deep-merges your values on top of the defaults. `resolveOptions()`
 * is used internally by every public function, so behaviour is always
 * consistent.
 */

/** Per-axis weights: how much pitch/mfcc/energy/timing count for a clip kind. */
export interface Weights {
  pitch: number;
  mfcc: number;
  energy: number;
  timing: number;
}

/** YIN pitch extraction constants (see docs/concepts.md for the "why"). */
export interface PitchOptions {
  /** Analysis window length in milliseconds. */
  windowMs: number;
  /** Below this RMS a window is treated as silence (no pitch). */
  silenceRmsThreshold: number;
  /** YIN "voiced" threshold on the normalized difference function. */
  yinThreshold: number;
  /** Lowest pitch to consider, in Hz. */
  minFreq: number;
  /** Highest pitch to consider, in Hz. */
  maxFreq: number;
}

/** MFCC timbre extraction constants. */
export interface MfccOptions {
  /** Number of cepstral coefficients (13 is classic). */
  coeffs: number;
  /** Number of triangular mel filters over the spectrum. */
  melFilters: number;
  /** Pre-emphasis factor (0.97 boosts highs, like a bass cut). */
  preEmphasis: number;
  /** Analysis frame length in milliseconds. */
  frameMs: number;
  /** RMS below this → the frame is treated as silence (zero vector). */
  rmsGate: number;
}

/** Energy gates that tell "nobody was at the mic" apart from a real take. */
export interface GatesOptions {
  /** Raw-envelope peak below this = room tone / background noise. */
  roomTonePeak: number;
  /** Peak RMS below this = "the mic heard nothing". */
  silencePeak: number;
  /** Envelope this flat (90th pct under flatRatio × 10th pct) = hum. */
  flatRatio: number;
}

/** In-memory normalization applied before feature extraction. 0 = off. */
export interface PreprocessOptions {
  /** Peak to scale the attempt (player) to, e.g. 0.5. */
  normalizePlayerPeak: number;
  /** Peak to scale the target to (off by default). */
  normalizeTargetPeak: number;
}

/** Frame-error bands: within tol = perfect, at/over max = 0. */
export interface ErrorBand {
  tol: number;
  max: number;
}

/** Weakest-link rule: an important axis scoring terribly caps the total. */
export interface WeakestLinkOptions {
  /** An axis with at least this (normalized) weight is "important". */
  weightMin: number;
  /** …and counts as terrible when its score is below this. */
  scoreBelow: number;
  /** The total is then capped at this raw value. */
  cap: number;
}

/** Shape of the length (duration match) multiplier. */
export interface LengthMulOptions {
  /** Ratio inside [centerLow, centerHigh] keeps the full multiplier (1). */
  centerLow: number;
  centerHigh: number;
  /** Below this ratio (or above highEdge) the multiplier hits `floor`. */
  lowEdge: number;
  highEdge: number;
  /** Multiplier at lowEdge/highEdge, ramping to 1 at center. */
  upFloor: number;
  upRamp: number;
  downRamp: number;
  /** Absolute worst-case multiplier. */
  floor: number;
}

/** Shape of the "sang a flat tone while the target moves" penalty. */
export interface StaticMonotoneOptions {
  /** Target std lower than this = it's a flat beep; no penalty. */
  monotoneHz: number;
  /** Player std over target std at/under this → clamps to voicedMul. */
  voicedBelow: number;
  /** The penalty multiplier. */
  voicedMul: number;
  /** Player/target std ratio at/over this → no penalty (1). */
  voicedHigh: number;
}

/** Bursts = connected frames above a fraction of peak. */
export interface BurstOptions {
  /** Strict mask / burst-count floor (fraction of peak). */
  floorRatio: number;
  /** Loose activity-mask floor used by the length ratio. */
  looseFloorRatio: number;
  /** Noise-clip burst weight: sim contributes `noiseMix + (1-noiseMix)*sim`. */
  noiseMix: number;
}

/** Judging constants. */
export interface ScoringOptions {
  /** MFCC distance sigma: err beyond this makes the timbre axis melt. */
  mfccSigma: number;
  /** Target octave-slip rate at/over this → pitch is unreliable, skip it. */
  octaveSlipLimit: number;
  /** Sentinel for "not a voiced frame" in cent contours. */
  voicedFloor: number;
  /** Minimum voiced target frames before pitch scoring is attempted. */
  minVoiced: number;
  /** Player voiced ratio (after trimming) needed to actually score pitch. */
  pitchGateVoiced: number;
  /** Pitch tolerance bands per clip kind. */
  tonalError: ErrorBand;
  speechError: ErrorBand;
  /** Multiplier applied when an octave fold was the best match. */
  foldedPenalty: number;
  /** DTW cost of pairing one voiced with one silent frame. */
  voicedMismatchCost: number;
  /** Sakoe-Chiba band (fraction of length) for pitch alignment. */
  dtwSlackAlign: number;
  /** Sakoe-Chiba band for the MFCC distance. */
  dtwSlackVec: number;
  weakestLink: WeakestLinkOptions;
  /** Piecewise "game feel" curve mapping raw 0..1 → score 0..100. */
  feelCurve: Array<[number, number]>;
  /** All four axes at/over this → perfect copy, total = 100. */
  perfectThreshold: number;
}

/** Energy-shape blend, weights used in the energy axis. */
export interface EnergyAxisOptions {
  /** Pearson correlation weight (with the MAD term). */
  corrWeight: number;
  /** MAD term divisor: exp(-mad / madDivisor). */
  madDivisor: number;
  /** How much the correlation/MAD blend counts vs. dynamic range. */
  baseWeight: number;
  /** Dynamic-range-similarity weight. */
  rangeWeight: number;
}

/** Timing axis blend: IoU of voiced masks, duration match, burst count. */
export interface TimingAxisOptions {
  iouWeight: number;
  durWeight: number;
  burstWeight: number;
}

export interface ScorerOptions {
  pitch: PitchOptions;
  mfcc: MfccOptions;
  gates: GatesOptions;
  preprocess: PreprocessOptions;
  weights: { tonal: Weights; speech: Weights; noise: Weights };
  scoring: ScoringOptions;
  multipliers: {
    staticMonotone: StaticMonotoneOptions;
    length: LengthMulOptions;
    burst: BurstOptions;
  };
  energyAxis: EnergyAxisOptions;
  timingAxis: TimingAxisOptions;
}

/** Defaults — the exact constants of the original Dart engine. */
export const DEFAULT_OPTIONS: ScorerOptions = {
  pitch: {
    windowMs: 50,
    silenceRmsThreshold: 0.02,
    yinThreshold: 0.2,
    minFreq: 50,
    maxFreq: 1000,
  },
  mfcc: {
    coeffs: 13,
    melFilters: 26,
    preEmphasis: 0.97,
    frameMs: 20,
    rmsGate: 0.005,
  },
  gates: {
    roomTonePeak: 0.04,
    silencePeak: 0.006,
    flatRatio: 1.8,
  },
  preprocess: {
    normalizePlayerPeak: 0.5,
    normalizeTargetPeak: 0,
  },
  weights: {
    // 2026-10 rebalance — keep in sync with lib/services/audio_scorer.dart:
    // melody (pitch) and rhythm (timing) weigh equally on sung clips.
    tonal: { pitch: 0.3, mfcc: 0.2, energy: 0.2, timing: 0.3 },
    speech: { pitch: 0.25, mfcc: 0.35, energy: 0.2, timing: 0.2 },
    noise: { pitch: 0, mfcc: 0.4, energy: 0.35, timing: 0.25 },
  },
  scoring: {
    mfccSigma: 12,
    octaveSlipLimit: 0.08,
    voicedFloor: -1e5,
    minVoiced: 4,
    pitchGateVoiced: 0.45,
    tonalError: { tol: 100, max: 450 },
    speechError: { tol: 200, max: 600 },
    foldedPenalty: 0.85,
    voicedMismatchCost: 400,
    dtwSlackAlign: 0.2,
    dtwSlackVec: 0.35,
    weakestLink: { weightMin: 0.25, scoreBelow: 0.15, cap: 0.45 },
    feelCurve: [
      [0, 0],
      [0.2, 10],
      [0.4, 40],
      [0.55, 70],
      [0.7, 88],
      [0.85, 97],
      [1, 100],
    ],
    perfectThreshold: 0.995,
  },
  multipliers: {
    staticMonotone: {
      monotoneHz: 200,
      voicedBelow: 0.15,
      voicedMul: 0.3,
      voicedHigh: 0.5,
    },
    length: {
      centerLow: 0.75,
      centerHigh: 1.35,
      lowEdge: 0.5,
      highEdge: 2.0,
      upFloor: 0.7,
      upRamp: 0.3,
      downRamp: 0.3,
      floor: 0.5,
    },
    burst: {
      floorRatio: 0.4,
      looseFloorRatio: 0.15,
      noiseMix: 0.5,
    },
  },
  energyAxis: {
    corrWeight: 0.5,
    madDivisor: 6,
    baseWeight: 0.85,
    rangeWeight: 0.15,
  },
  timingAxis: {
    iouWeight: 0.5,
    durWeight: 0.25,
    burstWeight: 0.25,
  },
};

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * A recursive "everything optional" view of the options, so callers can pass
 * just the leaf they care about: `{ scoring: { mfccSigma: 6 } }`.
 * Arrays (e.g. feelCurve) are treated as leaves: pass the whole array.
 */
export type DeepPartial<T> = {
  [K in keyof T]?: T[K] extends readonly unknown[]
    ? T[K]
    : T[K] extends object
      ? DeepPartial<T[K]>
      : T[K];
};

/**
 * Deep-merge one or more partial overrides into the defaults.
 * Arrays (e.g. feelCurve) and primitives are replaced, nested objects merge.
 */
export function resolveOptions(
  ...partials: Array<DeepPartial<ScorerOptions> | undefined>
): ScorerOptions {
  const merged = structuredClone(DEFAULT_OPTIONS) as ScorerOptions;
  for (const partial of partials) {
    if (!partial) continue;
    mergeInto(
      merged as unknown as Record<string, unknown>,
      partial as unknown as Record<string, unknown>,
    );
  }
  return merged;
}

function mergeInto(target: Record<string, unknown>, source: Record<string, unknown>) {
  for (const [key, value] of Object.entries(source)) {
    if (value === undefined) continue;
    if (isPlainObject(value) && isPlainObject(target[key])) {
      mergeInto(target[key] as Record<string, unknown>, value);
    } else {
      target[key] = value;
    }
  }
}