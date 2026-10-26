/**
 * core.ts — the judgment engine: four axes → one 0–100 "how good a mimic"
 * score.
 *
 * Given the features of the TARGET clip and the PLAYER attempt, it:
 *   1. Classifies the target: tonal (melody), speech, or noise. Each kind
 *      weighs the four axes differently (see options.weights).
 *   2. Scores each axis 0..1:
 *        pitch  — "same melody?" → cents contour + DTW alignment + shape
 *                 agreement (rank correlation of the aligned contour).
 *        mfcc   — "same timbre?" → DTW across MFCC frames → Gaussian.
 *        energy — "same loud/quiet shape?" → dB-normalized correlation.
 *        timing — "same pauses/bursts?" → IoU of voiced masks + duration.
 *   3. Mixes the axes by weight (missing axes renormalize; a failed axis
 *      keeps its weight so nobody is rewarded for skipping it).
 *   4. Applies "game feel": a monotone penalty, a length multiplier, a burst
 *      multiplier for percussive sounds, a weakest-link cap, then a piecewise
 *      curve mapping raw 0..1 onto the 0..100 the player sees.
 *
 * A perfect copy returns exactly 100. Silence returns 0.
 *
 * This is a pure function of numbers — no I/O, no async. Everything below
 * is transportable: same math, same op order → same results as the original
 * Dart engine (verified by the parity tests).
 */

import type { ScorerOptions, DeepPartial } from './options.js';
import { resolveOptions } from './options.js';

export type Kind = 'tonal' | 'speech' | 'noise';

export interface ScoreVerdict {
  /** The final 0..100 score. */
  total: number;
  /** 0..100 — how well the melody matched (pitch axis only). */
  melody: number;
  /** 0..100 — how well loud/quiet + pauses matched. */
  rhythm: number;
  /** false for pure noise clips (claps, laughs). */
  pitched: boolean;
  /** What the target was: 'tonal' | 'speech' | 'noise' | '' (nothing graded). */
  kind: string;
  /** Per-axis grades 0..100. −1 = the axis carried no weight (or no data). */
  pitch: number;
  timbre: number;
  energy: number;
  timing: number;
}

export interface JudgeFeatures {
  targetEnergy?: number[];
  playerEnergy?: number[];
  targetMfcc?: number[][];
  playerMfcc?: number[][];
}

export interface JudgeResult {
  kind: Kind;
  verdict: ScoreVerdict;
  sPitch?: number;
  sMfcc?: number;
  sEnergy?: number;
  sTiming?: number;
  staticMul: number;
  lengthMul: number;
  burstMul: number;
  weakestLink: boolean;
  silentGate: boolean;
  raw: number;
}

export const ZERO_VERDICT: ScoreVerdict = {
  total: 0,
  melody: 0,
  rhythm: 0,
  pitched: false,
  kind: '',
  pitch: -1,
  timbre: -1,
  energy: -1,
  timing: -1,
};

/** Zero total, but the clip class is still known (Dart: `zeroKinded`). */
function zeroKinded(kind: Kind): ScoreVerdict {
  return {
    total: 0,
    melody: 0,
    rhythm: 0,
    pitched: kind !== 'noise',
    kind,
    pitch: -1,
    timbre: -1,
    energy: -1,
    timing: -1,
  };
}

/** Sentinel for "this frame is silence" inside cent contours. */
const GAP = -1e6;

const clamp = (v: number, lo: number, hi: number) => Math.max(lo, Math.min(hi, v));
const clamp01 = (v: number) => clamp(v, 0, 1);

// --------------------------------------------------------------------------
// Small numeric helpers
// --------------------------------------------------------------------------

function peakOf(e: number[] | undefined): number {
  if (!e || e.length === 0) return 0;
  let p = 0;
  for (const v of e) if (v > p) p = v;
  return p;
}

function voicedCount(pitch: number[]): number {
  let n = 0;
  for (const f of pitch) if (f > 0) n++;
  return n;
}

function voicedRatio(pitch: number[]): number {
  if (pitch.length === 0) return 0;
  return voicedCount(pitch) / pitch.length;
}

function median(values: number[]): number {
  const s = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  if (s.length % 2 === 1) return s[mid]!;
  return (s[mid - 1]! + s[mid]!) / 2;
}

function trimSilence(pitch: number[]): number[] {
  let start = 0;
  let end = pitch.length;
  while (start < end && pitch[start]! <= 0) start++;
  while (end > start && pitch[end - 1]! <= 0) end--;
  return pitch.slice(start, end);
}

function trimEnds(env: number[], floor = 0.08): number[] {
  let start = 0;
  let end = env.length;
  while (start < end && env[start]! < floor) start++;
  while (end > start && env[end - 1]! < floor) end--;
  if (start >= end) return env;
  return env.slice(start, end);
}

