// Draws Pip into the PNG/ICO set Tauri needs. No dependencies: the icons are
// rasterised here and encoded with node:zlib, so the app icon stays "drawn in
// code" like the character itself.
//
// NOTE: this still renders the ancestor's blob silhouette — replace the body
// and eyes with your own Pip design (see LICENSE-ASSETS.md).
//
//   node scripts/gen-icons.mjs

import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "src-tauri", "icons");

// ── Pip ───────────────────────────────────────────────────────────────────────

const BASE_TOP = [255, 250, 245]; // #FFFAF5
const BASE_BOTTOM = [221, 204, 191]; // #DDCCBF
const INK = [26, 20, 18]; // #1A1412
const RIM = [0, 0, 0];

const SS = 4; // supersampling factor

/** Superellipse (exponent 2.7) test in body-local coordinates. */
function insideBody(x, y, rx, ry) {
  const n = 2.7;
  return Math.pow(Math.abs(x / rx), n) + Math.pow(Math.abs(y / ry), n) <= 1;
}

function insidePill(x, y, w, h) {
  const hw = w / 2;
  const hh = h / 2;
  const r = Math.min(hw, hh);
  const cx = Math.max(-hw + r, Math.min(hw - r, x));
  const cy = Math.max(-hh + r, Math.min(hh - r, y));
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

function renderPip(size) {
  const px = new Uint8Array(size * size * 4);
  const R = size * 0.3;
  const rx = R * 1.14;
  const ry = R * 0.88;
  const cx = size / 2;
  const cy = size / 2 + R * 0.06;
  const rim = R * 0.055; // dark outline so the tray icon reads on light themes

  // Head tuft — two small feathers splayed outward (same geometry as the engines)
  const feathers = [-1, 1].map((sd) => ({
    cx: cx + sd * rx * 0.16,
    cy: cy - ry - R * 0.16,
    w: R * 0.26,
    h: R * 0.55,
    ang: sd * -0.38,
  }));
  const insideFeather = (px0, py0, f, grow) => {
    const dx = px0 - f.cx;
    const dy = py0 - f.cy;
    const c = Math.cos(-f.ang);
    const s = Math.sin(-f.ang);
    const qx = dx * c - dy * s;
    const qy = dx * s + dy * c;
    const a = f.w / 2 + grow;
    const b = f.h / 2 + grow;
    return (qx / a) ** 2 + (qy / b) ** 2 <= 1;
  };
  const inTuft = (px0, py0, grow) => feathers.some((f) => insideFeather(px0, py0, f, grow));

  // Belly patch — soft light oval low on the body
  const belly = { cx, cy: cy + ry * 0.425, rx: rx * 0.55, ry: ry * 0.375 };
  const inBelly = (px0, py0) =>
    ((px0 - belly.cx) / belly.rx) ** 2 + ((py0 - belly.cy) / belly.ry) ** 2 <= 1;

  // Eyes — same geometry as the engines (tall ovals, close set)
  const eyeYaw = 0.335;
  const eyePitch = -0.12;
  const cp = Math.cos(eyePitch);
  const ex = Math.sin(eyeYaw) * cp * rx;
  const ey = -Math.sin(eyePitch) * ry;
  const fx = Math.max(0.18, Math.cos(eyeYaw));
  const fy = Math.max(0.18, cp);
  const ew = R * 0.22 * fx;
  const eh = R * 0.33 * fy;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let bodyHits = 0;
      let rimHits = 0;
      let eyeHits = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const px0 = x + (sx + 0.5) / SS - cx;
          const py0 = y + (sy + 0.5) / SS - cy;
          if (!insideBody(px0, py0, rx + rim, ry + rim) && !inTuft(px0, py0, rim)) continue;
          rimHits++;
          if (!insideBody(px0, py0, rx, ry) && !inTuft(px0, py0, 0)) continue;
          bodyHits++;
          if (
            insidePill(px0 + ex, py0 - ey, ew, eh) ||
            insidePill(px0 - ex, py0 - ey, ew, eh)
          ) {
            eyeHits++;
          }
        }
      }
      if (rimHits === 0) continue;

      const total = SS * SS;
      const rimA = rimHits / total;
      const bodyA = bodyHits / total;
      const eyeA = eyeHits / total;

      // Body gradient: top-right → bottom-left, like the Canvas gradient.
      const t = Math.min(1, Math.max(0, ((x - cx) * -0.6 + (y - cy) * 0.8) / (2 * ry) + 0.5));
      let body = [0, 1, 2].map((i) => BASE_TOP[i] + (BASE_BOTTOM[i] - BASE_TOP[i]) * t);

      // Belly patch lightens the lower body (pixel-centre test, scaled by coverage)
      const bellyOn =
        inBelly(x + 0.5 - cx, y + 0.5 - cy) && insideBody(x + 0.5 - cx, y + 0.5 - cy, rx, ry);
      if (bellyOn) body = body.map((c) => c + (255 - c) * 0.3 * (bodyA / rimA));

      // rim under body, body over rim, eyes over body
      let col = RIM.slice();
      let alpha = rimA;
      if (bodyA > 0) {
        col = col.map((c, i) => c * (1 - bodyA / rimA) + body[i] * (bodyA / rimA));
        alpha = rimA;
      }
      if (eyeA > 0) {
        col = col.map((c, i) => c * (1 - eyeA) + INK[i] * eyeA);
      }

      const o = (y * size + x) * 4;
      px[o] = Math.round(col[0]);
      px[o + 1] = Math.round(col[1]);
      px[o + 2] = Math.round(col[2]);
      px[o + 3] = Math.round(Math.min(1, alpha) * 255);
    }
  }
  return px;
}

