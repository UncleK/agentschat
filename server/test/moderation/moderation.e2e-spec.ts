import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  AgentDmAcceptanceMode,
  DebateSeatStance,
  DebateSeatStatus,
  DebateSessionStatus,
  DeliveryStatus,
  SubjectType,
  ThreadContextType,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import {
  APP_ENVIRONMENT,
  type AppEnvironment,
} from '../../src/config/environment';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { DebateSeatEntity } from '../../src/database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { DeliveryEntity } from '../../src/database/entities/delivery.entity';
import { EventEntity } from '../../src/database/entities/event.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { ContentService } from '../../src/modules/content/content.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';

interface ArchiveResponseBody {
  archive: {
    suspendedAgentId: string;
    eventIds: string[];
  };
}

interface AcceptedActionBody {
  id: string;
}

interface DeadLetterListBody {
  deliveries: Array<{
    id: string;
  }>;
}
import {
  claimFederatedAgent,
  importSelfAgent,
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

describe('Moderation and operator controls (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let environment: AppEnvironment;
  let contentService: ContentService;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;
  let agentRepository: Repository<AgentEntity>;
  let debateSessionRepository: Repository<DebateSessionEntity>;
  let debateSeatRepository: Repository<DebateSeatEntity>;
  let threadRepository: Repository<ThreadEntity>;
  let deliveryRepository: Repository<DeliveryEntity>;
  let eventRepository: Repository<EventEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    environment = app.get(APP_ENVIRONMENT);
    contentService = app.get(ContentService);
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
    agentRepository = context.dataSource.getRepository(AgentEntity);
    debateSessionRepository =
      context.dataSource.getRepository(DebateSessionEntity);
    debateSeatRepository = context.dataSource.getRepository(DebateSeatEntity);
    threadRepository = context.dataSource.getRepository(ThreadEntity);
    deliveryRepository = context.dataSource.getRepository(DeliveryEntity);
    eventRepository = context.dataSource.getRepository(EventEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('suspends an agent, removes it from active debate seats, and preserves debate archive state', async () => {
    const suspendedAgent = await importSelfAgent(
      app,
      'suspend-agent',
      'Suspend Agent',
    );
    const recipientAgent = await importSelfAgent(
      app,
      'suspend-recipient',
      'Suspend Recipient',
    );
    await policyService.upsertAgentSafetyPolicy(recipientAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const suspendedClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      suspendedAgent.id,
      {
        pollingEnabled: true,
      },
    );
    const debateThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Suspend debate',
      }),
    );
    const debateSession = await debateSessionRepository.save(
      debateSessionRepository.create({
        threadId: debateThread.id,
        topic: 'Should suspension archive debates?',
        proStance: 'Yes',
        conStance: 'No',
        hostType: SubjectType.Agent,
        hostAgentId: suspendedAgent.id,
        status: DebateSessionStatus.Live,
      }),
    );
    const seat = await debateSeatRepository.save(
      debateSeatRepository.create({
        debateSessionId: debateSession.id,
        stance: DebateSeatStance.Pro,
        status: DebateSeatStatus.Occupied,
        agentId: suspendedAgent.id,
        seatOrder: 1,
      }),
    );

    await contentService.submitDebateTurn(suspendedAgent.id, {
      debateSessionId: debateSession.id,
      seatId: seat.id,
      turnNumber: 1,
      content: 'This turn should remain in history.',
    });

    await request(app.getHttpServer())
      .post('/api/v1/moderation/operator/actions')
      .set('x-operator-token', environment.auth.operatorToken)
      .send({
        action: 'suspend',
        targetType: 'agent',
        targetId: suspendedAgent.id,
        reason: 'Operator suspension for task 7.',
      })
      .expect(201);

    const storedAgent = await agentRepository.findOneByOrFail({
      id: suspendedAgent.id,
    });
    const updatedSeat = await debateSeatRepository.findOneByOrFail({
      id: seat.id,
    });
    const archiveResponse = await request(app.getHttpServer())
      .get(`/api/v1/moderation/operator/debates/${debateSession.id}/archive`)
      .set('x-operator-token', environment.auth.operatorToken)
      .expect(200);
    const archiveBody = typedValue<ArchiveResponseBody>(archiveResponse.body);

    expect(storedAgent.status).toBe('suspended');
    expect(updatedSeat.status).toBe('replacing');
    expect(updatedSeat.agentId).toBeNull();
    expect(archiveBody.archive.suspendedAgentId).toBe(suspendedAgent.id);
    expect(archiveBody.archive.eventIds).toHaveLength(1);

    const dmActionResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${suspendedClaim.accessToken}`)
      .set('Idempotency-Key', 'suspended-agent-dm')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: recipientAgent.id,
          content: 'This should be rejected after suspension.',
        },
      })
      .expect(202);
    const dmActionResponseBody = typedValue<AcceptedActionBody>(
      dmActionResponse.body,
    );

    const dmAction = await waitForActionStatus(
      app,
      suspendedClaim.accessToken,
      dmActionResponseBody.id,
    );

    expect(dmAction.status).toBe('rejected');
    expect(dmAction.error?.message).toMatch(/suspended/i);
  });

  it('enforces rate limits, hides events, and exposes operator dead-letter review endpoints', async () => {
    const sender = await registerHuman(
      app,
      'rate-limit-sender@example.com',
      'Rate Sender',
    );
    const senderOwnedAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        handle: 'rate-limit-owned-agent',
        displayName: 'Rate Limit Owned Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);

    await request(app.getHttpServer())
      .post('/api/v1/moderation/operator/actions')
      .set('x-operator-token', environment.auth.operatorToken)
      .send({
        action: 'rate_limit',
        targetType: 'user',
        targetId: sender.user.id,
        reason: 'Temporary rate limit',
        metadata: {
          durationSeconds: 3600,
          minIntervalSeconds: 3600,
        },
      })
      .expect(201);

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: senderOwnedAgent.id,
        content: 'This should hit the moderation rate limit.',
      })
      .expect(429);

    const author = await importSelfAgent(app, 'hide-author', 'Hide Author');
    const replyAgent = await importSelfAgent(
      app,
      'hide-replier',
      'Hide Replier',
    );
    const topic = await contentService.createForumTopic(
      {
        type: SubjectType.Agent,
        id: author.id,
      },
      {
        title: 'Hideable topic',
        content: 'Opening post',
      },
    );
    const reply = await contentService.createForumReply(
      {
        type: SubjectType.Agent,
        id: replyAgent.id,
      },
      {
        threadId: topic.threadId,
        parentEventId: topic.eventId,
        content: 'Hide this reply.',
      },
    );

    await request(app.getHttpServer())
      .post('/api/v1/moderation/operator/actions')
      .set('x-operator-token', environment.auth.operatorToken)
      .send({
        action: 'hide',
        targetType: 'event',
        targetId: reply.eventId,
        reason: 'Hidden by operator.',
      })
      .expect(201);

    const hiddenEvent = await eventRepository.findOneByOrFail({
      id: reply.eventId,
    });
    expect(hiddenEvent.metadata.moderation).toMatchObject({ hidden: true });

    const deliveryRecipient = await importSelfAgent(
      app,
      'dead-letter-target',
      'Dead Letter',
    );
    const deliverySender = await importSelfAgent(
      app,
      'dead-letter-sender',
      'Dead Sender',
    );
    await policyService.upsertAgentSafetyPolicy(deliveryRecipient.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const deliveryRecipientClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      deliveryRecipient.id,
      {
        transportMode: 'webhook',
        webhookUrl: 'http://127.0.0.1:1/unreachable',
      },
    );
    const deliverySenderClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      deliverySender.id,
      {
        pollingEnabled: true,
      },
    );

    expect(deliveryRecipientClaim.transport.mode).toBe('webhook');

    const deliveryActionResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${deliverySenderClaim.accessToken}`)
      .set('Idempotency-Key', 'dead-letter-dm')
      .send({
        type: 'dm.send',
        payload: {
          targetType: 'agent',
          targetId: deliveryRecipient.id,
          content: 'Drive a dead letter for operator review.',
        },
      })
      .expect(202);
    const deliveryActionResponseBody = typedValue<AcceptedActionBody>(
      deliveryActionResponse.body,
    );

    const deliveryAction = await waitForActionStatus(
      app,
      deliverySenderClaim.accessToken,
      deliveryActionResponseBody.id,
    );
    expect(deliveryAction.status).toBe('succeeded');

    const deadLetter = await waitForDeadLetter(deliveryRecipient.id);

    const deadLetterList = await request(app.getHttpServer())
      .get('/api/v1/moderation/operator/dead-letters')
      .set('x-operator-token', environment.auth.operatorToken)
      .expect(200);
    const deadLetterListBody = typedValue<DeadLetterListBody>(
      deadLetterList.body,
    );

    expect(
      deadLetterListBody.deliveries.some((entry) => entry.id === deadLetter.id),
    ).toBe(true);

    await request(app.getHttpServer())
      .get(`/api/v1/moderation/operator/dead-letters/${deadLetter.id}`)
      .set('x-operator-token', environment.auth.operatorToken)
      .expect(200)
      .expect(({ body }: { body: { status: string } }) => {
        expect(body.status).toBe('dead_letter');
      });

    await request(app.getHttpServer())
      .post(`/api/v1/moderation/operator/dead-letters/${deadLetter.id}/requeue`)
      .set('x-operator-token', environment.auth.operatorToken)
      .expect(201);

    const requeuedDelivery = await deliveryRepository.findOneByOrFail({
      id: deadLetter.id,
    });
    expect(requeuedDelivery.status).toBe(DeliveryStatus.Pending);
  });

  async function waitForDeadLetter(recipientAgentId: string) {
    const deadline = Date.now() + 2_500;

    while (Date.now() < deadline) {
      const delivery = await deliveryRepository.findOne({
        where: {
          recipientAgentId,
          status: DeliveryStatus.DeadLetter,
        },
        order: {
          updatedAt: 'DESC',
        },
      });

      if (delivery) {
        return delivery;
      }

      await new Promise((resolve) => setTimeout(resolve, 50));
    }

    throw new Error(
      `Timed out waiting for dead-letter delivery for ${recipientAgentId}.`,
    );
  }
});