/** Hz → cents, silence stays the GAP sentinel; then normalize to the median. */
function centered(hz: number[], floor: number): number[] {
  if (hz.length === 0) return [];
  const cents: number[] = [];
  let prev: number | undefined;
  for (const f of hz) {
    if (f <= 0) {
      cents.push(GAP);
      continue;
    }
    let s = 1200.0 * (Math.log(f / 440.0) / Math.LN2);
    if (prev !== undefined) {
      const delta = s - prev;
      // Only a near-octave jump is a detector slip; real leaps stay.
      if (Math.abs(delta) > 1050 && Math.abs(delta) < 1350) {
        s -= 1200.0 * Math.sign(delta);
      }
    }
    cents.push(s);
    prev = s;
  }
  const voiced = cents.filter((c) => c > floor);
  if (voiced.length === 0) return cents;
  const mid = median(voiced);
  return cents.map((c) => (c > floor ? c - mid : GAP));
}

/** Fraction of adjacent voiced frames jumping > an octave (detector teleport). */
function octaveSlipRate(hz: number[], o: ScorerOptions): number {
  const c = centered(trimSilence(hz), o.scoring.voicedFloor);
  const v = c.filter((x) => x > o.scoring.voicedFloor);
  if (v.length < 3) return 0;
  let slips = 0;
  for (let i = 1; i < v.length; i++) {
    if (Math.abs(v[i]! - v[i - 1]!) > 1050) slips++;
  }
  return slips / (v.length - 1);
}

/** Median adjacent voiced jump, cents. Low on real song/speech, high on noise. */
function medianJumpCents(hz: number[], o: ScorerOptions): number {
  const c = centered(trimSilence(hz), o.scoring.voicedFloor);
  const v = c.filter((x) => x > o.scoring.voicedFloor);
  if (v.length < 3) return 0;
  const jumps: number[] = [];
  for (let i = 1; i < v.length; i++) jumps.push(Math.abs(v[i]! - v[i - 1]!));
  jumps.sort((a, b) => a - b);
  const mid = Math.floor(jumps.length / 2);
  return jumps.length % 2 === 1 ? jumps[mid]! : (jumps[mid - 1]! + jumps[mid]!) / 2;
}

// --------------------------------------------------------------------------
// Gates
// --------------------------------------------------------------------------

/** An envelope flatter than this is a constant hum, not a performance. */
function isFlatLine(energy: number[], flatRatio: number): boolean {
  if (energy.length < 8) return false;
  const sorted = energy.slice().sort((a, b) => a - b);
  const lo = sorted[clamp(Math.floor(sorted.length * 0.05), 0, sorted.length - 1)]!;
  const hi = sorted[clamp(Math.floor(sorted.length * 0.9), 0, sorted.length - 1)]!;
  return hi < lo * flatRatio + 1e-4;
}

/** True when raw mic audio is room tone: too quiet, or flat like a hum. */
export function isRoomTone(energy: number[], options?: DeepPartial<ScorerOptions>): boolean {
  const o = resolveOptions(options);
  if (energy.length === 0) return true;
  if (peakOf(energy) < o.gates.roomTonePeak) return true;
  return isFlatLine(energy, o.gates.flatRatio);
}

/**
 * Same voiced test used to decide "was this a real attempt".
 * Keep both tests consistent so a burst is never graded as speech.
 */
export function looksPitched(pitch: number[], options?: DeepPartial<ScorerOptions>): boolean {
  void options; // kept for API symmetry; current logic is unconditional
  return voicedRatio(pitch) >= 0.3 && voicedCount(pitch) >= 4;
}

// --------------------------------------------------------------------------
// Axis 1: pitch
// --------------------------------------------------------------------------

function pitchScore(targetHz: number[], playerHz: number[], kind: Kind, o: ScorerOptions): number {
  const f = o.scoring.voicedFloor;
  const tc = centered(trimSilence(targetHz), f);
  const pc = centered(trimSilence(playerHz), f);
  if (tc.length === 0 || pc.length === 0) return 0;
  const pairs = align(tc, pc, (a, b) => pitchCost(a, b, o), o);
  if (pairs.length === 0) return 0;

  const band = kind === 'tonal' ? o.scoring.tonalError : o.scoring.speechError;
  let sum = 0;
  let n = 0;
  let voiced = 0;
  let overlap = 0;
  for (const pair of pairs) {
    const av = pair[0] > f;
    const bv = pair[1] > f;
    if (!av) continue;
    n++;
    voiced++;
    if (!bv) continue;
    overlap++;
    const oct = octErr(pair[0], pair[1]);
    let s = 0;
    if (oct.err <= band.tol) {
      s = 1;
    } else if (oct.err < band.max) {
      s = Math.pow((band.max - oct.err) / (band.max - band.tol), 1.5);
    }
    if (oct.folded) s *= o.scoring.foldedPenalty;
    sum += s;
  }
  if (n === 0 || voiced === 0) return 0;

  // Frame tolerance alone lets a different shape score high by matching a few
  // nearby notes. The contour SHAPE must also agree — rank correlation along
  // the DTW path (warp-tolerant), not on resampled vectors.
  const frames = (sum / n) * (overlap / voiced);
  const ax: number[] = [];
  const bx: number[] = [];
  for (const pair of pairs) {
    if (pair[0] > f && pair[1] > f) {
      ax.push(pair[0]);
      bx.push(pair[1]);
    }
  }
  return clamp01(frames * pathAgreement(ax, bx, o));
}

