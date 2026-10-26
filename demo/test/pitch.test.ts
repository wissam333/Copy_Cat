/**
 * pitch.test.ts — sanity checks for the YIN pitch detector and RMS energy.
 * Synthetic signals keep the expectations obvious.
 */

import { describe, it, expect } from 'vitest';
import { extractPitch, energyEnvelope, resolveOptions, median3 } from '../src/index.js';

const o = resolveOptions();

/** A pure sine wave at `freq` Hz. */
function sine(freq: number, seconds: number, sampleRate = 44100, amplitude = 0.5): Float64Array {
  const n = Math.round(seconds * sampleRate);
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    out[i] = amplitude * Math.sin((2 * Math.PI * freq * i) / sampleRate);
  }
  return out;
}

describe('YIN pitch detection', () => {
  it('finds a 220 Hz sine', () => {
    const pitch = extractPitch(sine(220, 1), 44100, o);
    const voiced = pitch.filter((f) => f > 0);
    expect(voiced.length).toBeGreaterThan(5);
    const avg = voiced.reduce((a, b) => a + b, 0) / voiced.length;
    expect(avg).toBeGreaterThan(215);
    expect(avg).toBeLessThan(225);
  });

  it('finds a 440 Hz sine', () => {
    const pitch = extractPitch(sine(440, 1), 44100, o);
    const voiced = pitch.filter((f) => f > 0);
    const avg = voiced.reduce((a, b) => a + b, 0) / voiced.length;
    expect(avg).toBeGreaterThan(430);
    expect(avg).toBeLessThan(450);
  });

  it('reports silence as unvoiced (0)', () => {
    const pitch = extractPitch(new Float64Array(44100), 44100, o);
    expect(pitch.every((f) => f === 0)).toBe(true);
  });
});

describe('RMS energy envelope', () => {
  it('approximates A/√2 for a sine of amplitude A', () => {
    const energy = energyEnvelope(sine(300, 1, 44100, 0.5), 44100, o);
    const avg = energy.reduce((a, b) => a + b, 0) / energy.length;
    expect(avg).toBeGreaterThan(0.34);
    expect(avg).toBeLessThan(0.36);
  });
});

describe('median3 smoothing', () => {
  it('replaces a lone spike with its neighbours', () => {
    expect(median3([1, 1, 9, 1, 1])).toEqual([1, 1, 1, 1, 1]);
  });
});