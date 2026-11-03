#!/usr/bin/env node
// Generates Perch's 28 notification sounds from scratch — no dependencies,
// no samples, everything synthesized here with plain oscillators.
//
//   node scripts/gen-sounds.mjs
//
// Writes 16-bit mono 44.1 kHz WAVs into ../Perch/Resources/sounds/.
// Each sound is a small original motif (base frequency, intervals, envelope,
// vibrato). Nothing is copied from the ancestor's files — these replace them.

import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SR = 44100;
const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "Perch", "Resources", "sounds");

// A note: constant frequency, or a slide from f0 to f1 across its duration.
function tone(buf, { at = 0, dur = 0.1, f0 = 440, f1 = null, gain = 0.5, type = "sine" }) {
  const n0 = Math.floor(at * SR);
  const n = Math.floor(dur * SR);
  const attack = Math.max(1, Math.floor(0.006 * SR));
  for (let i = 0; i < n; i++) {
    const t = i / SR;
    const k = i / n;
    const f = f1 == null ? f0 : f0 + (f1 - f0) * k;
    let v;
    if (type === "triangle") v = (2 / Math.PI) * Math.asin(Math.sin(2 * Math.PI * f * t));
    else if (type === "square") v = Math.sign(Math.sin(2 * Math.PI * f * t)) * 0.6;
    else v = Math.sin(2 * Math.PI * f * t);
    // simple envelope: 6 ms attack, exponential-ish release
    const env = Math.min(1, i / attack) * Math.pow(1 - k, 1.6);
    const idx = n0 + i;
    if (idx < buf.length) buf[idx] += v * gain * env;
  }
}

// Frequency wobble applied as a second detuned voice (cheap chorus shimmer).
function shimmer(buf, opts, detune = 4) {
  tone(buf, opts);
  tone(buf, { ...opts, f0: opts.f0 + detune, f1: opts.f1 == null ? null : opts.f1 + detune, gain: (opts.gain ?? 0.5) * 0.4 });
}

function noiseBurst(buf, { at = 0, dur = 0.08, gain = 0.4, lowpass = 0.2 }) {
  const n0 = Math.floor(at * SR);
  const n = Math.floor(dur * SR);
  let last = 0;
  for (let i = 0; i < n; i++) {
    const w = Math.random() * 2 - 1;
    last = last + lowpass * (w - last); // one-pole lowpass
    const k = i / n;
    const env = Math.pow(1 - k, 2);
    const idx = n0 + i;
    if (idx < buf.length) buf[idx] += last * gain * env;
  }
}

function make(dur) {
  return new Float64Array(Math.ceil(dur * SR));
}

function toWav(samples) {
  let peak = 0;
  for (const s of samples) peak = Math.max(peak, Math.abs(s));
  const norm = peak > 0 ? 0.89 / peak : 1;
  const data = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i] * norm));
    data.writeInt16LE(Math.round(v * 32767), i * 2);
  }
  const head = Buffer.alloc(44);
  head.write("RIFF", 0);
  head.writeUInt32LE(36 + data.length, 4);
  head.write("WAVE", 8);
  head.write("fmt ", 12);
  head.writeUInt32LE(16, 16);
  head.writeUInt16LE(1, 20); // PCM
  head.writeUInt16LE(1, 22); // mono
  head.writeUInt32LE(SR, 24);
  head.writeUInt32LE(SR * 2, 28);
  head.writeUInt16LE(2, 32);
  head.writeUInt16LE(16, 34);
  head.write("data", 36);
  head.writeUInt32LE(data.length, 40);
  return Buffer.concat([head, data]);
}

// Note names → Hz (A4 = 440)
const N = (midi) => 440 * Math.pow(2, (midi - 69) / 12);
const C5 = 72, D5 = 74, E5 = 76, F5 = 77, G5 = 79, A5 = 81, B5 = 83, C6 = 84;
const G4 = 67, A4 = 69, B4 = 71, E4 = 64, D4 = 62, C4 = 60;

