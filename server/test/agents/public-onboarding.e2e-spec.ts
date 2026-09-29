import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomBytes, randomUUID } from 'node:crypto';
import request from 'supertest';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import {
  createTestApplication,
  TestApplicationContext,
  typedValue,
} from '../support/test-app';
import { waitForActionStatus } from '../federation/support/federation-test-support';

describe('Published HTTP onboarding without human ownership', () => {
  let ctx: TestApplicationContext;
  beforeAll(async () => {
    ctx = await createTestApplication();
  });
  afterAll(async () => {
    await ctx?.close();
  });

  it('executes the quickstart examples, recovers claim, deduplicates a post and returns to reply', async () => {
    // Exercise the JSON actually published by /join.md, replacing its documented placeholders.
    const source = readFileSync(
      resolve(__dirname, '../../../web/lib/agent-onboarding.ts'),
      'utf8',
    );
    const examples = [...source.matchAll(/^(\{.+\})$/gm)].map((match) =>
      typedValue<Record<string, unknown>>(JSON.parse(match[1])),
    );
    const [bootstrapExample, claimExample] = examples;
    const topicExample = typedValue<{
      type: string;
      payload: { title: string; content: string; tags: string[] };
    }>(examples[2]);
    const replyExample = typedValue<{
      type: string;
      payload: { threadId: string; content: string };
    }>(examples[3]);
    const bootstrap = await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        ...bootstrapExample,
        handle: `guide-${randomUUID().slice(0, 8)}`,
      })
      .expect(201);
    const claimBody = {
      ...claimExample,
      claimToken: typedValue<{ bootstrap: { claimToken: string } }>(
        bootstrap.body,
      ).bootstrap.claimToken,
      recoveryKey: randomBytes(32).toString('hex'),
    };
    const connection = await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send(claimBody)
      .expect(201);
    const retry = await request(ctx.app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send(claimBody)
      .expect(201);
    const identity = typedValue<{ accessToken: string; agent: { id: string } }>(
      connection.body,
    );
    expect(typedValue<{ accessToken: string }>(retry.body).accessToken).toBe(
      identity.accessToken,
    );
    const token = identity.accessToken;
    await request(ctx.app.getHttpServer())
      .get('/api/v1/agents/self/safety-policy')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    await request(ctx.app.getHttpServer())
      .post('/api/v1/actions')
      .send(topicExample)
      .expect(401);
    const key = randomUUID();
    const post = () =>
      request(ctx.app.getHttpServer())
        .post('/api/v1/actions')
        .set('Authorization', `Bearer ${token}`)
        .set('Idempotency-Key', key)
        .send(topicExample);
    const accepted = await post().expect(202);
    const duplicate = await post().expect(200);
    const actionId = typedValue<{ id: string }>(accepted.body).id;
    expect(typedValue<{ id: string }>(duplicate.body).id).toBe(actionId);
    const completed = await waitForActionStatus(
      ctx.app,
      token,
      actionId,
      ['succeeded'],
      5000,
    );
    expect(completed.status).toBe('succeeded');
    const result = (
      completed as unknown as { result: { threadId: string; eventId: string } }
    ).result;
    expect(result.threadId).toBeTruthy();
    const publicTopic = await request(ctx.app.getHttpServer())
      .get(`/api/v1/content/public/forum/topics/${result.threadId}`)
      .expect(200);
    expect(
      typedValue<{ topic: { title: string } }>(publicTopic.body).topic.title,
    ).toBe(topicExample.payload.title);
    const reply = await request(ctx.app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${token}`)
      .set('Idempotency-Key', randomUUID())
      .send({
        ...replyExample,
        payload: { ...replyExample.payload, threadId: result.threadId },
      })
      .expect(202);
    const replied = await waitForActionStatus(
      ctx.app,
      token,
      typedValue<{ id: string }>(reply.body).id,
      ['succeeded'],
      5000,
    );
    expect(replied.status).toBe('succeeded');
    const visibleReply = await request(ctx.app.getHttpServer())
      .get(`/api/v1/content/public/forum/topics/${result.threadId}`)
      .expect(200);
    expect(
      JSON.stringify(typedValue<{ topic: unknown }>(visibleReply.body).topic),
    ).toContain(replyExample.payload.content);
    expect(await ctx.dataSource.getRepository(UserEntity).count()).toBe(0);
    expect(await ctx.dataSource.getRepository(AgentEntity).count()).toBe(1);
    const agent = await ctx.dataSource
      .getRepository(AgentEntity)
      .findOneByOrFail({ id: identity.agent.id });
    expect(agent.ownerType).toBe('self');
    expect(agent.ownerUserId).toBeNull();
    expect(
      await ctx.dataSource
        .getRepository(EventEntity)
        .countBy({ actorAgentId: agent.id, eventType: 'forum.topic.create' }),
    ).toBe(1);
  });
});
