import request from 'supertest';
import { randomUUID } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { registerHuman } from '../federation/support/federation-test-support';
import { auditBody } from './audit-response';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { ClaimRequestEntity } from '../../src/database/entities/claim-request.entity';
const readStatus = (response: { body: unknown }) =>
  (response.body as { status: string }).status;

describe('Private OpenClaw binding invitation', () => {
  let ctx: TestApplicationContext;
  const api = () => request(ctx.app.getHttpServer());
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => ctx.close());
  async function fixture() {
    const h = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Invitation Owner',
    );
    const boot = auditBody(
      (
        await api()
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: 'invite-' + randomUUID().slice(0, 8),
            displayName: 'Invitation Agent',
          })
          .expect(201)
      ).body,
    );
    const c = auditBody(
      (
        await api()
          .post('/api/v1/agents/claim')
          .send({ claimToken: boot.bootstrap.claimToken, pollingEnabled: true })
          .expect(201)
      ).body,
    );
    const claim = auditBody(
      (
        await api()
          .post('/api/v1/agents/claim-requests')
          .set('Authorization', `Bearer ${h.accessToken}`)
          .send({ expiresInMinutes: 60 })
          .expect(201)
      ).body,
    );
    const status = () =>
      api()
        .get(
          `/api/v1/binding-devices/invitations/${claim.claimRequest.id}/status`,
        )
        .set('Authorization', `Bearer ${h.accessToken}`);
    const preview = () =>
      api()
        .post(
          `/api/v1/binding-devices/invitations/${claim.claimRequest.id}/preview`,
        )
        .set('Authorization', `Bearer ${c.accessToken}`)
        .send({ challengeToken: claim.challengeToken });
    return { h, c, claim, status, preview };
  }
  async function bind(f: Awaited<ReturnType<typeof fixture>>) {
    const device = auditBody(
      (
        await api()
          .post('/api/v1/binding-devices')
          .set('Authorization', `Bearer ${f.c.accessToken}`)
          .send({
            requestId: f.claim.claimRequest.id,
            challengeToken: f.claim.challengeToken,
          })
          .expect(201)
      ).body,
    );
    const authorization = {
      purpose: 'bind_account',
      accountId: f.h.user.id,
      agentId: f.c.agent.id,
      requestId: f.claim.claimRequest.id,
      approved: true,
    };
    expect(readStatus(await f.status().expect(200))).toBe('awaiting_browser');
    await api()
      .post(`/api/v1/binding-devices/browser/${device.userCode}/approve`)
      .set('Authorization', `Bearer ${f.h.accessToken}`)
      .send(authorization)
      .expect(200);
    expect(readStatus(await f.status().expect(200))).toBe(
      'awaiting_controller',
    );
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.c.agent.id })
      ).ownerUserId,
    ).toBeNull();
    await api()
      .post(`/api/v1/binding-devices/${device.id}/confirm`)
      .set('Authorization', `Bearer ${f.c.accessToken}`)
      .send({
        deviceSecret: device.deviceSecret,
        challengeToken: f.claim.challengeToken,
        authorization,
      })
      .expect(200);
  }
  it('prepares one identity, preserves both confirmations and rereads actual ownership', async () => {
    const f = await fixture();
    expect(readStatus(await f.status().expect(200))).toBe('pending');
    const p: unknown = (await f.preview().expect(200)).body;
    expect(p).toMatchObject({
      status: 'ready',
      agentId: f.c.agent.id,
      accountId: f.h.user.id,
    });
    expect(JSON.stringify(p)).not.toContain(f.claim.challengeToken);
    await bind(f);
    expect((await f.status().expect(200)).body).toMatchObject({
      status: 'bound',
      agent: { id: f.c.agent.id },
    });
    expect(readStatus(await f.preview().expect(200))).toBe('bound');
    const agent = await ctx.dataSource
      .getRepository(AgentEntity)
      .findOneByOrFail({ id: f.c.agent.id });
    expect(agent.ownerUserId).toBe(f.h.user.id);
  });
  it('only the requesting human can read status, and invalid controller challenges cannot prepare', async () => {
    const f = await fixture();
    const other = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Other Owner',
    );
    await api()
      .get(
        `/api/v1/binding-devices/invitations/${f.claim.claimRequest.id}/status`,
      )
      .expect(401);
    await api()
      .get(
        `/api/v1/binding-devices/invitations/${f.claim.claimRequest.id}/status`,
      )
      .set('Authorization', `Bearer ${other.accessToken}`)
      .expect(403);
    await api()
      .post(
        `/api/v1/binding-devices/invitations/${f.claim.claimRequest.id}/preview`,
      )
      .set('Authorization', `Bearer ${f.c.accessToken}`)
      .send({ challengeToken: 'wrong' })
      .expect(403);
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.c.agent.id })
      ).ownerUserId,
    ).toBeNull();
  });
  it('expired invitations stay expired, and another account cannot take over an already-bound Agent', async () => {
    const expired = await fixture();
    await ctx.dataSource
      .getRepository(ClaimRequestEntity)
      .update(expired.claim.claimRequest.id, {
        expiresAt: new Date(Date.now() - 1000),
      });
    await expired.preview().expect(409);
    expect(readStatus(await expired.status().expect(200))).toBe('expired');
    const f = await fixture();
    await bind(f);
    const other = await registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Other Owner',
    );
    const different = auditBody(
      (
        await api()
          .post('/api/v1/agents/claim-requests')
          .set('Authorization', `Bearer ${other.accessToken}`)
          .expect(201)
      ).body,
    );
    await api()
      .post(
        `/api/v1/binding-devices/invitations/${different.claimRequest.id}/preview`,
      )
      .set('Authorization', `Bearer ${f.c.accessToken}`)
      .send({ challengeToken: different.challengeToken })
      .expect(409);
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.c.agent.id })
      ).ownerUserId,
    ).toBe(f.h.user.id);
  });
  it('a new link for the same owner reports the existing binding without creating another identity', async () => {
    const f = await fixture();
    await bind(f);
    const next = auditBody(
      (
        await api()
          .post('/api/v1/agents/claim-requests')
          .set('Authorization', `Bearer ${f.h.accessToken}`)
          .expect(201)
      ).body,
    );
    const p: unknown = (
      await api()
        .post(
          `/api/v1/binding-devices/invitations/${next.claimRequest.id}/preview`,
        )
        .set('Authorization', `Bearer ${f.c.accessToken}`)
        .send({ challengeToken: next.challengeToken })
        .expect(200)
    ).body;
    expect(p).toMatchObject({ status: 'bound', agentId: f.c.agent.id });
    expect(
      (
        await api()
          .get(
            `/api/v1/binding-devices/invitations/${next.claimRequest.id}/status`,
          )
          .set('Authorization', `Bearer ${f.h.accessToken}`)
          .expect(200)
      ).body,
    ).toMatchObject({ status: 'bound', agent: { id: f.c.agent.id } });
  });
});
