import { randomBytes, randomUUID } from 'node:crypto';
import request from 'supertest';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { DeliveryStatus } from '../../src/database/domain.enums';
import {
  createTestApplication,
  type TestApplicationContext,
} from '../support/test-app';
import { type ForumReplyDto } from '../../src/modules/content/content.service';
import { DurableAgentInboxes1710000017000 } from '../../migrations/1710000017000-DurableAgentInboxes';

describe('Durable community participation', () => {
  let ctx: TestApplicationContext;
  const oldRetention = process.env.DELIVERY_RETENTION_MS;
  beforeAll(async () => {
    process.env.DELIVERY_RETENTION_MS = String(72 * 3600 * 1000);
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
    if (oldRetention === undefined) delete process.env.DELIVERY_RETENTION_MS;
    else process.env.DELIVERY_RETENTION_MS = oldRetention;
  });
  async function join() {
    const result = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send({
        handle: 'durable-' + randomUUID().slice(0, 8),
        displayName: 'Durable Agent',
        recoveryKey: randomBytes(32).toString('hex'),
      })
      .expect(201);
    return result.body as { accessToken: string; agent: { id: string } };
  }
  async function act(
    token: string,
    type: string,
    payload: Record<string, unknown>,
  ) {
    const response = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/actions')
      .set('Authorization', 'Bearer ' + token)
      .set('Idempotency-Key', randomUUID())
      .send({ type, payload })
      .expect(200);
    const result = response.body as {
      verified: boolean;
      action: { id: string; eventId: string; threadId: string; status: string };
    };
    expect(result.action.status).toBe('succeeded');
    expect(result.verified).toBe(true);
    return result.action;
  }
  it('continues A-B-A-B replies, preserves actual parents and resumes from an observed event', async () => {
    const a = await join(),
      b = await join();
    const topic = await act(a.accessToken, 'forum.topic.create', {
      title: 'Continuous exchange',
      content: 'What evidence would change this conclusion?',
      tags: ['community-build'],
    });
    const ids: string[] = [];
    let parentEventId = topic.eventId;
    for (let i = 0; i < 5; i++) {
      const reply = await act(
        i % 2 ? a.accessToken : b.accessToken,
        'forum.reply.create',
        {
          threadId: topic.threadId,
          parentEventId,
          content: 'Evidence round ' + i,
        },
      );
      ids.push(reply.eventId);
      parentEventId = reply.eventId;
    }
    const read = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/discussion')
      .query({ kind: 'forum', id: topic.threadId })
      .expect(200);
    const all: ForumReplyDto[] = [];
    const flatten = (replies: ForumReplyDto[]) => {
      for (const reply of replies) {
        all.push(reply);
        flatten(reply.children);
      }
    };
    flatten(
      (read.body as { topic: { replies: ForumReplyDto[] } }).topic.replies,
    );
    expect(all).toHaveLength(5);
    ids.forEach((id, i) =>
      expect(all.find((reply) => reply.id === id)?.parentEventId).toBe(
        i ? ids[i - 1] : topic.eventId,
      ),
    );
    const incremental = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/discussion')
      .query({ kind: 'forum', id: topic.threadId, afterEventId: ids[2] })
      .expect(200);
    expect(
      (incremental.body as { updates: ForumReplyDto[] }).updates.map(
        (reply) => reply.id,
      ),
    ).toEqual(ids.slice(3));
    const proposals = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/community')
      .expect(200);
    expect(
      (
        proposals.body as { proposals: { topics: Array<{ threadId: string }> } }
      ).proposals.topics.some((item) => item.threadId === topic.threadId),
    ).toBe(true);
  });
  it('delivers a 16-hour-old batch, survives more than three reads and only ACK removes it', async () => {
    const a = await join(),
      b = await join();
    const topic = await act(a.accessToken, 'forum.topic.create', {
      title: 'Delayed inbox',
      content: 'Please reply when you return.',
    });
    for (let i = 0; i < 3; i++)
      await act(b.accessToken, 'forum.reply.create', {
        threadId: topic.threadId,
        content: 'Reply ' + i,
      });
    const repository = ctx.dataSource.getRepository(DeliveryEntity);
    const rows = await repository.findBy({ recipientAgentId: a.agent.id });
    expect(rows.length).toBeGreaterThanOrEqual(3);
    for (const row of rows) {
      expect(
        row.replayExpiresAt.getTime() - row.createdAt.getTime(),
      ).toBeGreaterThan(71 * 3600 * 1000);
      await repository.update(row.id, {
        createdAt: new Date(Date.now() - 16 * 3600 * 1000),
        replayExpiresAt: new Date(Date.now() + 56 * 3600 * 1000),
        nextAttemptAt: null,
      });
    }
    const read = () =>
      request(ctx.app.getHttpServer())
        .get('/api/v1/connectors/inbox?limit=50')
        .set('Authorization', 'Bearer ' + a.accessToken)
        .expect(200);
    let deliveryIds: string[] = [];
    for (let i = 0; i < 5; i++) {
      if (i)
        await repository.update(
          { recipientAgentId: a.agent.id },
          { nextAttemptAt: null },
        );
      const result = await read();
      const body = result.body as {
        pendingCount: number;
        deliveries: Array<{ deliveryId: string; expiresAt: string }>;
      };
      expect(body.deliveries).toHaveLength(rows.length);
      expect(body.pendingCount).toBe(rows.length);
      deliveryIds = body.deliveries.map((item) => item.deliveryId);
    }
    const retained = await repository.findBy({ recipientAgentId: a.agent.id });
    retained.forEach((row) => {
      expect(row.attemptCount).toBe(5);
      expect(row.webhookAttemptCount).toBe(0);
      expect(row.status).not.toBe(DeliveryStatus.DeadLetter);
    });
    for (let i = 0; i < 2; i++)
      await request(ctx.app.getHttpServer())
        .post('/api/v1/connectors/inbox/ack')
        .set('Authorization', 'Bearer ' + a.accessToken)
        .send({ deliveryIds })
        .expect(200);
    expect((await read()).body).toMatchObject({
      pendingCount: 0,
      deliveries: [],
    });
  });
  it('reports capabilities, updates a public profile and rejects malformed connector reads', async () => {
    const a = await join();
    const policy = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/policy')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(200);
    expect(policy.body).toMatchObject({
      identity: { id: a.agent.id },
      capabilities: {
        inbox: { retentionMs: 259200000, maxBatch: 50 },
        backgroundScheduleCreated: false,
      },
    });
    await act(a.accessToken, 'agent.profile.update', {
      bio: 'Interested in community engineering',
      tags: ['community-build'],
    });
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/actions')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .set('Idempotency-Key', randomUUID())
      .send({
        type: 'agent.profile.update',
        payload: { webhookUrl: 'https://example.com' },
      })
      .expect(400);
    for (const path of [
      'forum/THREAD_ID',
      'debates/DEBATE_ID',
      'actions/ACTION_ID',
    ])
      await request(ctx.app.getHttpServer())
        .get('/api/v1/connectors/' + path)
        .set('Authorization', 'Bearer ' + a.accessToken)
        .expect(400);
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/inbox?limit=0')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(400);
  });
  it('recovers only untouched public notifications still within the new retention window', async () => {
    const a = await join(),
      b = await join();
    const topic = await act(a.accessToken, 'forum.topic.create', {
      title: 'Retention migration',
      content: 'Recover a delayed notification.',
    });
    await act(b.accessToken, 'forum.reply.create', {
      threadId: topic.threadId,
      content: 'A reply awaiting a delayed visitor.',
    });
    const repository = ctx.dataSource.getRepository(DeliveryEntity);
    const row = await repository.findOneByOrFail({
      recipientAgentId: a.agent.id,
    });
    const createdAt = new Date(Date.now() - 16 * 3600 * 1000);
    await repository.update(row.id, {
      createdAt,
      replayExpiresAt: new Date(createdAt.getTime() + 15 * 60000),
      status: DeliveryStatus.DeadLetter,
      attemptCount: 0,
      deadLetteredAt: new Date(),
    });
    const migration = new DurableAgentInboxes1710000017000();
    const runner = ctx.dataSource.createQueryRunner();
    try {
      await migration.down(runner);
      await migration.up(runner);
    } finally {
      await runner.release();
    }
    const restored = await repository.findOneByOrFail({ id: row.id });
    expect(restored.status).toBe(DeliveryStatus.Pending);
    expect(restored.sequence).toBe(row.sequence);
    expect(restored.deadLetteredAt).toBeNull();
    expect(restored.replayExpiresAt.getTime()).toBe(
      createdAt.getTime() + 72 * 3600 * 1000,
    );
  });
});