/** 1 when both contours are flat or rise/fall together; 0 when they oppose. */
function pathAgreement(a: number[], b: number[], o: ScorerOptions): number {
  if (a.length < 3 || b.length < 3) return 1;
  const aStd = voicedStd(a, o);
  const bStd = voicedStd(b, o);
  if (aStd < 80 && bStd < 80) return 1;
  if (aStd < 80 || bStd < 80) return 0;
  const corr = pearson(ranks(a), ranks(b));
  if (corr === null) return 1;
  return Math.max(0, corr);
}

/** Variance over voiced frames only (silence is a sentinel, not data). */
function voicedVariance(v: number[], o: ScorerOptions): number {
  let n = 0;
  let mean = 0;
  for (const x of v) {
    if (x < o.scoring.voicedFloor) continue;
    n++;
    mean += x;
  }
  if (n < 2) return 0;
  mean /= n;
  let s = 0;
  for (const x of v) {
    if (x < o.scoring.voicedFloor) continue;
    s += (x - mean) * (x - mean);
  }
  return s / n;
}

function voicedStd(v: number[], o: ScorerOptions): number {
  const variance = voicedVariance(v, o);
  return variance <= 0 ? 0 : Math.sqrt(variance);
}

/** Fractional ranks with averaged ties (Spearman preparation). */
function ranks(v: number[]): number[] {
  const order = v.map((_, i) => i).sort((i, j) => v[i]! - v[j]!);
  const out = new Array<number>(v.length).fill(0);
  let i = 0;
  while (i < order.length) {
    let j = i;
    while (j + 1 < order.length && v[order[j + 1]!] === v[order[i]!]) j++;
    const avg = (i + j) / 2;
    for (let k = i; k <= j; k++) out[order[k]!] = avg;
    i = j + 1;
  }
  return out;
}

/** Pearson correlation of two equal-ish lists, or null when degenerate. */
function pearson(x: number[], y: number[]): number | null {
  const n = Math.min(x.length, y.length);
  if (n < 3) return null;
  let mx = 0;
  let my = 0;
  for (let i = 0; i < n; i++) {
    mx += x[i]!;
    my += y[i]!;
  }
  mx /= n;
  my /= n;
  let num = 0;
  let vx = 0;
  let vy = 0;
  for (let i = 0; i < n; i++) {
    const dx = x[i]! - mx;
    const dy = y[i]! - my;
    num += dx * dy;
    vx += dx * dx;
    vy += dy * dy;
  }
  if (vx < 1e-8 || vy < 1e-8) return null;
  return clamp(num / Math.sqrt(vx * vy), -1, 1);
}

/** Cents difference, allowing an octave fold (down/up by 1200 cents). */
function octErr(a: number, b: number): { err: number; folded: boolean } {
  const d = Math.abs(a - b);
  const down = Math.abs(a - b - 1200);
  const up = Math.abs(a - b + 1200);
  if (down < d && down <= up) return { err: down, folded: true };
  if (up < d && up < down) return { err: up, folded: true };
  return { err: d, folded: false };
}

/** DTW cost of pairing one frame with another (pitch axis). */
function pitchCost(a: number, b: number, o: ScorerOptions): number {
  const f = o.scoring.voicedFloor;
  const av = a > f;
  const bv = b > f;
  if (!av && !bv) return 0;
  if (av !== bv) return o.scoring.voicedMismatchCost;
  return octErr(a, b).err;
}

// --------------------------------------------------------------------------
// DTW alignment (edit distance, but with continuous costs)
// --------------------------------------------------------------------------

type Pair = [number, number];

function align(
  a: number[],
  b: number[],
  costOf: (x: number, y: number) => number,
  o: ScorerOptions,
): Pair[] {
  const banded = alignBand(a, b, costOf, o);
  if (banded !== null) return banded;
  return alignFull(a, b, costOf);
}

