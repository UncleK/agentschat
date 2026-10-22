import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';

// npm's bundled packages ignore root overrides and lockfile version pins.
// CI applies these patches after every clean install and checks the real files.
const patched = {
  'brace-expansion': '5.0.12',
  'http-cache-semantics': '4.3.0',
  'ip-address': '10.7.1',
  'postcss-selector-parser': '7.1.6',
  undici: '6.28.1',
};
const mode = process.argv[2];
assert.ok(['repair', 'verify', 'verify-installed'].includes(mode), 'Expected repair, verify, or verify-installed');
const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));

if (mode === 'repair') {
  for (const [name, version] of Object.entries(patched)) {
    const entry = lock.packages[`node_modules/npm/node_modules/${name}`];
    assert.equal(entry?.version, version, `Install ${name}@${version} before repairing the lock`);
    delete entry.inBundle;
  }
  const pending = Object.entries(lock.packages).filter(([path, entry]) =>
    path && !entry.link && (!entry.resolved || !entry.integrity));
  await Promise.all(Array.from({ length: 8 }, async () => {
    while (pending.length) {
      const [path, entry] = pending.pop();
      const name = path.slice(path.lastIndexOf('node_modules/') + 'node_modules/'.length);
      const response = await fetch(`https://registry.npmjs.org/${encodeURIComponent(name)}/${encodeURIComponent(entry.version)}`, {
        signal: AbortSignal.timeout(60_000),
      });
      assert.ok(response.ok, `Registry metadata ${name}@${entry.version}: ${response.status}`);
      const metadata = await response.json();
      assert.equal(metadata.version, entry.version);
      assert.ok(metadata.dist?.tarball && metadata.dist?.integrity, `Missing distribution metadata for ${name}`);
      entry.resolved = metadata.dist.tarball;
      entry.integrity = metadata.dist.integrity;
    }
  }));
  await writeFile('package-lock.json', `${JSON.stringify(lock, null, 2)}\n`);
}

for (const [path, entry] of Object.entries(lock.packages)) {
  if (!path || entry.link || entry.inBundle) continue;
  assert.ok(entry.resolved && entry.integrity, `Missing content verification: ${path}`);
}
for (const [name, version] of Object.entries(patched)) {
  const path = `node_modules/npm/node_modules/${name}`;
  assert.equal(lock.packages[path]?.version, version);
  assert.ok(!lock.packages[path].inBundle, `${path} must replace the bundled copy`);
  if (mode === 'verify-installed') {
    assert.equal(JSON.parse(await readFile(`${path}/package.json`, 'utf8')).version, version,
      `${path}: clean installation restored a vulnerable bundled copy`);
  }
}
console.log(`Plugin dependency lock ${mode}: verified`);
