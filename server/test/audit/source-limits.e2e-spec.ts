import { createHmac } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';

describe('Audit C trusted sources and anonymous budgets', () => {
  let ctx: TestApplicationContext;
  const secret = 'synthetic-audit-proxy-secret-at-least-32-chars';
  const saved = {
    secret: process.env.BFF_PROXY_SECRET,
    peers: process.env.TRUSTED_PROXY_PEERS,
    limit: process.env.PUBLIC_BOOTSTRAP_SOURCE_LIMIT,
  };
  beforeAll(async () => {
    process.env.BFF_PROXY_SECRET = secret;
    process.env.TRUSTED_PROXY_PEERS = '127.0.0.1,::1';
    process.env.PUBLIC_BOOTSTRAP_SOURCE_LIMIT = '3';
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
    for (const [key, value] of Object.entries({
      BFF_PROXY_SECRET: saved.secret,
      TRUSTED_PROXY_PEERS: saved.peers,
      PUBLIC_BOOTSTRAP_SOURCE_LIMIT: saved.limit,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });
  function headers(ip: string, key = secret) {
    const source = Buffer.from(
      JSON.stringify({
        ip,
        method: 'POST',
        path: '/api/v1/agents/bootstrap/public',
        at: Date.now(),
      }),
    ).toString('base64url');
    return {
      'X-AgentsChat-Source': source,
      'X-AgentsChat-Source-Signature': createHmac('sha256', key)
        .update(source)
        .digest('hex'),
    };
  }
  function create(ip: string, suffix: string, key = secret) {
    return request(ctx.app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .set(headers(ip, key))
      .set('X-Forwarded-For', `192.0.2.${Math.floor(Math.random() * 200)}`)
      .send({
        handle: `limit-${suffix}`,
        displayName: 'Synthetic',
        installationId: suffix,
      });
  }
  it('RL-01/ON-10: signed BFF sources have independent public budgets despite installation resets', async () => {
    for (let i = 0; i < 3; i++)
      await create('203.0.113.1', `a${i}`).expect(201);
    await create('203.0.113.1', 'a-full').expect(429);
    await create('203.0.113.2', 'b-normal').expect(201);
  });
  it('RL-02/ON-10: forged source signatures and XFF share the actual peer budget', async () => {
    for (let i = 0; i < 3; i++)
      await create(`198.51.100.${i}`, `bad${i}`, 'attacker').expect(201);
    await create('198.51.100.99', 'bad-full', 'attacker').expect(429);
  });
});
