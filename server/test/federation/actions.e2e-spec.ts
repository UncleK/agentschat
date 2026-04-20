import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { AgentDmAcceptanceMode } from '../../src/database/domain.enums';
import { EventEntity } from '../../src/database/entities/event.entity';
import { FederationActionEntity } from '../../src/database/entities/federation-action.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
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
} from './support/federation-test-support';

describe('Federation actions (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;
  let eventRepository: Repository<EventEntity>;
  let federationActionRepository: Repository<FederationActionEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
    eventRepository = context.dataSource.getRepository(EventEntity);
    federationActionRepository = context.dataSource.getRepository(
      FederationActionEntity,
    );
  });

  afterAll(async () => {
    await context?.close();
  });

  it('accepts dm.send asynchronously and deduplicates repeated Idempotency-Key submissions', async () => {
    const sender = await importSelfAgent(
      app,
      'actions-sender',
      'Actions Sender',
    );
    const recipient = await importSelfAgent(
      app,
      'actions-recipient',
      'Actions Recipient',
    );
    await policyService.upsertAgentSafetyPolicy(recipient.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const senderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      sender.id,
      {
        pollingEnabled: true,
      },
    );
    await claimFederatedAgent(app, federationCredentialsService, recipient.id, {
      pollingEnabled: true,
    });

    const firstResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'dm-idempotency-1')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          contentType: 'text',
          content: 'Hello from Task 5.',
        },
      })
      .expect(202);

    const duplicateResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'dm-idempotency-1')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipient.id,
          contentType: 'text',
          content: 'Hello from Task 5.',
        },
      })
      .expect(200);
    const firstResponseBody = typedValue<{ id: string }>(firstResponse.body);
    const duplicateResponseBody = typedValue<{ id: string }>(
      duplicateResponse.body,
    );

    expect(duplicateResponseBody.id).toBe(firstResponseBody.id);

    const finalAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      firstResponseBody.id,
    );

    expect(finalAction.status).toBe('succeeded');
    expect(finalAction.eventId).toEqual(expect.any(String));

    const storedActions = await federationActionRepository.findBy({
      agentId: sender.id,
    });
    const dmEvents = await eventRepository.findBy({
      eventType: 'dm.send',
      actorAgentId: sender.id,
    });

    expect(storedActions).toHaveLength(1);
    expect(dmEvents).toHaveLength(1);
  });

  it('rejects requests without Idempotency-Key and surfaces async action errors via GET /actions/:id', async () => {
    const sender = await importSelfAgent(
      app,
      'actions-errors',
      'Actions Errors',
    );
    const senderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      sender.id,
      {
        pollingEnabled: true,
      },
    );

    await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .send({
        type: 'agent.profile.update',
        payload: {
          displayName: 'Missing Header',
        },
      })
      .expect(400)
      .expect(({ body }: { body: { error: { code: string } } }) => {
        expect(body.error.code).toBe('idempotency_key_required');
      });

    const unsupportedAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${senderClaim.accessToken}`)
      .set('Idempotency-Key', 'unsupported-action-1')
      .send({
        type: 'forum.topic.create',
        payload: {
          title: 'Unsupported in Task 5',
        },
      })
      .expect(202);
    const unsupportedActionBody = typedValue<{ id: string }>(
      unsupportedAction.body,
    );

    const finalAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      unsupportedActionBody.id,
    );

    expect(finalAction.status).toBe('rejected');
    expect(finalAction.error?.code).toBe('unsupported_action');
  });

  it('keeps federated agent replies inside the existing multi-party DM thread when threadId is provided', async () => {
    const owner = await registerHuman(
      app,
      'actions-thread-owner@example.com',
      'Actions Thread Owner',
    );
    const ownerAgent = await importHumanOwnedAgent(
      app,
      owner.accessToken,
      'actions-thread-owner-agent',
      'Actions Thread Owner Agent',
    );
    const remoteAgent = await importSelfAgent(
      app,
      'actions-thread-remote-agent',
      'Actions Thread Remote Agent',
    );

    await policyService.upsertAgentSafetyPolicy(ownerAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await policyService.upsertAgentSafetyPolicy(remoteAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const remoteClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      remoteAgent.id,
      {
        pollingEnabled: true,
      },
    );

    const initialThreadResponse = await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: ownerAgent.id,
        recipientType: 'agent',
        recipientAgentId: remoteAgent.id,
        contentType: 'text',
        content: 'Initial agent-authored opener.',
      })
      .expect(201);
    const initialThread = typedValue<{ threadId: string }>(
      initialThreadResponse.body,
    );

    await request(app.getHttpServer())
      .post(`/api/v1/content/dm/threads/${initialThread.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        activeAgentId: ownerAgent.id,
        contentType: 'text',
        content: 'Human clarification inside the existing thread.',
      })
      .expect(201);

    const actionResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${remoteClaim.accessToken}`)
      .set('Idempotency-Key', 'dm-thread-aware-reply-1')
      .send({
        type: 'dm.send',
        payload: {
          threadId: initialThread.threadId,
          targetType: 'human',
          targetId: owner.user.id,
          contentType: 'text',
          content: 'Federated reply stays in the shared DM thread.',
        },
      })
      .expect(202);
    const actionResponseBody = typedValue<{ id: string }>(actionResponse.body);

    const finalAction = await waitForActionStatus(
      app,
      remoteClaim.accessToken,
      actionResponseBody.id,
    );

    expect(finalAction.status).toBe('succeeded');
    expect(finalAction.threadId).toBe(initialThread.threadId);

    const threadEvents = await eventRepository.find({
      where: {
        threadId: initialThread.threadId,
        eventType: 'dm.send',
      },
      order: {
        occurredAt: 'ASC',
        id: 'ASC',
      },
    });

    expect(threadEvents).toHaveLength(3);
    expect(threadEvents[2]).toMatchObject({
      threadId: initialThread.threadId,
      actorAgentId: remoteAgent.id,
      targetType: 'human',
      targetId: owner.user.id,
      content: 'Federated reply stays in the shared DM thread.',
    });

    const ownerThreadsResponse = await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: ownerAgent.id,
      })
      .expect(200);
    const ownerThreadsBody = typedValue<{
      threads: Array<{ threadId: string }>;
    }>(ownerThreadsResponse.body);

    expect(ownerThreadsBody.threads).toHaveLength(1);
    expect(ownerThreadsBody.threads[0]?.threadId).toBe(initialThread.threadId);

    await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${initialThread.threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: ownerAgent.id,
      })
      .expect(200)
      .expect(
        ({
          body,
        }: {
          body: { messages: Array<{ content: string | null }> };
        }) => {
          expect(body.messages.map((message) => message.content)).toEqual([
            'Initial agent-authored opener.',
            'Human clarification inside the existing thread.',
            'Federated reply stays in the shared DM thread.',
          ]);
        },
      );
  });
});

async function importHumanOwnedAgent(
  app: INestApplication,
  accessToken: string,
  handle: string,
  displayName: string,
) {
  const response = await request(app.getHttpServer())
    .post('/api/v1/agents/import/human')
    .set('Authorization', `Bearer ${accessToken}`)
    .send({
      handle,
      displayName,
    })
    .expect(201);

  return typedValue<{ id: string; handle: string; displayName: string }>(
    response.body,
  );
}
