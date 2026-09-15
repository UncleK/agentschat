import { auditBody, type AuditResponse } from './audit-response';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { FederationService } from '../../src/modules/federation/federation.service';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import { FederationActionEntity } from '../../src/database/entities/federation-action.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import {
  EventActorType,
  EventContentType,
  FederationActionStatus,
  ThreadContextType,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import { waitForActionStatus } from '../federation/support/federation-test-support';

describe('Audit D durable work and atomic deliveries', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  async function agent() {
    const b = await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        handle: `durable-${randomUUID().slice(0, 8)}`,
        displayName: 'Synthetic',
      })
      .expect(201);
    return (
      await request(ctx.app.getHttpServer())
        .post('/api/v1/agents/claim')
        .send({
          claimToken: auditBody(b.body).bootstrap.claimToken,
          pollingEnabled: true,
        })
        .expect(201)
    ).body as AuditResponse;
  }
  it.each([FederationActionStatus.Accepted, FederationActionStatus.Processing])(
    'AQ-01/AQ-02 recovers persisted %s without an in-memory enqueue',
    async (status) => {
      const c = await agent();
      const repo = ctx.dataSource.getRepository(FederationActionEntity);
      const action = await repo.save(
        repo.create({
          agentId: c.agent.id,
          actionType: 'agent.profile.update',
          status,
          idempotencyKey: randomUUID(),
          requestHash: 'synthetic',
          payload: { bio: 'recovered durably' },
          processingStartedAt: new Date(0),
        }),
      );
      const result = await waitForActionStatus(
        ctx.app,
        c.accessToken,
        action.id,
        ['succeeded'],
        4000,
      );
      expect(result.status).toBe('succeeded');
    },
  );
  it('AQ-03 rolls back business effects when execution fails after the handler returns', async () => {
    const c = await agent();
    const service = ctx.app.get(FederationService);
    const execute = service['executeAction'].bind(service);
    const spy = jest
      .spyOn(
        service as unknown as { executeAction: typeof execute },
        'executeAction',
      )
      .mockImplementation(async (action: FederationActionEntity) => {
        const result = await execute(action);
        if (action.agentId === c.agent.id)
          throw new Error('synthetic failure after side effect');
        return result;
      });
    try {
      const submitted = await request(ctx.app.getHttpServer())
        .post('/api/v1/actions')
        .set('Authorization', `Bearer ${c.accessToken}`)
        .set('Idempotency-Key', randomUUID())
        .send({
          type: 'forum.topic.create',
          payload: {
            title: 'Crash canary',
            content: 'Synthetic rollback canary',
          },
        })
        .expect(202);
      await waitForActionStatus(
        ctx.app,
        c.accessToken,
        auditBody(submitted.body).id,
      );
      expect(
        await ctx.dataSource
          .getRepository(EventEntity)
          .countBy({ actorAgentId: c.agent.id }),
      ).toBe(0);
    } finally {
      spy.mockRestore();
    }
  });
  it('DL-01 concurrently enqueues 100 distinct events without losing or duplicating sequences', async () => {
    const c = await agent();
    const threads = ctx.dataSource.getRepository(ThreadEntity);
    const thread = await threads.save(
      threads.create({
        contextType: ThreadContextType.DirectMessage,
        visibility: ThreadVisibility.Private,
      }),
    );
    const events = ctx.dataSource.getRepository(EventEntity);
    const rows = await events.save(
      Array.from({ length: 100 }, (_, i) =>
        events.create({
          threadId: thread.id,
          eventType: 'audit.synthetic',
          actorType: EventActorType.System,
          contentType: EventContentType.Text,
          content: `canary-${i}`,
        }),
      ),
    );
    const delivery = ctx.app.get(FederationDeliveryService);
    const results = await Promise.allSettled(
      rows.map((event) => delivery.enqueueEventForRecipient(event, c.agent.id)),
    );
    expect(
      results.filter((result) => result.status === 'rejected'),
    ).toHaveLength(0);
    const saved = await ctx.dataSource.getRepository(DeliveryEntity).find({
      where: { recipientAgentId: c.agent.id },
      order: { sequence: 'ASC' },
    });
    expect(saved).toHaveLength(100);
    expect(new Set(saved.map((row) => row.eventId)).size).toBe(100);
    expect(saved.map((row) => row.sequence)).toEqual(
      Array.from({ length: 100 }, (_, i) => i + 1),
    );
    await delivery.enqueueEventForRecipient(rows[0], c.agent.id);
    expect(
      await ctx.dataSource
        .getRepository(DeliveryEntity)
        .countBy({ recipientAgentId: c.agent.id }),
    ).toBe(100);
  });
});
