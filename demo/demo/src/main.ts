import {
  scorePcm,
  decodeBlobToPcm,
  parseWav,
  resolveOptions,
  DEFAULT_OPTIONS,
  writeWav,
  type Pcm,
  type ScorerOptions,
  type DeepPartial,
  type WavData,
  type ScoreResult,
} from '../../src/index.js';

const $ = <T extends HTMLElement>(id: string): T => {
  const el = document.getElementById(id);
  if (!el) throw new Error(`missing #${id}`);
  return el as T;
};

interface Slot {
  wav: WavData | null;
  button: HTMLButtonElement;
  hint: HTMLElement;
  canvas: HTMLCanvasElement;
  playBtn: HTMLButtonElement;
  input: HTMLInputElement;
  /** Live recorder while a take is running — second click stops it. */
  recorder?: MediaRecorder;
}

function makeSlot(prefix: 'target' | 'attempt'): Slot {
  return {
    wav: null,
    button: $<HTMLButtonElement>(`${prefix}Rec`),
    hint: $<HTMLElement>(`${prefix}Hint`),
    canvas: $<HTMLCanvasElement>(`${prefix}Wave`),
    playBtn: $<HTMLButtonElement>(`${prefix}Play`),
    input: $<HTMLInputElement>(`${prefix}File`),
  };
}

const target = makeSlot('target');
const attempt = makeSlot('attempt');
const scoreBtn = $<HTMLButtonElement>('scoreBtn');

const TARGET_COLOR = '#a78bfa';
const ATTEMPT_COLOR = '#4ade80';

// ---------------------------------------------------------------------------
// Wave / contour drawing
// ---------------------------------------------------------------------------

function prepCanvas(canvas: HTMLCanvasElement): CanvasRenderingContext2D | null {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  ctx.scale(dpr, dpr);
  ctx.clearRect(0, 0, w, h);
  return ctx;
}

function drawWave(canvas: HTMLCanvasElement, mono: Pcm, accent: string): void {
  const ctx = prepCanvas(canvas);
  if (!ctx) return;
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;

  const buckets = 120;
  const step = Math.max(1, Math.floor(mono.length / buckets));
  ctx.strokeStyle = accent;
  ctx.lineWidth = 1.4;
  ctx.beginPath();
  for (let i = 0; i < buckets; i++) {
    let peak = 0;
    const start = i * step;
    const end = Math.min(mono.length, start + step);
    for (let j = start; j < end; j++) {
      const v = Math.abs(mono[j]!);
      if (v > peak) peak = v;
    }
    const x = (i / buckets) * w;
    const amp = peak * (h / 2 - 2);
    ctx.moveTo(x, h / 2 - amp);
    ctx.lineTo(x, h / 2 + amp);
  }
  ctx.stroke();
}

/** Target vs attempt pitch contours on one log-octave axis. */
function drawContours(canvas: HTMLCanvasElement, targetPitch: number[], playerPitch: number[]): void {
  const ctx = prepCanvas(canvas);
  if (!ctx) return;
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;

  ctx.strokeStyle = 'rgba(255,255,255,0.09)';
  ctx.lineWidth = 1;
  for (let g = 1; g < 3; g++) {
    ctx.beginPath();
    ctx.moveTo(0, (h / 3) * g);
    ctx.lineTo(w, (h / 3) * g);
    ctx.stroke();
  }

  const all = [...targetPitch, ...playerPitch].filter((v) => v > 0);
  if (all.length === 0) return;
  const maxHz = Math.max(220, Math.min(1000, Math.max(...all)));
  const lo = Math.log2(50);
  const span = Math.log2(maxHz) - lo;
  const yOf = (f: number) => h - 8 - ((Math.log2(f) - lo) / span) * (h - 16);

  const drawSeries = (p: number[], color: string) => {
    const n = p.length;
    if (n < 2) return;
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    let pen = false;
    for (let i = 0; i < n; i++) {
      const v = p[i]!;
      const x = (i / (n - 1)) * w;
      if (v <= 0) {
        pen = false;
        continue;
      }
      const y = yOf(v);
      if (pen) ctx.lineTo(x, y);
      else ctx.moveTo(x, y);
      pen = true;
    }
    ctx.stroke();
  };

  drawSeries(targetPitch, TARGET_COLOR);
  drawSeries(playerPitch, ATTEMPT_COLOR);
}

// ---------------------------------------------------------------------------
// Slot wiring: record / upload / play all funnel into setSlotWav
// ---------------------------------------------------------------------------