const RECIPES = {
  annoyed: (b) => { tone(b, { dur: 0.09, f0: 300, f1: 260, type: "square", gain: 0.4 }); tone(b, { at: 0.1, dur: 0.09, f0: 280, f1: 240, type: "square", gain: 0.4 }); },
  blip: (b) => tone(b, { dur: 0.07, f0: 880, gain: 0.5 }),
  open: (b) => { tone(b, { dur: 0.09, f0: N(E5), gain: 0.45 }); tone(b, { at: 0.08, dur: 0.12, f0: N(A5), gain: 0.45 }); },
  close: (b) => { tone(b, { dur: 0.09, f0: N(A5), gain: 0.4 }); tone(b, { at: 0.08, dur: 0.12, f0: N(E5), gain: 0.4 }); },
  hover: (b) => shimmer(b, { dur: 0.14, f0: 660, gain: 0.3 }),
  peek: (b) => tone(b, { dur: 0.11, f0: 600, f1: 920, gain: 0.45 }),
  greet: (b) => { tone(b, { dur: 0.1, f0: N(C5), gain: 0.4 }); tone(b, { at: 0.09, dur: 0.1, f0: N(E5), gain: 0.4 }); tone(b, { at: 0.18, dur: 0.16, f0: N(G5), gain: 0.45 }); },
  work: (b) => { tone(b, { dur: 0.06, f0: 220, type: "triangle", gain: 0.5 }); tone(b, { at: 0.09, dur: 0.06, f0: 233, type: "triangle", gain: 0.5 }); },
  think: (b) => { tone(b, { dur: 0.4, f0: 330, f1: 360, gain: 0.35 }); tone(b, { at: 0.2, dur: 0.2, f0: 495, gain: 0.2 }); },
  search: (b) => tone(b, { dur: 0.3, f0: 400, f1: 1250, gain: 0.35 }),
  approval: (b) => { tone(b, { dur: 0.12, f0: 880, gain: 0.5 }); tone(b, { at: 0.11, dur: 0.16, f0: N(D5 + 12), gain: 0.5 }); },
  approve: (b) => tone(b, { dur: 0.16, f0: 660, f1: 990, gain: 0.5 }),
  error: (b) => tone(b, { dur: 0.3, f0: 185, f1: 150, type: "square", gain: 0.4 }),
  finish: (b) => { tone(b, { dur: 0.12, f0: N(C5), gain: 0.4 }); tone(b, { at: 0.1, dur: 0.12, f0: N(E5), gain: 0.4 }); tone(b, { at: 0.2, dur: 0.12, f0: N(G5), gain: 0.4 }); tone(b, { at: 0.3, dur: 0.22, f0: N(C6), gain: 0.45 }); },
  rate: (b) => { for (let i = 0; i < 4; i++) tone(b, { at: i * 0.11, dur: 0.09, f0: i % 2 ? 520 : 700, type: "triangle", gain: 0.45 }); },
  question: (b) => tone(b, { dur: 0.26, f0: 500, f1: 810, gain: 0.45 }),
  dizzy: (b) => { tone(b, { dur: 0.6, f0: 800, f1: 190, gain: 0.4 }); tone(b, { dur: 0.6, f0: 806, f1: 196, gain: 0.25 }); },
  love: (b) => { tone(b, { dur: 0.3, f0: N(C5), gain: 0.35 }); tone(b, { dur: 0.3, f0: N(G4), gain: 0.35 }); },
  proud: (b) => { tone(b, { dur: 0.11, f0: N(G4), gain: 0.42 }); tone(b, { at: 0.1, dur: 0.11, f0: N(C5), gain: 0.42 }); tone(b, { at: 0.2, dur: 0.2, f0: N(E5), gain: 0.46 }); },
  wink: (b) => tone(b, { dur: 0.1, f0: 920, f1: 690, gain: 0.45 }),
  yawn: (b) => tone(b, { dur: 0.55, f0: 400, f1: 240, gain: 0.35 }),
  sleep: (b) => { tone(b, { dur: 0.25, f0: N(A4), gain: 0.3 }); tone(b, { at: 0.22, dur: 0.3, f0: N(E4), gain: 0.3 }); },
  slap: (b) => { noiseBurst(b, { dur: 0.07, gain: 0.55 }); tone(b, { at: 0.02, dur: 0.1, f0: 160, f1: 90, gain: 0.5 }); },
  tick: (b) => tone(b, { dur: 0.035, f0: 1250, gain: 0.4 }),
  pop: (b) => tone(b, { dur: 0.08, f0: 320, f1: 940, gain: 0.5 }),
  gulp: (b) => tone(b, { dur: 0.2, f0: 520, f1: 150, type: "triangle", gain: 0.5 }),
  send: (b) => { tone(b, { dur: 0.2, f0: 620, f1: 1450, gain: 0.35 }); noiseBurst(b, { dur: 0.2, gain: 0.12, lowpass: 0.4 }); },
  attach: (b) => { tone(b, { dur: 0.05, f0: 700, gain: 0.5 }); tone(b, { at: 0.07, dur: 0.07, f0: 1050, gain: 0.5 }); },
};

mkdirSync(OUT, { recursive: true });
let total = 0;
for (const [name, recipe] of Object.entries(RECIPES)) {
  const buf = make(0.9);
  recipe(buf);
  // trim trailing silence
  let end = buf.length;
  while (end > 0 && Math.abs(buf[end - 1]) < 0.004) end--;
  end = Math.min(buf.length, end + Math.floor(0.03 * SR));
  const wav = toWav(buf.slice(0, end));
  writeFileSync(join(OUT, `${name}.wav`), wav);
  total += wav.length;
  console.log(`${name}.wav — ${(end / SR).toFixed(2)}s`);
}
console.log(`${Object.keys(RECIPES).length} sounds, ${(total / 1024).toFixed(0)} KB total`);
