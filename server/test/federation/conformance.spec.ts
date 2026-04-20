import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import {
  AgentOwnerType,
  ClaimRequestStatus,
  FollowTargetType,
  SubjectType,
} from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { ClaimRequestEntity } from '../../src/database/entities/claim-request.entity';
import { FollowEntity } from '../../src/database/entities/follow.entity';
import { FederationCredentialsService } from '../../src/modules/federation/federation-credentials.service';
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
} from './support/federation-test-support';

describe('Federation conformance (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let federationCredentialsService: FederationCredentialsService;
  let agentRepository: Repository<AgentEntity>;
  let followRepository: Repository<FollowEntity>;
  let claimRequestRepository: Repository<ClaimRequestEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    federationCredentialsService = app.get(FederationCredentialsService);
    agentRepository = context.dataSource.getRepository(AgentEntity);
    followRepository = context.dataSource.getRepository(FollowEntity);
    claimRequestRepository =
      context.dataSource.getRepository(ClaimRequestEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('covers profile update, follow/unfollow, and claim.confirm against canonical models', async () => {
    const profileAgent = await importSelfAgent(
      app,
      'conformance-profile',
      'Conformance Profile',
    );
    const followTarget = await importSelfAgent(
      app,
      'conformance-target',
      'Conformance Target',
    );
    const claimAgent = await importSelfAgent(
      app,
      'conformance-claim',
      'Conformance Claim',
    );
    const profileClaim = await claimFederatedAgent(
      app,
      federationCredentialsService,
      profileAgent.id,
      {
        pollingEnabled: true,
      },
    );
    const claimConnection = await claimFederatedAgent(
      app,
      federationCredentialsService,
      claimAgent.id,
      {
        pollingEnabled: true,
      },
    );
    const human = await registerHuman(
      app,
      'conformance-owner@example.com',
      'Conformance Owner',
    );
    const persistedProfileAgent = await agentRepository.findOneByOrFail({
      id: profileAgent.id,
    });
    persistedProfileAgent.profileMetadata = {
      ...persistedProfileAgent.profileMetadata,
      existingFlag: true,
    };
    await agentRepository.save(persistedProfileAgent);

    const profileUpdate = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${profileClaim.accessToken}`)
      .set('Idempotency-Key', 'conformance-profile-update')
      .send({
        type: 'agent.profile.update',
        payload: {
          displayName: 'Conformance Profile Updated',
          bio: 'Updated through federation.',
          tags: ['federation', 'task-5'],
          personality: {
            summary: 'Warm but selective systems collaborator.',
            warmth: 'high',
            curiosity: 'medium',
            restraint: 'high',
            cadence: 'normal',
            autoEvolve: true,
            lastDreamedAt: '2026-04-20T00:00:00.000Z',
          },
        },
      })
      .expect(202);
    const profileUpdateBody = typedValue<{ id: string }>(profileUpdate.body);
    const finalProfileAction = await waitForActionStatus(
      app,
      profileClaim.accessToken,
      profileUpdateBody.id,
    );
    const updatedProfileActionAgent = finalProfileAction.result?.agent as
      | {
          personality?: { summary?: string; warmth?: string };
          profileMetadata?: { existingFlag?: boolean };
        }
      | undefined;
    expect(updatedProfileActionAgent?.personality?.summary).toBe(
      'Warm but selective systems collaborator.',
    );
    expect(updatedProfileActionAgent?.personality?.warmth).toBe('high');
    expect(updatedProfileActionAgent?.profileMetadata?.existingFlag).toBe(true);

    const updatedProfileAgent = await agentRepository.findOneByOrFail({
      id: profileAgent.id,
    });
    expect(updatedProfileAgent.displayName).toBe('Conformance Profile Updated');
    expect(updatedProfileAgent.bio).toBe('Updated through federation.');
    expect(updatedProfileAgent.profileTags).toEqual(['federation', 'task-5']);
    expect(updatedProfileAgent.profileMetadata).toMatchObject({
      existingFlag: true,
      personality: {
        summary: 'Warm but selective systems collaborator.',
        warmth: 'high',
        curiosity: 'medium',
        restraint: 'high',
        cadence: 'normal',
        autoEvolve: true,
        lastDreamedAt: '2026-04-20T00:00:00.000Z',
      },
    });

    const publicDirectoryResponse = await request(app.getHttpServer())
      .get('/api/v1/agents/public-directory')
      .expect(200);
    const publicDirectoryBody = typedValue<{
      agents: Array<{ id: string; personality?: { summary?: string } | null }>;
    }>(publicDirectoryResponse.body);
    const publicDirectoryAgent = publicDirectoryBody.agents.find(
      (agent) => agent.id === profileAgent.id,
    );
    expect(publicDirectoryAgent?.personality?.summary).toBe(
      'Warm but selective systems collaborator.',
    );

    const followAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${profileClaim.accessToken}`)
      .set('Idempotency-Key', 'conformance-follow')
      .send({
        type: 'agent.follow',
        payload: {
          targetType: 'agent',
          targetId: followTarget.id,
        },
      })
      .expect(202);
    const followActionBody = typedValue<{ id: string }>(followAction.body);
    await waitForActionStatus(
      app,
      profileClaim.accessToken,
      followActionBody.id,
    );

    const followEdge = await followRepository.findOneByOrFail({
      followerType: SubjectType.Agent,
      followerSubjectId: profileAgent.id,
      targetType: FollowTargetType.Agent,
      targetSubjectId: followTarget.id,
    });
    expect(followEdge.followerAgentId).toBe(profileAgent.id);

    const unfollowAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${profileClaim.accessToken}`)
      .set('Idempotency-Key', 'conformance-unfollow')
      .send({
        type: 'agent.unfollow',
        payload: {
          targetType: 'agent',
          targetId: followTarget.id,
        },
      })
      .expect(202);
    const unfollowActionBody = typedValue<{ id: string }>(unfollowAction.body);
    await waitForActionStatus(
      app,
      profileClaim.accessToken,
      unfollowActionBody.id,
    );

    const removedFollow = await followRepository.findOneBy({
      followerType: SubjectType.Agent,
      followerSubjectId: profileAgent.id,
      targetType: FollowTargetType.Agent,
      targetSubjectId: followTarget.id,
    });
    expect(removedFollow).toBeNull();

    const claimRequestResponse = await request(app.getHttpServer())
      .post(`/api/v1/agents/${claimAgent.id}/claim-requests`)
      .set('Authorization', `Bearer ${human.accessToken}`)
      .expect(201);
    const claimRequestBody = typedValue<{
      claimRequest: { id: string };
      challengeToken: string;
    }>(claimRequestResponse.body);

    const claimConfirmAction = await request(app.getHttpServer())
      .post('/api/v1/actions')
      .set('Authorization', `Bearer ${claimConnection.accessToken}`)
      .set('Idempotency-Key', 'conformance-claim-confirm')
      .send({
        type: 'claim.confirm',
        payload: {
          claimRequestId: claimRequestBody.claimRequest.id,
          challengeToken: claimRequestBody.challengeToken,
        },
      })
      .expect(202);
    const claimConfirmActionBody = typedValue<{ id: string }>(
      claimConfirmAction.body,
    );

    const finalClaimAction = await waitForActionStatus(
      app,
      claimConnection.accessToken,
      claimConfirmActionBody.id,
    );
    expect(finalClaimAction.status).toBe('succeeded');

    const claimedAgent = await agentRepository.findOneByOrFail({
      id: claimAgent.id,
    });
    const claimRequest = await claimRequestRepository.findOneByOrFail({
      id: claimRequestBody.claimRequest.id,
    });

    expect(claimedAgent.ownerType).toBe(AgentOwnerType.Human);
    expect(claimedAgent.ownerUserId).toBe(human.user.id);
    expect(claimRequest.status).toBe(ClaimRequestStatus.Confirmed);
  });
});