// ── PNG ───────────────────────────────────────────────────────────────────────

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function encodePNG(size, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const raw = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    Buffer.from(rgba.buffer, y * size * 4, size * 4).copy(raw, y * (size * 4 + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ── ICO (PNG-in-ICO, Vista and later) ─────────────────────────────────────────

function encodeICO(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(entries.length, 4);
  const dir = Buffer.alloc(16 * entries.length);
  let offset = header.length + dir.length;
  entries.forEach((e, i) => {
    const o = i * 16;
    dir[o] = e.size >= 256 ? 0 : e.size;
    dir[o + 1] = e.size >= 256 ? 0 : e.size;
    dir[o + 2] = 0;
    dir[o + 3] = 0;
    dir.writeUInt16LE(1, o + 4);
    dir.writeUInt16LE(32, o + 6);
    dir.writeUInt32LE(e.png.length, o + 8);
    dir.writeUInt32LE(offset, o + 12);
    offset += e.png.length;
  });
  return Buffer.concat([header, dir, ...entries.map((e) => e.png)]);
}

// ── Menubar silhouette (template image: solid shape, eyes knocked out) ───────

function renderSilhouette(w, h) {
  const px = new Uint8Array(w * h * 4);
  const R = Math.min(w, h) * 0.3;
  const rx = R * 1.14;
  const ry = R * 0.88;
  const cx = w / 2;
  const cy = h / 2 + R * 0.06;
  const feathers = [-1, 1].map((sd) => ({
    cx: cx + sd * rx * 0.16,
    cy: cy - ry - R * 0.16,
    w: R * 0.26,
    h: R * 0.55,
    ang: sd * -0.38,
  }));
  const inFeather = (px0, py0, f) => {
    const dx = px0 - f.cx;
    const dy = py0 - f.cy;
    const c = Math.cos(-f.ang);
    const s = Math.sin(-f.ang);
    const qx = dx * c - dy * s;
    const qy = dx * s + dy * c;
    return (qx / (f.w / 2)) ** 2 + (qy / (f.h / 2)) ** 2 <= 1;
  };
  const eyeYaw = 0.335;
  const ex = Math.sin(eyeYaw) * rx;
  const ey = R * 0.12;
  const ew = R * 0.22;
  const eh = R * 0.33;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px0 = x + 0.5 - cx;
      const py0 = y + 0.5 - cy;
      const inShape =
        insideBody(px0, py0, rx, ry) || feathers.some((f) => inFeather(px0, py0, f));
      if (!inShape) continue;
      const inEye =
        insidePill(px0 + ex, py0 - ey, ew, eh) || insidePill(px0 - ex, py0 - ey, ew, eh);
      if (inEye) continue;
      const o = (y * w + x) * 4;
      px[o] = px[o + 1] = px[o + 2] = 0;
      px[o + 3] = 255;
    }
  }
  return px;
}

// ── Go ────────────────────────────────────────────────────────────────────────

mkdirSync(OUT, { recursive: true });

const png = (size) => encodePNG(size, renderPip(size));

const files = {
  "32x32.png": png(32),
  "128x128.png": png(128),
  "128x128@2x.png": png(256),
  "icon.png": png(512),
};
for (const [name, data] of Object.entries(files)) {
  writeFileSync(join(OUT, name), data);
  console.log(`${name} — ${data.length} bytes`);
}

const ico = encodeICO([16, 24, 32, 48, 64, 128, 256].map((size) => ({ size, png: png(size) })));
writeFileSync(join(OUT, "icon.ico"), ico);
console.log(`icon.ico — ${ico.length} bytes`);

// macOS asset catalog + site icon, from the same renderer
const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const appIcon = join(repoRoot, "Perch", "Assets.xcassets", "AppIcon.appiconset");
for (const [name, size] of [
  ["icon_16x16.png", 16], ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32], ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128], ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256], ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512], ["icon_512x512@2x.png", 1024],
]) {
  writeFileSync(join(appIcon, name), png(size));
  console.log(`AppIcon ${name}`);
}
writeFileSync(join(repoRoot, "docs", "media", "icon.png"), png(256));
console.log("docs/media/icon.png");

// Menubar template images (match the committed aspect: 24x18 base)
const menuBar = join(repoRoot, "Perch", "Assets.xcassets", "MenuBarIcon.imageset");
const sil = (w, h) => {
  // encodePNG is square-only; build the small rect directly
  const rgba = renderSilhouette(w, h);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.alloc(h * (w * 4 + 1));
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
};
writeFileSync(join(menuBar, "menubar.png"), sil(24, 18));
writeFileSync(join(menuBar, "menubar@2x.png"), sil(48, 36));
writeFileSync(join(menuBar, "menubar@3x.png"), sil(72, 54));
console.log("menubar silhouettes");
