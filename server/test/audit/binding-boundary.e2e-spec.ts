import { auditBody, type AuditResponse } from './audit-response';
import request from 'supertest';
import { randomUUID } from 'node:crypto';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { ClaimRequestEntity } from '../../src/database/entities/claim-request.entity';
import { AuditLogEntity } from '../../src/database/entities/audit-log.entity';
import {
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';

describe('Audit v1.1 A binding and metadata boundaries', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  const api = () => request(ctx.app.getHttpServer());
  async function fixture() {
    const suffix = randomUUID().slice(0, 8);
    const bootstrap = await api()
      .post('/api/v1/agents/bootstrap/public')
      .send({ handle: `audit-${suffix}`, displayName: 'Synthetic audit agent' })
      .expect(201);
    const claim = await api()
      .post('/api/v1/agents/claim')
      .send({
        claimToken: auditBody(bootstrap.body).bootstrap.claimToken,
        pollingEnabled: true,
      })
      .expect(201);
    const human = await registerHuman(
      ctx.app,
      `${suffix}@example.com`,
      'Synthetic operator',
    );
    return {
      agentId: auditBody(claim.body).agent.id,
      agentToken: auditBody(claim.body).accessToken,
      human,
    };
  }
  async function binding(
    f: Awaited<ReturnType<typeof fixture>>,
    targeted = true,
  ) {
    return (
      await api()
        .post(
          targeted
            ? `/api/v1/agents/${f.agentId}/claim-requests`
            : '/api/v1/agents/claim-requests',
        )
        .set('Authorization', `Bearer ${f.human.accessToken}`)
        .expect(201)
    ).body as AuditResponse;
  }
  function approve(
    f: Awaited<ReturnType<typeof fixture>>,
    b: AuditResponse,
    token = f.agentToken,
    accountId = f.human.user.id,
  ) {
    return api()
      .post(
        `/api/v1/agents/${f.agentId}/claim-requests/${b.claimRequest.id}/confirm`,
      )
      .set('Authorization', `Bearer ${f.human.accessToken}`)
      .set('X-Agent-Control-Token', token)
      .send({
        challengeToken: b.challengeToken,
        authorization: {
          purpose: 'bind_account',
          accountId,
          agentId: f.agentId,
          approved: true,
        },
      });
  }
  it('CL-01: applicant challenge alone grants no ownership or history authority', async () => {
    const f = await fixture();
    const b = await binding(f);
    await api()
      .post(
        `/api/v1/agents/${f.agentId}/claim-requests/${b.claimRequest.id}/confirm`,
      )
      .set('Authorization', `Bearer ${f.human.accessToken}`)
      .send({ challengeToken: b.challengeToken })
      .expect(403);
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.agentId })
      ).ownerUserId,
    ).toBeNull();
  });
  it('CL-02/ON-05/ON-08: only the original credential plus explicit matching account approval can bind', async () => {
    const f = await fixture();
    const b = await binding(f);
    const other = await fixture();
    await approve(f, b, other.agentToken).expect(403);
    await approve(f, b, f.agentToken, other.human.user.id).expect(403);
    await approve(f, b, 'invalid').expect(401);
    await approve(f, b).expect(200);
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.agentId })
      ).ownerUserId,
    ).toBe(f.human.user.id);
  });
  it('CL-03/CL-04/ON-05: expiry, wrong challenge and replay fail; concurrent untargeted consumption binds once with one audit', async () => {
    const f = await fixture();
    const expired = await binding(f, false);
    await ctx.dataSource
      .getRepository(ClaimRequestEntity)
      .update(expired.claimRequest.id, { expiresAt: new Date(0) });
    await approve(f, expired).expect(409);
    const b = await binding(f, false);
    await approve(f, { ...b, challengeToken: 'wrong' }).expect(403);
    const results = await Promise.all([approve(f, b), approve(f, b)]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    await approve(f, b).expect(409);
    expect(
      await ctx.dataSource
        .getRepository(AuditLogEntity)
        .countBy({ action: 'agent.account_bound', entityId: f.agentId }),
    ).toBe(1);
  });
  it('ON-06: an unrelated pending applicant cannot reserve the target', async () => {
    const f = await fixture();
    await binding(f);
    const second = await fixture();
    const own = { ...f, human: second.human };
    const b = await binding(own);
    await approve(own, b).expect(200);
  });
  it('CL-02: social claim.confirm cannot grant management authority', async () => {
    const f = await fixture();
    const b = await binding(f);
    const submitted = await api()
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${f.agentToken}`)
      .set('Idempotency-Key', randomUUID())
      .send({
        type: 'claim.confirm',
        payload: {
          claimRequestId: b.claimRequest.id,
          challengeToken: b.challengeToken,
        },
      });
    if (submitted.status === 202) {
      const result = await waitForActionStatus(
        ctx.app,
        f.agentToken,
        auditBody(submitted.body).id,
      );
      expect(result.status).toBe('rejected');
    } else {
      expect(submitted.status).toBe(403);
    }
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.agentId })
      ).ownerUserId,
    ).toBeNull();
  });
  it.each([
    'emergencyStopForumResponses',
    'emergencyStopDmResponses',
    'emergencyStopLiveResponses',
    'dmRequiresMutualFollow',
    'avatarStorageKey',
    'owner',
    'platform',
    'storage',
  ])('MD-01/MD-02: rejects reserved public metadata %s', async (field) => {
    const f = await fixture();
    const submitted = await api()
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${f.agentToken}`)
      .set('Idempotency-Key', randomUUID())
      .send({
        type: 'agent.profile.update',
        payload: { profileMetadata: { [field]: false } },
      })
      .expect(202);
    expect(
      (
        await waitForActionStatus(
          ctx.app,
          f.agentToken,
          auditBody(submitted.body).id,
        )
      ).status,
    ).toBe('rejected');
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: f.agentId })
      ).profileMetadata[field],
    ).toBeUndefined();
  });
});
