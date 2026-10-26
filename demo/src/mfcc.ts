/**
 * mfcc.ts — "what does the voice sound like, ignoring pitch level?".
 *
 * Pitch tells you the *melody*; timbre tells you the *sound* (a laugh vs a
 * word vs a clap). We measure timbre with MFCC — Mel-frequency Cepstral
 * Coefficients. The pipeline, one frame at a time (20 ms):
 *
 *   pre-emphasis  → emphasize highs (a bass cut, so the shape carries info)
 *   Hamming window → fade the edges of each frame (avoids edge "clicks")
 *   FFT            → turn time samples into a spectrum (loudness per frequency)
 *   mel filterbank → squash frequencies onto the human ear's scale (log-ish)
 *   log            → decibels
 *   DCT            → compress the ~26 filter energies into a few "shape" numbers
 *   cepstral mean normalization → subtract the average frame so mics sound equal
 *
 * The FFT here is written from scratch (radix-2 Cooley–Tukey) so the whole
 * library stays dependency-free. It returns the same numbers as any FFT —
 * you can read it as "reorder the inputs, then repeat small butterflies".
 */

import type { ScorerOptions } from './options.js';
import type { Pcm } from './pcm.js';
import { resampleLinear } from './pitch.js';

/** MFCCs are computed on a fixed 44.1 kHz rate so clips recorded elsewhere
 *  (48 kHz) compare fairly instead of through a filterbank mismatch. */
export const MFCC_SAMPLE_RATE = 44100;

/** MFCC frames for a mono clip. Empty when too short to analyse. */
export function extractMfcc(
  mono: Pcm,
  sampleRate: number,
  options: ScorerOptions,
): number[][] {
  const mono44 = resampleLinear(mono, sampleRate, MFCC_SAMPLE_RATE);
  if (mono44.length === 0) return [];
  const sr = MFCC_SAMPLE_RATE;
  const frameLen = Math.round((sr * options.mfcc.frameMs) / 1000);
  const hop = Math.round((sr * options.mfcc.frameMs) / 1000);
  if (frameLen < 64 || hop <= 0) return [];

  // Pre-emphasis over the whole signal: each sample minus a bit of the last.
  const emphasized = new Array<number>(mono44.length).fill(0);
  for (let i = 0; i < mono44.length; i++) {
    emphasized[i] = mono44[i]! - (i > 0 ? options.mfcc.preEmphasis * mono44[i - 1]! : 0);
  }

  // Next power of two ≥ frameLen is the FFT size (capped at 2048).
  let n = 1;
  while (n < frameLen) n <<= 1;
  if (n > 2048) n = 2048;
  const filters = melFilters(options.mfcc.melFilters, n, sr);

  // Hamming window.
  const window = new Array<number>(frameLen);
  for (let i = 0; i < frameLen; i++) {
    window[i] = 0.54 - 0.46 * Math.cos((2 * Math.PI * i) / (frameLen - 1));
  }

  const frames: number[][] = [];
  for (let start = 0; start < mono44.length; start += hop) {
    const re = new Array<number>(n).fill(0);
    const im = new Array<number>(n).fill(0);
    let sumSq = 0;
    for (let i = 0; i < frameLen; i++) {
      const s = start + i < emphasized.length ? emphasized[start + i]! * window[i]! : 0;
      re[i] = s;
      sumSq += s * s;
    }
    const rms = Math.sqrt(sumSq / frameLen);
    if (rms < options.mfcc.rmsGate) {
      frames.push(new Array<number>(options.mfcc.coeffs).fill(0));
      continue;
    }
    fft(re, im);

    // Mel energies: weighted sum of the power spectrum over each triangle.
    const mel = filters.map((f) => {
      let e = 0;
      for (let k = 0; k < f.length; k++) {
        e += f[k]! * ((re[k]! * re[k]! + im[k]! * im[k]!) / n);
      }
      return Math.log(Math.max(e, 1e-10));
    });

    // DCT-II: cosine basis → cepstral coefficients.
    const cep = new Array<number>(options.mfcc.coeffs).fill(0);
    for (let k = 0; k < options.mfcc.coeffs; k++) {
      let s = 0;
      for (let m = 0; m < mel.length; m++) {
        s += mel[m]! * Math.cos((Math.PI * k * (2 * m + 1)) / (2 * mel.length));
      }
      cep[k] = s;
    }
    frames.push(cep);
  }
  if (frames.length === 0) return [];

  // Cepstral mean normalization: subtract each coefficient's mean so mic
  // and room color stop mattering.
  const mean = new Array<number>(options.mfcc.coeffs).fill(0);
  for (const f of frames) {
    for (let k = 0; k < options.mfcc.coeffs; k++) mean[k]! += f[k]!;
  }
  for (let k = 0; k < options.mfcc.coeffs; k++) mean[k] /= frames.length;
  return frames.map((f) =>
    Array.from({ length: options.mfcc.coeffs }, (_, k) => f[k]! - mean[k]!),
  );
}

/** `count` triangular mel filters over the FFT bins 0..n/2. */
function melFilters(count: number, n: number, sr: number): number[][] {
  const hz2mel = (hz: number) => 2595 * (Math.log(1 + hz / 700) / Math.LN10);
  const mel2hz = (mel: number) => 700 * (Math.pow(10, mel / 2595) - 1);
  const low = hz2mel(0);
  const high = hz2mel(sr / 2);
  const points = new Array<number>(count + 2);
  for (let i = 0; i < count + 2; i++) {
    points[i] = mel2hz(low + (i * (high - low)) / (count + 1));
  }
  const bins = Math.floor(n / 2) + 1;
  const rows: number[][] = [];
  for (let m = 0; m < count; m++) {
    const row = new Array<number>(bins).fill(0);
    const left = points[m]!;
    const center = points[m + 1]!;
    const right = points[m + 2]!;
    for (let k = 0; k < bins; k++) {
      const hz = (k * sr) / n;
      if (hz >= left && hz <= center && center !== left) {
        row[k] = (hz - left) / (center - left);
      } else if (hz >= center && hz <= right && right !== center) {
        row[k] = (right - hz) / (right - center);
      }
    }
    rows.push(row);
  }
  return rows;
}

/** In-place radix-2 iterative FFT (Cooley–Tukey). re/im hold real/imag parts. */
function fft(re: number[], im: number[]): void {
  const n = re.length;
  // Bit-reversal permutation.
  let j = 0;
  for (let i = 1; i < n; i++) {
    let bit = n >> 1;
    while ((j & bit) !== 0) {
      j ^= bit;
      bit >>= 1;
    }
    j ^= bit;
    if (i < j) {
      const tr = re[i]!;
      re[i] = re[j]!;
      re[j] = tr;
      const ti = im[i]!;
      im[i] = im[j]!;
      im[j] = ti;
    }
  }
  // Butterfly stages: combine pairs = len/2 apart.
  for (let len = 2; len <= n; len <<= 1) {
    const ang = (-2 * Math.PI) / len;
    const wr = Math.cos(ang);
    const wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) {
      let cwr = 1;
      let cwi = 0;
      for (let k = 0; k < len / 2; k++) {
        const ur = re[i + k]!;
        const ui = im[i + k]!;
        const vr = re[i + k + len / 2]! * cwr - im[i + k + len / 2]! * cwi;
        const vi = re[i + k + len / 2]! * cwi + im[i + k + len / 2]! * cwr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + len / 2] = ur - vr;
        im[i + k + len / 2] = ui - vi;
        const nwr = cwr * wr - cwi * wi;
        cwi = cwr * wi + cwi * wr;
        cwr = nwr;
      }
    }
  }
}