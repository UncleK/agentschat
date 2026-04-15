import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

describe('Forum human policies (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('rejects human-authenticated topic creation', async () => {
    const human = await registerHuman(
      app,
      'forum-human-topic@example.com',
      'Forum Human Topic',
    );

    await request(app.getHttpServer())
      .post('/api/v1/content/forum/topics')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        title: 'Humans cannot create forum topics here',
        content: 'This should be rejected.',
        tags: ['policy'],
      })
      .expect(403);
  });

  it('allows humans to reply only to first-level replies', async () => {
    const human = await registerHuman(
      app,
      'forum-human-reply@example.com',
      'Forum Human Reply',
    );
    const author = await importSelfAgent(
      app,
      'forum-human-author',
      'Forum Human Author',
    );
    const branchAgent = await importSelfAgent(
      app,
      'forum-human-branch',
      'Forum Human Branch',
    );
    const authorClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      author.id,
      {
        pollingEnabled: true,
      },
    );
    const branchClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      branchAgent.id,
      {
        pollingEnabled: true,
      },
    );

    const topic = await submitAgentAction({
      accessToken: authorClaim.accessToken,
      idempotencyKey: 'forum-human-topic-root',
      body: {
        type: 'forum.topic.create',
        payload: {
          title: 'Forum human reply boundaries',
          tags: ['policy', 'forum'],
          contentType: 'text',
          content: 'Root topic authored by an agent.',
        },
      },
    });
    const firstLevelReply = await submitAgentAction({
      accessToken: branchClaim.accessToken,
      idempotencyKey: 'forum-human-topic-first-level',
      body: {
        type: 'forum.reply.create',
        payload: {
          threadId: topic.threadId,
          parentEventId: topic.eventId,
          contentType: 'text',
          content: 'First-level agent reply.',
        },
      },
    });
    const secondLevelReply = await submitAgentAction({
      accessToken: authorClaim.accessToken,
      idempotencyKey: 'forum-human-topic-second-level',
      body: {
        type: 'forum.reply.create',
        payload: {
          threadId: topic.threadId,
          parentEventId: firstLevelReply.eventId,
          contentType: 'text',
          content: 'Second-level agent reply.',
        },
      },
    });

    await request(app.getHttpServer())
      .post(`/api/v1/content/forum/topics/${topic.threadId}/replies`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        contentType: 'text',
        content: 'Humans cannot reply without a branch target.',
      })
      .expect(403);

    await request(app.getHttpServer())
      .post(`/api/v1/content/forum/topics/${topic.threadId}/replies`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        parentEventId: topic.eventId,
        contentType: 'text',
        content: 'Humans cannot target the root event directly.',
      })
      .expect(403);

    await request(app.getHttpServer())
      .post(`/api/v1/content/forum/topics/${topic.threadId}/replies`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        parentEventId: firstLevelReply.eventId,
        contentType: 'text',
        content: 'Humans may reply to the first-level branch.',
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/content/forum/topics/${topic.threadId}/replies`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        parentEventId: secondLevelReply.eventId,
        contentType: 'text',
        content: 'Humans cannot reply deeper than first-level branches.',
      })
      .expect(403);
  });

  it('rejects human-authenticated forum reply likes, including active-agent payloads', async () => {
    const human = await registerHuman(
      app,
      'forum-human-like@example.com',
      'Forum Human Like',
    );
    const ownedAgentResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        handle: 'forum-like-owned-agent',
        displayName: 'Forum Like Owned Agent',
      })
      .expect(201);
    const ownedAgent = typedValue<{ id: string }>(ownedAgentResponse.body);
    const author = await importSelfAgent(
      app,
      'forum-like-author',
      'Forum Like Author',
    );
    const replier = await importSelfAgent(
      app,
      'forum-like-replier',
      'Forum Like Replier',
    );
    const authorClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      author.id,
      {
        pollingEnabled: true,
      },
    );
    const replierClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      replier.id,
      {
        pollingEnabled: true,
      },
    );

    const topic = await submitAgentAction({
      accessToken: authorClaim.accessToken,
      idempotencyKey: 'forum-human-like-topic-root',
      body: {
        type: 'forum.topic.create',
        payload: {
          title: 'Forum human like boundaries',
          tags: ['policy', 'forum'],
          contentType: 'text',
          content: 'Root topic authored by an agent.',
        },
      },
    });
    const reply = await submitAgentAction({
      accessToken: replierClaim.accessToken,
      idempotencyKey: 'forum-human-like-first-level',
      body: {
        type: 'forum.reply.create',
        payload: {
          threadId: topic.threadId,
          parentEventId: topic.eventId,
          contentType: 'text',
          content: 'First-level agent reply.',
        },
      },
    });

    await request(app.getHttpServer())
      .post(`/api/v1/content/forum/replies/${reply.eventId}/like`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({})
      .expect(403);

    await request(app.getHttpServer())
      .post(`/api/v1/content/forum/replies/${reply.eventId}/like`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        activeAgentId: ownedAgent.id,
      })
      .expect(403);
  });

  async function submitAgentAction({
    accessToken,
    idempotencyKey,
    body,
  }: {
    accessToken: string;
    idempotencyKey: string;
    body: {
      type: string;
      payload: Record<string, unknown>;
    };
  }) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${accessToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send(body)
      .expect(202);
    const responseBody = typedValue<{ id: string }>(response.body);

    const finalAction = await waitForActionStatus(
      app,
      accessToken,
      responseBody.id,
    );

    expect(finalAction.status).toBe('succeeded');

    return finalAction as {
      threadId: string;
      eventId: string;
    };
  }
});
