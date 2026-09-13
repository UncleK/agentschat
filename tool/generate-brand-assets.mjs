// Native assets are compiled from one approved vector; do not edit derivatives.
// Run: node tool/generate-brand-assets.mjs (after npm ci in web/).
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(resolve(root, 'web/package.json'));
const sharp = require('sharp');
const master = await readFile(resolve(root, 'brand/agentschat-mark.svg'), 'utf8');
const paths = [...master.matchAll(/<path d="([^"]+)"\s*\/>/g)].map(m => m[1]);
if (paths.length !== 3) throw new Error('Brand master must contain three bubble paths.');
const cyan = '#00BCD4';
const ink = '#11161C';
const body = paths.map(d => `<path d="${d}"/>`).join('');
const wrap = (content, width = 1024, height = width) => `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">${content}</svg>`;
const mark = (color = cyan, x = 0, y = 0, width = 256) => `<svg x="${x}" y="${y}" width="${width}" height="${width * 234 / 256}" viewBox="0 0 256 234" fill="${color}">${body}</svg>`;
const tile = (rounded = false) => wrap(`<rect width="1024" height="1024" rx="${rounded ? 224 : 0}" fill="${ink}"/>${mark('#FFFFFF', 152, 183, 720)}`);
const outputs = [];
async function save(path, value) {
  const target = resolve(root, path);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, value);
  outputs.push(path);
}
async function png(path, svg, size, opaque = false) {
  let output = sharp(Buffer.from(svg), { density: 192 }).resize(size, size, { fit: 'contain', background: '#00000000' });
  if (opaque) output = output.flatten({ background: ink });
  await save(path, await output.png().toBuffer());
}
async function ico(path, svg) {
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const images = await Promise.all(sizes.map(s => sharp(Buffer.from(svg), { density: 192 }).resize(s, s).png().toBuffer()));
  const header = Buffer.alloc(6 + sizes.length * 16);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  sizes.forEach((s, i) => {
    const at = 6 + i * 16;
    header[at] = s === 256 ? 0 : s;
    header[at + 1] = s === 256 ? 0 : s;
    header.writeUInt16LE(1, at + 4);
    header.writeUInt16LE(32, at + 6);
    header.writeUInt32LE(images[i].length, at + 8);
    header.writeUInt32LE(offset, at + 12);
    offset += images[i].length;
  });
  await save(path, Buffer.concat([header, ...images]));
}

await save('web/lib/brand-paths.ts', `// Generated from brand/agentschat-mark.svg. Run node tool/generate-brand-assets.mjs.\nexport const brandViewBox = "0 0 256 234";\nexport const brandPaths = ${JSON.stringify(paths, null, 2)} as const;\n`);
for (const [name, color] of [['cyan', cyan], ['white', '#FFFFFF'], ['black', ink]]) {
  await save(`web/public/brand/mark-${name}.svg`, wrap(mark(color), 256, 234));
  await png(`web/public/brand/mark-${name}.png`, wrap(mark(color), 256, 234), 512);
}
await save('web/public/icon.svg', wrap(mark(cyan, 0, 11), 256));
await ico('web/public/favicon.ico', wrap(mark(cyan, 0, 11), 256));
for (const size of [16, 32]) await png(`web/public/favicon-${size}.png`, wrap(mark(cyan, 0, 11), 256), size);
await png('web/public/apple-touch-icon.png', tile(), 180, true);
for (const size of [192, 512]) await png(`web/public/brand/app-icon-${size}.png`, tile(), size, true);
// Maskable icons need a smaller mark than regular icons, inside the central safe circle.
await png('web/public/brand/app-icon-maskable-512.png', wrap(`<rect width="1024" height="1024" fill="${ink}"/>${mark('#FFFFFF', 222, 247, 580)}`), 512, true);
await png('app/assets/brand/agentschat_mark.png', wrap(mark(cyan), 256, 234), 512);
await png('app/assets/brand/agentschat_mark_white.png', wrap(mark('#FFFFFF'), 256, 234), 512);
await png('app/assets/brand/agentschat_app_icon_1024.png', tile(), 1024, true);
await ico('app/windows/runner/resources/app_icon.ico', tile(true));

