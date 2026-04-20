import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  AgentDmAcceptanceMode,
  FollowTargetType,
  SubjectType,
} from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { FollowEntity } from '../../src/database/entities/follow.entity';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
} from '../support/test-app';

describe('Safety policies', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let policyService: PolicyService;
  let followRepository: Repository<FollowEntity>;
  let agentRepository: Repository<AgentEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    policyService = app.get(PolicyService);
    followRepository = context.dataSource.getRepository(FollowEntity);
    agentRepository = context.dataSource.getRepository(AgentEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('requires an active agent before opening external human direct messages', async () => {
    const recipient = await registerHuman(
      'recipient@example.com',
      'Recipient Human',
    );
    const sender = await registerHuman('sender@example.com', 'Sender Human');

    await policyService.updateHumanSafetyPolicy(recipient.user.id, {
      blockStrangerHumanDm: true,
    });

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        content: 'Hello from a stranger human.',
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(
          /activate an owned agent before creating an external direct message/i,
        );
      });
  });

  it('enforces the agent safety policy through active-agent follow edges', async () => {
    const sender = await registerHuman(
      'agent-sender@example.com',
      'Agent Sender',
    );
    const activeAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        handle: 'followed-active-agent',
        displayName: 'Followed Active Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);
    const followedAgent = await importSelfAgent(
      'followed-agent',
      'Followed Agent',
    );

    await policyService.upsertAgentSafetyPolicy(followedAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.FollowedOnly,
    });

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: followedAgent.id,
        activeAgentId: activeAgent.id,
        content: 'I should be blocked before following.',
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(
          /only allows direct messages from followers/i,
        );
      });

    await followRepository.save(
      followRepository.create({
        followerType: SubjectType.Agent,
        followerSubjectId: activeAgent.id,
        followerAgentId: activeAgent.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: followedAgent.id,
        targetAgentId: followedAgent.id,
      }),
    );

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: followedAgent.id,
        activeAgentId: activeAgent.id,
        content: 'I follow the agent now.',
      })
      .expect(201);
  });

  it('applies explicit block rules even when agent DMs are otherwise open', async () => {
    const sender = await registerHuman(
      'blocked-sender@example.com',
      'Blocked Sender',
    );
    const senderAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        handle: 'blocked-sender-agent',
        displayName: 'Blocked Sender Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);
    const blockedAgent = await importSelfAgent(
      'blocked-agent',
      'Blocked Agent',
    );

    await policyService.upsertAgentSafetyPolicy(blockedAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    await policyService.createBlockRule(
      {
        type: SubjectType.Agent,
        id: blockedAgent.id,
      },
      {
        type: SubjectType.Agent,
        id: senderAgent.id,
      },
      'Block this specific human sender.',
    );

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: blockedAgent.id,
        activeAgentId: senderAgent.id,
        content: 'I should be blocked by an explicit rule.',
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(
          /block rule prevents this direct message/i,
        );
      });
  });

  it('enforces mutual follow when an agent profile requires it', async () => {
    const sender = await registerHuman(
      'mutual-sender@example.com',
      'Mutual Sender',
    );
    const activeAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        handle: 'mutual-active-agent',
        displayName: 'Mutual Active Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);
    const recipientAgent = await importSelfAgent(
      'mutual-required-agent',
      'Mutual Required Agent',
    );

    await policyService.upsertAgentSafetyPolicy(recipientAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });
    await agentRepository.update(
      { id: recipientAgent.id },
      { profileMetadata: { dmRequiresMutualFollow: true } },
    );

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: recipientAgent.id,
        activeAgentId: activeAgent.id,
        content: 'Blocked until both agents follow each other.',
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(/requires mutual follow/i);
      });

    await followRepository.save([
      followRepository.create({
        followerType: SubjectType.Agent,
        followerSubjectId: activeAgent.id,
        followerAgentId: activeAgent.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: recipientAgent.id,
        targetAgentId: recipientAgent.id,
      }),
      followRepository.create({
        followerType: SubjectType.Agent,
        followerSubjectId: recipientAgent.id,
        followerAgentId: recipientAgent.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: activeAgent.id,
        targetAgentId: activeAgent.id,
      }),
    ]);

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: recipientAgent.id,
        activeAgentId: activeAgent.id,
        content: 'Both agent follow edges are present now.',
      })
      .expect(201);
  });

  it('lets a human owner open and read a direct admin thread with their own agent', async () => {
    const owner = await registerHuman('owned-admin@example.com', 'Owned Admin');
    const ownedAgent = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        handle: 'owned-admin-agent',
        displayName: 'Owned Admin Agent',
      })
      .expect(201)
      .then(({ body }: { body: { id: string } }) => body);

    await policyService.upsertAgentSafetyPolicy(ownedAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.FollowedOnly,
    });
    await agentRepository.update(
      { id: ownedAgent.id },
      { profileMetadata: { dmRequiresMutualFollow: true } },
    );

    const sendResponse = await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: ownedAgent.id,
        content: 'Admin command ping.',
      })
      .expect(201);

    const threadId = (sendResponse.body as { threadId: string }).threadId;
    expect(threadId).toBeTruthy();

    await request(app.getHttpServer())
      .get('/api/v1/content/dm/threads')
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({
        activeAgentId: ownedAgent.id,
        threadUsage: 'owned_agent_command',
      })
      .expect(200)
      .expect(
        ({
          body,
        }: {
          body: {
            threads: Array<{
              threadId: string;
              threadUsage?: string;
              counterpart: { type: string; id: string };
            }>;
          };
        }) => {
          expect(body.threads).toHaveLength(1);
          expect(body.threads[0]?.threadId).toBe(threadId);
          expect(body.threads[0]?.threadUsage).toBe('owned_agent_command');
          expect(body.threads[0]?.counterpart.type).toBe('human');
          expect(body.threads[0]?.counterpart.id).toBe(owner.user.id);
        },
      );

    await request(app.getHttpServer())
      .get(`/api/v1/content/dm/threads/${threadId}/messages`)
      .set('Authorization', `Bearer ${owner.accessToken}`)
      .query({ activeAgentId: ownedAgent.id })
      .expect(200)
      .expect(
        ({
          body,
        }: {
          body: {
            messages: Array<{
              actor: { type: string; id: string };
              content: string | null;
            }>;
          };
        }) => {
          expect(body.messages).toHaveLength(1);
          expect(body.messages[0]?.actor.type).toBe('human');
          expect(body.messages[0]?.actor.id).toBe(owner.user.id);
          expect(body.messages[0]?.content).toBe('Admin command ping.');
        },
      );
  });

  it('prevents humans from authoring agent content through human-authenticated paths', async () => {
    const sender = await registerHuman(
      'impersonator@example.com',
      'Impersonator',
    );
    const recipient = await registerHuman(
      'recipient-two@example.com',
      'Recipient Two',
    );
    const agent = await importSelfAgent(
      'impersonated-agent',
      'Impersonated Agent',
    );

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'human',
        recipientUserId: recipient.user.id,
        content: 'Pretending to be an agent.',
        actorType: 'agent',
        actorAgentId: agent.id,
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(
          /humans can never impersonate agent-authored content/i,
        );
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
        email: string;
      };
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

  async function importSelfAgent(handle: string, displayName: string) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/self')
      .send({
        handle,
        displayName,
      })
      .expect(201);

    return response.body as {
      id: string;
      ownerType: string;
    };
  }
});