/** Band-limited DTW (Sakoe–Chiba) — fast; null when no path fits in band. */
function alignBand(a: number[], b: number[], costOf: (x: number, y: number) => number, o: ScorerOptions): Pair[] | null {
  const n = a.length;
  const m = b.length;
  if (n === 0 || m === 0) return [];
  const longer = n > m ? n : m;
  const slack = Math.round(longer * o.scoring.dtwSlackAlign);
  const band = Math.abs(n - m) + (slack < 2 ? 2 : slack);
  const dtw: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(Infinity));
  const ptr: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  dtw[0]![0] = 0;
  for (let i = 1; i <= n; i++) {
    const j0 = Math.max(1, i - band);
    const j1 = Math.min(m, i + band);
    for (let j = j0; j <= j1; j++) {
      step(dtw, ptr, i, j, costOf(a[i - 1]!, b[j - 1]!));
    }
  }
  if (!Number.isFinite(dtw[n]![m])) return null;
  return backtrack(a, b, ptr);
}

/** Unconstrained DTW — always finds a path, slower. */
function alignFull(a: number[], b: number[], costOf: (x: number, y: number) => number): Pair[] {
  const n = a.length;
  const m = b.length;
  if (n === 0 || m === 0) return [];
  const dtw: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(Infinity));
  const ptr: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  dtw[0]![0] = 0;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      step(dtw, ptr, i, j, costOf(a[i - 1]!, b[j - 1]!));
    }
  }
  if (!Number.isFinite(dtw[n]![m])) return [];
  return backtrack(a, b, ptr);
}

/** One DP cell: best of diagonal / up / left, remembered in ptr (0/1/2). */
function step(dtw: number[][], ptr: number[][], i: number, j: number, cost: number): void {
  const diag = dtw[i - 1]![j - 1]!;
  const up = dtw[i - 1]![j]!;
  const left = dtw[i]![j - 1]!;
  let best = diag;
  let dir = 0;
  if (up < best) {
    best = up;
    dir = 1;
  }
  if (left < best) {
    best = left;
    dir = 2;
  }
  dtw[i]![j] = cost + best;
  ptr[i]![j] = dir;
}

/** Rebuild the aligned frame pairs from the pointer table. */
function backtrack(a: number[], b: number[], ptr: number[][]): Pair[] {
  const pairs: Pair[] = [];
  let i = a.length;
  let j = b.length;
  while (i > 0 && j > 0) {
    pairs.push([a[i - 1]!, b[j - 1]!]);
    const dir = ptr[i]![j]!;
    if (dir === 1) i--;
    else if (dir === 2) j--;
    else {
      i--;
      j--;
    }
  }
  return pairs.reverse();
}

// --------------------------------------------------------------------------
// Axis 2: timbre (MFCC)
// --------------------------------------------------------------------------

function vecCost(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  if (n === 0) return 1e9;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const d = a[i]! - b[i]!;
    sum += d * d;
  }
  return Math.sqrt(sum);
}

/** DTW distance between two sequences of MFCC frames. */
function dtwVec(a: number[][], b: number[][], o: ScorerOptions): number {
  const n = a.length;
  const m = b.length;
  if (n === 0 || m === 0) return 1e9;
  const longer = n > m ? n : m;
  const slack = Math.round(longer * o.scoring.dtwSlackVec);
  const band = Math.abs(n - m) + (slack < 2 ? 2 : slack);
  const dtw: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(Infinity));
  dtw[0]![0] = 0;
  for (let i = 1; i <= n; i++) {
    const j0 = Math.max(1, i - band);
    const j1 = Math.min(m, i + band);
    for (let j = j0; j <= j1; j++) {
      const up = dtw[i - 1]![j]!;
      const left = dtw[i]![j - 1]!;
      const diag = dtw[i - 1]![j - 1]!;
      const best = Math.min(up, left, diag);
      dtw[i]![j] = vecCost(a[i - 1]!, b[j - 1]!) + best;
    }
  }
  const v = dtw[n]![m]!;
  if (!Number.isFinite(v)) return dtwVecFull(a, b);
  return v;
}

function dtwVecFull(a: number[][], b: number[][]): number {
  const n = a.length;
  const m = b.length;
  const dtw: number[][] = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(Infinity));
  dtw[0]![0] = 0;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      const best = Math.min(dtw[i - 1]![j]!, dtw[i]![j - 1]!, dtw[i - 1]![j - 1]!);
      dtw[i]![j] = vecCost(a[i - 1]!, b[j - 1]!) + best;
    }
  }
  return dtw[n]![m]!;
}

/** Raw DTW cost per frame (before the Gaussian). Same voice sits well under sigma. */
function mfccErr(target: number[][] | undefined, player: number[][] | undefined, o: ScorerOptions): number {
  if (!target || !player || target.length === 0 || player.length === 0) return -1;
  const t = dropC0(trimVecEnds(target));
  const p = dropC0(trimVecEnds(player));
  if (t.length === 0 || p.length === 0) return -1;
  const err = dtwVec(t, p, o) / Math.max(t.length, p.length);
  if (Number.isNaN(err) || !Number.isFinite(err)) return -1;
  return err;
}

