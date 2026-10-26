# How the scoring works, from first principles

This document is written for someone who is comfortable with JavaScript and
arrays but has never touched audio or signal processing. Every idea is built
from the one below it. No prior DSP knowledge is assumed.

If you just want to use the API, read the [README](../README.md) instead.

---

## 0. The big picture

We take two recordings — a **target** and an **attempt** (your imitation) — and
produce a single 0–100 score, plus two sub-scores: **melody** and **rhythm**.

There is no machine learning and no network. The whole thing is arithmetic over
arrays of numbers, and it is a direct port of a Dart implementation, so the two
engines agree to the last floating-point digit.

The pipeline has two halves:

1. **Extraction** turns a waveform (thousands of "how loud right now" numbers)
   into compact **features**: a pitch curve, an energy curve, an MFCC curve, and
   some summary statistics.
2. **Judging** compares the two sets of features and folds the comparison into
   a score.

Features are just `number[]`. That is the only data type you need to keep in
mind for the first half.

---

## 1. Samples, PCM, and WAV

A digital recording is a long list of samples: the air pressure measured at
fixed instants, as a number roughly between `-1` and `+1`.

- **Sample rate** — how many samples per second. Audio is usually `44100`
  (music) or `48000` (video/phones).
- **PCM** ("pulse-code modulation") is the fancy name for "the list of
  samples". A `Float32Array` or `Float64Array` is PCM.
- **Monaural ("mono")** — one channel. Stereo has two lists; we average or pick
  one, because pitch and timbre do not need two ears.
- A **WAV file** is just a tiny header (sample rate, channel count, bit depth)
  followed by those raw samples. `parseWav()` reads that header and hands you
  `{ mono, sampleRate }`.

If you have heard "44.1 kHz", that is 44,100 samples per second.

> **Web-dev analogy:** a recording is an array of numbers, and a WAV file is
> JSON with a fixed schema prefix followed by a packed payload.

---

## 2. Loudness: RMS and the energy envelope

The simplest question about a chunk of samples is "how loud is it?". The answer
is **RMS** (root mean square): square every sample (making negatives positive),
average them, then take the square root. It is the audio equivalent of a
standard deviation, and it tracks perceived loudness well.

We do not compute one RMS for the whole clip. We slice the clip into short
frames (a few milliseconds each) and compute RMS per frame, producing one RMS
value per frame over time. That sequence is the **energy envelope** — a curve
that rises when you sing and falls when you pause.

This envelope drives two things later: deciding which frames are "voiced"
(actually singing/speaking vs silence), and scoring how well your loudness
*shape* matches the target's.

> **Web-dev analogy:** a downsampling/reduce pass. Map thousands of points to a
> few hundred by summarizing each window.

---

## 3. Pitch: how high a note is, as a number

Pitch is the sensation of "how high". Physically it is the **fundamental
frequency** in hertz (Hz): vibrations per second. Concert A is 440 Hz; doubling
frequency is one **octave** up (880 Hz), halving is one octave down (220 Hz).

### Why it is hard

A sung note is not a pure sine wave. It is a rich, buzzy signal whose perceived
pitch is the *slowest* repeating rhythm inside it, even though the signal also
wiggles at many faster rates (its **harmonics**). To find the fundamental we
must find the repeating period.

### Autocorrelation

The classic trick: **autocorrelation**. For a candidate lag `L`, slide the
signal against a copy of itself shifted by `L` and measure how well they line
up (sum of products). When `L` equals the true period, the signal lines up with
itself and the sum peaks. The lag of the biggest peak, converted to
`sampleRate / lag`, is the frequency.

Think of it as answering "how many samples until the pattern repeats?".

### YIN: doing it more robustly

Plain autocorrelation has a well-known failure: it can lock onto a *multiple* of
the true period (an octave error). The **YIN** algorithm (de Cheveigné &
Kawahara, 2002) fixes this elegantly:

1. Compute the **difference function** `d(τ)` — the sum of squared differences
   between the signal and its shift by `τ`. This is the mirror image of
   autocorrelation; the true period becomes a *minimum*, not a maximum.
2. Normalize it into the **cumulative mean normalized difference** function
   `d'(τ) = d(τ) / ((1/τ) · Σ_{j=1..τ} d(j))`. This division cancels the
   tendency of the difference to grow with lag, flattening the octave problem.
