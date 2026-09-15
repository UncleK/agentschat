import request from 'supertest';
import { randomUUID } from 'node:crypto';
import {
  createTestApplication,
  TestApplicationContext,
  typedValue,
} from '../support/test-app';
import { auditBody, AuditResponse } from './audit-response';
import { approveBinding } from './control-test-support';
import {
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { ClaimRequestEntity } from '../../src/database/entities/claim-request.entity';
import {
  ClaimRequestStatus,
  AgentDmAcceptanceMode,
} from '../../src/database/domain.enums';
import { PolicyService } from '../../src/modules/policy/policy.service';
import { AuthService } from '../../src/modules/auth/auth.service';
import { AgentsService } from '../../src/modules/agents/agents.service';

describe('ON product continuity with synthetic identities and private history', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  const api = () => request(ctx.app.getHttpServer());
  async function agent() {
    const b = auditBody(
      (
        await api()
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `continuity-${randomUUID().slice(0, 8)}`,
            displayName: 'Synthetic unbound',
          })
          .expect(201)
      ).body,
    );
    return auditBody(
      (
        await api()
          .post('/api/v1/agents/claim')
          .send({ claimToken: b.bootstrap.claimToken, pollingEnabled: true })
          .expect(201)
      ).body,
    );
  }
  async function human() {
    return registerHuman(
      ctx.app,
      `${randomUUID()}@example.test`,
      'Synthetic owner',
    );
  }
  async function binding(
    c: AuditResponse,
    h: Awaited<ReturnType<typeof human>>,
    target = true,
  ) {
    return auditBody(
      (
        await api()
          .post(
            target
              ? `/api/v1/agents/${c.agent.id}/claim-requests`
              : '/api/v1/agents/claim-requests',
          )
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(201)
      ).body,
    );
  }
  async function action(c: AuditResponse, type: string, payload: object) {
    const submitted = auditBody(
      (
        await api()
          .post('/api/v1/actions')
          .set('Authorization', `Bearer ${c.accessToken}`)
          .set('Idempotency-Key', randomUUID())
          .send({ type, payload })
          .expect(202)
      ).body,
    );
    const result = await waitForActionStatus(
      ctx.app,
      c.accessToken,
      submitted.id,
    );
    expect(result.status).toBe('succeeded');
  }
  it('ON-01/02/03/04: public social participation and poll/ACK survive same-identity binding with private history', async () => {
    const c = await agent();
    const peer = await agent();
    expect(await ctx.dataSource.getRepository(UserEntity).count()).toBe(0);
    await ctx.app.get(PolicyService).upsertAgentSafetyPolicy(peer.agent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await action(c, 'forum.topic.create', {
      title: 'Synthetic continuity',
      content: 'Retain original post',
    });
    await action(c, 'dm.send', {
      targetType: 'agent',
      targetId: peer.agent.id,
      content: 'PRIVATE synthetic history',
    });
    await action(c, 'agent.follow', {
      targetType: 'agent',
      targetId: peer.agent.id,
    });
    const poll = typedValue<{ deliveries: Array<{ deliveryId: string }> }>(
      (
        await api()
          .get('/api/v1/deliveries/poll?wait_seconds=0')
          .set('Authorization', `Bearer ${peer.accessToken}`)
          .expect(200)
      ).body,
    );
    expect(poll.deliveries.length).toBeGreaterThan(0);
    await api()
      .post('/api/v1/acks')
      .set('Authorization', `Bearer ${peer.accessToken}`)
      .send({ deliveryIds: poll.deliveries.map((d) => d.deliveryId) })
      .expect(201);
    const events = await ctx.dataSource
      .getRepository(EventEntity)
      .findBy({ actorAgentId: c.agent.id });
    const dm = events.find((e) => e.content === 'PRIVATE synthetic history')!;
    const deliveryIds = (
      await ctx.dataSource
        .getRepository(DeliveryEntity)
        .findBy({ eventId: dm.id })
    )
      .map((d) => d.id)
      .sort();
    const followIds = await ctx.dataSource.query<Array<{ id: string }>>(
      'SELECT id FROM follows WHERE follower_agent_id=$1 ORDER BY id',
      [c.agent.id],
    );
    const participants = await ctx.dataSource.query<Array<{ id: string }>>(
      'SELECT id FROM thread_participants WHERE agent_id=$1 ORDER BY id',
      [c.agent.id],
    );
    await ctx.dataSource
      .getRepository(AgentEntity)
      .update(c.agent.id, { isPublic: false });
    const h = await human();
    const stranger = await human();
    const url = `/api/v1/content/dm/threads/${dm.threadId}/messages?activeAgentId=${c.agent.id}`;
    await api()
      .get(url)
      .set('Authorization', `Bearer ${h.accessToken}`)
      .expect(403);
    const b = await binding(c, h);
    await approveBinding(
      ctx.app,
      h.accessToken,
      c.accessToken,
      c.agent.id,
      b.claimRequest.id,
      b.challengeToken,
    );
    const managed = await ctx.dataSource
      .getRepository(AgentEntity)
      .findOneByOrFail({ id: c.agent.id });
    expect(managed.ownerUserId).toBe(h.user.id);
    expect(managed.isPublic).toBe(false);
    expect(
      await ctx.dataSource
        .getRepository(EventEntity)
        .findBy({ actorAgentId: c.agent.id }),
    ).toEqual(events);
    expect(
      (
        await ctx.dataSource
          .getRepository(DeliveryEntity)
          .findBy({ eventId: dm.id })
      )
        .map((d) => d.id)
        .sort(),
    ).toEqual(deliveryIds);
    expect(
      await ctx.dataSource.query(
        'SELECT id FROM follows WHERE follower_agent_id=$1 ORDER BY id',
        [c.agent.id],
      ),
    ).toEqual(followIds);
    expect(
      await ctx.dataSource.query(
        'SELECT id FROM thread_participants WHERE agent_id=$1 ORDER BY id',
        [c.agent.id],
      ),
    ).toEqual(participants);
    await api()
      .get(url)
      .set('Authorization', `Bearer ${h.accessToken}`)
      .expect(200);
    await api()
      .get(url)
      .set('Authorization', `Bearer ${stranger.accessToken}`)
      .expect(403);
    await action(c, 'agent.profile.update', {
      bio: 'same credential resumed after bind',
    });
  });
  it('CL-03/ON-08: cancelled/rejected requests and revoked original credentials cannot bind', async () => {
    const c = await agent();
    const h = await human();
    for (const cancel of [true, false]) {
      const b = await binding(c, h);
      if (cancel)
        await api()
          .post(
            `/api/v1/agents/${c.agent.id}/claim-requests/${b.claimRequest.id}/cancel`,
          )
          .set('Authorization', `Bearer ${h.accessToken}`)
          .expect(200);
      else
        await ctx.dataSource
          .getRepository(ClaimRequestEntity)
          .update(b.claimRequest.id, { status: ClaimRequestStatus.Rejected });
      await api()
        .post(
          `/api/v1/agents/${c.agent.id}/claim-requests/${b.claimRequest.id}/confirm`,
        )
        .set('Authorization', `Bearer ${h.accessToken}`)
        .set('X-Agent-Control-Token', c.accessToken)
        .send({
          challengeToken: b.challengeToken,
          authorization: {
            purpose: 'bind_account',
            accountId: h.user.id,
            agentId: c.agent.id,
            approved: true,
          },
        })
        .expect(409);
    }
    const b = await binding(c, h);
    await ctx.dataSource
      .getRepository(AgentConnectionEntity)
      .update({ agentId: c.agent.id }, { tokenHash: 'synthetic-revoked' });
    await api()
      .get(
        `/api/v1/agents/${c.agent.id}/claim-requests/${b.claimRequest.id}/control-preview`,
      )
      .set('Authorization', `Bearer ${h.accessToken}`)
      .set('X-Agent-Control-Token', c.accessToken)
      .expect(401);
  });
  it('CL-04/ON-05: untargeted request racing across different agents selects one target once', async () => {
    const c = await agent();
    const other = await agent();
    const h = await human();
    const b = await binding(c, h, false);
    const results = await Promise.all(
      [c, other].map((target) =>
        api()
          .post(
            `/api/v1/agents/${target.agent.id}/claim-requests/${b.claimRequest.id}/confirm`,
          )
          .set('Authorization', `Bearer ${h.accessToken}`)
          .set('X-Agent-Control-Token', target.accessToken)
          .send({
            challengeToken: b.challengeToken,
            authorization: {
              purpose: 'bind_account',
              accountId: h.user.id,
              agentId: target.agent.id,
              approved: true,
            },
          }),
      ),
    );
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    const saved = await ctx.dataSource
      .getRepository(ClaimRequestEntity)
      .findOneByOrFail({ id: b.claimRequest.id });
    expect([c.agent.id, other.agent.id]).toContain(saved.agentId);
    expect(
      await ctx.dataSource
        .getRepository(AgentEntity)
        .countBy({ ownerUserId: h.user.id }),
    ).toBe(1);
  });
  it('ON-05 targeted requests retain their target in the database', async () => {
    const c = await agent();
    const h = await human();
    const b = await binding(c, h);
    expect(
      (
        await ctx.dataSource
          .getRepository(ClaimRequestEntity)
          .findOneByOrFail({ id: b.claimRequest.id })
      ).agentId,
    ).toBe(c.agent.id);
  });
  it('CL-02: a human session revoked after guard authentication is rejected inside the binding transaction', async () => {
    const c = await agent();
    const h = await human();
    const b = await binding(c, h);
    const principal = await ctx.app
      .get(AuthService)
      .authenticateHumanToken(h.accessToken);
    await ctx.dataSource
      .getRepository(UserEntity)
      .increment({ id: h.user.id }, 'authTokenVersion', 1);
    await expect(
      ctx.app
        .get(AgentsService)
        .confirmClaim(
          principal,
          c.agent.id,
          b.claimRequest.id,
          b.challengeToken,
          c.accessToken,
          {
            purpose: 'bind_account',
            accountId: h.user.id,
            agentId: c.agent.id,
            approved: true,
          },
        ),
    ).rejects.toThrow('session');
    expect(
      (
        await ctx.dataSource
          .getRepository(AgentEntity)
          .findOneByOrFail({ id: c.agent.id })
      ).ownerUserId,
    ).toBeNull();
  });
});
