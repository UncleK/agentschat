import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';

describe('Agent claim flow (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
  });

  afterAll(async () => {
    await context?.close();
  });

  it('moves a self-owned agent to human-owned after deterministic challenge confirmation', async () => {
    const registerResponse = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email: 'claim-owner@example.com',
        displayName: 'Claim Owner',
        password: 'password123',
      })
      .expect(201);

    const humanToken = registerResponse.body.accessToken as string;

    const selfOwnedAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/self')
      .send({
        handle: 'self-owned-agent',
        displayName: 'Self Owned Agent',
      })
      .expect(201);

    expect(selfOwnedAgent.body.ownerType).toBe('self');
    expect(selfOwnedAgent.body.ownerUserId).toBeNull();

    const firstClaimRequest = await request(app.getHttpServer())
      .post(`/api/v1/agents/${selfOwnedAgent.body.id}/claim-requests`)
      .set('Authorization', `Bearer ${humanToken}`)
      .expect(201);

    const secondClaimRequest = await request(app.getHttpServer())
      .post(`/api/v1/agents/${selfOwnedAgent.body.id}/claim-requests`)
      .set('Authorization', `Bearer ${humanToken}`)
      .expect(201);

    expect(firstClaimRequest.body.claimRequest.status).toBe('pending');
    expect(secondClaimRequest.body.claimRequest.id).toBe(
      firstClaimRequest.body.claimRequest.id,
    );
    expect(secondClaimRequest.body.challengeToken).toBe(
      firstClaimRequest.body.challengeToken,
    );
    expect(firstClaimRequest.body.challengeToken).toBe(
      `claim:${selfOwnedAgent.body.id}:${registerResponse.body.user.id}`,
    );

    const confirmationResponse = await request(app.getHttpServer())
      .post(
        `/api/v1/agents/${selfOwnedAgent.body.id}/claim-requests/${firstClaimRequest.body.claimRequest.id}/confirm`,
      )
      .set('Authorization', `Bearer ${humanToken}`)
      .send({
        challengeToken: firstClaimRequest.body.challengeToken,
      })
      .expect(200);

    expect(confirmationResponse.body.claimRequest.status).toBe('confirmed');
    expect(confirmationResponse.body.agent.ownerType).toBe('human');
    expect(confirmationResponse.body.agent.ownerUserId).toBe(
      registerResponse.body.user.id,
    );
  });
});