3. Find the first `τ` where `d'(τ)` dips below a **threshold** (we use `0.20`)
   and is a local minimum. That is the period.
4. Convert: `frequency = sampleRate / τ`.

If no dip below the threshold exists, the frame is **unvoiced** (a consonant, a
pause, noise) and we emit `null` for pitch at that frame.

Every tunable in that list is exposed: `searchMinHz`, `searchMaxHz`, the
threshold (`yinThreshold`), and the frame/window lengths.

### The pitch contour

Running YIN on every frame gives a `(time, frequency)` curve — the **pitch
contour**. It is `null` where there is no pitch. This contour is the single most
important feature: melody imitation lives here.

### Cents

To compare pitches we use **cents**, a logarithmic unit where `1200` cents = one
octave, `100` cents = one semitone. `cents = 1200 · log2(f2 / f1)`. Why log?
Because our ears hear *ratios*, not differences — the step from 220→440 Hz
feels the same size as 440→880 Hz. Cents turn a ratio into a difference, which
is much easier to score.

---

## 4. Timbre: MFCCs ("what the voice sounds like")

Two people can sing the same note (same pitch) at the same loudness and still
sound different — that is **timbre**, driven by the shape of the vocal tract and
which harmonics are loud.

**MFCCs (mel-frequency cepstral coefficients)** are the standard compact
description of timbre. The recipe:

1. **Frame** the signal into ~20 ms windows.
2. **Window** each frame with a bell shape (a Hann window) so the edges taper to
   zero and do not create fake high frequencies.
3. **Pre-emphasis**: a simple high-pass filter (`out[n] = x[n] - 0.97·x[n-1]`)
   that boosts the higher frequencies the ear cares about.
4. **FFT** (Fast Fourier Transform) each frame: convert from time domain to
   **frequency domain**, giving the amount of energy at each frequency. This is
   where the fast transform matters — see §5.
5. **Mel filterbank**: humans do not hear frequency linearly. We are sharp at low
   frequencies and coarse at high ones. The **mel scale** warps the frequency
   axis to match perception, and we sum the spectrum into 26 overlapping
   triangular buckets on that warped axis.
6. **Log**: take the log of each bucket energy — this matches how loudness is
   perceived and turns products into sums.
7. **DCT**: apply a Discrete Cosine Transform (a compact, real-valued cousin of
   the FFT) to the 26 log-energies to decorrelate them into ~13 coefficients.
   We keep coefficients 1..12 and **drop coefficient 0** (see §6).

The result is 13 numbers per frame that describe timbre while ignoring overall
volume.

### CMN (cepstral mean normalization)

Before comparing, we subtract each coefficient's average over the whole
recording. This removes constant channel/color effects (a cheap microphone, a
different room) so we compare *shape*, not recording setup.

> **Web-dev analogy:** MFCC is a feature-vector transform, like turning a string
> into a bag-of-words vector. FFT/mel/DCT are the tokenizer; CMN is removing the
> document-wide boilerplate.

---

## 5. The FFT, briefly

The **FFT** computes the **DFT**: given `N` time samples it returns `N` complex
numbers saying how much of each frequency is present. Naively this is O(N²);
the FFT exploits symmetry to do it in O(N·log N). We implement the classic
in-place **radix-2 Cooley–Tukey** FFT, which requires a power-of-two length
(we pad each frame). This is the one "clever" algorithm in the codebase, and it
is only ~40 lines.

---

## 6. Why we drop coefficient 0

Coefficient 0 of the DCT is essentially the average log-energy of the frame —
i.e. *overall loudness*. Since loudness is scored separately (§2), keeping it
here would double-count it and make the timbre score sensitive to volume. So we
drop it. The remaining coefficients describe timbre "for free of" volume.

---

## 7. Comparing two contours: DTW

Now we have two pitch contours (or energy, or timbre curves) that are *almost*
aligned in time but not exactly — you were a quarter-second late, or held a note
slightly longer. Comparing them index-by-index would punish tiny timing slips.

**Dynamic Time Warping (DTW)** fixes this. It finds the cheapest alignment
between two sequences, allowing either sequence to "stall" (repeat a frame) so
that similar shapes line up even when stretched. The cost is the sum of
local differences along the best path.

