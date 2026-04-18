import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { Repository } from 'typeorm';
import { AgentStatus } from '../../src/database/domain.enums';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { ClaimRequestEntity } from '../../src/database/entities/claim-request.entity';
import { AgentsService } from '../../src/modules/agents/agents.service';
import {
  TestApplicationContext,
  createTestApplication,
  typedValue,
} from '../support/test-app';

interface HumanAuthResponse {
  accessToken: string;
  user: {
    id: string;
  };
}

interface AgentSummaryResponse {
  id: string;
  handle: string;
  displayName: string;
  avatarUrl: null;
  bio: string | null;
  ownerType: string;
  ownerUserId: string | null;
  status: string;
}

interface ClaimRequestResponse {
  claimRequest: {
    id: string;
    agentId: string;
    status: string;
    requestedAt: string;
    expiresAt: string;
  };
  challengeToken: string;
}

interface AgentsMineResponse {
  agents: AgentSummaryResponse[];
  claimableAgents: AgentSummaryResponse[];
  pendingClaims: Array<{
    claimRequestId: string;
    agentId: string;
    handle: string;
    displayName: string;
    status: string;
    requestedAt: string;
    expiresAt: string;
  }>;
}

interface ClaimConfirmationResponse {
  claimRequest: {
    status: string;
  };
  agent: {
    ownerType: string;
    ownerUserId: string | null;
  };
}

interface HumanOwnedInvitationResponse {
  invitation: {
    agentId: string;
    code: string;
    bootstrapPath: string;
    claimToken: string;
    expiresAt: string;
  };
}

interface AgentBootstrapResponse {
  protocolVersion: string;
  claimToken: string;
  expiresAt: string;
  agent: {
    id: string;
    handle: string;
    displayName: string;
    ownerType: string;
  };
  transport: {
    claimPath: string;
    actionsPath: string;
    pollingPath: string;
    acksPath: string;
  };
}

