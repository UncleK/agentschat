import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { FederationCredentialsService } from '../../../src/modules/federation/federation-credentials.service';

export async function importSelfAgent(
  app: INestApplication,
  handle: string,
  displayName: string,
) {
  const response = await request(app.getHttpServer())
    .post('/api/v1/agents/import/self')
    .send({
      handle,
      displayName,
    })
    .expect(201);

  return response.body as {
    id: string;
    handle: string;
    ownerType: string;
  };
}

export async function registerHuman(
  app: INestApplication,
  email: string,
  displayName: string,
) {
  const response = await request(app.getHttpServer())
    .post('/api/v1/auth/register/email')
    .send({
      email,
      displayName,
      password: 'password123',
    })
    .expect(201);

  return response.body as {
    accessToken: string;
    user: {
      id: string;
      email: string;
      displayName: string;
    };
  };
}

export async function claimFederatedAgent(
  app: INestApplication,
  federationCredentialsService: FederationCredentialsService,
  agentId: string,
  body?: {
    transportMode?: string;
    webhookUrl?: string;
    pollingEnabled?: boolean;
    capabilities?: Record<string, unknown>;
  },
) {
  const claimToken = federationCredentialsService.createAgentClaimToken(agentId);
  const response = await request(app.getHttpServer())
    .post('/api/v1/agents/claim')
    .send({
      claimToken,
      ...body,
    })
    .expect(201);

  return response.body as {
    accessToken: string;
    transport: {
      mode: string;
      webhook: {
        url: string;
        signingSecret: string;
      } | null;
      polling: {
        enabled: boolean;
      };
    };
  };
}

export async function waitForActionStatus(
  app: INestApplication,
  accessToken: string,
  actionId: string,
  statuses: string[] = ['succeeded', 'rejected', 'failed'],
  timeoutMs = 2_000,
) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const response = await request(app.getHttpServer())
      .get(`/api/v1/actions/${actionId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    if (statuses.includes(response.body.status)) {
      return response.body as {
        id: string;
        status: string;
        eventId: string | null;
        threadId: string | null;
        result: Record<string, unknown>;
        error: Record<string, unknown> | null;
      };
    }

    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  throw new Error(`Timed out waiting for action ${actionId} to reach ${statuses.join(', ')}.`);
}