- The **cost** (we call it `mfccErr` for timbre, and similar for others) is
  small when the two curves have the same shape.
- We then convert cost to a 0..1 score with an exponential decay:
  `score = exp(-cost / sigma)`, where `sigma` (`mfccSigma`, default `12`) sets
  how forgiving we are. Cost 0 → score 1; larger cost → score decays toward 0.

We also expose a **band** (a maximum allowed warp) so the alignment cannot
cheat by sliding one clip entirely past the other — `slackAlign`, `slackVec`.

> **Web-dev analogy:** DTW is edit distance (Levenshtein), but the substitution
> cost is how different two frames are and diagonal steps are allowed. It is a
> small dynamic-programming grid.

---

## 8. Correlation and ranks

For loudness shape we also use the **Pearson correlation** between the two
energy curves — a number in `-1..1` measuring whether they rise and fall
together, scale-independent.

For rhythm we sometimes use the **Spearman** version: replace every value by its
**rank** (1st, 2nd, 3rd…) then correlate. Ranking throws away exact magnitudes
and keeps only *order*, which is robust to outliers.

> **Web-dev analogy:** Pearson is `cov(x,y)/σxσy`; Spearman is "sort both,
> correlate the indices".

---

## 9. Scoring axes

The comparison produces four axis scores, each in `0..1`:

| Axis   | Question it answers | Built from |
|--------|---------------------|-----------|
| pitch  | Did you hit the same notes / melody? | pitch contour DTW + octave-slip check |
| mfcc   | Does your voice sound like the target's? | MFCC DTW |
| energy | Did your loudness shape match? | envelope DTW + correlation |
| timing | Did it last the right length, with the right rhythm? | overlap, duration, onset/offset |

Each axis gets a **weight**. The weights depend on what the target is, decided
by `classify()`:

- **tonal** (mostly steady pitch — singing): pitch matters most.
- **speech** (some pitch, lots of variation): timbre and timing dominate.
- **noise** (no clear pitch): pitch is irrelevant, dropped.

Missing or unreliable axes (e.g. pitch, when the target has too many octave
slips) are **dropped** and the remaining weights are **renormalized** to sum to
1, so a clip is never punished for an axis we could not measure.

---

## 10. Multipliers and the weakest link

Before the final curve, three multipliers can scale the raw score down:

- **static multiplier** — if the whole attempt sits on one vowel/monotone,
  penalize the monotony.
- **length multiplier** — if the attempt is far too short or long.
- **burst multiplier** — if the attempt is choppy (starts and stops).

There is also a **weakest-link cap**: if any weighted axis is very bad, the
total cannot exceed a ceiling, because "great pitch but no rhythm" should not
score as a great imitation.

---

## 11. The feel curve

`rawPreFeel` is a number in `0..1` after the multipliers. Human perception is
non-linear: the difference between 0.2 and 0.3 feels much bigger than between
0.8 and 0.9. The **feel curve** is a lookup table mapping `rawPreFeel` to the
final 0–100:

```
[0.00 → 0] [0.20 → 10] [0.40 → 40] [0.55 → 70]
[0.70 → 88] [0.85 → 97] [1.00 → 100]
```

It is applied by interpolating between these control points. Above
`perfectThreshold` (`0.995`) the score is forced to exactly `100`, so a true
perfect copy reads as 100 rather than 99.

---

## 12. The verdict

The final result is:

```ts
{
  verdict: { total, melody, rhythm, pitched },
  note: 'ok' | 'silent' | 'empty-pitch' | 'unreadable',
  voicedPct: number,
  diagnose: { /* every intermediate value, for debugging */ }
}
```

`diagnose` is deliberately fat: it contains every feature and intermediate score
so you can see *why* a clip scored what it did. The demo's options panel and
the parity tests both lean on it.

---

## 13. Where to look next

- `src/pitch.ts` — YIN and the envelope (start here; it is the most self-contained).
- `src/mfcc.ts` — frames → FFT → mel → DCT.
- `src/core.ts` — DTW, the axes, the multipliers, the feel curve, `judge()`.
- `src/options.ts` — every number above, with its default.
- `test/` — each file runs a tiny, readable scenario for one part.
