import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { AgentStatus, AuthProvider } from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';

interface HumanAuthResponse {
  accessToken: string;
  user: {
    id: string;
    email: string;
    username: string;
    displayName: string;
    authProvider: AuthProvider;
    avatarUrl?: string | null;
    emailVerified?: boolean;
  };
}

interface ImportedAgentResponse {
  id: string;
  ownerType: string;
  ownerUserId: string | null;
}

interface AgentsMineResponse {
  agents: Array<{
    id: string;
  }>;
}

interface MeResponse {
  user: {
    id: string;
    email: string;
    username: string;
    displayName: string;
    authProvider: AuthProvider;
    avatarUrl: string | null;
    emailVerified: boolean;
  };
  session: {
    authenticated: boolean;
  };
  recommendedActiveAgentId: string | null;
}

describe('Human auth (e2e)', () => {
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

  it('registers and logs in with email/password, then uses the human token on a protected route', async () => {
    const registerResponse = await registerEmailHuman(
      'owner@example.com',
      'owner_human',
      'Owner Human',
    );

    expect(registerResponse.user.email).toBe('owner@example.com');
    expect(registerResponse.user.username).toBe('owner_human');
    expect(registerResponse.user.authProvider).toBe(AuthProvider.Email);
    expect(registerResponse.user.emailVerified).toBe(false);
    expect(registerResponse.accessToken).toEqual(expect.any(String));

    const loginResponse = await loginEmailHuman('owner@example.com');

    expect(loginResponse.user.id).toBe(registerResponse.user.id);
    expect(loginResponse.accessToken).toEqual(expect.any(String));

    const importedAgentResponse = await importHumanOwnedAgent(
      loginResponse.accessToken,
      'owner-agent',
      'Owner Agent',
    );

    expect(importedAgentResponse.ownerType).toBe('human');
    expect(importedAgentResponse.ownerUserId).toBe(registerResponse.user.id);
  });

  it('rejects external-provider login until provider token verification exists', async () => {
    await loginProviderHuman(
      '/api/v1/auth/login/google',
      'google-user@example.com',
      'Google User',
      'google-subject-1',
      501,
    );

    await loginProviderHuman(
      '/api/v1/auth/login/github',
      'github-user@example.com',
      'GitHub User',
      'github-subject-1',
      501,
    );
  });

  it('returns the bootstrap contract with a null recommendedActiveAgentId when no eligible owned agent exists', async () => {
    const registerResponse = await registerEmailHuman(
      'bootstrap-owner@example.com',
      'bootstrap_owner',
      'Bootstrap Owner',
    );

    const humanToken = registerResponse.accessToken;

    await importSelfOwnedAgent(
      'bootstrap-claimable-agent',
      'Bootstrap Claimable Agent',
    );

    const pendingAgent = await importSelfOwnedAgent(
      'bootstrap-pending-agent',
      'Bootstrap Pending Agent',
    );

    await request(app.getHttpServer())
      .post(`/api/v1/agents/${pendingAgent.id}/claim-requests`)
      .set('Authorization', `Bearer ${humanToken}`)
      .expect(201);

    const meResponse = await readMe(humanToken);

    expect(meResponse).toEqual({
      user: {
        id: registerResponse.user.id,
        email: 'bootstrap-owner@example.com',
        username: 'bootstrap_owner',
        displayName: 'Bootstrap Owner',
        authProvider: AuthProvider.Email,
        avatarUrl: null,
        emailVerified: false,
      },
      session: {
        authenticated: true,
      },
      recommendedActiveAgentId: null,
    });
  });

  it('rejects /auth/me when the bearer token is invalid', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', 'Bearer not-a-valid-human-token')
      .expect(401);
  });

  it('reuses the /agents/mine ordering for recommendedActiveAgentId', async () => {
    const registerResponse = await registerEmailHuman(
      'recommended-owner@example.com',
      'recommended_owner',
      'Recommended Owner',
    );

    const humanToken = registerResponse.accessToken;

    const ownedOlder = await importHumanOwnedAgent(
      humanToken,
      'recommended-owned-older',
      'Recommended Owned Older',
    );

    const ownedNewer = await importHumanOwnedAgent(
      humanToken,
      'recommended-owned-newer',
      'Recommended Owned Newer',
    );

    const suspendedOwned = await importHumanOwnedAgent(
      humanToken,
      'recommended-owned-suspended',
      'Recommended Owned Suspended',
    );

    await agentRepository.update(
      { id: suspendedOwned.id },
      { status: AgentStatus.Suspended },
    );

    const claimableAgent = await importSelfOwnedAgent(
      'recommended-claimable-agent',
      'Recommended Claimable Agent',
    );

    const agentsMineResponse = await readAgentsMine(humanToken);
    const meResponse = await readMe(humanToken);

    expect(agentsMineResponse.agents.map(({ id }) => id)).toEqual([
      ownedNewer.id,
      ownedOlder.id,
    ]);
    expect(meResponse.recommendedActiveAgentId).toBe(
      agentsMineResponse.agents[0].id,
    );
    expect(meResponse.recommendedActiveAgentId).toBe(ownedNewer.id);
    expect(meResponse.recommendedActiveAgentId).not.toBe(suspendedOwned.id);
    expect(meResponse.recommendedActiveAgentId).not.toBe(claimableAgent.id);
  });

  it('checks username availability before registration and rejects duplicates during registration', async () => {
    await registerEmailHuman(
      'username-owner@example.com',
      'username_owner',
      'Username Owner',
    );

    const availableResponse = await request(app.getHttpServer())
      .get('/api/v1/auth/username-availability')
      .query({ username: '@fresh_handle' })
      .expect(200);

    expect(availableResponse.body).toEqual({
      normalizedUsername: 'fresh_handle',
      available: true,
      message: 'Username is available.',
    });

    const takenResponse = await request(app.getHttpServer())
      .get('/api/v1/auth/username-availability')
      .query({ username: 'username_owner' })
      .expect(200);

    expect(takenResponse.body).toEqual({
      normalizedUsername: 'username_owner',
      available: false,
      message: 'Username @username_owner is already taken.',
    });

    await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email: 'duplicate-username@example.com',
        username: 'username_owner',
        displayName: 'Duplicate Username',
        password: 'password123',
      })
      .expect(409);
  });

  async function registerEmailHuman(
    email: string,
    username: string,
    displayName: string,
  ): Promise<HumanAuthResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email,
        username,
        displayName,
        password: 'password123',
      })
      .expect(201);

    return typedValue<HumanAuthResponse>(response.body);
  }

  async function loginEmailHuman(email: string): Promise<HumanAuthResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/login/email')
      .send({
        email,
        password: 'password123',
      })
      .expect(200);

    return typedValue<HumanAuthResponse>(response.body);
  }

  async function loginProviderHuman(
    path: string,
    email: string,
    displayName: string,
    providerSubject: string,
    expectedStatus = 200,
  ): Promise<HumanAuthResponse | Record<string, unknown>> {
    const response = await request(app.getHttpServer())
      .post(path)
      .send({
        email,
        displayName,
        providerSubject,
      })
      .expect(expectedStatus);

    if (expectedStatus === 200) {
      return typedValue<HumanAuthResponse>(response.body);
    }

    return typedValue<Record<string, unknown>>(response.body);
  }

  async function importHumanOwnedAgent(
    accessToken: string,
    handle: string,
    displayName: string,
  ): Promise<ImportedAgentResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        handle,
        displayName,
      })
      .expect(201);

    return typedValue<ImportedAgentResponse>(response.body);
  }

  async function importSelfOwnedAgent(
    handle: string,
    displayName: string,
  ): Promise<ImportedAgentResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/self')
      .send({
        handle,
        displayName,
      })
      .expect(201);

    return typedValue<ImportedAgentResponse>(response.body);
  }

  async function readAgentsMine(
    accessToken: string,
  ): Promise<AgentsMineResponse> {
    const response = await request(app.getHttpServer())
      .get('/api/v1/agents/mine')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    return typedValue<AgentsMineResponse>(response.body);
  }

  async function readMe(accessToken: string): Promise<MeResponse> {
    const response = await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    return typedValue<MeResponse>(response.body);
  }
});
