/**
 * options.test.ts — the tuning surface behaves as documented: deep merge
 * preserves siblings, and changing a value changes the outcome.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolveOptions, DEFAULT_OPTIONS, scoreWavBytes } from '../src/index.js';

const fixture = (name: string) =>
  new Uint8Array(readFileSync(fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url))));

describe('resolveOptions', () => {
  it('returns the defaults when given nothing', () => {
    expect(resolveOptions()).toEqual(DEFAULT_OPTIONS);
  });

  it('deep-merges an override without losing sibling defaults', () => {
    const o = resolveOptions({ scoring: { mfccSigma: 6 } });
    expect(o.scoring.mfccSigma).toBe(6);
    // Sibling values survive.
    expect(o.scoring.octaveSlipLimit).toBe(DEFAULT_OPTIONS.scoring.octaveSlipLimit);
    expect(o.pitch.windowMs).toBe(DEFAULT_OPTIONS.pitch.windowMs);
  });

  it('does not mutate the defaults', () => {
    resolveOptions({ scoring: { mfccSigma: 99 } });
    expect(DEFAULT_OPTIONS.scoring.mfccSigma).toBe(12);
  });
});

describe('tuning actually changes scoring', () => {
  it('a flat feel curve pushes any non-zero raw score to 100', () => {
    const base = scoreWavBytes(fixture('ogre_target.wav'), fixture('ogre_attempt.wav'));
    const generous = scoreWavBytes(fixture('ogre_target.wav'), fixture('ogre_attempt.wav'), {
      scoring: { feelCurve: [[0, 100], [1, 100]] },
    });
    expect(generous.verdict.total).toBeGreaterThan(base.verdict.total);
    expect(generous.verdict.total).toBe(100);
  });
});