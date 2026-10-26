/**
 * score.test.ts — end-to-end behaviour a user would notice: perfect copies
 * score 100, silence scores 0, and different takes score in between.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parseWav, scorePcm, scoreWavBytes, resolveOptions } from '../src/index.js';

const fixture = (name: string) =>
  new Uint8Array(readFileSync(fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url))));

describe('scorePcm', () => {
  const target = parseWav(fixture('ogre_target.wav'))!;
  const player = parseWav(fixture('ogre_attempt.wav'))!;
  const o = resolveOptions();

  it('gives an identical take exactly 100 (normalization off)', () => {
    // With the player peak-normalized to 0.5, a quiet target is subtly
    // altered, so the true "identical signals" case is with it disabled.
    const r = scorePcm(target.mono, target.sampleRate, target.mono, target.sampleRate, {
      preprocess: { normalizePlayerPeak: 0 },
    });
    expect(r.note).toBe('ok');
    expect(r.verdict.total).toBe(100);
  });

  it('gives a near-perfect score when only the level is normalized', () => {
    const r = scorePcm(target.mono, target.sampleRate, target.mono, target.sampleRate, o);
    expect(r.note).toBe('ok');
    expect(r.verdict.total).toBeGreaterThanOrEqual(99);
  });

  it('gives silence 0 with note "silent"', () => {
    const silence = new Float64Array(target.mono.length);
    const r = scorePcm(target.mono, target.sampleRate, silence, target.sampleRate, o);
    expect(r.verdict.total).toBe(0);
    expect(r.note).toBe('silent');
  });

  it('scores a genuine attempt between 0 and 100', () => {
    const r = scorePcm(target.mono, target.sampleRate, player.mono, player.sampleRate, o);
    expect(r.note).toBe('ok');
    expect(r.verdict.total).toBeGreaterThan(0);
    expect(r.verdict.total).toBeLessThan(100);
    expect(r.waveform.length).toBe(48);
  });
});

describe('scoreWavBytes', () => {
  it('flags unreadable input instead of throwing', () => {
    const junk = new Uint8Array([1, 2, 3, 4, 5]);
    const r = scoreWavBytes(junk, junk);
    expect(r.note).toBe('unreadable');
    expect(r.verdict.total).toBe(0);
  });
});