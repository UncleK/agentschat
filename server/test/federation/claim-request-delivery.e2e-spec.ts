import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { AgentOwnerType } from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  registerHuman,
  waitForActionStatus,
} from './support/federation-test-support';

interface PublicBootstrapResponse {
  bootstrap: {
    claimToken: string;
    agent: {
      id: string;
    };
  };
}

interface ClaimAgentResponse {
  accessToken: string;
  agent: {
    id: string;
    handle: string;
  };
}

interface ClaimRequestResponse {
  claimRequest: {
    id: string;
    agentId: string;
    status: string;
  };
  challengeToken: string;
}

interface DeliveryPollResponse {
  cursor: string | null;
  deliveries: Array<{
    deliveryId: string;
    event: {
      type: string;
      targetId: string | null;
      metadata: {
        claimRequestId: string;
        challengeToken: string;
        expiresAt: string;
        claimant: {
          id: string;
          username: string;
          displayName: string;
          email: string;
        };
      };
    };
  }>;
}

interface AcceptedActionResponse {
  id: string;
}

describe('Federation claim-request delivery (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let agentRepository: Repository<AgentEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    agentRepository = context.dataSource.getRepository(AgentEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('delivers claim.requested to the agent poll stream and lets the agent confirm ownership transfer', async () => {
    const bootstrapResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        handle: 'claim-requested-agent',
        displayName: 'Claim Requested Agent',
      })
      .expect(201);
    const bootstrapBody = typedValue<PublicBootstrapResponse>(
      bootstrapResponse.body,
    );

    const claimAgentResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: bootstrapBody.bootstrap.claimToken,
        pollingEnabled: true,
      })
      .expect(201);
    const claimAgentBody = typedValue<ClaimAgentResponse>(
      claimAgentResponse.body,
    );

    const human = await registerHuman(
      app,
      'skill-claim-owner@example.com',
      'Skill Claim Owner',
    );

    const requestClaimResponse = await request(app.getHttpServer())
      .post(`/api/v1/agents/${claimAgentBody.agent.id}/claim-requests`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .expect(201);
    const requestClaimBody = typedValue<ClaimRequestResponse>(
      requestClaimResponse.body,
    );

    expect(requestClaimBody.claimRequest.status).toBe('pending');

    const pollResponse = await request(app.getHttpServer())
      .get('/api/v1/deliveries/poll?wait_seconds=1')
      .set('Authorization', `Bearer ${claimAgentBody.accessToken}`)
      .expect(200);
    const pollBody = typedValue<DeliveryPollResponse>(pollResponse.body);
    const claimDelivery = pollBody.deliveries[0];

    expect(pollBody.deliveries).toHaveLength(1);
    expect(claimDelivery).toBeDefined();
    if (!claimDelivery) {
      throw new Error('Expected claim.requested delivery to exist.');
    }

    expect(claimDelivery.event.type).toBe('claim.requested');
    expect(claimDelivery.event.targetId).toBe(claimAgentBody.agent.id);
    expect(claimDelivery.event.metadata.claimRequestId).toBe(
      requestClaimBody.claimRequest.id,
    );
    expect(typeof claimDelivery.event.metadata.challengeToken).toBe('string');
    expect(typeof claimDelivery.event.metadata.expiresAt).toBe('string');
    expect(claimDelivery.event.metadata.claimant).toEqual({
      id: human.user.id,
      username: human.user.username,
      displayName: human.user.displayName,
      email: human.user.email,
    });

    const confirmResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${claimAgentBody.accessToken}`)
      .set('Idempotency-Key', 'claim-requested-confirm')
      .send({
        type: 'claim.confirm',
        payload: {
          claimRequestId: claimDelivery.event.metadata.claimRequestId,
          challengeToken: claimDelivery.event.metadata.challengeToken,
        },
      })
      .expect(202);
    const confirmBody = typedValue<AcceptedActionResponse>(
      confirmResponse.body,
    );
    const completedConfirmation = await waitForActionStatus(
      app,
      claimAgentBody.accessToken,
      confirmBody.id,
    );

    expect(completedConfirmation.status).toBe('succeeded');
    expect(completedConfirmation.result).toMatchObject({
      agentId: claimAgentBody.agent.id,
      ownerType: 'human',
      ownerUserId: human.user.id,
      claimRequestId: requestClaimBody.claimRequest.id,
      claimStatus: 'confirmed',
    });

    const updatedAgent = await agentRepository.findOneByOrFail({
      id: claimAgentBody.agent.id,
    });

    expect(updatedAgent.ownerType).toBe(AgentOwnerType.Human);
    expect(updatedAgent.ownerUserId).toBe(human.user.id);
  });

  it('lets a connected self-owned agent confirm a generic claim link without broadcasting claim.requested deliveries', async () => {
    const bootstrapResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        handle: 'generic-claim-agent',
        displayName: 'Generic Claim Agent',
      })
      .expect(201);
    const bootstrapBody = typedValue<PublicBootstrapResponse>(
      bootstrapResponse.body,
    );

    const claimAgentResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: bootstrapBody.bootstrap.claimToken,
        pollingEnabled: true,
      })
      .expect(201);
    const claimAgentBody = typedValue<ClaimAgentResponse>(
      claimAgentResponse.body,
    );

    const human = await registerHuman(
      app,
      'generic-claim-owner@example.com',
      'Generic Claim Owner',
    );

    const requestClaimResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/claim-requests')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .expect(201);
    const requestClaimBody = typedValue<ClaimRequestResponse>(
      requestClaimResponse.body,
    );

    expect(requestClaimBody.claimRequest.status).toBe('pending');
    expect(requestClaimBody.claimRequest.agentId).toBe('');

    const pollResponse = await request(app.getHttpServer())
      .get('/api/v1/deliveries/poll?wait_seconds=1')
      .set('Authorization', `Bearer ${claimAgentBody.accessToken}`)
      .expect(200);
    const pollBody = typedValue<DeliveryPollResponse>(pollResponse.body);

    expect(pollBody.deliveries).toEqual([]);

    const confirmResponse = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${claimAgentBody.accessToken}`)
      .set('Idempotency-Key', 'generic-claim-confirm')
      .send({
        type: 'claim.confirm',
        payload: {
          claimRequestId: requestClaimBody.claimRequest.id,
          challengeToken: requestClaimBody.challengeToken,
        },
      })
      .expect(202);
    const confirmBody = typedValue<AcceptedActionResponse>(
      confirmResponse.body,
    );
    const completedConfirmation = await waitForActionStatus(
      app,
      claimAgentBody.accessToken,
      confirmBody.id,
    );

    expect(completedConfirmation.status).toBe('succeeded');
    expect(completedConfirmation.result).toMatchObject({
      agentId: claimAgentBody.agent.id,
      ownerType: 'human',
      ownerUserId: human.user.id,
      claimRequestId: requestClaimBody.claimRequest.id,
      claimStatus: 'confirmed',
    });

    const updatedAgent = await agentRepository.findOneByOrFail({
      id: claimAgentBody.agent.id,
    });

    expect(updatedAgent.ownerType).toBe(AgentOwnerType.Human);
    expect(updatedAgent.ownerUserId).toBe(human.user.id);
  });
});
