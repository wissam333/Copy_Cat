# Scoring risks

This file tracks scoring risks for the mimic party app. Solo and LAN share one scoring pipeline (`AttemptScorer` → `AudioScorer.judge`). `mimic_scoring_spec.md` is a source of ideas only and is not modified.

## LAN always scored 18 (the bug this pass fixes)

LAN turns kept landing on **exactly 18**. That number was a hard cap, not a real grade.

In the old `AudioScorer.judge`, any pitched target whose player contour looked “too flat” did this:

```
if (pitched && contourMismatch) total = min(total, 18)
```

Mismatch meant: target pitch variance > 1 semitone², and player variance < 15% of that. Variance shrinks with the **square** of the range, so a timid but real mimic at ~25–40% of the target’s pitch range still tripped the cap and glued at 18.

LAN hit this on almost every take because:

1. LAN graded the **stored library `pitchMap`** (clean ingest, wide contour) against a **live YIN extract** of the phone recording (noisier, compressed, missing frames).
2. Solo often **re-extracted the target from the same file** as the attempt, so both sides were compressed the same way and the cap fired less.
3. Speech clips were treated as tunes. A spoken mimic rarely matches a library pitchMap’s variance, so the cap fired even when rhythm/timbre were fine.
4. Melody was still a non-null `0` when the player was under 45% voiced, so a decent envelope score was pulled down to 18 as well.

**Fix:** drop the hard 18 cap. Use the spec’s graduated static-vowel multiplier (`m_static` 0.30 → 1.0 from 15% to 50% of target pitch std, and only when the target itself moves). Solo and LAN both extract target **and** player from WAV at score time, so they cannot disagree. A compressed-but-shaped take can score above 18; a true held “aaaa” against a moving clip stays low.

## Remaining product risks

### Speech totals will drop for lucky old scores

Talking memes used to skip MFCC and put 72% of the grade on melody. They now use speech weights (pitch 25%, MFCC 35%, energy 20%, timing 20%). A take that hummed the pitch of a spoken clip and scored high will come down. That is intended.

### Reveal meters still say melody / rhythm

`ScoreVerdict` still exposes `melody` (pitch axis) and `rhythm` (energy+timing mix) so LAN packet `0x05` and the reveal UI stay unchanged. On speech/noise clips the “لحن” meter can look low while the total is fair. Totals are the number that matters.

### Always-on MFCC costs CPU at reveal

Every attempt now extracts MFCC for both files (3–6 s). Expected well under one second on a phone at the current 20 ms hop. If a device stutters on the scoring spinner, cache the **target** MFCC for the turn inside `AttemptScorer` (still shared). Do not skip MFCC for “pitched” clips — that was the speech bug.

### Game-feel curve changes the muscle memory of numbers

Raw similarity is mapped through a piecewise curve (good ~75–92, average ~45–65, random ~0–25, silence 0). Old scores from the exponential `exp(-err/tau)` curve will not match. Funny-line tiers and celebration thresholds (20 / 40 / 60 / 80 / 85 / 95) stay as they are; they will simply fire on the new totals.

### Weakest-link vs one strong axis

If any axis with weight ≥ 0.25 scores under 0.15, raw is capped at 0.45 (about 50 after the curve, then other guards). White noise that matches loudness still cannot ride energy alone on a sung clip. A very good rhythm with no tune on a song stays low because the unused pitch weight stays in the mix (a failed axis is 0, not “missing”).

### Noise clips and burst count

One thump vs four claps: noise totals are still scaled by burst similarity (`0.5 + 0.5 * sim`). Without that, identical MFCC plus a long envelope can fake a high score. Matched burst counts are unchanged (multiplier 1).

## Risks we are accepting (out of scope)

These are in the spec as product/engine work. This pass does not do them:

| Risk | Why it stays |
|---|---|
| Replay of the original from another speaker | No audio watermark. Known limit. |
| Loud TV / people in the room beating the gate | Relative energy gate + room-tone / flat-line checks. No mic calibration UI. |
| SHOUT vs scream-like FX | No spectral centroid/ZCR yet. Shouts classify as speech or tonal from voiced ratio. Claps that this YIN marks 15–30% voiced stay in the noise bucket (same bar as `looksPitched`), so they are not graded as speech. |
| Score-time median smoothing | A second 3-frame median on 50 ms pitch frames flattened different melodies into one line (unrelated contours scored ~99). Scoring uses the extractor's contour as-is. Octave repair only fixes a near-octave jump (1050–1350 cents), not every leap. |
| 50 ms YIN hop vs spec 10 ms pYIN | Library `pitchMap` hop stays 50 ms; we re-extract at score time with the same extractor. Finer pitch is a later extractor change. |
| Capture at 44.1 kHz, AGC off not guaranteed | `AudioIoService` / `record` settings unchanged. |
| Child vs adult timbre (MFCC) | Pitch is median-centered (fair). MFCC weight is already lower on tonal clips. |
| Slow scoring on a very old phone | No `Isolate.run` in this pass. |

## Test / ship checks

- Silence, empty, room tone → 0, no NaN.
- Perfect copy → 100.
- Same melody, other key / +5 semitones → high; +octave → high with a small fold penalty.
- Flat “aaaa” vs moving speech → ≤ 30, **and not stuck at 18**.
- Compressed-but-shaped contour → **above 18**.
- Unrelated clip / white noise vs a tune → low.
- One burst vs four claps → clearly worse than matched bursts.
- Same two WAVs through `AttemptScorer` twice (and from solo vs LAN call sites) → identical `ScoreVerdict`.
- `mimic_scoring_spec.md` untouched.