function setSlotWav(slot: Slot, wav: WavData): void {
  slot.wav = wav;
  const seconds = (wav.mono.length / wav.sampleRate).toFixed(1);
  slot.hint.textContent = `${seconds}s @ ${wav.sampleRate} Hz`;
  drawWave(slot.canvas, wav.mono, slot === target ? TARGET_COLOR : ATTEMPT_COLOR);
  slot.playBtn.disabled = false;
  scoreBtn.disabled = !(target.wav && attempt.wav);
}

async function record(slot: Slot): Promise<void> {
  if (!navigator.mediaDevices?.getUserMedia) {
    slot.hint.textContent = 'Recording is not supported in this browser — upload files instead';
    return;
  }
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const chunks: BlobPart[] = [];
  const recorder = new MediaRecorder(stream);
  slot.recorder = recorder;
  recorder.ondataavailable = (e) => {
    if (e.data.size > 0) chunks.push(e.data);
  };

  slot.button.textContent = '■ Stop';
  slot.button.classList.add('on');
  slot.hint.textContent = 'Recording… click again to stop';

  await new Promise<void>((resolve) => {
    recorder.onstop = () => resolve();
    recorder.start();
  });
  stream.getTracks().forEach((t) => t.stop());
  slot.recorder = undefined;
  slot.button.textContent = '● Record';
  slot.button.classList.remove('on');

  const blob = new Blob(chunks, { type: recorder.mimeType });
  const wav = await decodeBlobToPcm(blob);
  if (!wav) {
    slot.hint.textContent = 'Could not decode that recording';
  } else {
    setSlotWav(slot, wav);
  }
}

function wireRecorder(slot: Slot): void {
  let busy = false;
  slot.button.addEventListener('click', () => {
    const live = slot.recorder;
    if (live && live.state !== 'inactive') {
      live.stop(); // second click — { resolve() fires inside the running record()
      return;
    }
    if (busy) return;
    busy = true;
    record(slot)
      .catch(() => {
        slot.hint.textContent = 'Microphone permission denied — upload files instead';
      })
      .finally(() => {
        busy = false;
      });
  });
}

async function wireUpload(slot: Slot): Promise<void> {
  slot.input.addEventListener('change', async () => {
    const file = slot.input.files?.[0];
    if (!file) return;
    slot.hint.textContent = `Reading ${file.name}…`;
    // WAV files are parsed by the engine itself (byte-exact — same numbers as
    // the game). Anything else goes through the browser's decoder, which
    // resamples to the hardware rate and may shift borderline classifications.
    let wav: WavData | null = null;
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());
      wav = parseWav(bytes);
    } catch {
      wav = null;
    }
    if (!wav) wav = await decodeBlobToPcm(file);
    if (!wav) {
      slot.hint.textContent = 'Could not decode that file — try WAV, MP3 or OGG';
      return;
    }
    setSlotWav(slot, wav);
    slot.input.value = '';
  });
}

let currentAudio: HTMLAudioElement | null = null;

function wirePlay(slot: Slot): void {
  slot.playBtn.addEventListener('click', () => {
    if (!slot.wav) return;
    if (currentAudio) {
      currentAudio.pause();
      currentAudio = null;
    }
    const bytes = writeWav(slot.wav.mono, slot.wav.sampleRate);
    const url = URL.createObjectURL(new Blob([bytes as unknown as BlobPart], { type: 'audio/wav' }));
    const audio = new Audio(url);
    audio.onended = () => {
      slot.playBtn.textContent = '▶';
    };
    slot.playBtn.textContent = '❚❚';
    audio.play();
    currentAudio = audio;
  });
}

wireRecorder(target);
wireRecorder(attempt);
void wireUpload(target);
void wireUpload(attempt);
wirePlay(target);
wirePlay(attempt);

// ---------------------------------------------------------------------------
// Options panel (unchanged ids — tune the engine live)
// ---------------------------------------------------------------------------

const OPTION_FIELDS: Array<{ key: string; label: string; get: (o: ScorerOptions) => number }> = [
  { key: 'mfccSigma', label: 'scoring.mfccSigma', get: (o) => o.scoring.mfccSigma },
  { key: 'octaveSlip', label: 'scoring.octaveSlipLimit', get: (o) => o.scoring.octaveSlipLimit },
  { key: 'pitchGate', label: 'scoring.pitchGateVoiced', get: (o) => o.scoring.pitchGateVoiced },
  { key: 'roomTone', label: 'gates.roomTonePeak', get: (o) => o.gates.roomTonePeak },
  { key: 'silence', label: 'gates.silencePeak', get: (o) => o.gates.silencePeak },
  { key: 'flat', label: 'gates.flatRatio', get: (o) => o.gates.flatRatio },
  { key: 'wPitch', label: 'weights.tonal.pitch', get: (o) => o.weights.tonal.pitch },
  { key: 'wMfcc', label: 'weights.tonal.mfcc', get: (o) => o.weights.tonal.mfcc },
  { key: 'wEnergy', label: 'weights.tonal.energy', get: (o) => o.weights.tonal.energy },
  { key: 'wTiming', label: 'weights.tonal.timing', get: (o) => o.weights.tonal.timing },
];

