import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { auditBody } from './audit-response';
import { randomUUID } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  TestApplicationContext,
} from '../support/test-app';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import {
  EventActorType,
  ThreadContextType,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import * as transport from '../../src/modules/federation/webhook-http';

describe('WH-01/WH-02 endpoint isolation with synthetic transport', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });
  it('does not let a stalled endpoint block a healthy recipient and claims each attempt once', async () => {
    const service = ctx.app.get(FederationDeliveryService);
    clearInterval(service['deliverySweepTimer']);
    service['deliverySweepTimer'] = null;
    const poke = jest
      .spyOn(service, 'poke')
      .mockImplementation(() => undefined);
    const seen: string[] = [];
    let release!: () => void;
    const stalled = new Promise<void>((resolve) => {
      release = resolve;
    });
    const send = jest
      .spyOn(transport, 'postWebhook')
      .mockImplementation(async (url) => {
        seen.push(url);
        if (url.includes('slow')) await stalled;
        return { ok: true, status: 200 };
      });
    try {
      const threads = ctx.dataSource.getRepository(ThreadEntity);
      const events = ctx.dataSource.getRepository(EventEntity);
      const thread = await threads.save(
        threads.create({
          contextType: ThreadContextType.DirectMessage,
          visibility: ThreadVisibility.Private,
        }),
      );
      for (const name of ['slow', 'fast']) {
        const b = await request(ctx.app.getHttpServer())
          .post('/api/v1/agents/bootstrap/public')
          .send({
            handle: `fair-${name}-${randomUUID().slice(0, 6)}`,
            displayName: 'Synthetic',
          })
          .expect(201);
        const c = await request(ctx.app.getHttpServer())
          .post('/api/v1/agents/claim')
          .send({
            claimToken: auditBody(b.body).bootstrap.claimToken,
            transportMode: 'webhook',
            webhookUrl: `https://${name}.audit.invalid/events`,
          })
          .expect(201);
        const event = await events.save(
          events.create({
            threadId: thread.id,
            eventType: 'audit.fairness',
            actorType: EventActorType.System,
          }),
        );
        await service.enqueueEventForRecipient(
          event,
          auditBody(c.body).agent.id,
        );
      }
      const first = service.processDueWebhookDeliveries();
      const second = new FederationDeliveryService(
        service['environment'],
        service['deliveryRepository'],
        service['agentConnectionRepository'],
        service['agentRepository'],
        service['eventRepository'],
        service['federationCredentialsService'],
      );
      await new Promise((r) => setTimeout(r, 80));
      const beforeRelease = [...seen];
      const competing = second.processDueWebhookDeliveries();
      release();
      await Promise.all([first, competing]);
      expect(beforeRelease.some((url) => url.includes('fast'))).toBe(true);
      expect(seen.filter((url) => url.includes('fast'))).toHaveLength(1);
      expect(seen.filter((url) => url.includes('slow'))).toHaveLength(1);
    } finally {
      release?.();
      send.mockRestore();
      poke.mockRestore();
    }
  });
  it('WH-02 persists backoff and circuit state and resumes oldest remaining delivery after cooldown', async () => {
    const service = ctx.app.get(FederationDeliveryService);
    const pause = jest
      .spyOn(service, 'poke')
      .mockImplementation(() => undefined);
    const send = jest
      .spyOn(transport, 'postWebhook')
      .mockResolvedValue({ ok: false, status: 503 });
    try {
      const b = auditBody(
        (
          await request(ctx.app.getHttpServer())
            .post('/api/v1/agents/bootstrap/public')
            .send({
              handle: `circuit-${randomUUID().slice(0, 8)}`,
              displayName: 'Synthetic',
            })
            .expect(201)
        ).body,
      );
      const c = auditBody(
        (
          await request(ctx.app.getHttpServer())
            .post('/api/v1/agents/claim')
            .send({
              claimToken: b.bootstrap.claimToken,
              transportMode: 'webhook',
              webhookUrl: 'https://circuit.audit.invalid/events',
            })
            .expect(201)
        ).body,
      );
      const threads = ctx.dataSource.getRepository(ThreadEntity);
      const thread = await threads.save(
        threads.create({
          contextType: ThreadContextType.DirectMessage,
          visibility: ThreadVisibility.Private,
        }),
      );
      const events = ctx.dataSource.getRepository(EventEntity);
      const event = await events.save(
        events.create({
          threadId: thread.id,
          eventType: 'audit.circuit',
          actorType: EventActorType.System,
        }),
      );
      const delivery = await service.enqueueEventForRecipient(
        event,
        c.agent.id,
      );
      const deliveries = ctx.dataSource.getRepository(DeliveryEntity);
      const connections = ctx.dataSource.getRepository(AgentConnectionEntity);
      await deliveries.update(delivery.id, {
        replayExpiresAt: new Date(Date.now() + 60000),
      });
      for (let i = 0; i < 3; i++) {
        await deliveries.update(delivery.id, { nextAttemptAt: new Date(0) });
        await service['processDueWebhookDeliveries']();
        const saved = await deliveries.findOneByOrFail({ id: delivery.id });
        expect(saved.attemptCount).toBe(i + 1);
        if (i < 2) expect(saved.nextAttemptAt).not.toBeNull();
        else expect(saved.status).toBe('dead_letter');
      }
      const blocked = await connections.findOneByOrFail({
        agentId: c.agent.id,
      });
      expect(blocked.webhookConsecutiveFailures).toBe(3);
      expect(blocked.webhookBlockedUntil!.getTime()).toBeGreaterThan(
        Date.now(),
      );
      const before = send.mock.calls.filter(([url]) =>
        url.includes('circuit'),
      ).length;
      await service['processDueWebhookDeliveries']();
      expect(
        send.mock.calls.filter(([url]) => url.includes('circuit')),
      ).toHaveLength(before);
      // Advance only the synthetic cooldown and retry timestamps.
      await connections.update(blocked.id, {
        webhookBlockedUntil: new Date(0),
      });
      const nextEvent = await events.save(
        events.create({
          threadId: thread.id,
          eventType: 'audit.circuit.next',
          actorType: EventActorType.System,
        }),
      );
      const nextDelivery = await service.enqueueEventForRecipient(
        nextEvent,
        c.agent.id,
      );
      send.mockResolvedValue({ ok: true, status: 200 });
      await service['processDueWebhookDeliveries']();
      const recovered = await connections.findOneByOrFail({ id: blocked.id });
      expect(recovered.webhookConsecutiveFailures).toBe(0);
      expect(recovered.webhookBlockedUntil).toBeNull();
      expect(
        (await deliveries.findOneByOrFail({ id: nextDelivery.id })).eventId,
      ).toBe(nextEvent.id);
      expect(
        (await deliveries.findOneByOrFail({ id: nextDelivery.id })).status,
      ).toBe('sent');
      expect(
        (await deliveries.findOneByOrFail({ id: delivery.id })).status,
      ).toBe('dead_letter');
    } finally {
      send.mockRestore();
      pause.mockRestore();
    }
  });
});
