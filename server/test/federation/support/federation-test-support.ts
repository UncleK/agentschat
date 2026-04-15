import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { FederationCredentialsService } from '../../../src/modules/federation/federation-credentials.service';
import { typedValue } from '../../support/test-app';

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
  const username = buildUsername(email, displayName);
  const response = await request(app.getHttpServer())
    .post('/api/v1/auth/register/email')
    .send({
      email,
      username,
      displayName,
      password: 'password123',
    })
    .expect(201);

  return response.body as {
    accessToken: string;
    user: {
      id: string;
      email: string;
      username: string;
      displayName: string;
    };
  };
}

function buildUsername(email: string, displayName: string): string {
  const emailLocal = email.trim().toLowerCase().split('@')[0] ?? '';
  const displaySeed = displayName
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_');
  const baseSeed = emailLocal || displaySeed || 'human_user';
  const normalizedBase = baseSeed
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .replace(/_+/g, '_');
  const fallback = normalizedBase || 'human_user';
  const truncatedBase = fallback.slice(0, 18);
  const suffix = createDeterministicSuffix(email, displayName);

  return `${truncatedBase}_${suffix}`.slice(0, 24);
}

function createDeterministicSuffix(email: string, displayName: string): string {
  const input = `${email.trim().toLowerCase()}|${displayName.trim().toLowerCase()}`;
  let hash = 0;

  for (const character of input) {
    hash = (hash * 33 + character.charCodeAt(0)) >>> 0;
  }

  return hash.toString(36).padStart(5, '0').slice(0, 5);
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
  const claimToken =
    federationCredentialsService.createAgentClaimToken(agentId);
  const response = await request(app.getHttpServer())
    .post('/api/v1/agents/claim')
    .send({
      claimToken,
      ...body,
    })
    .expect(201);

  return response.body as {
    accessToken: string;
    agent: {
      id: string;
      handle: string;
    };
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
    const body = typedValue<{
      id: string;
      status: string;
      eventId: string | null;
      threadId: string | null;
      result: Record<string, unknown>;
      error: Record<string, unknown> | null;
    }>(response.body);

    if (statuses.includes(body.status)) {
      return body;
    }

    await new Promise((resolve) => setTimeout(resolve, 50));
  }

  throw new Error(
    `Timed out waiting for action ${actionId} to reach ${statuses.join(', ')}.`,
  );
}
