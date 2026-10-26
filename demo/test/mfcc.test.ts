/**
 * mfcc.test.ts — the timbre fingerprint: shape, silence handling, and the
 * effect of cepstral mean normalization.
 */

import { describe, it, expect } from 'vitest';
import { extractMfcc, resolveOptions } from '../src/index.js';

const o = resolveOptions();

function sine(freq: number, seconds: number, sampleRate = 44100, amplitude = 0.5): Float64Array {
  const n = Math.round(seconds * sampleRate);
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) out[i] = amplitude * Math.sin((2 * Math.PI * freq * i) / sampleRate);
  return out;
}

describe('MFCC extraction', () => {
  it('returns one 13-coefficient frame per 20 ms hop', () => {
    const frames = extractMfcc(sine(440, 0.2), 44100, o);
    expect(frames.length).toBeGreaterThan(5);
    expect(frames[0]!.length).toBe(13);
  });

  it('mean-normalizes each coefficient across frames (CMN ≈ 0)', () => {
    const frames = extractMfcc(sine(440, 0.5), 44100, o);
    for (let k = 0; k < 13; k++) {
      const mean = frames.reduce((a, f) => a + f[k]!, 0) / frames.length;
      expect(Math.abs(mean)).toBeLessThan(1e-9);
    }
  });

  it('turns silence into all-zero frames', () => {
    const frames = extractMfcc(new Float64Array(44100), 44100, o);
    expect(frames.length).toBeGreaterThan(0);
    expect(frames.every((f) => f.every((c) => c === 0))).toBe(true);
  });
});