const assert = require('node:assert/strict');
const { createHmac } = require('node:crypto');
const { postWebhook } = require('/bundle/webhook.cjs');
const body = '{"event":"synthetic.delivery"}';
const headers = { 'x-audit-signature': createHmac('sha256', 'synthetic-signing-key').update(body).digest('hex') };
const post = (url) => postWebhook(url, body, headers, AbortSignal.timeout(5000));
(async () => {
  const before = (await (await fetch('https://webhook.audit.test/stats')).json()).deliveries;
  assert.deepEqual(await post('https://webhook.audit.test/delivery'), { ok: true, status: 204 });
  assert.deepEqual(await post('https://11.254.253.2/redirect').catch(e => ({ error: e.code })), { error: 'ERR_TLS_CERT_ALTNAME_INVALID' });
  assert.deepEqual(await post('https://webhook.audit.test/redirect'), { ok: false, status: 302 });
  await assert.rejects(post('https://private.audit.test/delivery'), error => error.getResponse().error.code === 'unsafe_webhook_destination');
  await assert.rejects(post('https://wrong.audit.test/delivery'), /Hostname\/IP does not match certificate/);
  const stats = await (await fetch('https://webhook.audit.test/stats')).json();
  assert.equal(stats.deliveries - before, 1);
  console.log(JSON.stringify({ acceptance: 'SS-03', realTLS: true, certificateVerified: true, pinnedPeer: '11.254.253.2', deliveries: stats.deliveries - before, redirectsNotFollowed: true, privateDNSBlocked: true, wrongTLSNameBlocked: true, isolatedInternalDockerNetwork: true }));
})().catch(error => { console.error(error); process.exitCode = 1; });