function mfccScore(target: number[][], player: number[][], o: ScorerOptions): number {
  const t = dropC0(trimVecEnds(target));
  const p = dropC0(trimVecEnds(player));
  if (t.length === 0 || p.length === 0) return 0;
  if (t[0]!.length === 0 || p[0]!.length === 0) return 0;
  const err = dtwVec(t, p, o) / Math.max(t.length, p.length);
  if (Number.isNaN(err) || !Number.isFinite(err)) return 0;
  const s = o.scoring.mfccSigma;
  return clamp01(Math.exp((-err * err) / (2 * s * s)));
}

/** Drop coefficient C0 (the energy-like one) — pure timbre comparison. */
function dropC0(frames: number[][]): number[][] {
  return frames.map((f) => (f.length > 1 ? f.slice(1) : f.slice()));
}

/** Drop leading/trailing all-silent (zero-vector) frames. */
function trimVecEnds(frames: number[][]): number[][] {
  let start = 0;
  let end = frames.length;
  const silent = (f: number[]) => f.every((v) => v === 0.0);
  while (start < end && silent(frames[start]!)) start++;
  while (end > start && silent(frames[end - 1]!)) end--;
  if (start >= end) return frames;
  return frames.slice(start, end);
}

// --------------------------------------------------------------------------
// Axes 3 & 4: energy shape + timing
// --------------------------------------------------------------------------

function centerDb(rms: number[]): number[] {
  if (rms.length === 0) return [];
  const db = rms.map((v) => 20.0 * (Math.log(Math.max(v, 1e-8)) / Math.LN10));
  const mid = median(db);
  return db.map((v) => v - mid);
}

function trimRelative(rms: number[], o: ScorerOptions): number[] {
  if (rms.length === 0) return rms;
  const peak = peakOf(rms);
  if (peak < o.gates.silencePeak) return [];
  return trimEnds(rms, peak * 0.08);
}

function mad(x: number[], y: number[]): number {
  const n = Math.min(x.length, y.length);
  if (n === 0) return 99;
  let s = 0;
  for (let i = 0; i < n; i++) s += Math.abs(x[i]! - y[i]!);
  return s / n;
}

/** dB span between the 10th and 90th percentiles (dynamic-range proxy). */
function span(v: number[]): number {
  if (v.length < 2) return 0;
  const s = v.slice().sort((a, b) => a - b);
  const lo = s[clamp(Math.floor(s.length * 0.1), 0, s.length - 1)]!;
  const hi = s[clamp(Math.floor(s.length * 0.9), 0, s.length - 1)]!;
  return hi - lo;
}

function resample(v: number[], n: number): number[] {
  if (v.length === 0 || n <= 0) return [];
  if (v.length === n) return v;
  if (n === 1) return [v[0]!];
  const out = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    const x = (i * (v.length - 1)) / (n - 1);
    const j = Math.floor(x);
    const t = x - j;
    const a = v[j]!;
    const b = v[Math.min(j + 1, v.length - 1)]!;
    out[i] = a + t * (b - a);
  }
  return out;
}

function mask(energy: number[], o: ScorerOptions): boolean[] {
  const peak = peakOf(energy);
  if (peak <= 0) return new Array(energy.length).fill(false);
  const floor = peak * o.multipliers.burst.floorRatio;
  return energy.map((v) => v >= floor);
}

function maskLoose(energy: number[], o: ScorerOptions): boolean[] {
  const peak = peakOf(energy);
  if (peak <= 0) return new Array(energy.length).fill(false);
  const floor = peak * o.multipliers.burst.looseFloorRatio;
  return energy.map((v) => v >= floor);
}

function activeCount(mask: boolean[]): number {
  return mask.filter(Boolean).length;
}

/** Loose floor on purpose: only catches "way too much / way too little". */
function activeRatio(target: number[], player: number[], o: ScorerOptions): number {
  const ta = activeCount(maskLoose(target, o));
  const pa = activeCount(maskLoose(player, o));
  if (ta === 0) return pa === 0 ? 1 : 0;
  return pa / ta;
}

function resampleBool(v: boolean[], n: number): boolean[] {
  if (v.length === 0 || n <= 0) return [];
  if (v.length === n) return v;
  const out = new Array<boolean>(n);
  for (let i = 0; i < n; i++) out[i] = v[clamp(Math.floor((i * v.length) / n), 0, v.length - 1)]!;
  return out;
}

function dilate(mask: boolean[], radius: number): boolean[] {
  const out = mask.slice();
  for (let i = 0; i < mask.length; i++) {
    if (!mask[i]) continue;
    const a = Math.max(0, i - radius);
    const b = Math.min(mask.length - 1, i + radius);
    for (let k = a; k <= b; k++) out[k] = true;
  }
  return out;
}

