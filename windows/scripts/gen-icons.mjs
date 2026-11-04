// Regenerates every app/icon asset from the canonical vector artwork.
//
//   design/perch.svg          — app icon (coral bird on dark gradient tile)
//   design/perch-menubar.svg  — menubar template (monochrome bird silhouette)
//
// Usage: cd windows && npm ci && node scripts/gen-icons.mjs
import sharp from 'sharp';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const appIconSvg = join(repoRoot, 'design', 'perch.svg');
const menubarSvg = join(repoRoot, 'design', 'perch-menubar.svg');
const appIconBuf = readFileSync(appIconSvg);
const menubarBuf = readFileSync(menubarSvg);

const render = (svg, size) =>
  sharp(svg, { density: 384 }).resize(size, size).png().toBuffer();

// ── Windows icons ─────────────────────────────────────────────────────────────
const winDir = join(repoRoot, 'windows', 'src-tauri', 'icons');
const win = [
  ['32x32.png', 32],
  ['128x128.png', 128],
  ['128x128@2x.png', 256],
  ['icon.png', 512],
];
for (const [name, size] of win) {
  writeFileSync(join(winDir, name), await render(appIconBuf, size));
  console.log(`icons/${name}`);
}

// ── ICO (PNG-in-ICO, Vista and later) ─────────────────────────────────────────
function encodeICO(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(entries.length, 4);
  const dir = Buffer.alloc(16 * entries.length);
  let offset = 6 + dir.length;
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
const icoSizes = [16, 24, 32, 48, 64, 128, 256];
const icoEntries = [];
for (const size of icoSizes) {
  icoEntries.push({ size, png: await render(appIconBuf, size) });
}
writeFileSync(join(winDir, 'icon.ico'), encodeICO(icoEntries));
console.log('icons/icon.ico');

// ── macOS AppIcon asset catalog ───────────────────────────────────────────────
const appDir = join(repoRoot, 'Perch', 'Assets.xcassets', 'AppIcon.appiconset');
const appIconFiles = [
  ['icon_16x16.png', 16], ['icon_16x16@2x.png', 32],
  ['icon_32x32.png', 32], ['icon_32x32@2x.png', 64],
  ['icon_128x128.png', 128], ['icon_128x128@2x.png', 256],
  ['icon_256x256.png', 256], ['icon_256x256@2x.png', 512],
  ['icon_512x512.png', 512], ['icon_512x512@2x.png', 1024],
];
for (const [name, size] of appIconFiles) {
  writeFileSync(join(appDir, name), await render(appIconBuf, size));
  console.log(`AppIcon ${name}`);
}

// ── Menubar template images (black silhouette, alpha) ─────────────────────────
const menuDir = join(repoRoot, 'Perch', 'Assets.xcassets', 'MenuBarIcon.imageset');
const menuIcon = (w, h) =>
  sharp(menubarBuf, { density: 384 })
    .resize(w, h, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toBuffer();
writeFileSync(join(menuDir, 'menubar.png'), await menuIcon(24, 18));
writeFileSync(join(menuDir, 'menubar@2x.png'), await menuIcon(48, 36));
writeFileSync(join(menuDir, 'menubar@3x.png'), await menuIcon(72, 54));
console.log('MenuBarIcon menubar*.png');

// ── Docs site favicon ─────────────────────────────────────────────────────────
const docsDir = join(repoRoot, 'docs', 'media');
mkdirSync(docsDir, { recursive: true });
writeFileSync(join(docsDir, 'icon.png'), await render(appIconBuf, 256));
console.log('docs/media/icon.png');

// The docs/media/logo.png wordmark is hand-drawn artwork (not generated).
// design/perch-social.svg renders the GitHub social preview at 1280x640.
const social = sharp(readFileSync(join(repoRoot, 'design', 'perch-social.svg')), {
  density: 384,
});
await social.resize(1280, 640).png().toFile(join(repoRoot, 'design', 'perch-social.png'));
console.log('design/perch-social.png');
