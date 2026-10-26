/**
 * parity.test.ts — the proof.
 *
 * `dart_ogre.json` was produced by the original Dart engine running on the
 * bundled WAV fixtures (see the game repo's tool/score_json.dart). If the
 * TypeScript port is faithful, it re-extracts the same features from the
 * same bytes and judges them to the same numbers.
 *
 * Numbers are compared with a tiny tolerance (float text round-trip); the
 * final 0–100 scores and integer counts must match EXACTLY.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  parseWav,
  extractPitch,
  energyEnvelope,
  extractMfcc,
  diagnose,
  scoreWavBytes,
  resolveOptions,
} from '../src/index.js';

const fixture = (name: string) =>
  new Uint8Array(readFileSync(fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url))));

const oracle = JSON.parse(
  readFileSync(fileURLToPath(new URL('./fixtures/dart_ogre.json', import.meta.url)), 'utf8'),
) as {
  features: {
    targetPitch: number[];
    playerPitch: number[];
    targetEnergy: number[];
    playerEnergy: number[];
    targetMfcc: number[][];
    playerMfcc: number[][];
  };
  diagnose: Record<string, number | string | boolean>;
  e2e: { total: number; melody: number; rhythm: number; pitched: boolean; note: string };
};

/** Largest absolute difference between two nested number structures. */
function maxAbsDiff(a: unknown, b: unknown): number {
  if (typeof a === 'number' && typeof b === 'number') return Math.abs(a - b);
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return Infinity;
    let m = 0;
    for (let i = 0; i < a.length; i++) m = Math.max(m, maxAbsDiff(a[i], b[i]));
    return m;
  }
  return a === b ? 0 : Infinity;
}

const FEATURE_TOL = 1e-6;
const DIAGNOSE_TOL = 1e-6;

describe('feature extraction parity with Dart', () => {
  const target = parseWav(fixture('ogre_target.wav'))!;
  const player = parseWav(fixture('ogre_attempt.wav'))!;
  const o = resolveOptions();

  it('parses both WAVs', () => {
    expect(target).not.toBeNull();
    expect(player).not.toBeNull();
  });

  it('produces identical pitch contours', () => {
    const tp = extractPitch(target.mono, target.sampleRate, o);
    const pp = extractPitch(player.mono, player.sampleRate, o);
    expect(tp.length).toBe(oracle.features.targetPitch.length);
    expect(pp.length).toBe(oracle.features.playerPitch.length);
    expect(maxAbsDiff(tp, oracle.features.targetPitch)).toBeLessThan(FEATURE_TOL);
    expect(maxAbsDiff(pp, oracle.features.playerPitch)).toBeLessThan(FEATURE_TOL);
  });

  it('produces identical energy envelopes', () => {
    const te = energyEnvelope(target.mono, target.sampleRate, o);
    const pe = energyEnvelope(player.mono, player.sampleRate, o);
    expect(te.length).toBe(oracle.features.targetEnergy.length);
    expect(pe.length).toBe(oracle.features.playerEnergy.length);
    expect(maxAbsDiff(te, oracle.features.targetEnergy)).toBeLessThan(FEATURE_TOL);
    expect(maxAbsDiff(pe, oracle.features.playerEnergy)).toBeLessThan(FEATURE_TOL);
  });

  it('produces identical MFCC frames', () => {
    const tm = extractMfcc(target.mono, target.sampleRate, o);
    const pm = extractMfcc(player.mono, player.sampleRate, o);
    expect(tm.length).toBe(oracle.features.targetMfcc.length);
    expect(pm.length).toBe(oracle.features.playerMfcc.length);
    expect(maxAbsDiff(tm, oracle.features.targetMfcc)).toBeLessThan(FEATURE_TOL);
    expect(maxAbsDiff(pm, oracle.features.playerMfcc)).toBeLessThan(FEATURE_TOL);
  });
});

describe('judging parity with Dart', () => {
  const o = resolveOptions();

  it('reproduces the Dart diagnose() map from the Dart features', () => {
    const r = diagnose(
      oracle.features.targetPitch,
      oracle.features.playerPitch,
      {
        targetEnergy: oracle.features.targetEnergy,
        playerEnergy: oracle.features.playerEnergy,
        targetMfcc: oracle.features.targetMfcc,
        playerMfcc: oracle.features.playerMfcc,
      },
      o,
    );
    for (const [key, expected] of Object.entries(oracle.diagnose)) {
      const actual = r[key];
      if (typeof expected === 'number') {
        expect(
          maxAbsDiff(actual, expected),
          `${key}: expected ${expected}, got ${String(actual)}`,
        ).toBeLessThan(DIAGNOSE_TOL);
      } else {
        expect(actual, `${key}`).toBe(expected);
      }
    }
  });

  it('scores the fixture pair exactly like the Dart end-to-end pipeline', () => {
    const result = scoreWavBytes(fixture('ogre_target.wav'), fixture('ogre_attempt.wav'), o);
    expect(result.note).toBe(oracle.e2e.note);
    expect(result.verdict.total).toBe(oracle.e2e.total);
    expect(result.verdict.melody).toBe(oracle.e2e.melody);
    expect(result.verdict.rhythm).toBe(oracle.e2e.rhythm);
    expect(result.verdict.pitched).toBe(oracle.e2e.pitched);
  });
});