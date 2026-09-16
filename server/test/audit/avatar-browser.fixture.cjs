// Synthetic-only browser fixture. Run from server with ts-node/register.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { randomUUID } = require('node:crypto');
require('../setup-env');
const { createMigratedTestDataSource, dropTestDatabase } = require('../support/test-database');
const { NestFactory } = require('@nestjs/core');
const { DataSource } = require('typeorm');
const { AgentEntity } = require('../../src/database/entities/agent.entity');
const { AssetStorageService } = require('../../src/modules/assets/asset-storage.service');
const { onePixelPngBuffer } = require('../assets/support/image-upload-test-support');

(async () => {
  assert.equal(new URL(process.env.DATABASE_URL).hostname, '127.0.0.1');
  assert.equal(new URL(process.env.DATABASE_URL).port, '55439');
  assert.equal(process.env.MINIO_PORT, '55440');
  const migration = await createMigratedTestDataSource();
  const databaseUrl = migration.options.url;
  await migration.destroy();
  process.env.DATABASE_URL = databaseUrl;
  const { AppModule } = require('../../src/app.module');
  const app = await NestFactory.create(AppModule, { logger: ['error', 'warn'] });
  app.setGlobalPrefix('api/v1');
  let canaryHits = 0;
  const active = '<svg xmlns="http://www.w3.org/2000/svg"><script>window.CANARY="executed";fetch("/canary")</script></svg>';
  app.getHttpAdapter().get('/canary', (_req, res) => { canaryHits++; res.end('synthetic'); });
  app.getHttpAdapter().get('/canary-status', (_req, res) => res.json({ canaryHits }));
  app.getHttpAdapter().get('/control.svg', (_req, res) => res.type('image/svg+xml').send(active));
  let fixture;
  app.getHttpAdapter().get('/fixture', (_req, res) => res.json(fixture));
  app.getHttpAdapter().get('/harness', (_req, res) => res.type('html').send(
    `<html><title>AV-02 synthetic avatar harness</title><img id="legal" src="${fixture.legal}"><img id="legacy" src="${fixture.legacyRaster}"></html>`,
  ));
  await app.listen(55441, '127.0.0.1');
  const base = 'http://127.0.0.1:55441';
  const post = async (path, body, token) => {
    const r = await fetch(base + path, { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
    assert.ok(r.ok, `${path}: ${r.status}`);
    return r.json();
  };
  const connected = async () => {
    const b = await post('/api/v1/agents/bootstrap/public', { handle: `browser-${randomUUID().slice(0, 8)}`, displayName: 'Synthetic browser audit' });
    return post('/api/v1/agents/claim', { claimToken: b.bootstrap.claimToken, pollingEnabled: true });
  };
  const c = await connected();
  const upload = await post('/api/v1/agents/self/avatar-upload', { fileName: 'legal.png', mimeType: 'image/png' }, c.accessToken);
  assert.ok((await fetch(upload.upload.url, { method: 'PUT', body: onePixelPngBuffer, headers: { 'content-type': 'image/png' } })).ok);
  const complete = await post('/api/v1/agents/self/avatar-upload/complete', {}, c.accessToken);
  fixture = { legal: complete.avatarUrl, rejected: [] };
  const repository = app.get(DataSource).getRepository(AgentEntity);
  const storage = app.get(AssetStorageService);
  for (const [name, bytes, mimeType] of [
    ['svg', Buffer.from(active), 'image/svg+xml'],
    ['disguised-png', Buffer.from(active), 'image/png'],
    ['html', Buffer.from('<html><script>window.CANARY="executed";fetch("/canary")</script></html>'), 'text/html'],
    ['legacy-raster', Buffer.concat([onePixelPngBuffer, Buffer.from(active)]), 'image/png'],
  ]) {
    const target = await connected();
    const key = `agent-avatars/${target.agent.id}/legacy-${name}.png`;
    await storage.writeObject({ bucket: process.env.MINIO_BUCKET, key, body: bytes, mimeType });
    await repository.update(target.agent.id, { profileMetadata: { avatarStorageBucket: process.env.MINIO_BUCKET, avatarStorageKey: key, avatarMimeType: mimeType } });
    const url = `/api/v1/agents/${target.agent.id}/avatar`;
    if (name === 'legacy-raster') fixture.legacyRaster = url;
    else fixture.rejected.push(url);
  }
  console.log(JSON.stringify({ ready: true, base, fixture }));
  const close = async () => { await app.close(); await dropTestDatabase(databaseUrl); process.exit(0); };
  process.on('SIGINT', close);
  process.on('SIGTERM', close);
  // A local sentinel permits graceful shutdown from PowerShell on Windows.
  const timer = setInterval(() => { if (fs.existsSync(process.env.AVATAR_FIXTURE_STOP)) { clearInterval(timer); void close(); } }, 500);
})().catch((error) => { console.error(error); process.exitCode = 1; });
