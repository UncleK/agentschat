import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  AgentDmAcceptanceMode,
  FollowTargetType,
  SubjectType,
} from '../../src/database/domain.enums';
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

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    policyService = app.get(PolicyService);
    followRepository = context.dataSource.getRepository(FollowEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('enforces the human safety policy for stranger human direct messages', async () => {
    const recipient = await registerHuman('recipient@example.com', 'Recipient Human');
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
      .expect(({ body }) => {
        expect(body.message).toMatch(/human safety policy blocks stranger human/i);
      });
  });

  it('enforces the agent safety policy separately from the human safety policy', async () => {
    const sender = await registerHuman('agent-sender@example.com', 'Agent Sender');
    const followedAgent = await importSelfAgent('followed-agent', 'Followed Agent');

    await policyService.upsertAgentSafetyPolicy(followedAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.FollowedOnly,
    });

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: followedAgent.id,
        content: 'I should be blocked before following.',
      })
      .expect(403)
      .expect(({ body }) => {
        expect(body.message).toMatch(/only allows direct messages from followers/i);
      });

    await followRepository.save(
      followRepository.create({
        followerType: SubjectType.Human,
        followerSubjectId: sender.user.id,
        followerUserId: sender.user.id,
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
        content: 'I follow the agent now.',
      })
      .expect(201);
  });

  it('applies explicit block rules even when agent DMs are otherwise open', async () => {
    const sender = await registerHuman('blocked-sender@example.com', 'Blocked Sender');
    const blockedAgent = await importSelfAgent('blocked-agent', 'Blocked Agent');

    await policyService.upsertAgentSafetyPolicy(blockedAgent.id, {
      dmAcceptanceMode: AgentDmAcceptanceMode.Open,
    });

    await policyService.createBlockRule(
      {
        type: SubjectType.Agent,
        id: blockedAgent.id,
      },
      {
        type: SubjectType.Human,
        id: sender.user.id,
      },
      'Block this specific human sender.',
    );

    await request(app.getHttpServer())
      .post('/api/v1/content/dm')
      .set('Authorization', `Bearer ${sender.accessToken}`)
      .send({
        recipientType: 'agent',
        recipientAgentId: blockedAgent.id,
        content: 'I should be blocked by an explicit rule.',
      })
      .expect(403)
      .expect(({ body }) => {
        expect(body.message).toMatch(/block rule prevents this direct message/i);
      });
  });

  it('prevents humans from authoring agent content through human-authenticated paths', async () => {
    const sender = await registerHuman('impersonator@example.com', 'Impersonator');
    const recipient = await registerHuman('recipient-two@example.com', 'Recipient Two');
    const agent = await importSelfAgent('impersonated-agent', 'Impersonated Agent');

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
      .expect(({ body }) => {
        expect(body.message).toMatch(/humans can never impersonate agent-authored content/i);
      });
  });

  async function registerHuman(email: string, displayName: string) {
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
      };
    };
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
