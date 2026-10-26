/**
 * pitch.ts — "how high is the voice right now?", answered 20 times per
 * second (a 50 ms window each time).
 *
 * The method is called YIN and it is built on **autocorrelation**: a signal
 * is compared against a shifted copy of itself. If the shift (delay) matches
 * one full wave of the pitch, the two align and the difference is tiny.
 *
 * Concrete steps, exactly as implemented:
 *   1. Take a 50 ms window of samples.
 *   2. If the window is quiet (RMS < silenceRmsThreshold) → unvoiced (0).
 *   3. For every delay tau, compute the squared difference between sample i
 *      and sample i+tau, summed over the window → "difference function" d(tau).
 *   4. Normalize it cumulatively (CMND) so early delays don't look too good.
 *   5. The pitch delay is the first dip below the threshold, refined to a
 *      local minimum, then sub-sample precision via parabolic interpolation.
 *   6. Frequency = sampleRate / delay. Done.
 *
 * Every 50 ms window produces one number. The whole clip becomes a list of
 * numbers — that list is the "pitch contour" the scorer compares.
 */

import type { ScorerOptions } from './options.js';
import type { Pcm } from './pcm.js';

/** RMS (root-mean-square) energy per 50 ms window. Unnormalized. */
export function energyEnvelope(mono: Pcm, sampleRate: number, options: ScorerOptions): number[] {
  const windowSamples = Math.round((sampleRate * options.pitch.windowMs) / 1000);
  if (windowSamples <= 0) return [];
  const out: number[] = [];
  for (let start = 0; start < mono.length; start += windowSamples) {
    const end = Math.min(start + windowSamples, mono.length);
    let sumSq = 0;
    for (let i = start; i < end; i++) {
      const s = mono[i]!;
      sumSq += s * s;
    }
    out.push(Math.sqrt(sumSq / (end - start)));
  }
  return out;
}

/** Pitch (F0) in Hz every 50 ms. 0 = unvoiced window. */
export function extractPitch(mono: Pcm, sampleRate: number, options: ScorerOptions): number[] {
  const windowSamples = Math.round((sampleRate * options.pitch.windowMs) / 1000);
  if (windowSamples <= 0) return [];
  const raw: number[] = [];
  for (let start = 0; start < mono.length; start += windowSamples) {
    const end = Math.min(start + windowSamples, mono.length);
    const window = windowFrom(mono, start, end);
    raw.push(yin(window, sampleRate, options));
  }
  return median3(raw);
}

function windowFrom(mono: Pcm, start: number, end: number): number[] {
  const win = new Array<number>(end - start);
  for (let i = start; i < end; i++) win[i - start] = mono[i]!;
  return win;
}

/**
 * YIN fundamental-frequency estimate for one window.
 * Returns 0.0 when the window is unvoiced or unmeasurable.
 */
export function yin(window: number[], sampleRate: number, options: ScorerOptions): number {
  const n = window.length;
  if (n < 64) return 0;

  let sumSq = 0;
  for (const s of window) sumSq += s * s;
  if (Math.sqrt(sumSq / n) < options.pitch.silenceRmsThreshold) return 0;

  const maxLag = Math.min(n - 2, Math.round(sampleRate / options.pitch.minFreq));
  const minLag = Math.max(2, Math.round(sampleRate / options.pitch.maxFreq));
  if (maxLag <= minLag) return 0;

  // Step 1–2: difference function + cumulative mean normalized difference.
  const cmnd = new Array<number>(maxLag + 1).fill(1.0);
  let runningSum = 0;
  for (let tau = 1; tau <= maxLag; tau++) {
    let d = 0;
    for (let j = 0; j < n - tau; j++) {
      const diff = window[j]! - window[j + tau]!;
      d += diff * diff;
    }
    runningSum += d;
    cmnd[tau] = runningSum === 0 ? 1.0 : (d * tau) / runningSum;
  }

  // Step 3: first dip below threshold, then its local minimum.
  // Fallback: the global minimum — a noisy-but-voiced frame keeps a pitch.
  let tau = -1;
  for (let t = minLag; t <= maxLag; t++) {
    if (cmnd[t]! < options.pitch.yinThreshold) {
      while (t + 1 <= maxLag && cmnd[t + 1]! < cmnd[t]!) t++;
      tau = t;
      break;
    }
  }
  if (tau < 0) {
    let best = minLag;
    for (let t = minLag + 1; t <= maxLag; t++) {
      if (cmnd[t]! < cmnd[best]!) best = t;
    }
    tau = best;
  }

  // Step 4: parabolic interpolation for sub-sample accuracy.
  let period = tau;
  if (tau > 0 && tau < maxLag) {
    const s0 = cmnd[tau - 1]!;
    const s1 = cmnd[tau]!;
    const s2 = cmnd[tau + 1]!;
    const denom = s0 + s2 - 2 * s1;
    if (denom !== 0) {
      period = tau + (s0 - s2) / (2 * denom);
    }
  }
  if (period < 1) return 0;
  const freq = sampleRate / period;
  if (freq < options.pitch.minFreq || freq > options.pitch.maxFreq) return 0;
  return freq;
}

/** 3-point median smoothing: replaces each value with the median of (i-1, i, i+1). */
export function median3(values: number[]): number[] {
  if (values.length < 3) return values;
  const out = values.slice();
  for (let i = 1; i < values.length - 1; i++) {
    const a = values[i - 1]!;
    const b = values[i]!;
    const c = values[i + 1]!;
    out[i] = a < b ? (b < c ? b : a < c ? c : a) : b > c ? b : a > c ? c : a;
  }
  return out;
}

/** Peak-normalized waveform buckets (0..1) for drawing sound waves. */
export function waveformBuckets(
  mono: Pcm,
  sampleRate: number,
  options: ScorerOptions,
  buckets = 64,
): number[] {
  if (mono.length === 0) return [];
  const perBucket = Math.ceil(mono.length / buckets);
  const rms = new Array<number>(buckets).fill(0);
  let peak = 0;
  for (let b = 0; b < buckets; b++) {
    const start = b * perBucket;
    if (start >= mono.length) break;
    const end = Math.min(start + perBucket, mono.length);
    let sumSq = 0;
    for (let i = start; i < end; i++) {
      const s = mono[i]!;
      sumSq += s * s;
    }
    rms[b] = Math.sqrt(sumSq / (end - start));
    if (rms[b] > peak) peak = rms[b];
  }
  if (peak <= 0) return rms.map(() => 0);
  return rms.map((v) => Math.max(0, Math.min(1, v / peak)));
}

/** Linear resample of samples to a target rate (used to normalize MFCC rates). */
export function resampleLinear(mono: Pcm, fromRate: number, toRate: number): number[] {
  if (fromRate === toRate || mono.length === 0) return Array.from(mono);
  const n = Math.round((mono.length * toRate) / fromRate);
  if (n < 1) return [];
  const out = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    const x = (i * (mono.length - 1)) / (n - 1);
    const j = Math.floor(x);
    const t = x - j;
    const a = mono[j]!;
    const b = mono[Math.min(j + 1, mono.length - 1)]!;
    out[i] = a + t * (b - a);
  }
  return out;
}