/** Intersection-over-union of two voiced masks (with a 2-frame tolerance). */
function iou(a: boolean[], b: boolean[]): number {
  const n = Math.max(a.length, b.length);
  if (n === 0) return 1;
  const aa = dilate(resampleBool(a, n), 2);
  const bb = dilate(resampleBool(b, n), 2);
  let inter = 0;
  let union = 0;
  for (let i = 0; i < n; i++) {
    if (aa[i] || bb[i]) union++;
    if (aa[i] && bb[i]) inter++;
  }
  if (union === 0) return 1;
  return inter / union;
}

/** 0..1: do both envelopes have a similar number of loud bursts? */
function burstSimilarity(a: number[], b: number[], o: ScorerOptions): number {
  const bursts = (env: number[]) => {
    const peak = peakOf(env);
    if (peak <= 0) return 0;
    const floor = peak * o.multipliers.burst.floorRatio;
    let count = 0;
    let inside = false;
    for (const v of env) {
      if (v >= floor) {
        if (!inside) {
          inside = true;
          count++;
        }
      } else {
        inside = false;
      }
    }
    return count;
  };
  const x = bursts(a);
  const y = bursts(b);
  if (x === 0 && y === 0) return 1;
  const hi = Math.max(x, y);
  if (hi === 0) return 1;
  return Math.min(x, y) / hi;
}

// --------------------------------------------------------------------------
// Multipliers (game feel)
// --------------------------------------------------------------------------

/** Penalize singing one flat tone while the target actually moves. */
function staticMulValue(targetHz: number[], playerHz: number[], o: ScorerOptions): number {
  const t = centered(trimSilence(targetHz), o.scoring.voicedFloor);
  const p = centered(trimSilence(playerHz), o.scoring.voicedFloor);
  if (t.length === 0 || p.length === 0) return 1;
  const tStd = voicedStd(t, o);
  if (tStd <= o.multipliers.staticMonotone.monotoneHz) return 1;
  const r = voicedStd(p, o) / tStd;
  const m = o.multipliers.staticMonotone;
  if (r <= m.voicedBelow) return m.voicedMul;
  if (r >= m.voicedHigh) return 1;
  return m.voicedMul + (1 - m.voicedMul) * ((r - m.voicedBelow) / (m.voicedHigh - m.voicedBelow));
}

/** 1 when durations match; down to floor when absurdly short/long. */
function lengthValue(ratio: number, o: ScorerOptions): number {
  const l = o.multipliers.length;
  if (ratio >= l.centerLow && ratio <= l.centerHigh) return 1;
  if (ratio >= l.lowEdge && ratio < l.centerLow) {
    return l.upFloor + l.upRamp * ((ratio - l.lowEdge) / (l.centerLow - l.lowEdge));
  }
  if (ratio > l.centerHigh && ratio <= l.highEdge) {
    return 1 - l.downRamp * ((ratio - l.centerHigh) / (l.highEdge - l.centerHigh));
  }
  return l.floor;
}

/** Any important axis scoring terribly caps the total. */
function weakestLink(
  wp: number,
  sPitch: number | undefined,
  wm: number,
  sMfcc: number | undefined,
  we: number,
  sEnergy: number | undefined,
  wt: number,
  sTiming: number | undefined,
  o: ScorerOptions,
): boolean {
  const bad = (w: number, s: number | undefined) =>
    w >= o.scoring.weakestLink.weightMin && s !== undefined && s < o.scoring.weakestLink.scoreBelow;
  return bad(wp, sPitch) || bad(wm, sMfcc) || bad(we, sEnergy) || bad(wt, sTiming);
}

/** Piecewise "game feel" curve: raw 0..1 → player-visible 0..100. */
function feel(raw: number, o: ScorerOptions): number {
  if (Number.isNaN(raw) || !Number.isFinite(raw) || raw <= 0) return 0;
  const x = raw > 1 ? 1 : raw;
  const pts = o.scoring.feelCurve;
  for (let i = 1; i < pts.length; i++) {
    const x1 = pts[i]![0];
    if (x <= x1) {
      const x0 = pts[i - 1]![0];
      const y0 = pts[i - 1]![1];
      const y1 = pts[i]![1];
      const span = x1 - x0;
      const t = span === 0 ? 0 : (x - x0) / span;
      return y0 + t * (y1 - y0);
    }
  }
  return 100;
}

// --------------------------------------------------------------------------
// Composition
// --------------------------------------------------------------------------

export function classify(pitch: number[]): Kind {
  const r = voicedRatio(pitch);
  const n = voicedCount(pitch);
  if (r >= 0.6 && n >= 4) return 'tonal';
  if (r < 0.3 || n < 4) return 'noise';
  return 'speech';
}

