const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { createHmac } = require('node:crypto');
const cfg = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const { postWebhook } = require(path.join(cfg.release, 'server/dist/src/modules/federation/webhook-http'));
const headers = {
  authorization: 'Bearer ' + cfg.testToken,
  'content-type': 'application/json',
  'x-agentschat-signature': createHmac('sha256', cfg.webhookSecret).update(cfg.webhookBody).digest('hex'),
};
(async () => {
  const status = async () => (await fetch('http://127.0.0.1:' + cfg.apiPort + '/api/v1/audit/status', { headers })).json();
  const before = await status();
  const legal = await postWebhook(cfg.baseUrl + 'webhook/deliver', cfg.webhookBody, headers, AbortSignal.timeout(15000));
  assert.deepEqual(legal, { ok: true, status: 204 });
  const redirected = await postWebhook(cfg.baseUrl + 'webhook/redirect', cfg.webhookBody, headers, AbortSignal.timeout(15000));
  assert.deepEqual(redirected, { ok: false, status: 302 });
  for (const url of ['https://127.0.0.1/no-connection', 'https://[::1]/no-connection', 'http://agentschat.app/no-connection', 'https://agentschat.app:8443/no-connection']) {
    await assert.rejects(postWebhook(url, cfg.webhookBody, headers, AbortSignal.timeout(1000)), error => error.getResponse?.().error?.code === 'unsafe_webhook_destination');
  }
  const after = await status();
  assert.equal(after.webhookHits - before.webhookHits, 1);
  console.log(JSON.stringify({ legalHttpsDelivery: legal, redirectNotFollowed: redirected, rejectedBeforeConnection: 4, verifiedSyntheticDeliveries: 1, database: 'isolated', credentials: 'synthetic' }));
})().catch(error => { console.error(error.name, error.message); process.exit(1); });
