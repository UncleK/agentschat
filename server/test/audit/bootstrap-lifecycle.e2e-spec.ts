import request from 'supertest';
import { randomBytes, randomUUID } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { auditBody } from './audit-response';
import { registerHuman } from '../federation/support/federation-test-support';
import { approveBinding } from './control-test-support';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { FederationService } from '../../src/modules/federation/federation.service';

describe('RR-02 bootstrap lifecycle (HTTP/PostgreSQL)', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  const api = () => request(ctx.app.getHttpServer());
  const proof = () => randomBytes(32).toString('hex');
  async function bootstrap() {
    return auditBody(
      (
        await api()
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `boot-${randomUUID().slice(0, 8)}`,
            displayName: 'Synthetic bootstrap',
          })
          .expect(201)
      ).body,
    ).bootstrap;
  }
  const claim = (claimToken: string, recoveryKey?: string) =>
    api()
      .post('/api/v1/agents/claim')
      .send({ claimToken, pollingEnabled: true, recoveryKey });
  const alive = (token: string) =>
    api()
      .get('/api/v1/agents/self/safety-policy')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
  it('RR2-01 used bootstrap without the independent recovery proof cannot reset a connection', async () => {
    const b = await bootstrap();
    const c = auditBody((await claim(b.claimToken).expect(201)).body);
    await claim(b.claimToken).expect(409);
    await alive(c.accessToken);
  });
  it('RR2-01 lost response recovery returns the same credential only for the original proof and parameters', async () => {
    const b = await bootstrap();
    const key = proof();
    const c = auditBody((await claim(b.claimToken, key).expect(201)).body);
    const retry = auditBody((await claim(b.claimToken, key).expect(201)).body);
    expect(retry.accessToken).toBe(c.accessToken);
    await claim(b.claimToken, proof()).expect(409);
    await api()
      .post('/api/v1/agents/claim')
      .send({
        claimToken: b.claimToken,
        recoveryKey: key,
        pollingEnabled: true,
        capabilities: { changed: true },
      })
      .expect(409);
    await alive(c.accessToken);
  });
  it('RR2-02 rotation permanently rejects bootstrap recovery as well as old-link replay', async () => {
    const b = await bootstrap();
    const key = proof();
    const c = auditBody((await claim(b.claimToken, key).expect(201)).body);
    const rotated = auditBody(
      (
        await api()
          .post('/api/v1/agents/token/rotate')
          .set('Authorization', `Bearer ${c.accessToken}`)
          .expect(200)
      ).body,
    );
    await claim(b.claimToken, key).expect(409);
    await claim(b.claimToken).expect(409);
    await alive(rotated.accessToken);
  });
  it('RR2-03 disconnect rejects old initialization; authorized owner recovery keeps the same identity', async () => {
    const b = await bootstrap();
    const key = proof();
    const c = auditBody((await claim(b.claimToken, key).expect(201)).body);
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Owner',
    );
    const binding = auditBody(
      (
        await api()
          .post(`/api/v1/agents/${c.agent.id}/claim-requests`)
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    await approveBinding(
      ctx.app,
      h.accessToken,
      c.accessToken,
      c.agent.id,
      binding.claimRequest.id,
      binding.challengeToken,
    );
    await api()
      .post('/api/v1/agents/connections/disconnect-all')
      .set('Authorization', `Bearer ${h.accessToken}`)
      .expect(200);
    await claim(b.claimToken, key).expect(409);
    const recovered = auditBody(
      (
        await api()
          .post(`/api/v1/agents/${c.agent.id}/connection-invitation`)
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    await claim(b.claimToken).expect(409);
    const next = auditBody(
      (await claim(recovered.invitation.claimToken, proof()).expect(201)).body,
    );
    expect(next.agent.id).toBe(c.agent.id);
    expect(next.agent.ownerType).toBe('human');
    await alive(next.accessToken);
  });
  it('RR2-04 concurrent initializers consume once and cannot return competing credentials', async () => {
    const b = await bootstrap();
    const results = await Promise.all([
      claim(b.claimToken, proof()),
      claim(b.claimToken, proof()),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([201, 409]);
    const winner = results.find((r) => r.status === 201)!;
    await alive(auditBody(winner.body).accessToken);
    const rows = await ctx.dataSource.query<Array<{ count: string }>>(
      'SELECT count(*) FROM agent_connections WHERE agent_id=$1',
      [b.agent.id],
    );
    expect(rows[0].count).toBe('1');
  });
  it('RR2-02 rotation rechecks a credential authenticated before a concurrent revocation', async () => {
    const b = await bootstrap();
    const c = auditBody((await claim(b.claimToken).expect(201)).body);
    const stale = await ctx.app
      .get(FederationCredentialsService)
      .authenticateAgentToken(c.accessToken);
    await api()
      .post('/api/v1/agents/token/rotate')
      .set('Authorization', `Bearer ${c.accessToken}`)
      .expect(200);
    await expect(
      ctx.app.get(FederationService).rotateAgentToken(stale),
    ).rejects.toMatchObject({
      response: {
        error: {
          code: 'invalid_agent_token',
          message: 'The control credential was revoked.',
        },
      },
    });
  });
});
