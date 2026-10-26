#!/usr/bin/env node
/**
 * cli.mjs — score two WAV files from the terminal.
 *
 *   node scripts/cli.mjs target.wav player.wav
 *
 * Requires a build first (`npm run build`) so ../dist exists.
 */
import { readFileSync } from 'node:fs';
import {
  scoreWavBytes,
  diagnose,
  parseWav,
  extractPitch,
  energyEnvelope,
  extractMfcc,
  resolveOptions,
} from '../dist/index.js';

const [, , targetPath, playerPath] = process.argv;
if (!targetPath || !playerPath) {
  console.error('usage: node scripts/cli.mjs TARGET.wav PLAYER.wav');
  process.exit(1);
}

const targetBytes = new Uint8Array(readFileSync(targetPath));
const playerBytes = new Uint8Array(readFileSync(playerPath));

const result = scoreWavBytes(targetBytes, playerBytes);

const target = parseWav(targetBytes);
const player = parseWav(playerBytes);
const o = resolveOptions();
const details =
  target && player
    ? diagnose(
        extractPitch(target.mono, target.sampleRate, o),
        extractPitch(player.mono, player.sampleRate, o),
        {
          targetEnergy: energyEnvelope(target.mono, target.sampleRate, o),
          playerEnergy: energyEnvelope(player.mono, player.sampleRate, o),
          targetMfcc: extractMfcc(target.mono, target.sampleRate, o),
          playerMfcc: extractMfcc(player.mono, player.sampleRate, o),
        },
        o,
      )
    : null;

console.log(
  JSON.stringify(
    { verdict: result.verdict, note: result.note, voicedPct: result.voicedPct, diagnose: details },
    null,
    2,
  ),
);