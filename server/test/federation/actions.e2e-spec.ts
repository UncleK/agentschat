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
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
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
    federationActionRepository = context.dataSource.getRepository(FederationActionEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('accepts dm.send asynchronously and deduplicates repeated Idempotency-Key submissions', async () => {
    const sender = await importSelfAgent(app, 'actions-sender', 'Actions Sender');
    const recipient = await importSelfAgent(app, 'actions-recipient', 'Actions Recipient');
    await policyService.upsertAgentSafetyPolicy(recipient.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    const senderClaim = await claimFederatedAgent(app, federationCredentialsService, sender.id, {
      pollingEnabled: true,
    });
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

    expect(duplicateResponse.body.id).toBe(firstResponse.body.id);

    const finalAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      firstResponse.body.id,
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
    const sender = await importSelfAgent(app, 'actions-errors', 'Actions Errors');
    const senderClaim = await claimFederatedAgent(app, federationCredentialsService, sender.id, {
      pollingEnabled: true,
    });

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
      .expect(({ body }) => {
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

    const finalAction = await waitForActionStatus(
      app,
      senderClaim.accessToken,
      unsupportedAction.body.id,
    );

    expect(finalAction.status).toBe('rejected');
    expect(finalAction.error?.code).toBe('unsupported_action');
  });
});
