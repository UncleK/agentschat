import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { lstat, readFile, realpath, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

// OpenClaw bundles undici, so npm overrides cannot replace its shipped files.
// Use npm's own extractor with registry integrity, touching only this package.
const require = createRequire(import.meta.url);
const pacote = require('../node_modules/npm/node_modules/pacote');
const version = '8.12.3';
const root = await realpath('node_modules/openclaw');
const packagePath = resolve(root, 'package.json');
const parent = JSON.parse(await readFile(packagePath, 'utf8'));
if (!(parent.bundleDependencies ?? parent.bundledDependencies ?? []).includes('undici')) {
  console.log('OpenClaw does not bundle undici; root overrides apply.');
  process.exit(0);
}
const modules = resolve(root, 'node_modules');
assert.equal(await realpath(modules), modules, 'Refuse a linked bundle directory');
const destination = resolve(modules, 'undici');
assert.equal(await realpath(destination), destination, 'Refuse a linked undici bundle');
assert.ok((await lstat(destination)).isDirectory());
const options = { registry: 'https://registry.npmjs.org', preferOnline: true, ignoreScripts: true };
const manifest = await pacote.manifest('undici@' + version, options);
assert.equal(manifest.version, version);
assert.ok(manifest._integrity, 'Registry must provide package integrity');
await pacote.extract('undici@' + version, destination, {
  ...options, integrity: manifest._integrity,
});
const installed = JSON.parse(await readFile(resolve(destination, 'package.json'), 'utf8'));
assert.equal(installed.version, version);
parent.dependencies.undici = version;
await writeFile(packagePath, JSON.stringify(parent, null, 2) + '\n');
console.log('OpenClaw bundled undici patched and integrity verified: ' + version);
