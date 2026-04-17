import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';

describe('Agent safety policy (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
  });

  afterAll(async () => {
    await context?.close();
  });

  it('returns owned agent safety policy from /agents/mine with proactive interactions enabled by default', async () => {
    const owner = await registerHuman(
      'safety-owner@example.com',
      'Safety Owner',
    );

    const importedAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        handle: 'safety-owned-agent',
        displayName: 'Safety Owned Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);

    await request(app.getHttpServer())
      .get('/api/v1/agents/mine')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(200)
      .expect(
        ({
          body,
        }: {
          body: {
            agents: Array<{
              id: string;
              safetyPolicy?: {
                dmPolicyMode: string;
                requiresMutualFollowForDm: boolean;
                allowProactiveInteractions: boolean;
                activityLevel: string;
              };
            }>;
          };
        }) => {
          const agent = body.agents.find(
            (entry) => entry.id === importedAgent.id,
          );
          expect(agent?.safetyPolicy).toEqual({
            dmPolicyMode: 'followers_only',
            requiresMutualFollowForDm: false,
            allowProactiveInteractions: true,
            activityLevel: 'normal',
          });
        },
      );
  });

  it('lets the owner read and update an owned agent safety policy', async () => {
    const owner = await registerHuman(
      'policy-owner@example.com',
      'Policy Owner',
    );

    const ownedAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        handle: 'policy-owned-agent',
        displayName: 'Policy Owned Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);

    await request(app.getHttpServer())
      .get(`/api/v1/agents/${ownedAgent.id}/safety-policy`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(200)
      .expect(({ body }: { body: Record<string, unknown> }) => {
        expect(body).toMatchObject({
          dmPolicyMode: 'followers_only',
          requiresMutualFollowForDm: false,
          allowProactiveInteractions: true,
          activityLevel: 'normal',
        });
      });

    await request(app.getHttpServer())
      .patch(`/api/v1/agents/${ownedAgent.id}/safety-policy`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        dmPolicyMode: 'followers_only',
        requiresMutualFollowForDm: true,
        activityLevel: 'high',
      })
      .expect(200)
      .expect(({ body }: { body: Record<string, unknown> }) => {
        expect(body).toMatchObject({
          dmPolicyMode: 'followers_only',
          requiresMutualFollowForDm: true,
          allowProactiveInteractions: true,
          activityLevel: 'high',
        });
      });

    await request(app.getHttpServer())
      .get(`/api/v1/agents/${ownedAgent.id}/safety-policy`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .expect(200)
      .expect(({ body }: { body: Record<string, unknown> }) => {
        expect(body).toMatchObject({
          dmPolicyMode: 'followers_only',
          requiresMutualFollowForDm: true,
          allowProactiveInteractions: true,
          activityLevel: 'high',
        });
      });
  });

  it('returns 403 when a non-owner tries to modify another human-owned agent safety policy', async () => {
    const owner = await registerHuman('owner-two@example.com', 'Owner Two');
    const intruder = await registerHuman(
      'policy-intruder@example.com',
      'Policy Intruder',
    );

    const ownedAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        handle: 'intruder-target-agent',
        displayName: 'Intruder Target Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);

    await request(app.getHttpServer())
      .patch(`/api/v1/agents/${ownedAgent.id}/safety-policy`)
      .set('Authorization', `Bearer ${intruder.accessToken}`)
      .send({
        dmPolicyMode: 'closed',
      })
      .expect(403);
  });

  it('lets a federated agent read its own safety policy', async () => {
    const claimed = await bootstrapAndClaimSelfAgent(
      'federated-safety-agent',
      'Federated Safety Agent',
    );

    await request(app.getHttpServer())
      .get('/api/v1/agents/self/safety-policy')
      .set('Authorization', `Bearer ${claimed.accessToken}`)
      .expect(200)
      .expect(({ body }: { body: Record<string, unknown> }) => {
        expect(body).toMatchObject({
          dmPolicyMode: 'followers_only',
          requiresMutualFollowForDm: false,
          allowProactiveInteractions: true,
          activityLevel: 'normal',
        });
      });
  });

  async function registerHuman(email: string, displayName: string) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email,
        username: buildUsername(email),
        displayName,
        password: 'password123',
      })
      .expect(201);

    return response.body as {
      accessToken: string;
      user: {
        id: string;
      };
    };
  }

  async function bootstrapAndClaimSelfAgent(
    handle: string,
    displayName: string,
  ) {
    const bootstrap = await request(app.getHttpServer())
      .post('/api/v1/agents/bootstrap/public')
      .send({
        handle,
        displayName,
      })
      .expect(201)
      .then(
        ({
          body,
        }: {
          body: {
            bootstrap: {
              agent: { id: string };
              claimToken: string;
            };
          };
        }) => body.bootstrap,
      );

    const claim = await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: bootstrap.claimToken,
        pollingEnabled: true,
      })
      .expect(201)
      .then(
        ({
          body,
        }: {
          body: {
            accessToken: string;
          };
        }) => body,
      );

    return {
      agentId: bootstrap.agent.id,
      accessToken: claim.accessToken,
    };
  }

  function buildUsername(email: string): string {
    return (
      email
        .trim()
        .toLowerCase()
        .split('@')[0]
        ?.replace(/[^a-z0-9]+/g, '_')
        .replace(/^_+|_+$/g, '')
        .slice(0, 24) || 'human_user'
    );
  }
});
