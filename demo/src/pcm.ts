/**
 * pcm.ts — turning raw audio bytes into sample arrays.
 *
 * Sound, for this library, is just an array of numbers between -1 and 1
 * ("samples"), plus a sample rate: how many of those numbers describe one
 * second of audio. 44100 Hz = 44100 numbers per second — the CD standard.
 *
 * A WAV file stores those numbers in a tiny container:
 *
 *   "RIFF" .... "WAVE" "fmt " <format info> "data" <the samples>
 *
 * We read that container ourselves so the library has ZERO dependencies in
 * Node. In the browser you rarely need this: `AudioContext.decodeAudioData()`
 * already gives you a `Float32Array` + sampleRate for any format (MP3, OGG…).
 */

/**
 * PCM samples can be a Float32Array (what the browser decoder gives us),
 * a Float64Array (what our WAV parser gives — full double precision), or a
 * plain number[] (also full precision). All internal math reads these the
 * same way.
 */
export type Pcm = Float32Array | Float64Array | number[];

/** Decoded audio: samples in -1..1 for one mono channel, plus sample rate. */
export interface WavData {
  mono: Pcm;
  sampleRate: number;
}

/**
 * Parse a PCM WAV file (8 or 16 bit, mono or stereo) into mono samples.
 * Returns null when the bytes are not a readable WAV.
 */
export function parseWav(bytes: Uint8Array): WavData | null {
  if (bytes.length < 44) return null;
  // "RIFF"
  if (bytes[0] !== 0x52 || bytes[1] !== 0x49 || bytes[2] !== 0x46 || bytes[3] !== 0x46) {
    return null;
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

  const channels = view.getUint16(22, true);
  const sampleRate = view.getUint32(24, true);
  const bits = view.getUint16(34, true);
  if (channels <= 0 || sampleRate <= 0 || (bits !== 8 && bits !== 16)) {
    return null;
  }

  // The "data" chunk can live anywhere after the header (some writers put
  // extra chunks before it), so we scan for its four magic bytes.
  let dataStart = -1;
  let dataLen = 0;
  for (let i = 12; i + 8 < bytes.length; i++) {
    if (
      bytes[i] === 0x64 && // d
      bytes[i + 1] === 0x61 && // a
      bytes[i + 2] === 0x74 && // t
      bytes[i + 3] === 0x61 // a
    ) {
      dataStart = i + 8;
      dataLen = view.getUint32(i + 4, true);
      break;
    }
  }
  if (dataStart < 0) return null;
  dataLen = Math.min(dataLen, bytes.length - dataStart);

  const frameBytes = channels * (bits >> 3);
  const frames = Math.floor(dataLen / frameBytes);
  if (frames === 0) return null;

  const mono = new Float64Array(frames);
  for (let f = 0; f < frames; f++) {
    let sum = 0;
    for (let ch = 0; ch < channels; ch++) {
      const off = dataStart + f * frameBytes + ch * (bits >> 3);
      if (bits === 16) {
        sum += view.getInt16(off, true) / 32768.0;
      } else {
        sum += (view.getUint8(off) - 128) / 128.0;
      }
    }
    mono[f] = sum / channels;
  }
  return { mono, sampleRate };
}

/** Encode samples as a 16-bit mono PCM WAV (the inverse of parseWav). */
export function writeWav(mono: Pcm, sampleRate: number): Uint8Array {
  const dataLen = mono.length * 2;
  const out = new Uint8Array(44 + dataLen);
  const view = new DataView(out.buffer);

  const ascii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) out[offset + i] = text.charCodeAt(i);
  };

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataLen, true);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  ascii(36, 'data');
  view.setUint32(40, dataLen, true);

  for (let i = 0; i < mono.length; i++) {
    const s = Math.max(-1, Math.min(1, mono[i]));
    view.setInt16(44 + i * 2, Math.round(s * 32767), true);
  }
  return out;
}

/**
 * Scale samples in memory so the loudest sample hits `target` (e.g. 0.5).
 * Digital silence stays silent. Returns a new array; the input is untouched.
 * This is the in-memory twin of a "normalize the audio file" step — same
 * math, but we never touch the disk. Pass target = 0 to skip.
 */
export function normalizePeak(mono: Pcm, target: number): Pcm {
  if (target <= 0) return mono;
  let peak = 0;
  for (let i = 0; i < mono.length; i++) {
    const a = Math.abs(mono[i]!);
    if (a > peak) peak = a;
  }
  if (peak <= 0) return mono;
  const gain = target / peak;
  if (gain > 0.99 && gain < 1.01) return mono;
  const out = new Float64Array(mono.length);
  for (let i = 0; i < mono.length; i++) {
    out[i] = Math.max(-1, Math.min(1, mono[i]! * gain));
  }
  return out;
}

/**
 * Browser helper: turn a Blob (MP3/OGG/WAV…) into `WavData` using the
 * browser's own decoder. Returns null when decoding fails.
 */
export async function decodeBlobToPcm(blob: Blob, audioCtx?: AudioContext): Promise<WavData | null> {
  try {
    const ctx = audioCtx ?? new AudioContext();
    const buffer = await ctx.decodeAudioData(await blob.arrayBuffer());
    const mono = buffer.getChannelData(0);
    return { mono, sampleRate: buffer.sampleRate };
  } catch {
    return null;
  }
}