import { randomUUID } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { auditBody } from './audit-response';
import { EventOutboxService } from '../../src/modules/notifications/event-outbox.service';
import { NotificationsService } from '../../src/modules/notifications/notifications.service';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';

describe('DL-02 persisted fanout failure and recovery', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  it('a new worker retries a committed outbox row after fanout rollback, with recipient-isolated idempotent ACK', async () => {
    const worker = ctx.app.get(EventOutboxService);
    await worker.onModuleDestroy();
    const agent = auditBody(
      (
        await request(ctx.app.getHttpServer())
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `outbox-${randomUUID().slice(0, 8)}`,
            displayName: 'Synthetic',
          })
          .expect(201)
      ).body,
    );
    const connected = auditBody(
      (
        await request(ctx.app.getHttpServer())
          .post('/api/v1/agents/claim')
          .send({
            claimToken: agent.bootstrap.claimToken,
            pollingEnabled: true,
          })
          .expect(201)
      ).body,
    );
    await worker.sweep();
    const threadId = randomUUID();
    const eventId = randomUUID();
    await ctx.dataSource.query(
      "INSERT INTO threads(id,context_type,visibility) VALUES ($1,'dm','private')",
      [threadId],
    );
    await ctx.dataSource.query(
      "INSERT INTO events(id,thread_id,event_type,actor_type,target_type,target_id) VALUES ($1,$2,'claim.requested','system','agent',$3)",
      [eventId, threadId, connected.agent.id],
    );
    const notifications = ctx.app.get(NotificationsService);
    const fail = jest
      .spyOn(notifications, 'processEventById')
      .mockRejectedValueOnce(new Error('Synthetic fanout failure'));
    await worker.sweep();
    fail.mockRestore();
    const failed = await ctx.dataSource.query<
      Array<{ completed_at: Date | null; last_error: string }>
    >('SELECT completed_at,last_error FROM event_outbox WHERE event_id=$1', [
      eventId,
    ]);
    expect(failed[0]).toEqual({
      completed_at: null,
      last_error: 'fanout_failed',
    });
    expect(
      await ctx.dataSource.getRepository(DeliveryEntity).countBy({ eventId }),
    ).toBe(0);
    await ctx.dataSource.query(
      'UPDATE event_outbox SET next_attempt_at=now() WHERE event_id=$1',
      [eventId],
    );
    const restarted = new EventOutboxService(ctx.dataSource, notifications);
    await restarted.sweep();
    await restarted.sweep();
    const deliveries = await ctx.dataSource
      .getRepository(DeliveryEntity)
      .findBy({ eventId });
    expect(deliveries).toHaveLength(1);
    expect(deliveries[0].recipientAgentId).toBe(connected.agent.id);
    for (let i = 0; i < 2; i++)
      await request(ctx.app.getHttpServer())
        .post('/api/v1/acks')
        .set('Authorization', `Bearer ${connected.accessToken}`)
        .send({ deliveryIds: [deliveries[0].id] })
        .expect(201);
    expect(
      (
        await ctx.dataSource
          .getRepository(DeliveryEntity)
          .findOneByOrFail({ id: deliveries[0].id })
      ).status,
    ).toBe('acked');
  });
});
