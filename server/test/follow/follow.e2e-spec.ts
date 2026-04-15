import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  DebateSessionStatus,
  SubjectType,
  ThreadContextType,
  ThreadVisibility,
} from '../../src/database/domain.enums';
import { DebateSessionEntity } from '../../src/database/entities/debate-session.entity';
import { FollowEntity } from '../../src/database/entities/follow.entity';
import { ForumTopicViewEntity } from '../../src/database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../src/database/entities/thread.entity';
import { ContentService } from '../../src/modules/content/content.service';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
import { PolicyService } from '../../src/modules/policy/policy.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';
import {
  claimFederatedAgent,
  importSelfAgent,
  registerHuman,
  waitForActionStatus,
} from '../federation/support/federation-test-support';

describe('Follow backend (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let contentService: ContentService;
  let federationCredentialsService: FederationCredentialsService;
  let policyService: PolicyService;
  let threadRepository: Repository<ThreadEntity>;
  let debateSessionRepository: Repository<DebateSessionEntity>;
  let followRepository: Repository<FollowEntity>;
  let forumTopicViewRepository: Repository<ForumTopicViewEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    contentService = app.get(ContentService);
    federationCredentialsService = app.get(FederationCredentialsService);
    policyService = app.get(PolicyService);
    threadRepository = context.dataSource.getRepository(ThreadEntity);
    debateSessionRepository =
      context.dataSource.getRepository(DebateSessionEntity);
    followRepository = context.dataSource.getRepository(FollowEntity);
    forumTopicViewRepository =
      context.dataSource.getRepository(ForumTopicViewEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('routes agent follows through an owned active agent while forum topic follows stay agent-only', async () => {
    const human = await registerHuman(
      app,
      'follow-human@example.com',
      'Follow Human',
    );
    const ownedActorResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        handle: 'follow-owned-actor',
        displayName: 'Follow Owned Actor',
      })
      .expect(201);
    const ownedActor = typedValue<{ id: string }>(ownedActorResponse.body);
    const followedAgent = await importSelfAgent(
      app,
      'follow-target-agent',
      'Follow Target',
    );
    const topic = await contentService.createForumTopic(
      {
        type: SubjectType.Human,
        id: human.user.id,
      },
      {
        title: 'Task 7 topic',
        content: 'Topic body',
      },
    );
    const debateThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Task 7 debate',
      }),
    );
    const debateSession = await debateSessionRepository.save(
      debateSessionRepository.create({
        threadId: debateThread.id,
        topic: 'Should follows be unified?',
        proStance: 'Yes',
        conStance: 'No',
        hostType: SubjectType.Human,
        hostUserId: human.user.id,
        status: DebateSessionStatus.Live,
      }),
    );

    await request(app.getHttpServer())
      .post('/api/v1/follows')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({ targetType: 'agent', targetId: followedAgent.id })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(/active agent/i);
      });

    await request(app.getHttpServer())
      .post('/api/v1/follows')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        targetType: 'agent',
        targetId: followedAgent.id,
        actorType: 'agent',
        actorAgentId: ownedActor.id,
      })
      .expect(201)
      .expect(({ body }: { body: { following: boolean; actorId: string } }) => {
        expect(body.actorId).toBe(ownedActor.id);
        expect(body.following).toBe(true);
      });

    await request(app.getHttpServer())
      .post('/api/v1/follows')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({ targetType: 'topic', targetId: topic.threadId })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(
          /topic follows must be initiated by an agent/i,
        );
      });

    await request(app.getHttpServer())
      .post('/api/v1/follows')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({ targetType: 'debate', targetId: debateSession.id })
      .expect(201);

    const topicView = await forumTopicViewRepository.findOneByOrFail({
      threadId: topic.threadId,
    });
    const storedFollows = await followRepository.findBy({
      followerSubjectId: human.user.id,
    });
    const storedAgentFollows = await followRepository.findBy({
      followerSubjectId: ownedActor.id,
    });

    expect(storedFollows).toHaveLength(1);
    expect(storedAgentFollows).toHaveLength(1);
    expect(topicView.followCount).toBe(0);

    await request(app.getHttpServer())
      .delete('/api/v1/follows')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({ targetType: 'debate', targetId: debateSession.id })
      .expect(200)
      .expect(({ body }: { body: { following: boolean } }) => {
        expect(body.following).toBe(false);
      });

    await request(app.getHttpServer())
      .get('/api/v1/follows/state')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .query({ targetType: 'topic', targetId: topic.threadId })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(
          /topic follows must be initiated by an agent/i,
        );
      });

    await request(app.getHttpServer())
      .get('/api/v1/follows/state')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .query({ targetType: 'agent', targetId: followedAgent.id })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(/active agent/i);
      });

    await request(app.getHttpServer())
      .get('/api/v1/follows/state')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .query({
        targetType: 'agent',
        targetId: followedAgent.id,
        actorType: 'agent',
        actorAgentId: ownedActor.id,
      })
      .expect(200)
      .expect(({ body }: { body: { following: boolean } }) => {
        expect(body.following).toBe(true);
      });

    await request(app.getHttpServer())
      .get('/api/v1/agents/directory')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .query({ activeAgentId: ownedActor.id })
      .expect(200)
      .expect(
        ({
          body,
        }: {
          body: {
            actor: { type: string; id: string };
            agents: Array<{
              id: string;
              followerCount: number;
              relationship: {
                viewerFollowsAgent: boolean;
                agentFollowsViewer: boolean;
              };
              dmPolicy: {
                acceptanceMode: string;
                directMessageAllowed: boolean;
              };
            }>;
          };
        }) => {
          const directoryAgent = body.agents.find(
            (agent) => agent.id === followedAgent.id,
          );

          expect(body.actor).toEqual({
            type: SubjectType.Agent,
            id: ownedActor.id,
          });
          expect(directoryAgent).toBeDefined();
          expect(directoryAgent?.followerCount).toBe(1);
          expect(directoryAgent?.relationship.viewerFollowsAgent).toBe(true);
          expect(directoryAgent?.relationship.agentFollowsViewer).toBe(false);
          expect(directoryAgent?.dmPolicy.acceptanceMode).toBe(
            'approval_required',
          );
          expect(directoryAgent?.dmPolicy.directMessageAllowed).toBe(false);
        },
      );
  });

  it('lets a federated agent follow all target types and reuses block rules for human follows', async () => {
    const human = await registerHuman(
      app,
      'blocked-follow@example.com',
      'Blocked Follow',
    );
    const blocker = await importSelfAgent(
      app,
      'blocker-agent',
      'Blocker Agent',
    );
    const followerAgent = await importSelfAgent(
      app,
      'follower-agent',
      'Follower Agent',
    );
    const ownedBlockTestResponse = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        handle: 'blocked-owned-follower',
        displayName: 'Blocked Owned Follower',
      })
      .expect(201);
    const ownedBlockTestAgent = typedValue<{ id: string }>(
      ownedBlockTestResponse.body,
    );
    const topicAuthor = await importSelfAgent(
      app,
      'topic-author-agent',
      'Topic Author',
    );
    const agentClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      followerAgent.id,
      {
        pollingEnabled: true,
      },
    );
    const topic = await contentService.createForumTopic(
      {
        type: SubjectType.Agent,
        id: topicAuthor.id,
      },
      {
        title: 'Agent follow topic',
        content: 'Topic authored by agent.',
      },
    );
    const debateThread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DebateSpectator,
        visibility: ThreadVisibility.Public,
        title: 'Agent follow debate',
      }),
    );
    const debateSession = await debateSessionRepository.save(
      debateSessionRepository.create({
        threadId: debateThread.id,
        topic: 'Agent follow debate topic',
        proStance: 'Pro',
        conStance: 'Con',
        hostType: SubjectType.Agent,
        hostAgentId: topicAuthor.id,
        status: DebateSessionStatus.Live,
      }),
    );

    await submitAgentFollowAction(
      agentClaim.accessToken,
      'agent.follow.agent',
      {
        targetType: 'agent',
        targetId: blocker.id,
      },
    );
    await submitAgentFollowAction(
      agentClaim.accessToken,
      'agent.follow.topic',
      {
        targetType: 'topic',
        targetId: topic.threadId,
      },
    );
    await submitAgentFollowAction(
      agentClaim.accessToken,
      'agent.follow.debate',
      {
        targetType: 'debate',
        targetId: debateSession.id,
      },
    );

    const agentFollows = await followRepository.findBy({
      followerSubjectId: followerAgent.id,
    });

    expect(agentFollows).toHaveLength(3);

    await submitAgentFollowAction(
      agentClaim.accessToken,
      'agent.unfollow.agent',
      {
        type: 'agent.unfollow',
        targetType: 'agent',
        targetId: blocker.id,
      },
    );

    await policyService.createBlockRule(
      {
        type: SubjectType.Agent,
        id: blocker.id,
      },
      {
        type: SubjectType.Agent,
        id: ownedBlockTestAgent.id,
      },
      'Block this active agent from following.',
    );

    await request(app.getHttpServer())
      .post('/api/v1/follows')
      .set('Authorization', `Bearer ${human.accessToken}`)
      .send({
        targetType: 'agent',
        targetId: blocker.id,
        actorType: 'agent',
        actorAgentId: ownedBlockTestAgent.id,
      })
      .expect(403)
      .expect(({ body }: { body: { message: string } }) => {
        expect(body.message).toMatch(/block rule prevents this follow/i);
      });
  });

  async function submitAgentFollowAction(
    accessToken: string,
    idempotencyKey: string,
    payload: Record<string, unknown> & { type?: string },
  ) {
    const response = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${accessToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({
        type: payload.type ?? 'agent.follow',
        payload: {
          targetType: payload.targetType,
          targetId: payload.targetId,
        },
      })
      .expect(202);
    const responseBody = typedValue<{ id: string }>(response.body);

    const finalAction = await waitForActionStatus(
      app,
      accessToken,
      responseBody.id,
    );

    expect(finalAction.status).toBe('succeeded');
  }
});
