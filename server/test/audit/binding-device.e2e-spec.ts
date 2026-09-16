import request from 'supertest';
import { randomUUID } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { auditBody } from './audit-response';
import {
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';
import { AgentEntity } from '../../src/database/entities/agent.entity';

describe('RR-03/04 browser-to-controller one-use authorization', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  const api = () => request(ctx.app.getHttpServer());
  async function fixture() {
    const b = auditBody(
      (
        await api()
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `device-${randomUUID().slice(0, 8)}`,
            displayName: 'Device Agent',
          })
          .expect(201)
      ).body,
    );
    const c = auditBody(
      (
        await api()
          .post('/api/v1/agents/claim')
          .send({ claimToken: b.bootstrap.claimToken, pollingEnabled: true })
          .expect(201)
      ).body,
    );
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Browser owner',
    );
    const binding = auditBody(
      (
        await api()
          .post('/api/v1/agents/claim-requests')
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
    const startBody = {
      requestId: binding.claimRequest.id,
      challengeToken: binding.challengeToken,
    };
    const device = auditBody(
      (
        await api()
          .post('/api/v1/binding-devices')
          .set('Authorization', `Bearer ${c.accessToken}`)
          .send(startBody)
          .expect(201)
      ).body,
    );
    const authorization = {
      purpose: 'bind_account',
      accountId: h.user.id,
      agentId: c.agent.id,
      requestId: binding.claimRequest.id,
      approved: true,
    };
    return { c, h, binding, device, authorization, startBody };
  }
  it('RR4-02 browser approval alone cannot bind; explicit controller approval consumes once', async () => {
    const { c, h, binding, device, authorization } = await fixture();
    const finish = () =>
      api()
        .post(`/api/v1/binding-devices/${device.id}/confirm`)
        .set('Authorization', `Bearer ${c.accessToken}`)
        .send({
          deviceSecret: device.deviceSecret,
          challengeToken: binding.challengeToken,
          authorization,
        });
    await finish().expect(403);
    await api()
      .post(`/api/v1/binding-devices/browser/${device.userCode}/approve`)
      .set('Authorization', `Bearer ${h.accessToken}`)
      .send(authorization)
      .expect(200);
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: c.agent.id })
      ).ownerUserId,
    ).toBeNull();
    await finish().expect(200);
    await finish().expect(409);
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: c.agent.id })
      ).ownerUserId,
    ).toBe(h.user.id);
  });
  it('RR3-02/RR4-02 rejects other accounts, mismatched purpose/target, wrong secret, expiry and revoked sessions', async () => {
    const { c, h, binding, device, authorization } = await fixture();
    const otherController = await fixture();
    await api()
      .post(`/api/v1/binding-devices/${device.id}/poll`)
      .set('Authorization', `Bearer ${otherController.c.accessToken}`)
      .send({ deviceSecret: device.deviceSecret })
      .expect(403);
    const other = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Other',
    );
    const approve = (token: string, body: object) =>
      api()
        .post(`/api/v1/binding-devices/browser/${device.userCode}/approve`)
        .set('Authorization', `Bearer ${token}`)
        .send(body);
    await approve(other.accessToken, authorization).expect(403);
    await approve(h.accessToken, { ...authorization, purpose: 'login' }).expect(
      403,
    );
    await approve(h.accessToken, {
      ...authorization,
      agentId: randomUUID(),
    }).expect(403);
    await approve(h.accessToken, authorization).expect(200);
    const finish = (secret: string) =>
      api()
        .post(`/api/v1/binding-devices/${device.id}/confirm`)
        .set('Authorization', `Bearer ${c.accessToken}`)
        .send({
          deviceSecret: secret,
          challengeToken: binding.challengeToken,
          authorization,
        });
    await finish('wrong').expect(403);
    await ctx.dataSource.query(
      'UPDATE users SET auth_token_version=auth_token_version+1 WHERE id=$1',
      [h.user.id],
    );
    await finish(device.deviceSecret).expect(403);
    await ctx.dataSource.query(
      "UPDATE binding_devices SET expires_at=now()-interval '1 minute' WHERE id=$1",
      [device.id],
    );
    await finish(device.deviceSecret).expect(409);
    const action = auditBody(
      (
        await api()
          .post('/api/v1/actions')
          .set('Authorization', `Bearer ${c.accessToken}`)
          .set('Idempotency-Key', randomUUID())
          .send({
            type: 'claim.confirm',
            payload: {
              claimRequestId: binding.claimRequest.id,
              challengeToken: binding.challengeToken,
            },
          })
          .expect(202)
      ).body,
    );
    expect(
      (await waitForActionStatus(ctx.app, c.accessToken, action.id)).status,
    ).toBe('rejected');
  });
  it('RR4-02 concurrent terminal confirmations consume one grant and produce one binding audit', async () => {
    const { c, h, binding, device, authorization } = await fixture();
    await api()
      .post(`/api/v1/binding-devices/browser/${device.userCode}/approve`)
      .set('Authorization', `Bearer ${h.accessToken}`)
      .send(authorization)
      .expect(200);
    const finish = () =>
      api()
        .post(`/api/v1/binding-devices/${device.id}/confirm`)
        .set('Authorization', `Bearer ${c.accessToken}`)
        .send({
          deviceSecret: device.deviceSecret,
          challengeToken: binding.challengeToken,
          authorization,
        });
    const results = await Promise.all([finish(), finish()]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    const rows = await ctx.dataSource.query<Array<{ status: string }>>(
      'SELECT status FROM binding_devices WHERE id=$1',
      [device.id],
    );
    expect(rows[0].status).toBe('consumed');
    const audits = await ctx.dataSource.query<Array<{ count: string }>>(
      "SELECT count(*) FROM audit_logs WHERE entity_id=$1 AND action='agent.account_bound'",
      [c.agent.id],
    );
    expect(audits[0].count).toBe('1');
  });
});
