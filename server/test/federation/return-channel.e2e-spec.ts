jest.mock('../../src/modules/federation/webhook-http', () => ({
  ...jest.requireActual<
    typeof import('../../src/modules/federation/webhook-http')
  >('../../src/modules/federation/webhook-http'),
  postWebhook: jest.fn(() => Promise.resolve({ ok: true, status: 200 })),
}));
import { randomBytes, randomUUID } from 'node:crypto';
import request from 'supertest';
import { postWebhook } from '../../src/modules/federation/webhook-http';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { AgentConnectionEntity } from '../../src/database/entities/agent-connection.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { AgentStatus, DeliveryStatus } from '../../src/database/domain.enums';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { FederationService } from '../../src/modules/federation/federation.service';
import {
  createTestApplication,
  type TestApplicationContext,
} from '../support/test-app';

describe('Existing identity return channel', () => {
  let ctx: TestApplicationContext;
  const previousRetention = process.env.DELIVERY_RETENTION_MS;
  beforeAll(async () => {
    process.env.DELIVERY_RETENTION_MS = String(72 * 3600000);
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
    if (previousRetention === undefined)
      delete process.env.DELIVERY_RETENTION_MS;
    else process.env.DELIVERY_RETENTION_MS = previousRetention;
  });
  async function join() {
    const result = await request(ctx.app.getHttpServer())
      .post('/api/v1/connectors/connect')
      .send({
        handle: 'return-' + randomUUID().slice(0, 8),
        displayName: 'Return channel',
        recoveryKey: randomBytes(32).toString('hex'),
      })
      .expect(201);
    return result.body as { agent: { id: string }; accessToken: string };
  }
  const path = '/api/v1/agents/connection/transport';
  it('upgrades an existing polling identity, delivers signed pending events, and preserves ACKs and idempotency', async () => {
    const a = await join(),
      b = await join();
    const act = async (
      token: string,
      type: string,
      payload: Record<string, unknown>,
    ) => {
      const result = await request(ctx.app.getHttpServer())
        .post('/api/v1/connectors/actions')
        .set('Authorization', 'Bearer ' + token)
        .set('Idempotency-Key', randomUUID())
        .send({ type, payload })
        .expect(200);
      return (result.body as { action: { threadId: string } }).action;
    };
    const topic = await act(a.accessToken, 'forum.topic.create', {
      title: 'Callback test',
      content: 'Return with this identity.',
    });
    for (let i = 0; i < 2; i++)
      await act(b.accessToken, 'forum.reply.create', {
        threadId: topic.threadId,
        content: 'Reply ' + i,
      });
    const repo = ctx.dataSource.getRepository(DeliveryEntity);
    const rows = await repo.find({
      where: { recipientAgentId: a.agent.id },
      order: { sequence: 'ASC' },
    });
    expect(rows).toHaveLength(2);
    await repo.update(rows[0].id, {
      status: DeliveryStatus.Acked,
      ackedAt: new Date(),
      nextAttemptAt: null,
    });
    const body = {
      transportMode: 'hybrid',
      webhookUrl: 'https://runtime.fixture/return',
    };
    const configure = () =>
      request(ctx.app.getHttpServer())
        .post(path)
        .set('Authorization', 'Bearer ' + a.accessToken)
        .send(body)
        .expect(200);
    const response = await configure();
    const result = response.body as {
      agentId: string;
      connectionId: string;
      webhook: { signingSecret: string };
    };
    expect(result.agentId).toBe(a.agent.id);
    expect(response.headers['cache-control']).toBe('no-store');
    expect(result.webhook.signingSecret).toMatch(/^[a-f0-9]{48}$/);
    expect((await configure()).body).toEqual(result);
    const deadline = Date.now() + 3000;
    while (!jest.mocked(postWebhook).mock.calls.length && Date.now() < deadline)
      await new Promise((resolve) => setTimeout(resolve, 20));
    const call = jest
      .mocked(postWebhook)
      .mock.calls.find((args) => args[0] === body.webhookUrl);
    expect(call).toBeDefined();
    const [, payload, headers] = call!;
    expect(
      (JSON.parse(payload) as { delivery: { deliveryId: string } }).delivery
        .deliveryId,
    ).toBe(rows[1].id);
    expect(headers['x-agents-chat-signature']).toBe(
      ctx.app
        .get(FederationCredentialsService)
        .signWebhookPayload(
          result.webhook.signingSecret,
          headers['x-agents-chat-timestamp'],
          payload,
        ),
    );
    expect((await repo.findOneByOrFail({ id: rows[0].id })).status).toBe(
      DeliveryStatus.Acked,
    );
    await request(ctx.app.getHttpServer())
      .post(path)
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({ transportMode: 'polling' })
      .expect(200);
    const connection = await ctx.dataSource
      .getRepository(AgentConnectionEntity)
      .findOneByOrFail({ agentId: a.agent.id });
    expect(connection).toMatchObject({
      id: result.connectionId,
      transportMode: 'polling',
      webhookUrl: null,
      webhookSecret: null,
      pollingEnabled: true,
    });
    await request(ctx.app.getHttpServer())
      .get('/api/v1/connectors/policy')
      .set('Authorization', 'Bearer ' + a.accessToken)
      .expect(200);
  });
  it('rejects missing/scoped/revoked credentials, unsafe destinations and suspended identities', async () => {
    const a = await join();
    await request(ctx.app.getHttpServer())
      .post(path)
      .send({ transportMode: 'polling' })
      .expect(401);
    await request(ctx.app.getHttpServer())
      .post(path)
      .set('Authorization', 'Bearer ac_oauth_scoped')
      .send({ transportMode: 'polling' })
      .expect(401);
    for (const body of [
      { transportMode: 'hybrid', webhookUrl: 'https://127.0.0.1/hook' },
      { transportMode: 'hybrid', webhookUrl: 'http://runtime.fixture/hook' },
      { transportMode: 'hybrid' },
      { transportMode: 'polling', webhookUrl: 'https://runtime.fixture/hook' },
      { transportMode: 'polling', agentId: randomUUID() },
    ])
      await request(ctx.app.getHttpServer())
        .post(path)
        .set('Authorization', 'Bearer ' + a.accessToken)
        .send(body)
        .expect(400);
    await ctx.dataSource
      .getRepository(AgentEntity)
      .update(a.agent.id, { status: AgentStatus.Suspended });
    await request(ctx.app.getHttpServer())
      .post(path)
      .set('Authorization', 'Bearer ' + a.accessToken)
      .send({ transportMode: 'polling' })
      .expect(403);
    await ctx.dataSource
      .getRepository(AgentEntity)
      .update(a.agent.id, { status: AgentStatus.Offline });
    const authenticated = await ctx.app
      .get(FederationCredentialsService)
      .authenticateAgentToken(a.accessToken);
    await ctx.app.get(FederationService).rotateAgentToken(authenticated);
    await expect(
      ctx.app
        .get(FederationService)
        .configureTransport(authenticated, { transportMode: 'polling' }),
    ).rejects.toMatchObject({ status: 401 });
  });
});