function isSilent(pitch: number[], energy: number[] | undefined, o: ScorerOptions): boolean {
  if (energy && energy.length > 0) {
    if (peakOf(energy) < o.gates.silencePeak) return true;
    if (isFlatLine(energy, o.gates.flatRatio)) return true;
    return false;
  }
  if (pitch.length === 0) return true;
  return voicedRatio(pitch) < 0.3;
}

function energyScore(targetRaw: number[], playerRaw: number[], o: ScorerOptions): number {
  const t = centerDb(trimRelative(targetRaw, o));
  const p = centerDb(trimRelative(playerRaw, o));
  if (t.length === 0 || p.length === 0) return 0;
  const n = Math.max(t.length, p.length);
  const ta = resample(t, n);
  const pa = resample(p, n);
  const corr = pearson(ta, pa);
  const madTerm = Math.exp(-(mad(ta, pa) / o.energyAxis.madDivisor));
  const base =
    corr === null ? madTerm : o.energyAxis.corrWeight * Math.max(0, corr) + (1 - o.energyAxis.corrWeight) * madTerm;
  const ra = span(ta);
  const rb = span(pa);
  const rangeSim = ra + rb < 1e-6 ? 1.0 : Math.min(ra, rb) / Math.max(ra, rb);
  return clamp01(o.energyAxis.baseWeight * base + o.energyAxis.rangeWeight * rangeSim);
}

function timingScore(targetRaw: number[], playerRaw: number[], o: ScorerOptions): number {
  const iouVal = iou(mask(targetRaw, o), mask(playerRaw, o));
  const dur = lengthValue(activeRatio(targetRaw, playerRaw, o), o);
  const bursts = burstSimilarity(targetRaw, playerRaw, o);
  const t = o.timingAxis;
  return clamp01(t.iouWeight * iouVal + t.durWeight * dur + t.burstWeight * bursts);
}

// --------------------------------------------------------------------------
// Public scoring entry points
// --------------------------------------------------------------------------

/**
 * Score two clips from their raw F0 contours (0 = unvoiced frame).
 * Optional energy + MFCC features make the timbre/rhythm axes available.
 */
export function judge(
  targetPitch: number[],
  playerPitch: number[],
  features?: JudgeFeatures,
  options?: DeepPartial<ScorerOptions>,
): ScoreVerdict {
  return judgeInternal(targetPitch, playerPitch, features ?? {}, resolveOptions(options)).verdict;
}

/**
 * Same pipeline with every intermediate exposed — the numbers behind a
 * verdict, ready for a debug screen. Keys match the Dart analyser.
 */
export function diagnose(
  targetPitch: number[],
  playerPitch: number[],
  features?: JudgeFeatures,
  options?: DeepPartial<ScorerOptions>,
): Record<string, number | string | boolean> {
  const o = resolveOptions(options);
  const r = judgeInternal(targetPitch, playerPitch, features ?? {}, o);
  const tE = features?.targetEnergy;
  const pE = features?.playerEnergy;
  const hasBothEnergy =
    tE !== undefined && pE !== undefined && tE.length > 0 && pE.length > 0;
  return {
    kind: r.kind,
    targetVoicedRatio: voicedRatio(targetPitch),
    targetVoicedCount: voicedCount(targetPitch),
    playerVoicedRatio: voicedRatio(playerPitch),
    playerVoicedCount: voicedCount(playerPitch),
    trimmedPlayerVoicedRatio: voicedRatio(trimSilence(playerPitch)),
    targetOctaveSlipRate: octaveSlipRate(targetPitch, o),
    targetMedianJumpCents: medianJumpCents(targetPitch, o),
    activeRatio: hasBothEnergy ? activeRatio(tE, pE, o) : -1,
    targetPeak: peakOf(tE),
    playerPeak: peakOf(pE),
    sPitch: r.sPitch ?? -1,
    sMfcc: r.sMfcc ?? -1,
    sEnergy: r.sEnergy ?? -1,
    sTiming: r.sTiming ?? -1,
    mfccErr: mfccErr(features?.targetMfcc, features?.playerMfcc, o),
    staticMul: r.staticMul,
    lengthMul: r.lengthMul,
    burstMul: r.burstMul,
    weakestLink: r.weakestLink,
    silentGate: r.silentGate,
    rawPreFeel: r.raw,
    total: r.verdict.total,
    melody: r.verdict.melody,
    rhythm: r.verdict.rhythm,
    pitched: r.verdict.pitched,
  };
}