const optsHost = $<HTMLElement>('opts');

function buildOptionsPanel(): void {
  const d = DEFAULT_OPTIONS;
  optsHost.innerHTML = '';
  for (const field of OPTION_FIELDS) {
    const label = document.createElement('label');
    label.textContent = field.label;
    const input = document.createElement('input');
    input.type = 'number';
    input.step = '0.01';
    input.id = `opt-${field.key}`;
    input.value = String(field.get(d));
    label.appendChild(input);
    optsHost.appendChild(label);
  }
}

function num(key: string): number {
  const el = document.getElementById(`opt-${key}`) as HTMLInputElement | null;
  return el ? Number(el.value) : 0;
}

function readOptions(): DeepPartial<ScorerOptions> {
  return {
    scoring: {
      mfccSigma: num('mfccSigma'),
      octaveSlipLimit: num('octaveSlip'),
      pitchGateVoiced: num('pitchGate'),
    },
    gates: {
      roomTonePeak: num('roomTone'),
      silencePeak: num('silence'),
      flatRatio: num('flat'),
    },
    weights: {
      tonal: {
        pitch: num('wPitch'),
        mfcc: num('wMfcc'),
        energy: num('wEnergy'),
        timing: num('wTiming'),
      },
    },
  };
}

buildOptionsPanel();

$<HTMLButtonElement>('resetOpts').addEventListener('click', () => {
  buildOptionsPanel();
});

$<HTMLButtonElement>('copyOpts').addEventListener('click', async () => {
  const merged = resolveOptions(readOptions());
  await navigator.clipboard.writeText(JSON.stringify(merged, null, 2));
});

// ---------------------------------------------------------------------------
// Scoring + result rendering (the game's own meter design)
// ---------------------------------------------------------------------------

const result = $<HTMLElement>('result');

const KINDS_AR: Record<string, string> = {
  tonal: '🎵 Tonal',
  speech: '🗣️ Speech',
  noise: '👏 Noise',
};

const METER_META: Array<{ key: 'pitch' | 'timbre' | 'energy' | 'timing'; label: string }> = [
  { key: 'pitch', label: 'Melody' },
  { key: 'timbre', label: 'Timbre' },
  { key: 'energy', label: 'Energy' },
  { key: 'timing', label: 'Rhythm' },
];

const NOTE_AR: Record<string, string> = {
  ok: '',
  silent: 'Too quiet — that read as room tone, not a take. Get closer to the mic and speak up.',
  'empty-pitch': 'No stable pitch could be extracted from your take — try again with less dead air.',
  unreadable: 'Could not decode one of the recordings.',
};

function renderResult(scored: ScoreResult): void {
  const v = scored.verdict;

  $('total').textContent = String(v.total);
  $('kind').textContent = v.kind ? (KINDS_AR[v.kind] ?? v.kind) : '—';
  $('voiced').textContent = `${Math.round(scored.voicedPct * 100)}%`;

  const metersHost = $<HTMLElement>('meters');
  metersHost.innerHTML = '';
  for (const m of METER_META) {
    const value = v[m.key];
    if (value < 0) continue; // weight-0 axis for this clip kind — hidden like the game
    const row = document.createElement('div');
    row.className = 'meter';
    const fillClass = value >= 80 ? ' hi' : value < 50 ? ' lo' : '';
    row.innerHTML =
      `<div class="name">${m.label}</div>` +
      `<div class="track"><div class="fill${fillClass}" style="width:${value}%"></div></div>`;
    metersHost.appendChild(row);
  }

  const cHint = $<HTMLElement>('contourHint');
  const cv = $<HTMLCanvasElement>('contourCv');
  if (scored.targetPitch?.length && scored.playerPitch?.length) {
    cv.style.display = '';
    cHint.style.display = '';
    drawContours(cv, scored.targetPitch, scored.playerPitch);
  } else {
    cv.style.display = 'none';
    cHint.style.display = 'none';
  }

  const note = $('note');
  note.textContent = NOTE_AR[scored.note] ?? scored.note;

  result.classList.add('show');
  result.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

scoreBtn.addEventListener('click', () => {
  if (!target.wav || !attempt.wav) return;
  const options = readOptions();
  const scored = scorePcm(
    target.wav.mono,
    target.wav.sampleRate,
    attempt.wav.mono,
    attempt.wav.sampleRate,
    options,
  );
  renderResult(scored);
});
