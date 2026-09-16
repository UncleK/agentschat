// Isolated canary: no production business tables, accounts, or credentials.
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { createHash, createHmac, timingSafeEqual } = require('node:crypto');
const cfg = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const dbUrl = new URL(cfg.databaseUrl);
if (!/^agentschat_audit_[a-f0-9]+$/.test(dbUrl.pathname.slice(1)) || dbUrl.username !== dbUrl.pathname.slice(1)) throw Error('Synthetic database required');
const { DataSource } = require(path.join(cfg.release, 'server/node_modules/typeorm'));
const { AuthRateLimitGuard } = require(path.join(cfg.release, 'server/dist/src/modules/auth/auth-rate-limit.guard'));
const { requestSource } = require(path.join(cfg.release, 'server/dist/src/modules/auth/request-source'));
process.env.BFF_PROXY_SECRET = cfg.bffSecret;
process.env.TRUSTED_PROXY_PEERS = '127.0.0.1,::1';
process.env.PUBLIC_BOOTSTRAP_SOURCE_LIMIT = '3';
const db = new DataSource({ type: 'postgres', url: cfg.databaseUrl });
let webhookHits = 0;
let server;
function json(res, status, value) {
  res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'private, no-store' });
  res.end(JSON.stringify(value));
}
(async () => {
  await db.initialize();
  await db.query('CREATE TABLE auth_request_limits (key_hash varchar(64) PRIMARY KEY, attempts integer NOT NULL, expires_at timestamptz NOT NULL)');
  const guard = new AuthRateLimitGuard(db, { auth: { jwtSecret: cfg.rateSecret } });
  server = http.createServer(async (req, res) => {
    try {
      if (req.headers.authorization !== 'Bearer ' + cfg.testToken) return json(res, 401, { error: 'synthetic authorization required' });
      const route = new URL(req.url, 'http://127.0.0.1').pathname;
      let body = '';
      for await (const chunk of req) {
        body += chunk.toString();
        if (body.length > 4096) return json(res, 413, {});
      }
      if (route === '/api/v1/audit/status' && req.method === 'GET') return json(res, 200, { ready: true, webhookHits });
      if (route === '/api/v1/audit/webhook/redirect' && req.method === 'POST') {
        res.writeHead(302, { location: 'https://127.0.0.1/agentschat-audit-must-not-connect', 'cache-control': 'no-store' });
        return res.end();
      }
      if (route === '/api/v1/audit/webhook/deliver' && req.method === 'POST') {
        const signature = req.headers['x-agentschat-signature'] || '';
        const expected = createHmac('sha256', cfg.webhookSecret).update(body).digest('hex');
        if (body !== cfg.webhookBody || signature.length !== expected.length || !timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return json(res, 400, { error: 'synthetic signature/body mismatch' });
        webhookHits++;
        res.writeHead(204, { 'cache-control': 'no-store' });
        return res.end();
      }
      if (route !== '/api/v1/audit/bootstrap/public' || req.method !== 'POST') return json(res, 404, {});
      req.path = route;
      req.body = JSON.parse(body || '{}');
      req.header = (name) => req.headers[name.toLowerCase()];
      const sourceHash = createHash('sha256').update(requestSource(req)).digest('hex');
      try {
        await guard.canActivate({ switchToHttp: () => ({ getRequest: () => req, getResponse: () => res }) });
        return json(res, 201, { synthetic: true, sourceHash });
      } catch (error) {
        return json(res, error.getStatus?.() || 500, { synthetic: true, sourceHash });
      }
    } catch (error) {
      json(res, 500, { error: error.name });
    }
  });
  server.listen(cfg.apiPort, '127.0.0.1', () => console.log(JSON.stringify({ ready: true, port: cfg.apiPort })));
})().catch(error => { console.error(error.name, error.message); process.exit(1); });
async function stop() { if (server) await new Promise(resolve => server.close(resolve)); if (db.isInitialized) await db.destroy(); process.exit(0); }
process.on('SIGTERM', stop);
process.on('SIGINT', stop);