function judgeInternal(
  targetPitch: number[],
  playerPitch: number[],
  features: JudgeFeatures,
  o: ScorerOptions,
): JudgeResult {
  if (isSilent(playerPitch, features.playerEnergy, o)) {
    return {
      kind: classify(targetPitch),
      verdict: zeroKinded(classify(targetPitch)),
      silentGate: true,
      staticMul: 1,
      lengthMul: 1,
      burstMul: 1,
      weakestLink: false,
      raw: 0,
    };
  }

  const kind = classify(targetPitch);
  const w = o.weights[kind];
  const reliable = octaveSlipRate(targetPitch, o) < o.scoring.octaveSlipLimit;

  let sPitch: number | undefined;
  if (w.pitch > 0 && reliable) {
    if (voicedCount(targetPitch) >= o.scoring.minVoiced) {
      sPitch =
        voicedRatio(trimSilence(playerPitch)) >= o.scoring.pitchGateVoiced
          ? pitchScore(targetPitch, playerPitch, kind, o)
          : 0.0;
    }
  }

  let sMfcc: number | undefined;
  const hasMfcc =
    features.targetMfcc !== undefined &&
    features.playerMfcc !== undefined &&
    features.targetMfcc.length > 0 &&
    features.playerMfcc.length > 0;
  if (hasMfcc) sMfcc = mfccScore(features.targetMfcc!, features.playerMfcc!, o);

  let sEnergy: number | undefined;
  let sTiming: number | undefined;
  let lengthMul = 1;
  let burstMul = 1;
  const hasEnergy =
    features.targetEnergy !== undefined &&
    features.playerEnergy !== undefined &&
    features.targetEnergy.length > 0 &&
    features.playerEnergy.length > 0;
  if (hasEnergy) {
    sEnergy = energyScore(features.targetEnergy!, features.playerEnergy!, o);
    sTiming = timingScore(features.targetEnergy!, features.playerEnergy!, o);
    lengthMul = lengthValue(activeRatio(features.targetEnergy!, features.playerEnergy!, o), o);
    if (kind === 'noise') {
      const b = o.multipliers.burst;
      burstMul = b.noiseMix + (1 - b.noiseMix) * burstSimilarity(features.targetEnergy!, features.playerEnergy!, o);
    }
  }

  // Missing axes drop out; present axes renormalize. A failed axis keeps its
  // weight (0 contribution) so nobody can skip an axis for free.
  let wp = sPitch === undefined ? 0 : w.pitch;
  let wm = sMfcc === undefined ? 0 : w.mfcc;
  let we = sEnergy === undefined ? 0 : w.energy;
  let wt = sTiming === undefined ? 0 : w.timing;
  const sumW = wp + wm + we + wt;
  if (sumW <= 0) {
    return {
      kind,
      verdict: zeroKinded(kind),
      silentGate: false,
      staticMul: 1,
      lengthMul: 1,
      burstMul: 1,
      weakestLink: false,
      raw: 0,
    };
  }
  wp /= sumW;
  wm /= sumW;
  we /= sumW;
  wt /= sumW;

  const used = [sPitch, sMfcc, sEnergy, sTiming].filter((s): s is number => s !== undefined);
  let raw = wp * (sPitch ?? 0) + wm * (sMfcc ?? 0) + we * (sEnergy ?? 0) + wt * (sTiming ?? 0);

  const staticMul = reliable ? staticMulValue(targetPitch, playerPitch, o) : 1;
  raw *= staticMul;
  raw *= lengthMul;
  raw *= burstMul;
  const weak = weakestLink(wp, sPitch, wm, sMfcc, we, sEnergy, wt, sTiming, o);
  if (weak) raw = Math.min(raw, o.scoring.weakestLink.cap);
  if (Number.isNaN(raw) || !Number.isFinite(raw)) raw = 0;

  const perfect = used.length > 0 && used.every((s) => s >= o.scoring.perfectThreshold);
  const total = perfect ? 100 : feel(raw, o);

  const rhythmDen = (sEnergy === undefined ? 0 : we) + (sTiming === undefined ? 0 : wt);
  const rhythm =
    rhythmDen <= 0
      ? 0
      : (100 *
          (((sEnergy === undefined ? 0 : we) * (sEnergy ?? 0)) +
            ((sTiming === undefined ? 0 : wt) * (sTiming ?? 0)))) /
        rhythmDen;

  const verdict: ScoreVerdict = {
    total: clamp(Math.round(total), 0, 100),
    melody: clamp(Math.round((sPitch ?? 0) * 100), 0, 100),
    rhythm: clamp(Math.round(rhythm), 0, 100),
    pitched: kind !== 'noise',
    kind,
    pitch: sPitch === undefined ? -1 : clamp(Math.round(sPitch * 100), 0, 100),
    timbre: sMfcc === undefined ? -1 : clamp(Math.round(sMfcc * 100), 0, 100),
    energy: sEnergy === undefined ? -1 : clamp(Math.round(sEnergy * 100), 0, 100),
    timing: sTiming === undefined ? -1 : clamp(Math.round(sTiming * 100), 0, 100),
  };

  return {
    kind,
    verdict,
    sPitch,
    sMfcc,
    sEnergy,
    sTiming,
    staticMul,
    lengthMul,
    burstMul,
    weakestLink: weak,
    silentGate: false,
    raw,
  };
}