describe('Agent claim flow (e2e)', () => {
  let app: INestApplication;
  let context: TestApplicationContext;
  let agentRepository: Repository<AgentEntity>;
  let claimRequestRepository: Repository<ClaimRequestEntity>;

  beforeAll(async () => {
    context = await createTestApplication();
    app = context.app;
    agentRepository = context.dataSource.getRepository(AgentEntity);
    claimRequestRepository =
      context.dataSource.getRepository(ClaimRequestEntity);
  });

  afterAll(async () => {
    await context?.close();
  });

  it('returns distinct owned, claimable, and pending partitions for the current human', async () => {
    const registerResponse = await registerEmailHuman(
      'agents-mine-owner@example.com',
      'Agents Mine Owner',
    );

    const otherHuman = await registerEmailHuman(
      'agents-mine-other@example.com',
      'Other Claimer',
    );

    const humanToken = registerResponse.accessToken;
    const otherHumanToken = otherHuman.accessToken;

    const ownedOlder = await importHumanOwnedAgent(humanToken, {
      handle: 'owned-older-agent',
      displayName: 'Owned Older Agent',
      bio: 'Owned older bio',
    });

    const ownedNewer = await importHumanOwnedAgent(humanToken, {
      handle: 'owned-newer-agent',
      displayName: 'Owned Newer Agent',
    });

    const suspendedOwned = await importHumanOwnedAgent(humanToken, {
      handle: 'owned-suspended-agent',
      displayName: 'Owned Suspended Agent',
    });

    await agentRepository.update(
      { id: suspendedOwned.id },
      { status: AgentStatus.Suspended },
    );

    const claimableOlder = await importSelfOwnedAgent({
      handle: 'claimable-older-agent',
      displayName: 'Claimable Older Agent',
      bio: 'Claimable older bio',
    });

    const claimableNewer = await importSelfOwnedAgent({
      handle: 'claimable-newer-agent',
      displayName: 'Claimable Newer Agent',
    });

    const pendingOlder = await importSelfOwnedAgent({
      handle: 'pending-older-agent',
      displayName: 'Pending Older Agent',
    });

    const pendingNewer = await importSelfOwnedAgent({
      handle: 'pending-newer-agent',
      displayName: 'Pending Newer Agent',
    });

    const blockedByOtherPending = await importSelfOwnedAgent({
      handle: 'blocked-by-other-pending',
      displayName: 'Blocked By Other Pending',
    });

    const pendingOlderClaim = await createClaimRequest(
      humanToken,
      pendingOlder.id,
    );

    const pendingNewerClaim = await createClaimRequest(
      humanToken,
      pendingNewer.id,
    );

    await request(app.getHttpServer())
      .post(`/api/v1/agents/${blockedByOtherPending.id}/claim-requests`)
      .set('Authorization', `Bearer ${otherHumanToken}`)
      .expect(201);

    const agentsMineResponse = await readAgentsMine(humanToken);

    expect(agentsMineResponse.agents.map(({ id }) => id)).toEqual([
      ownedNewer.id,
      ownedOlder.id,
    ]);
    expect(agentsMineResponse.claimableAgents.map(({ id }) => id)).toEqual([
      claimableNewer.id,
      claimableOlder.id,
    ]);
    expect(
      agentsMineResponse.pendingClaims.map(
        ({ claimRequestId }) => claimRequestId,
      ),
    ).toEqual([
      pendingNewerClaim.claimRequest.id,
      pendingOlderClaim.claimRequest.id,
    ]);

    expect(agentsMineResponse.agents).toEqual([
      {
        id: ownedNewer.id,
        handle: 'owned-newer-agent',
        displayName: 'Owned Newer Agent',
        avatarUrl: null,
        bio: null,
        ownerType: 'human',
        safetyPolicy: {
          dmPolicyMode: 'followers_only',
          requiresMutualFollowForDm: false,
          allowProactiveInteractions: true,
          activityLevel: 'normal',
        },
        status: 'offline',
      },
      {
        id: ownedOlder.id,
        handle: 'owned-older-agent',
        displayName: 'Owned Older Agent',
        avatarUrl: null,
        bio: 'Owned older bio',
        ownerType: 'human',
        safetyPolicy: {
          dmPolicyMode: 'followers_only',
          requiresMutualFollowForDm: false,
          allowProactiveInteractions: true,
          activityLevel: 'normal',
        },
        status: 'offline',
      },
    ]);
    expect(agentsMineResponse.claimableAgents).toEqual([
      {
        id: claimableNewer.id,
        handle: 'claimable-newer-agent',
        displayName: 'Claimable Newer Agent',
        avatarUrl: null,
        bio: null,
        ownerType: 'self',
        status: 'offline',
      },
      {
        id: claimableOlder.id,
        handle: 'claimable-older-agent',
        displayName: 'Claimable Older Agent',
        avatarUrl: null,
        bio: 'Claimable older bio',
        ownerType: 'self',
        status: 'offline',
      },
    ]);
    expect(agentsMineResponse.pendingClaims).toEqual(
      typedValue<Array<Record<string, unknown>>>([
        {
          claimRequestId: pendingNewerClaim.claimRequest.id,
          agentId: pendingNewer.id,
          handle: 'pending-newer-agent',
          displayName: 'Pending Newer Agent',
          status: 'pending',
          requestedAt: typedValue<unknown>(expect.any(String)),
          expiresAt: typedValue<unknown>(expect.any(String)),
        },
        {
          claimRequestId: pendingOlderClaim.claimRequest.id,
          agentId: pendingOlder.id,
          handle: 'pending-older-agent',
          displayName: 'Pending Older Agent',
          status: 'pending',
          requestedAt: typedValue<unknown>(expect.any(String)),
          expiresAt: typedValue<unknown>(expect.any(String)),
        },
      ]),
    );

    expect(agentsMineResponse.agents).not.toContainEqual(
      expect.objectContaining({ id: suspendedOwned.id }),
    );
    expect(agentsMineResponse.claimableAgents).not.toContainEqual(
      expect.objectContaining({ id: blockedByOtherPending.id }),
    );
    expect(agentsMineResponse.pendingClaims).not.toContainEqual(
      expect.objectContaining({ agentId: blockedByOtherPending.id }),
    );

    expect(Object.keys(agentsMineResponse.agents[0] ?? {}).sort()).toEqual([
      'avatarUrl',
      'bio',
      'displayName',
      'handle',
      'id',
      'ownerType',
      'safetyPolicy',
      'status',
    ]);
    expect(
      Object.keys(agentsMineResponse.pendingClaims[0] ?? {}).sort(),
    ).toEqual([
      'agentId',
      'claimRequestId',
      'displayName',
      'expiresAt',
      'handle',
      'requestedAt',
      'status',
    ]);
  });

  it('moves a self-owned agent through claimable, pending, and owned partitions', async () => {
    const registerResponse = await registerEmailHuman(
      'claim-owner@example.com',
      'Claim Owner',
    );

    const humanToken = registerResponse.accessToken;

    const selfOwnedAgent = await importSelfOwnedAgent({
      handle: 'self-owned-agent',
      displayName: 'Self Owned Agent',
    });

    expect(selfOwnedAgent.ownerType).toBe('self');
    expect(selfOwnedAgent.ownerUserId).toBeNull();

    const claimableResponse = await readAgentsMine(humanToken);

    expect(claimableResponse.agents).toEqual([]);
    expect(claimableResponse.claimableAgents).toContainEqual({
      id: selfOwnedAgent.id,
      handle: 'self-owned-agent',
      displayName: 'Self Owned Agent',
      avatarUrl: null,
      bio: null,
      ownerType: 'self',
      status: 'offline',
    });
    expect(claimableResponse.pendingClaims).toEqual([]);

    const firstClaimRequest = await createClaimRequest(
      humanToken,
      selfOwnedAgent.id,
    );

    const secondClaimRequest = await createClaimRequest(
      humanToken,
      selfOwnedAgent.id,
      15,
    );

    expect(firstClaimRequest.claimRequest.status).toBe('pending');
    expect(firstClaimRequest.claimRequest.agentId).toBe(selfOwnedAgent.id);
    expect(firstClaimRequest.claimRequest.requestedAt).toEqual(
      expect.any(String),
    );
    expect(firstClaimRequest.claimRequest.expiresAt).toEqual(
      expect.any(String),
    );
    expect(secondClaimRequest.claimRequest.id).not.toBe(
      firstClaimRequest.claimRequest.id,
    );
    expect(secondClaimRequest.challengeToken).not.toBe(
      firstClaimRequest.challengeToken,
    );
    expect(firstClaimRequest.challengeToken).toMatch(/^claimreq\.v1\./);
    expect(secondClaimRequest.challengeToken).toMatch(/^claimreq\.v1\./);

    const pendingResponse = await readAgentsMine(humanToken);

    expect(pendingResponse.agents).toEqual([]);
    expect(pendingResponse.claimableAgents).not.toContainEqual(
      expect.objectContaining({ id: selfOwnedAgent.id }),
    );
    expect(pendingResponse.pendingClaims).toContainEqual(
      typedValue<Record<string, unknown>>({
        claimRequestId: secondClaimRequest.claimRequest.id,
        agentId: selfOwnedAgent.id,
        handle: 'self-owned-agent',
        displayName: 'Self Owned Agent',
        status: 'pending',
        requestedAt: typedValue<unknown>(expect.any(String)),
        expiresAt: typedValue<unknown>(expect.any(String)),
      }),
    );

    const confirmationResponse = await confirmClaimRequest(
      humanToken,
      selfOwnedAgent.id,
      secondClaimRequest.claimRequest.id,
      secondClaimRequest.challengeToken,
    );

    expect(confirmationResponse.claimRequest.status).toBe('confirmed');
    expect(confirmationResponse.agent.ownerType).toBe('human');
    expect(confirmationResponse.agent.ownerUserId).toBe(
      registerResponse.user.id,
    );

    const ownedResponse = await readAgentsMine(humanToken);

    expect(ownedResponse.agents).toContainEqual({
      id: selfOwnedAgent.id,
      handle: 'self-owned-agent',
      displayName: 'Self Owned Agent',
      avatarUrl: null,
      bio: null,
      ownerType: 'human',
      safetyPolicy: {
        dmPolicyMode: 'followers_only',
        requiresMutualFollowForDm: false,
        allowProactiveInteractions: true,
        activityLevel: 'normal',
      },
      status: 'offline',
    });
    expect(ownedResponse.claimableAgents).not.toContainEqual(
      expect.objectContaining({ id: selfOwnedAgent.id }),
    );
    expect(ownedResponse.pendingClaims).not.toContainEqual(
      expect.objectContaining({ agentId: selfOwnedAgent.id }),
    );
  });

  it('keeps a generic claim link visible as pending without forcing the human to choose from claimable agents first', async () => {
    const registerResponse = await registerEmailHuman(
      'generic-claim-link@example.com',
      'Generic Claim Link',
    );

    const humanToken = registerResponse.accessToken;
    const selfOwnedAgent = await importSelfOwnedAgent({
      handle: 'generic-claimable-agent',
      displayName: 'Generic Claimable Agent',
    });

    const genericClaimRequest = await createUntargetedClaimRequest(humanToken);

    expect(genericClaimRequest.claimRequest.status).toBe('pending');
    expect(genericClaimRequest.claimRequest.agentId).toBe('');
    expect(genericClaimRequest.challengeToken).toMatch(/^claimreq\.v1\./);

    const pendingResponse = await readAgentsMine(humanToken);

    expect(pendingResponse.claimableAgents).toContainEqual({
      id: selfOwnedAgent.id,
      handle: 'generic-claimable-agent',
      displayName: 'Generic Claimable Agent',
      avatarUrl: null,
      bio: null,
      ownerType: 'self',
      status: 'offline',
    });
    expect(pendingResponse.pendingClaims).toContainEqual(
      typedValue<Record<string, unknown>>({
        claimRequestId: genericClaimRequest.claimRequest.id,
        agentId: '',
        handle: '',
        displayName: '',
        status: 'pending',
        requestedAt: typedValue<unknown>(expect.any(String)),
        expiresAt: typedValue<unknown>(expect.any(String)),
      }),
    );
  });

  it('expires stale pending claims during readMine and allows a fresh claim link to be generated', async () => {
    const registerResponse = await registerEmailHuman(
      'claim-expire-owner@example.com',
      'Claim Expire Owner',
    );
    const humanToken = registerResponse.accessToken;
    const selfOwnedAgent = await importSelfOwnedAgent({
      handle: 'claim-expire-agent',
      displayName: 'Claim Expire Agent',
    });

    const firstClaimRequest = await createClaimRequest(
      humanToken,
      selfOwnedAgent.id,
      15,
    );

    await claimRequestRepository.update(
      { id: firstClaimRequest.claimRequest.id },
      {
        expiresAt: new Date(Date.now() - 60 * 1000),
      },
    );

    const expiredResponse = await readAgentsMine(humanToken);
    expect(expiredResponse.pendingClaims).toEqual([]);
    expect(expiredResponse.claimableAgents).toContainEqual({
      id: selfOwnedAgent.id,
      handle: 'claim-expire-agent',
      displayName: 'Claim Expire Agent',
      avatarUrl: null,
      bio: null,
      ownerType: 'self',
      status: 'offline',
    });

    const secondClaimRequest = await createClaimRequest(
      humanToken,
      selfOwnedAgent.id,
      60,
    );
    expect(secondClaimRequest.claimRequest.id).not.toBe(
      firstClaimRequest.claimRequest.id,
    );
    expect(secondClaimRequest.challengeToken).not.toBe(
      firstClaimRequest.challengeToken,
    );
  });

  it('creates a human-bound bootstrap invitation and keeps it hidden until the agent claims it', async () => {
    const registerResponse = await registerEmailHuman(
      'invite-owner@example.com',
      'Invite Owner',
    );

    const invitation = await createHumanOwnedInvitation(
      registerResponse.accessToken,
    );

    expect(invitation.invitation.code).toHaveLength(12);
    expect(invitation.invitation.bootstrapPath).toContain(
      '/api/v1/agents/bootstrap?claimToken=',
    );
    expect(invitation.invitation.claimToken).toContain('claim.v1.');

    const preClaimMine = await readAgentsMine(registerResponse.accessToken);
    expect(preClaimMine.agents).toEqual([]);

    const bootstrapResponse = await request(app.getHttpServer())
      .get(invitation.invitation.bootstrapPath)
      .expect(200);
    const bootstrap = typedValue<AgentBootstrapResponse>(
      bootstrapResponse.body,
    );

    expect(bootstrap.protocolVersion).toBe('v1');
    expect(bootstrap.claimToken).toBe(invitation.invitation.claimToken);
    expect(bootstrap.agent.id).toBe(invitation.invitation.agentId);
    expect(bootstrap.agent.ownerType).toBe('human');
    expect(bootstrap.transport.claimPath).toBe('/api/v1/agents/claim');

    await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: invitation.invitation.claimToken,
        pollingEnabled: true,
      })
      .expect(201)
      .expect(({ body }: { body: { agent: { id: string } } }) => {
        expect(body.agent.id).toBe(invitation.invitation.agentId);
      });

    const ownedResponse = await readAgentsMine(registerResponse.accessToken);
    expect(ownedResponse.agents).toContainEqual(
      expect.objectContaining({
        id: invitation.invitation.agentId,
        ownerType: 'human',
        status: 'online',
      }),
    );
  });

  it('marks claimed human-owned agents offline again when the human disconnects them', async () => {
    const registerResponse = await registerEmailHuman(
      'invite-disconnect@example.com',
      'Invite Disconnect',
    );

    const invitation = await createHumanOwnedInvitation(
      registerResponse.accessToken,
    );

    await request(app.getHttpServer())
      .post('/api/v1/agents/claim')
      .send({
        claimToken: invitation.invitation.claimToken,
        pollingEnabled: true,
      })
      .expect(201);

    const preDisconnectMine = await readAgentsMine(
      registerResponse.accessToken,
    );
    expect(preDisconnectMine.agents).toContainEqual(
      expect.objectContaining({
        id: invitation.invitation.agentId,
        status: 'online',
      }),
    );

    await request(app.getHttpServer())
      .post('/api/v1/agents/connections/disconnect-all')
      .set('Authorization', `Bearer ${registerResponse.accessToken}`)
      .expect(200)
      .expect(({ body }: { body: { disconnectedCount: number } }) => {
        expect(body.disconnectedCount).toBe(1);
      });

    const postDisconnectMine = await readAgentsMine(
      registerResponse.accessToken,
    );
    expect(postDisconnectMine.agents).toContainEqual(
      expect.objectContaining({
        id: invitation.invitation.agentId,
        status: 'offline',
      }),
    );
  });

  it('reuses the same pending human invitation instead of creating duplicate placeholder agents', async () => {
    const registerResponse = await registerEmailHuman(
      'invite-reuse@example.com',
      'Invite Reuse',
    );

    const firstInvitation = await createHumanOwnedInvitation(
      registerResponse.accessToken,
    );
    const secondInvitation = await createHumanOwnedInvitation(
      registerResponse.accessToken,
    );

    expect(secondInvitation.invitation.agentId).toBe(
      firstInvitation.invitation.agentId,
    );
    expect(secondInvitation.invitation.claimToken).not.toBe(
      firstInvitation.invitation.claimToken,
    );

    const pendingInvitationAgents = await context.dataSource
      .getRepository(AgentEntity)
      .createQueryBuilder('agent')
      .where('agent.ownerUserId = :ownerUserId', {
        ownerUserId: registerResponse.user.id,
      })
      .andWhere('agent.sourceType = :sourceType', {
        sourceType: 'hub_invitation',
      })
      .getCount();

    expect(pendingInvitationAgents).toBe(1);

    const preClaimMine = await readAgentsMine(registerResponse.accessToken);
    expect(preClaimMine.agents).toEqual([]);
  });

  it('deletes long-stale unclaimed human invitations during cleanup', async () => {
    const registerResponse = await registerEmailHuman(
      'invite-stale@example.com',
      'Invite Stale',
    );

    const invitation = await createHumanOwnedInvitation(
      registerResponse.accessToken,
    );
    const agentRepository = context.dataSource.getRepository(AgentEntity);
    const staleAgent = await agentRepository.findOneByOrFail({
      id: invitation.invitation.agentId,
    });

    staleAgent.profileMetadata = {
      ...staleAgent.profileMetadata,
      invitationPending: true,
      invitationIssuedAt: new Date(
        Date.now() - 25 * 60 * 60 * 1000,
      ).toISOString(),
    };
    await agentRepository.save(staleAgent);

    const cleanupResult = await app
      .get(AgentsService)
      .pruneStaleHumanOwnedInvitations(new Date());

    expect(cleanupResult.deletedCount).toBe(1);
    await expect(
      agentRepository.findOneBy({ id: invitation.invitation.agentId }),
    ).resolves.toBeNull();
  });

  it('rejects /agents/mine without valid human auth', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/agents/mine')
      .set('Authorization', 'Bearer invalid-token')
      .expect(401);
  });

  async function registerEmailHuman(
    email: string,
    displayName: string,
  ): Promise<HumanAuthResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email')
      .send({
        email,
        username: buildUsername(email),
        displayName,
        password: 'password123',
      })
      .expect(201);

    return typedValue<HumanAuthResponse>(response.body);
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

  async function importHumanOwnedAgent(
    accessToken: string,
    body: {
      handle: string;
      displayName: string;
      bio?: string;
    },
  ): Promise<AgentSummaryResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human')
      .set('Authorization', `Bearer ${accessToken}`)
      .send(body)
      .expect(201);

    return typedValue<AgentSummaryResponse>(response.body);
  }

  async function createHumanOwnedInvitation(
    accessToken: string,
  ): Promise<HumanOwnedInvitationResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/human/invitations')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    return typedValue<HumanOwnedInvitationResponse>(response.body);
  }

  async function importSelfOwnedAgent(body: {
    handle: string;
    displayName: string;
    bio?: string;
  }): Promise<AgentSummaryResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/import/self')
      .send(body)
      .expect(201);

    return typedValue<AgentSummaryResponse>(response.body);
  }

  async function createClaimRequest(
    accessToken: string,
    agentId: string,
    expiresInMinutes?: number,
  ): Promise<ClaimRequestResponse> {
    const response = await request(app.getHttpServer())
      .post(`/api/v1/agents/${agentId}/claim-requests`)
      .set('Authorization', `Bearer ${accessToken}`)
      .send(
        expiresInMinutes == null
          ? {}
          : {
              expiresInMinutes,
            },
      )
      .expect(201);

    return typedValue<ClaimRequestResponse>(response.body);
  }

  async function createUntargetedClaimRequest(
    accessToken: string,
    expiresInMinutes?: number,
  ): Promise<ClaimRequestResponse> {
    const response = await request(app.getHttpServer())
      .post('/api/v1/agents/claim-requests')
      .set('Authorization', `Bearer ${accessToken}`)
      .send(
        expiresInMinutes == null
          ? {}
          : {
              expiresInMinutes,
            },
      )
      .expect(201);

    return typedValue<ClaimRequestResponse>(response.body);
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

  async function confirmClaimRequest(
    accessToken: string,
    agentId: string,
    claimRequestId: string,
    challengeToken: string,
  ): Promise<ClaimConfirmationResponse> {
    const response = await request(app.getHttpServer())
      .post(
        `/api/v1/agents/${agentId}/claim-requests/${claimRequestId}/confirm`,
      )
      .set('Authorization', `Bearer ${accessToken}`)
      .send({
        challengeToken,
      })
      .expect(200);

    return typedValue<ClaimConfirmationResponse>(response.body);
  }
});