const res = 'app/android/app/src/main/res';
for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  await png(`${res}/mipmap-${density}/ic_launcher.png`, tile(true), size);
}
const vectorPaths = paths.map(d => `    <path android:fillColor="#FFFFFF" android:pathData="${d}"/>`).join('\n');
// 108dp layer, artwork fits in the central 66dp safe circle (including its corners).
await save(`${res}/drawable/ic_launcher_foreground.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">\n  <group android:scaleX="0.22" android:scaleY="0.22" android:translateX="25.84" android:translateY="28.26">\n${vectorPaths}\n  </group>\n</vector>\n`);
await save(`${res}/values/brand_colors.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="brand_background">${ink}</color></resources>\n`);
await save(`${res}/mipmap-anydpi-v26/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n  <background android:drawable="@color/brand_background"/>\n  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n</adaptive-icon>\n`);
await save(`${res}/mipmap-anydpi-v33/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n  <background android:drawable="@color/brand_background"/>\n  <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n  <monochrome android:drawable="@drawable/ic_launcher_foreground"/>\n</adaptive-icon>\n`);
const launchXml = `<?xml version="1.0" encoding="utf-8"?>\n<layer-list xmlns:android="http://schemas.android.com/apk/res/android">\n  <item android:drawable="@color/brand_background"/>\n  <item android:width="112dp" android:height="112dp" android:gravity="center" android:drawable="@drawable/ic_launcher_foreground"/>\n</layer-list>\n`;
await save(`${res}/drawable/launch_background.xml`, launchXml);
await save(`${res}/drawable-v21/launch_background.xml`, launchXml);

const catalog = 'app/ios/Runner/Assets.xcassets';
const iconSet = JSON.parse(await readFile(resolve(root, `${catalog}/AppIcon.appiconset/Contents.json`), 'utf8'));
const seen = new Set();
for (const image of iconSet.images) {
  if (!image.filename || seen.has(image.filename)) continue;
  seen.add(image.filename);
  const size = Math.round(parseFloat(image.size) * parseFloat(image.scale));
  await png(`${catalog}/AppIcon.appiconset/${image.filename}`, tile(), size, true);
}
for (const [suffix, scale] of [['', 1], ['@2x', 2], ['@3x', 3]]) {
  await png(`${catalog}/LaunchImage.imageset/LaunchImage${suffix}.png`, wrap(mark('#FFFFFF', 40, 48, 176), 256), 168 * scale);
}

const og = wrap(`<rect width="1200" height="630" fill="${ink}"/>${mark(cyan, 80, 58, 68)}<text x="164" y="105" fill="#FFFFFF" font-family="Arial,sans-serif" font-size="38" font-weight="700">agentschat<tspan fill="${cyan}">.</tspan></text><text x="80" y="280" fill="#FFFFFF" font-family="Arial,sans-serif" font-size="80" font-weight="700">A world beyond</text><text x="80" y="375" fill="${cyan}" font-family="Arial,sans-serif" font-size="80" font-weight="700">the prompt.</text><text x="80" y="535" fill="#ABB5C4" font-family="Arial,sans-serif" font-size="25">A shared world for humans and autonomous agents.</text>${mark(cyan, 850, 178, 275)}`, 1200, 630);
await save('web/public/og.svg', og);
const hero = wrap(`<rect width="1408" height="768" rx="36" fill="${ink}"/>${mark(cyan, 860, 180, 400)}<text x="76" y="128" fill="${cyan}" font-family="Arial,sans-serif" font-size="30">agentschat.app</text><text x="76" y="315" fill="#FFFFFF" font-family="Arial,sans-serif" font-size="86" font-weight="700">agentschat<tspan fill="${cyan}">.</tspan></text><text x="80" y="411" fill="#E2E8F0" font-family="Arial,sans-serif" font-size="35">Let intelligences meet.</text><text x="80" y="465" fill="#E2E8F0" font-family="Arial,sans-serif" font-size="35">Let conversations happen.</text><text x="80" y="654" fill="#A7B3C2" font-family="Arial,sans-serif" font-size="25">Four voices. One conversation.</text>`, 1408, 768);
await save('docs/readme/hero-homepage.png', await sharp(Buffer.from(hero)).png().toBuffer());
// Existing README preview badges also share the canonical mark.
for (const name of ['hall', 'dm', 'forum', 'live']) {
  const path = `docs/readme/preview-${name}.svg`;
  let svg = await readFile(resolve(root, path), 'utf8');
  svg = svg.replace(/<circle cx="94" cy="93" r="6" fill="#00DAF3"\/>|<svg data-brand-badge="true"[\s\S]*?<\/svg>/, mark(cyan, 81, 80, 24).replace('<svg ', '<svg data-brand-badge="true" '));
  await save(path, svg);
}
await save('brand/asset-manifest.json', JSON.stringify({ source: 'brand/agentschat-mark.svg', colors: { cyan, ink }, intentionalDetail: 'The lower-right bubble has two tips; preserve both.', files: outputs }, null, 2) + '\n');
console.log(`Generated ${outputs.length} brand assets from the approved three-bubble mark.`);
