import { randomBytes, randomUUID } from 'node:crypto';
import request from 'supertest';
import {
  createTestApplication,
  typedValue,
  type TestApplicationContext,
} from '../support/test-app';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import {
  ThreadContextType,
  ThreadVisibility,
  EventActorType,
  EventContentType,
  SubjectType,
} from '../../src/database/domain.enums';
import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { FederationDeliveryService } from '../../src/modules/federation/federation-delivery.service';
import { readDeliveryHealth } from '../../src/database/delivery-health';

type Identity = { accessToken: string; agent: { id: string } };
type Action = {
  id: string;
  status: string;
  threadId: string;
  eventId: string;
  error?: { code: string; details?: object };
};
type UpdatePacket = {
  groups: Array<{
    threadId: string;
    readUrl: string | null;
    checkpoint: string | null;
    messages: Array<{
      eventId: string;
      deliveryId: string;
      reason: string;
      content: string;
      truncated: boolean;
      parent?: { author: { handle: string } };
    }>;
    deliveryIds: string[];
  }>;
  freshness: { state: string };
  participationVerification?: { verificationId: string; nonce: string };
};

describe('Agent-focused upgrades', () => {
  let ctx: TestApplicationContext;
  const previousRetention = process.env.DELIVERY_RETENTION_MS;
  beforeAll(async () => {
    process.env.DELIVERY_RETENTION_MS = String(72 * 3600000);
    ctx = await createTestApplication();
    const delivery = ctx.app.get(FederationDeliveryService);
    clearInterval(delivery['deliverySweepTimer']);
    delivery['deliverySweepTimer'] = null;
    jest.spyOn(delivery, 'poke').mockImplementation(() => undefined);
  });
  afterAll(async () => {
    jest.restoreAllMocks();
    await ctx?.close();
    if (previousRetention === undefined)
      delete process.env.DELIVERY_RETENTION_MS;
    else process.env.DELIVERY_RETENTION_MS = previousRetention;
  });
  async function join(): Promise<Identity> {
    return typedValue<Identity>(
      (
        await request(ctx.app.getHttpServer())
          .post('/api/v1/connectors/connect')
          .send({
            handle: 'upgrade-' + randomUUID().slice(0, 8),
            displayName: 'Upgrade fixture',
            recoveryKey: randomBytes(32).toString('hex'),
          })
          .expect(201)
      ).body,
    );
  }
  async function act(
    a: Identity,
    type: string,
    payload: object,
    key = randomUUID(),
    status = 'succeeded',
  ) {
    const response = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/actions')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .set('Idempotency-Key', key)
      .send({ type, payload })
      .expect(200);
    const body = typedValue<{
      action: Action;
      verified: boolean;
      repair?: object;
    }>(response.body);
    expect(body.action.status).toBe(status);
    if (status === 'succeeded') expect(body.verified).toBe(true);
    return body;
  }
  async function read(threadId: string) {
    const response = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/forum/' + threadId)
      .expect(200);
    return typedValue<{
      topic: { replies: unknown[]; asyncDebate: { status: string } };
      asyncDebate: {
        status: string;
        currentTurn: number;
        turns: unknown[];
        seats: object;
        deadlineAt: string | null;
        nextSpeaker: { id: string } | null;
      };
    }>(response.body);
  }
  async function modifyState(threadId: string, patch: object) {
    const repo = ctx.dataSource.getRepository(ThreadEntity);
    const thread = await repo.findOneByOrFail({ id: threadId });
    await repo.update(threadId, {
      metadata: {
        ...thread.metadata,
        asyncDebate: {
          ...typedValue<object>(thread.metadata.asyncDebate),
          ...patch,
        },
      },
    });
  }
  async function updates(a: Identity, limit = 20) {
    const response = await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/updates')
      .query({ limit })
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(200);
    expect(response.headers['cache-control']).toBe('no-store');
    return typedValue<UpdatePacket>(response.body);
  }

  it('requires explicit independent seats, serializes six turns and preserves idempotency', async () => {
    const moderator = await join(),
      pro = await join(),
      con = await join();
    const created = await act(moderator, 'forum.debate.create', {
      topic: 'A slow written debate',
      proStance: 'Pro case',
      conStance: 'Con case',
      windowHours: 12,
    });
    const threadId = created.action.threadId;
    expect((await read(threadId)).asyncDebate).toMatchObject({
      status: 'recruiting',
      currentTurn: 1,
    });
    await act(
      pro,
      'forum.debate.join',
      { threadId, stance: 'pro', acceptTerms: false },
      randomUUID(),
      'rejected',
    );
    await act(
      moderator,
      'forum.debate.join',
      { threadId, stance: 'pro', acceptTerms: true },
      randomUUID(),
      'rejected',
    );
    await act(pro, 'forum.debate.join', {
      threadId,
      stance: 'pro',
      acceptTerms: true,
    });
    await act(
      pro,
      'forum.debate.turn',
      {
        threadId,
        turnNumber: 1,
        content: 'Too early',
        whatIChecked: 'Nothing',
      },
      randomUUID(),
      'rejected',
    );
    await act(con, 'forum.debate.join', {
      threadId,
      stance: 'con',
      acceptTerms: true,
    });
    const state = (await read(threadId)).asyncDebate;
    expect(state).toMatchObject({
      status: 'running',
      nextSpeaker: { id: pro.agent.id },
    });
    expect(
      (await updates(pro)).groups
        .flatMap((group) => group.messages)
        .some((message) => message.reason === 'your_turn'),
    ).toBe(true);
    expect(Date.parse(state.deadlineAt!) - Date.now()).toBeGreaterThan(
      11 * 3600000,
    );
    await act(
      con,
      'forum.debate.turn',
      {
        threadId,
        turnNumber: 1,
        content: 'Wrong speaker',
        whatIChecked: 'Nothing',
      },
      randomUUID(),
      'rejected',
    );
    await act(pro, 'forum.reply.create', {
      threadId,
      content: 'An ordinary comment is not an official turn.',
    });
    expect((await read(threadId)).asyncDebate.turns).toHaveLength(0);
    const key = randomUUID();
    const payload = {
      threadId,
      turnNumber: 1,
      content: 'Opening statement',
      whatIChecked: 'I re-read the motion.',
    };
    const first = await act(pro, 'forum.debate.turn', payload, key);
    const repeat = await act(pro, 'forum.debate.turn', payload, key);
    expect(repeat.action.id).toBe(first.action.id);
    await act(pro, 'forum.debate.turn', payload, randomUUID(), 'rejected');
    for (let turnNumber = 2; turnNumber <= 6; turnNumber++)
      await act(turnNumber % 2 ? pro : con, 'forum.debate.turn', {
        threadId,
        turnNumber,
        content: 'Formal turn ' + turnNumber,
        whatIChecked: 'Nothing re-checked.',
      });
    expect((await read(threadId)).asyncDebate).toMatchObject({
      status: 'completed',
      currentTurn: 6,
      nextSpeaker: null,
    });
    expect((await read(threadId)).asyncDebate.turns).toHaveLength(6);
  });

  it('expires recruitment and a missed turn without filling it, and permits only the owner to withdraw', async () => {
    const moderator = await join(),
      pro = await join(),
      con = await join();
    const create = async () =>
      (
        await act(moderator, 'forum.debate.create', {
          topic: 'Deadline boundaries',
          proStance: 'Pro',
          conStance: 'Con',
          windowHours: 6,
        })
      ).action.threadId;
    const expired = await create();
    await modifyState(expired, {
      recruitmentClosesAt: new Date(0).toISOString(),
    });
    await act(
      pro,
      'forum.debate.join',
      { threadId: expired, stance: 'pro', acceptTerms: true },
      randomUUID(),
      'rejected',
    );
    expect((await read(expired)).asyncDebate.status).toBe('expired');
    const active = await create();
    for (const [a, stance] of [
      [pro, 'pro'],
      [con, 'con'],
    ] as const)
      await act(a, 'forum.debate.join', {
        threadId: active,
        stance,
        acceptTerms: true,
      });
    await modifyState(active, { deadlineAt: new Date(0).toISOString() });
    await act(
      pro,
      'forum.debate.turn',
      {
        threadId: active,
        turnNumber: 1,
        content: 'Late',
        whatIChecked: 'Nothing',
      },
      randomUUID(),
      'rejected',
    );
    expect((await read(active)).asyncDebate).toMatchObject({
      status: 'expired',
      turns: [],
    });
    const withdrawal = await create();
    await act(pro, 'forum.debate.join', {
      threadId: withdrawal,
      stance: 'pro',
      acceptTerms: true,
    });
    await act(
      con,
      'forum.debate.withdraw',
      { threadId: withdrawal, reason: 'Not my seat' },
      randomUUID(),
      'rejected',
    );
    await act(pro, 'forum.debate.withdraw', {
      threadId: withdrawal,
      reason: 'No longer available',
    });
    await act(moderator, 'forum.debate.close', {
      threadId: withdrawal,
      reason: 'Recruitment closed',
    });
    expect((await read(withdrawal)).asyncDebate.status).toBe('cancelled');
  });

  it('prioritizes direct replies, groups bounded previews, and keeps checkpoints separate from ACK', async () => {
    const reader = await join(),
      writer = await join();
    const broad = (
      await act(writer, 'forum.topic.create', {
        title: 'Subscribed conversation',
        content: 'Root',
      })
    ).action;
    await act(reader, 'forum.reply.create', {
      threadId: broad.threadId,
      content: 'I participate here.',
    });
    await act(writer, 'forum.reply.create', {
      threadId: broad.threadId,
      content: 'An older general thread update.',
    });
    const own = (
      await act(reader, 'forum.topic.create', {
        title: 'A direct reply target',
        content: 'Question',
      })
    ).action;
    const direct = (
      await act(writer, 'forum.reply.create', {
        threadId: own.threadId,
        content: 'a'.repeat(3000),
      })
    ).action;
    const packet = await updates(reader, 1);
    expect(packet.groups).toHaveLength(1);
    expect(packet.groups[0].threadId).toBe(own.threadId);
    const message = packet.groups[0].messages[0];
    expect(message).toMatchObject({
      eventId: direct.eventId,
      reason: 'direct_reply',
      truncated: true,
    });
    expect(message.parent).toBeDefined();
    expect(message.content.length).toBeLessThanOrEqual(1200);
    const checkpoint = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/updates/checkpoint')
      .set('Authorization', 'Bearer ' + reader.accessToken)
      .send({ threadId: own.threadId, lastEventId: direct.eventId })
      .expect(200);
    expect(checkpoint.body).toMatchObject({ saved: true, acknowledged: false });
    const deliveryRepo = ctx.dataSource.getRepository(DeliveryEntity);
    expect(
      (await deliveryRepo.findOneByOrFail({ id: message.deliveryId })).ackedAt,
    ).toBeNull();
    await deliveryRepo.update(message.deliveryId, {
      nextAttemptAt: new Date(0),
    });
    expect((await updates(reader, 1)).groups[0].checkpoint).toBe(
      direct.eventId,
    );
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/updates/checkpoint')
      .set('Authorization', 'Bearer ' + reader.accessToken)
      .send({ threadId: own.threadId, lastEventId: own.eventId })
      .expect(200)
      .expect((response) =>
        expect(response.body).toMatchObject({
          saved: false,
          reason: 'older_checkpoint',
        }),
      );
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/updates/checkpoint')
      .set('Authorization', 'Bearer ' + reader.accessToken)
      .send({ threadId: broad.threadId, lastEventId: direct.eventId })
      .expect(404);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/inbox/ack')
      .set('Authorization', 'Bearer ' + reader.accessToken)
      .send({ deliveryIds: [message.deliveryId] })
      .expect(200);
    expect(
      (await deliveryRepo.findOneByOrFail({ id: message.deliveryId })).ackedAt,
    ).not.toBeNull();
    expect((await updates(await join())).freshness.state).toBe(
      'no_new_event_to_test',
    );
  });

  it('routes live debate notifications to the debate reader and signals omitted media', async () => {
    const a = await join(),
      b = await join();
    const topic = (
      await act(a, 'forum.topic.create', {
        title: 'Media completeness',
        content: 'Question',
      })
    ).action;
    const image = (
      await act(b, 'forum.reply.create', {
        threadId: topic.threadId,
        content: 'Short caption',
        metadata: { nextSpeakerAgentId: a.agent.id },
      })
    ).action;
    await ctx.dataSource
      .getRepository(EventEntity)
      .update(image.eventId, { contentType: EventContentType.Image });
    const media = (await updates(a)).groups
      .flatMap((group) => group.messages)
      .find((message) => message.eventId === image.eventId)!;
    expect(media).toMatchObject({
      contentType: 'image',
      hasMedia: true,
      truncated: true,
      requiresFullRead: true,
      reason: 'direct_reply',
      media: { omitted: true },
    });
    const threads = ctx.dataSource.getRepository(ThreadEntity);
    const thread = await threads.save(
      threads.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Existing live debate',
      }),
    );
    const sessions = ctx.dataSource.getRepository(DebateSessionEntity);
    const session = await sessions.save(
      sessions.create({
        threadId: thread.id,
        topic: 'Existing live debate',
        proStance: 'Pro',
        conStance: 'Con',
        hostType: SubjectType.Agent,
        hostAgentId: b.agent.id,
      }),
    );
    const events = ctx.dataSource.getRepository(EventEntity);
    const event = await events.save(
      events.create({
        threadId: thread.id,
        eventType: 'debate.turn.assigned',
        actorType: EventActorType.System,
        metadata: { debateSessionId: session.id, assignedAgentId: a.agent.id },
      }),
    );
    await ctx.app
      .get(FederationDeliveryService)
      .enqueueEventForRecipient(event, a.agent.id);
    const group = (await updates(a)).groups.find(
      (item) => item.threadId === thread.id,
    )!;
    expect(group.readUrl).toBe(
      'http://127.0.0.1:3000/api/v1/connectors/debates/' + session.id,
    );
    expect(group.messages[0]).toMatchObject({
      reason: 'your_turn',
      publicUrl: 'http://127.0.0.1:3000/live/' + session.id,
    });
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/debates/' + session.id)
      .expect(200);
  });

  it('does not leak private or hidden-root messages through previews, checkpoints or freshness markers', async () => {
    const reader = await join(),
      writer = await join();
    const root = (
      await act(reader, 'forum.topic.create', {
        title: 'A moderated discussion',
        content: 'Public root',
      })
    ).action;
    const reply = (
      await act(writer, 'forum.reply.create', {
        threadId: root.threadId,
        content: 'Hidden thread secret',
      })
    ).action;
    await ctx.dataSource
      .getRepository(EventEntity)
      .update(root.eventId, { metadata: { moderation: { hidden: true } } });
    const threads = ctx.dataSource.getRepository(ThreadEntity);
    const thread = await threads.save(
      threads.create({
        contextType: ThreadContextType.DirectMessage,
        visibility: ThreadVisibility.Private,
      }),
    );
    const events = ctx.dataSource.getRepository(EventEntity);
    const privateEvent = await events.save(
      events.create({
        threadId: thread.id,
        eventType: 'dm.send',
        actorType: EventActorType.System,
        content: 'Private message secret',
      }),
    );
    await ctx.app
      .get(FederationDeliveryService)
      .enqueueEventForRecipient(privateEvent, reader.agent.id);
    const packet = await updates(reader);
    expect(packet.groups).toEqual([]);
    expect(JSON.stringify(packet)).not.toContain('secret');
    expect(packet.freshness).toMatchObject({ latestEligibleSequence: null });
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/updates/checkpoint')
      .set('Authorization', 'Bearer ' + reader.accessToken)
      .send({ threadId: root.threadId, lastEventId: reply.eventId })
      .expect(404);
  });

  it('allows only one concurrent claimant of a seat', async () => {
    const moderator = await join(),
      a = await join(),
      b = await join();
    const created = await act(moderator, 'forum.debate.create', {
      topic: 'Concurrent acceptance',
      proStance: 'Pro',
      conStance: 'Con',
    });
    const threadId = created.action.threadId;
    const responses = await Promise.all(
      [a, b].map((agent) =>
        request(ctx.app.getHttpServer())
          .post('/api/v1/connectors/actions')
          .set('Authorization', 'Bearer ' + agent.accessToken)
          .set('Idempotency-Key', randomUUID())
          .send({
            type: 'forum.debate.join',
            payload: { threadId, stance: 'pro', acceptTerms: true },
          })
          .expect(200),
      ),
    );
    expect(
      responses
        .map(
          (response) =>
            typedValue<{ action: Action }>(response.body).action.status,
        )
        .sort(),
    ).toEqual(['rejected', 'succeeded']);
  });

  it('records actual selection, configured route and verified return as distinct milestones', async () => {
    const a = await join();
    const base = '/api/v1/connectors/participation';
    const before = (await readDeliveryHealth(ctx.dataSource))
      .participationFunnel;
    await request(ctx.app.getHttpServer())
      .post(base + '/prepare')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({ authorized: false })
      .expect(400);
    for (let i = 0; i < 2; i++)
      await request(ctx.app.getHttpServer())
        .post(base + '/prepare')
        .set('Authorization', 'Bearer ' + a.accessToken)
        .send({ authorized: true })
        .expect(200)
        .expect((response) =>
          expect(response.body).toMatchObject({
            state: 'not_configured',
            selected: true,
            hostScheduleCreatedByPlatform: false,
          }),
        );
    const selected = (await readDeliveryHealth(ctx.dataSource))
      .participationFunnel;
    expect(selected).toEqual({
      selected: before.selected + 1,
      configured: before.configured,
      verified: before.verified,
    });
    await request(ctx.app.getHttpServer())
      .post(base)
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({
        enabled: true,
        authorized: true,
        mode: 'host_schedule',
        hostScheduleId: 'real-host-task',
      })
      .expect(200);
    const connection = await ctx.dataSource
      .getRepository(AgentConnectionEntity)
      .findOneByOrFail({ agentId: a.agent.id });
    await ctx.dataSource
      .getRepository(AgentConnectionEntity)
      .update(connection.id, {
        continuousParticipation: {
          ...connection.continuousParticipation!,
          probeNotBefore: new Date(0).toISOString(),
        },
      });
    const challenge = (await updates(a)).participationVerification!;
    await request(ctx.app.getHttpServer())
      .post(base + '/confirm')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({ ...challenge, runId: 'actual-host-return' })
      .expect(200);
    expect(
      (await readDeliveryHealth(ctx.dataSource)).participationFunnel,
    ).toEqual({
      selected: before.selected + 1,
      configured: before.configured + 1,
      verified: before.verified + 1,
    });
  });

  it('provides actionable rejected-payload details and typed text entry points', async () => {
    const a = await join();
    const wrong = await act(
      a,
      'forum.topic.create',
      { title: 'Bad input', body: 'Wrong field' },
      randomUUID(),
      'rejected',
    );
    expect(wrong.action.error).toMatchObject({
      code: 'invalid_payload',
      details: { renameField: { body: 'content' }, retryable: false },
    });
    const topic = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/forum/topics')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({
        title: 'Typed text route',
        content: 'Actual content',
        idempotencyKey: randomUUID(),
      })
      .expect(200);
    const threadId = typedValue<{ action: Action }>(topic.body).action.threadId;
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/forum/replies')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({ threadId, content: 'Typed reply', idempotencyKey: randomUUID() })
      .expect(200)
      .expect((response) =>
        expect(response.body).toMatchObject({ verified: true }),
      );
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/updates')
      .expect(401);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/participation/prepare')
      .send({ authorized: true })
      .expect(401);
  });
});
