import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash, randomBytes } from 'node:crypto';
import { DataSource, In, IsNull, Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import {
  AgentActivityLevel,
  AgentDmAcceptanceMode,
  EventActorType,
  EventContentType,
  AgentOwnerType,
  AgentStatus,
  ClaimRequestStatus,
  ConnectionTransportMode,
  FollowTargetType,
  SubjectType,
  ThreadContextType,
  ThreadVisibility,
} from '../../database/domain.enums';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { AuthenticatedHuman } from '../auth/auth.types';
import { FederationCredentialsService } from '../federation/federation-credentials.service';
import { FederationDeliveryService } from '../federation/federation-delivery.service';
import type { AuthenticatedFederatedAgent } from '../federation/federation.types';

interface ImportAgentInput {
  handle: string;
  displayName: string;
  avatarUrl?: string | null;
  bio?: string | null;
}

export type AgentDmPolicyMode =
  | 'open'
  | 'followers_only'
  | 'approval_required'
  | 'closed';

interface UpdateAgentSafetyPolicyInput {
  dmPolicyMode?: string;
  requiresMutualFollowForDm?: boolean;
  allowProactiveInteractions?: boolean;
  activityLevel?: string;
}

export interface AgentSafetyPolicySummary {
  dmPolicyMode: AgentDmPolicyMode;
  requiresMutualFollowForDm: boolean;
  allowProactiveInteractions: boolean;
  activityLevel: AgentActivityLevel;
}

export interface AgentSummary {
  id: string;
  handle: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  ownerType: AgentOwnerType;
  status: AgentStatus;
  safetyPolicy?: AgentSafetyPolicySummary;
}

export interface PendingClaimSummary {
  claimRequestId: string;
  agentId: string;
  handle: string;
  displayName: string;
  status: ClaimRequestStatus;
  requestedAt: string;
  expiresAt: string;
}

export interface AgentsMineResponse {
  agents: AgentSummary[];
  claimableAgents: AgentSummary[];
  pendingClaims: PendingClaimSummary[];
}

export interface ConnectedAgentSummary extends AgentSummary {
  protocolVersion: string;
  transportMode: ConnectionTransportMode;
  pollingEnabled: boolean;
  lastSeenAt: string | null;
  lastHeartbeatAt: string | null;
}

export interface ConnectedAgentsResponse {
  connectedAgents: ConnectedAgentSummary[];
}

export interface DisconnectConnectedAgentsResponse {
  disconnectedCount: number;
}

export interface HumanOwnedAgentInvitationResponse {
  invitation: {
    agentId: string;
    code: string;
    bootstrapPath: string;
    claimToken: string;
    expiresAt: string;
  };
}

export interface ClaimRequestResponse {
  claimRequest: {
    id: string;
    agentId: string;
    status: ClaimRequestStatus;
    requestedAt: string;
    expiresAt: string;
  };
  challengeToken: string;
}

export interface AgentBootstrapResponse {
  protocolVersion: string;
  claimToken: string;
  expiresAt: string;
  agent: {
    id: string;
    handle: string;
    displayName: string;
    ownerType: AgentOwnerType;
  };
  transport: {
    claimPath: string;
    actionsPath: string;
    pollingPath: string;
    acksPath: string;
  };
}

export interface PublicAgentBootstrapResponse {
  bootstrap: AgentBootstrapResponse & {
    code: string;
    bootstrapPath: string;
  };
}

export interface AgentDirectoryEntry extends AgentSummary {
  sourceType: string | null;
  vendorName: string | null;
  runtimeName: string | null;
  profileTags: string[];
  profileMetadata: Record<string, unknown>;
  followerCount: number;
  relationship: {
    actorType: SubjectType;
    actorId: string;
    viewerFollowsAgent: boolean;
    agentFollowsViewer: boolean;
  };
  dmPolicy: {
    acceptanceMode: AgentDmAcceptanceMode;
    directMessageAllowed: boolean;
    requiresFollowForDm: boolean;
    requiresMutualFollowForDm: boolean;
    blockedReasons: string[];
  };
}

export interface AgentDirectoryResponse {
  actor: {
    type: SubjectType;
    id: string;
  };
  agents: AgentDirectoryEntry[];
}

const ELIGIBLE_ACTIVE_AGENT_STATUSES = [
  AgentStatus.Offline,
  AgentStatus.Online,
  AgentStatus.Debating,
] as const;

@Injectable()
export class AgentsService implements OnModuleInit, OnModuleDestroy {
  private static readonly humanInvitationTtlMs = 60 * 60 * 1000;
  private static readonly staleHumanInvitationMs = 24 * 60 * 60 * 1000;
  private static readonly invitationIssuedAtKey = 'invitationIssuedAt';
  private static readonly allowInitialHandleClaimKey =
    'allowInitialHandleClaim';
  private static readonly defaultClaimRequestTtlMinutes = 60;
  private static readonly minClaimRequestTtlMinutes = 15;
  private static readonly maxClaimRequestTtlMinutes = 24 * 60;
  private readonly invitationCleanupIntervalMs: number;
  private invitationCleanupTimer: ReturnType<typeof setInterval> | null = null;

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    private readonly dataSource: DataSource,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
    @InjectRepository(ClaimRequestEntity)
    private readonly claimRequestRepository: Repository<ClaimRequestEntity>,
    @InjectRepository(AgentPolicyEntity)
    private readonly agentPolicyRepository: Repository<AgentPolicyEntity>,
    @InjectRepository(FollowEntity)
    private readonly followRepository: Repository<FollowEntity>,
    private readonly federationCredentialsService: FederationCredentialsService,
    private readonly federationDeliveryService: FederationDeliveryService,
  ) {
    this.invitationCleanupIntervalMs =
      environment.nodeEnv === 'test' ? 60_000 : 60 * 60 * 1000;
  }

  onModuleInit(): void {
    this.invitationCleanupTimer = setInterval(() => {
      void this.pruneStaleHumanOwnedInvitations().catch(() => undefined);
    }, this.invitationCleanupIntervalMs);
    this.invitationCleanupTimer.unref?.();
  }

  onModuleDestroy(): void {
    if (this.invitationCleanupTimer) {
      clearInterval(this.invitationCleanupTimer);
      this.invitationCleanupTimer = null;
    }
  }

  async importSelfOwnedAgent(input: ImportAgentInput) {
    return this.createAgent(input, AgentOwnerType.Self, null);
  }

  async importHumanOwnedAgent(
    owner: AuthenticatedHuman,
    input: ImportAgentInput,
  ) {
    return this.createAgent(input, AgentOwnerType.Human, owner.id);
  }

  async createPublicAgentBootstrap(
    input: ImportAgentInput,
  ): Promise<PublicAgentBootstrapResponse> {
    const agent = await this.createAgent(input, AgentOwnerType.Self, null);
    const claimToken = this.federationCredentialsService.createAgentClaimToken(
      agent.id,
      AgentsService.humanInvitationTtlMs,
    );
    const bootstrap = await this.readAgentBootstrap(claimToken);

    return {
      bootstrap: {
        ...bootstrap,
        code: this.buildInvitationCode(claimToken),
        bootstrapPath: this.buildBootstrapPath(claimToken),
      },
    };
  }

  async createHumanOwnedAgentInvitation(
    owner: AuthenticatedHuman,
  ): Promise<HumanOwnedAgentInvitationResponse> {
    const reusableInvitation =
      await this.findOrPruneReusableHumanOwnedInvitation(owner.id);

    if (reusableInvitation) {
      reusableInvitation.profileMetadata = this.withInvitationIssuedAt({
        ...reusableInvitation.profileMetadata,
        [AgentsService.allowInitialHandleClaimKey]: true,
      });
      const refreshedInvitation =
        await this.agentRepository.save(reusableInvitation);
      return this.buildHumanOwnedAgentInvitationResponse(
        refreshedInvitation.id,
      );
    }

    const agent = await this.agentRepository.save(
      this.agentRepository.create({
        handle: await this.generateInvitationHandle(),
        displayName: 'Pending agent',
        bio: 'Waiting for terminal bootstrap and profile sync.',
        ownerType: AgentOwnerType.Human,
        ownerUserId: owner.id,
        status: AgentStatus.Suspended,
        sourceType: 'hub_invitation',
        runtimeName: 'Pending bootstrap',
        profileMetadata: this.withInvitationIssuedAt({
          invitationPending: true,
          [AgentsService.allowInitialHandleClaimKey]: true,
        }),
      }),
    );

    await this.agentPolicyRepository.save(
      this.agentPolicyRepository.create({
        agentId: agent.id,
      }),
    );

    return this.buildHumanOwnedAgentInvitationResponse(agent.id);
  }

  async pruneStaleHumanOwnedInvitations(
    now = new Date(),
  ): Promise<{ deletedCount: number }> {
    const cutoff = now.getTime() - AgentsService.staleHumanInvitationMs;
    const invitationAgents = await this.agentRepository.find({
      where: {
        ownerType: AgentOwnerType.Human,
        sourceType: 'hub_invitation',
        status: AgentStatus.Suspended,
      },
      relations: {
        connection: true,
      },
    });

    const staleInvitationIds = invitationAgents
      .filter(
        (agent) =>
          agent.connection == null &&
          agent.profileMetadata['invitationPending'] === true &&
          this.readInvitationIssuedAtMs(agent) <= cutoff,
      )
      .map((agent) => agent.id);

    if (staleInvitationIds.length === 0) {
      return { deletedCount: 0 };
    }

    await this.agentRepository.delete(staleInvitationIds);
    return { deletedCount: staleInvitationIds.length };
  }

  private buildHumanOwnedAgentInvitationResponse(
    agentId: string,
  ): HumanOwnedAgentInvitationResponse {
    const claimToken = this.federationCredentialsService.createAgentClaimToken(
      agentId,
      AgentsService.humanInvitationTtlMs,
    );
    const expiresAt = new Date(
      Date.now() + AgentsService.humanInvitationTtlMs,
    ).toISOString();

    return {
      invitation: {
        agentId,
        code: this.buildInvitationCode(claimToken),
        bootstrapPath: this.buildBootstrapPath(claimToken),
        claimToken,
        expiresAt,
      },
    };
  }

  private async findOrPruneReusableHumanOwnedInvitation(
    ownerUserId: string,
  ): Promise<AgentEntity | null> {
    const invitationAgents = await this.agentRepository.find({
      where: {
        ownerType: AgentOwnerType.Human,
        ownerUserId,
        sourceType: 'hub_invitation',
        status: AgentStatus.Suspended,
      },
      relations: {
        connection: true,
      },
      order: {
        updatedAt: 'DESC',
        createdAt: 'DESC',
      },
    });

    const pendingInvitations = invitationAgents.filter(
      (agent) =>
        agent.connection == null &&
        agent.profileMetadata['invitationPending'] === true,
    );

    if (pendingInvitations.length === 0) {
      return null;
    }

    const [reusableInvitation, ...redundantInvitations] = pendingInvitations;

    if (redundantInvitations.length > 0) {
      await this.agentRepository.delete(
        redundantInvitations.map((agent) => agent.id),
      );
    }

    return reusableInvitation;
  }

  private withInvitationIssuedAt(
    metadata: Record<string, unknown>,
    issuedAt = new Date(),
  ): Record<string, unknown> {
    return {
      ...metadata,
      invitationPending: true,
      [AgentsService.invitationIssuedAtKey]: issuedAt.toISOString(),
    };
  }

  private readInvitationIssuedAtMs(agent: AgentEntity): number {
    const rawIssuedAt =
      agent.profileMetadata[AgentsService.invitationIssuedAtKey];
    if (typeof rawIssuedAt === 'string') {
      const parsed = Date.parse(rawIssuedAt);
      if (!Number.isNaN(parsed)) {
        return parsed;
      }
    }

    return agent.updatedAt.getTime();
  }

  async readAgentBootstrap(
    claimToken: string | undefined,
  ): Promise<AgentBootstrapResponse> {
    const normalizedClaimToken = claimToken?.trim();

    if (!normalizedClaimToken) {
      throw new BadRequestException('claimToken is required.');
    }

    const payload =
      this.federationCredentialsService.verifyAgentClaimToken(
        normalizedClaimToken,
      );
    const agent = await this.federationCredentialsService.assertAgentExists(
      payload.agentId,
    );

    return {
      protocolVersion: 'v1',
      claimToken: normalizedClaimToken,
      expiresAt: new Date(payload.exp).toISOString(),
      agent: {
        id: agent.id,
        handle: agent.handle,
        displayName: agent.displayName,
        ownerType: agent.ownerType,
      },
      transport: {
        claimPath: this.environment.transport.federation.claimPath,
        actionsPath: this.environment.transport.federation.actionsPath,
        pollingPath: this.environment.transport.federation.pollingPath,
        acksPath: this.environment.transport.federation.acksPath,
      },
    };
  }

  async readMine(owner: AuthenticatedHuman): Promise<AgentsMineResponse> {
    await this.expireStaleClaimRequests(this.claimRequestRepository);

    const [agents, selfOwnedAgents, pendingClaims, otherPendingClaimAgentIds] =
      await Promise.all([
        this.findEligibleOwnedAgents(owner.id),
        this.agentRepository.find({
          where: {
            ownerType: AgentOwnerType.Self,
          },
          order: {
            updatedAt: 'DESC',
            createdAt: 'DESC',
          },
        }),
        this.claimRequestRepository.find({
          relations: {
            agent: true,
          },
          where: {
            requestedByUserId: owner.id,
            status: ClaimRequestStatus.Pending,
          },
          order: {
            createdAt: 'DESC',
            updatedAt: 'DESC',
          },
        }),
        this.findOtherPendingClaimAgentIds(owner.id),
      ]);

    const pendingClaimAgentIds = new Set(
      pendingClaims
        .map((claimRequest) => claimRequest.agentId)
        .filter((agentId): agentId is string => typeof agentId === 'string'),
    );

    return {
      agents: agents.map((agent) => this.serializeAgentSummary(agent)),
      claimableAgents: selfOwnedAgents
        .filter(
          (agent) =>
            !pendingClaimAgentIds.has(agent.id) &&
            !otherPendingClaimAgentIds.has(agent.id),
        )
        .map((agent) => this.serializeAgentSummary(agent)),
      pendingClaims: pendingClaims.map((claimRequest) =>
        this.serializePendingClaim(claimRequest),
      ),
    };
  }

  async readConnectedAgents(
    owner: AuthenticatedHuman,
  ): Promise<ConnectedAgentsResponse> {
    const agents = await this.agentRepository.find({
      where: {
        ownerType: AgentOwnerType.Human,
        ownerUserId: owner.id,
      },
      relations: {
        connection: true,
      },
      order: {
        updatedAt: 'DESC',
        createdAt: 'DESC',
      },
    });

    return {
      connectedAgents: agents
        .filter((agent) => agent.connection != null)
        .map((agent) => this.serializeConnectedAgent(agent)),
    };
  }

  async disconnectConnectedAgents(
    owner: AuthenticatedHuman,
  ): Promise<DisconnectConnectedAgentsResponse> {
    const agents = await this.agentRepository.find({
      where: {
        ownerType: AgentOwnerType.Human,
        ownerUserId: owner.id,
      },
      relations: {
        connection: true,
      },
    });
    const connectionIds = agents
      .map((agent) => agent.connection?.id)
      .filter((connectionId): connectionId is string => connectionId != null);
    const disconnectableAgentIds = agents
      .filter(
        (agent) =>
          agent.connection != null && agent.status !== AgentStatus.Suspended,
      )
      .map((agent) => agent.id);

    if (connectionIds.length === 0) {
      return {
        disconnectedCount: 0,
      };
    }

    await this.dataSource.transaction(async (manager) => {
      await manager.getRepository(AgentConnectionEntity).delete(connectionIds);
      if (disconnectableAgentIds.length > 0) {
        await manager.getRepository(AgentEntity).update(
          {
            id: In(disconnectableAgentIds),
          },
          {
            status: AgentStatus.Offline,
          },
        );
      }
    });

    return {
      disconnectedCount: connectionIds.length,
    };
  }

  async readDirectory(
    viewer: AuthenticatedHuman,
    activeAgentId?: string | null,
  ): Promise<AgentDirectoryResponse> {
    const actor = await this.resolveDirectoryActor(viewer, activeAgentId);
    return this.readDirectoryForActor(actor);
  }

  async readDirectoryForAgent(
    agentId: string,
  ): Promise<AgentDirectoryResponse> {
    const agent = await this.agentRepository.findOneBy({
      id: agentId,
    });

    if (!agent) {
      throw new NotFoundException(`Agent ${agentId} was not found.`);
    }

    return this.readDirectoryForActor({
      type: SubjectType.Agent,
      id: agent.id,
    });
  }

  async readSafetyPolicyForFederatedAgent(
    agent: AuthenticatedFederatedAgent,
  ): Promise<AgentSafetyPolicySummary> {
    return this.readAgentSafetyPolicy(agent.id);
  }

  async readHumanOwnedAgentSafetyPolicy(
    owner: AuthenticatedHuman,
    agentId: string,
  ): Promise<AgentSafetyPolicySummary> {
    await this.assertHumanOwnsAgent(owner.id, agentId);
    return this.readAgentSafetyPolicy(agentId);
  }

  async updateHumanOwnedAgentSafetyPolicy(
    owner: AuthenticatedHuman,
    agentId: string,
    input: UpdateAgentSafetyPolicyInput,
  ): Promise<AgentSafetyPolicySummary> {
    const dmPolicyMode = this.parseAgentDmPolicyMode(input.dmPolicyMode);
    const requiresMutualFollowForDm = this.parseOptionalBooleanField(
      input.requiresMutualFollowForDm,
      'requiresMutualFollowForDm',
    );
    const activityLevel = this.parseAgentActivityLevel(input.activityLevel);
    const allowProactiveInteractions = this.parseOptionalBooleanField(
      input.allowProactiveInteractions,
      'allowProactiveInteractions',
    );

    await this.dataSource.transaction(async (manager) => {
      const agentRepository = manager.getRepository(AgentEntity);
      const agentPolicyRepository = manager.getRepository(AgentPolicyEntity);
      const agent = await this.assertHumanOwnsAgent(
        owner.id,
        agentId,
        agentRepository,
      );
      let policy = await agentPolicyRepository.findOneBy({ agentId });

      if (!policy) {
        policy = agentPolicyRepository.create({ agentId });
      }

      if (dmPolicyMode !== undefined) {
        policy.dmAcceptanceMode =
          this.mapDmPolicyModeToAcceptanceMode(dmPolicyMode);
      }
      if (activityLevel !== undefined) {
        policy.activityLevel = activityLevel;
        policy.allowProactiveInteractions =
          activityLevel !== AgentActivityLevel.Low;
      } else if (allowProactiveInteractions !== undefined) {
        policy.allowProactiveInteractions = allowProactiveInteractions;
        if (allowProactiveInteractions) {
          if (policy.activityLevel === AgentActivityLevel.Low) {
            policy.activityLevel = AgentActivityLevel.Normal;
          }
        } else {
          policy.activityLevel = AgentActivityLevel.Low;
        }
      }
      await agentPolicyRepository.save(policy);

      if (requiresMutualFollowForDm !== undefined) {
        agent.profileMetadata = this.setBooleanMetadata(
          agent.profileMetadata,
          'dmRequiresMutualFollow',
          requiresMutualFollowForDm,
        );
        await agentRepository.save(agent);
      }
    });

    return this.readAgentSafetyPolicy(agentId);
  }

  async findEligibleOwnedAgents(ownerUserId: string): Promise<AgentEntity[]> {
    return this.agentRepository.find({
      where: {
        ownerType: AgentOwnerType.Human,
        ownerUserId,
        status: In([...ELIGIBLE_ACTIVE_AGENT_STATUSES]),
      },
      relations: {
        policy: true,
      },
      order: {
        updatedAt: 'DESC',
        createdAt: 'DESC',
      },
    });
  }

  async requestClaim(
    owner: AuthenticatedHuman,
    agentId: string,
    expiresInMinutes?: number,
  ): Promise<ClaimRequestResponse> {
    const result = await this.dataSource.transaction(async (manager) => {
      const agentRepository = manager.getRepository(AgentEntity);
      const claimRequestRepository = manager.getRepository(ClaimRequestEntity);
      const threadRepository = manager.getRepository(ThreadEntity);
      const eventRepository = manager.getRepository(EventEntity);
      const ttlMs = this.resolveClaimRequestTtlMs(expiresInMinutes);
      const agent = await agentRepository.findOneBy({ id: agentId });
      await this.expireStaleClaimRequests(claimRequestRepository);

      if (!agent) {
        throw new NotFoundException(`Agent ${agentId} was not found.`);
      }

      if (agent.ownerType === AgentOwnerType.Human) {
        if (agent.ownerUserId === owner.id) {
          throw new ConflictException(
            'This agent is already owned by the requesting human.',
          );
        }

        throw new ConflictException(
          'Human-owned agents must be imported by their owner.',
        );
      }

      const existingPendingRequests = await claimRequestRepository.find({
        where: {
          agentId,
          status: ClaimRequestStatus.Pending,
        },
        order: {
          createdAt: 'DESC',
        },
      });
      const conflictingPendingRequest = existingPendingRequests.find(
        (claimRequest) => claimRequest.requestedByUserId !== owner.id,
      );

      if (conflictingPendingRequest) {
        throw new ConflictException(
          'Another pending claim request already exists for this agent.',
        );
      }

      const reusablePendingRequests = existingPendingRequests.filter(
        (claimRequest) => claimRequest.requestedByUserId === owner.id,
      );
      if (reusablePendingRequests.length > 0) {
        const rotatedAt = new Date();
        for (const claimRequest of reusablePendingRequests) {
          claimRequest.status = ClaimRequestStatus.Expired;
          claimRequest.rejectedAt = rotatedAt;
          claimRequest.rejectionReason = 'claim_link_rotated';
        }
        await claimRequestRepository.save(reusablePendingRequests);
      }

      const challengeToken = this.buildChallengeToken();
      const claimRequest = await claimRequestRepository.save(
        claimRequestRepository.create({
          agentId: agent.id,
          requestedByUserId: owner.id,
          challengeTokenHash: this.hashToken(challengeToken),
          expiresAt: new Date(Date.now() + ttlMs),
        }),
      );
      const thread = await threadRepository.save(
        threadRepository.create({
          contextType: ThreadContextType.DirectMessage,
          visibility: ThreadVisibility.Private,
          title: 'Claim request',
          metadata: {
            systemThread: 'claim_request',
            agentId: agent.id,
            claimRequestId: claimRequest.id,
          },
        }),
      );
      const event = await eventRepository.save(
        eventRepository.create({
          threadId: thread.id,
          eventType: 'claim.requested',
          actorType: EventActorType.Human,
          actorUserId: owner.id,
          targetType: SubjectType.Agent,
          targetId: agent.id,
          contentType: EventContentType.None,
          content: null,
          metadata: {
            claimRequestId: claimRequest.id,
            challengeToken,
            expiresAt: claimRequest.expiresAt.toISOString(),
            claimant: {
              id: owner.id,
              username: owner.username,
              displayName: owner.displayName,
              email: owner.email,
            },
          },
        }),
      );

      return {
        claimRequest,
        challengeToken,
        event,
      };
    });

    await this.federationDeliveryService.enqueueEventForRecipient(
      result.event,
      result.claimRequest.agentId ?? agentId,
    );

    return this.serializeClaimRequestResponse(
      result.claimRequest,
      result.challengeToken,
      agentId,
    );
  }

  async requestUntargetedClaim(
    owner: AuthenticatedHuman,
    expiresInMinutes?: number,
  ): Promise<ClaimRequestResponse> {
    const result = await this.dataSource.transaction(async (manager) => {
      const claimRequestRepository = manager.getRepository(ClaimRequestEntity);
      const ttlMs = this.resolveClaimRequestTtlMs(expiresInMinutes);
      await this.expireStaleClaimRequests(claimRequestRepository);

      const reusablePendingRequests = await claimRequestRepository.find({
        where: {
          requestedByUserId: owner.id,
          status: ClaimRequestStatus.Pending,
          agentId: IsNull(),
        },
        order: {
          createdAt: 'DESC',
        },
      });
      if (reusablePendingRequests.length > 0) {
        const rotatedAt = new Date();
        for (const claimRequest of reusablePendingRequests) {
          claimRequest.status = ClaimRequestStatus.Expired;
          claimRequest.rejectedAt = rotatedAt;
          claimRequest.rejectionReason = 'claim_link_rotated';
        }
        await claimRequestRepository.save(reusablePendingRequests);
      }

      const challengeToken = this.buildChallengeToken();
      const claimRequest = await claimRequestRepository.save(
        claimRequestRepository.create({
          agentId: null,
          requestedByUserId: owner.id,
          challengeTokenHash: this.hashToken(challengeToken),
          expiresAt: new Date(Date.now() + ttlMs),
        }),
      );

      return {
        claimRequest,
        challengeToken,
      };
    });

    return this.serializeClaimRequestResponse(
      result.claimRequest,
      result.challengeToken,
    );
  }

  async confirmClaim(
    owner: AuthenticatedHuman,
    agentId: string,
    claimRequestId: string,
    challengeToken: string,
  ) {
    if (!challengeToken?.trim()) {
      throw new BadRequestException('challengeToken is required.');
    }

    const claimRequest = await this.claimRequestRepository.findOneBy({
      id: claimRequestId,
      agentId,
    });

    if (!claimRequest) {
      throw new NotFoundException(
        `Claim request ${claimRequestId} was not found.`,
      );
    }

    if (claimRequest.requestedByUserId !== owner.id) {
      throw new ForbiddenException(
        'Claim requests can only be confirmed by the requesting human.',
      );
    }

    if (claimRequest.status !== ClaimRequestStatus.Pending) {
      throw new ConflictException(
        'Only pending claim requests can be confirmed.',
      );
    }

    if (claimRequest.expiresAt.getTime() <= Date.now()) {
      claimRequest.status = ClaimRequestStatus.Expired;
      await this.claimRequestRepository.save(claimRequest);
      throw new ConflictException('The claim request challenge has expired.');
    }

    if (
      claimRequest.challengeTokenHash !== this.hashToken(challengeToken.trim())
    ) {
      throw new ForbiddenException(
        'The claim challenge confirmation is invalid.',
      );
    }

    const confirmedAt = new Date();

    await this.dataSource.transaction(async (manager) => {
      const agentRepository = manager.getRepository(AgentEntity);
      const claimRepository = manager.getRepository(ClaimRequestEntity);
      const agent = await agentRepository.findOneBy({ id: agentId });

      if (!agent) {
        throw new NotFoundException(`Agent ${agentId} was not found.`);
      }

      if (agent.ownerType !== AgentOwnerType.Self) {
        throw new ConflictException('Only self-owned agents can be claimed.');
      }

      agent.ownerType = AgentOwnerType.Human;
      agent.ownerUserId = owner.id;
      await agentRepository.save(agent);

      claimRequest.status = ClaimRequestStatus.Confirmed;
      claimRequest.confirmedAt = confirmedAt;
      await claimRepository.save(claimRequest);
    });

    const updatedAgent = await this.agentRepository.findOneByOrFail({
      id: agentId,
    });
    const updatedClaim = await this.claimRequestRepository.findOneByOrFail({
      id: claimRequestId,
    });

    return {
      agent: updatedAgent,
      claimRequest: updatedClaim,
    };
  }

  private async createAgent(
    input: ImportAgentInput,
    ownerType: AgentOwnerType,
    ownerUserId: string | null,
  ) {
    const agent = await this.agentRepository.save(
      this.agentRepository.create({
        handle: this.normalizeHandle(input.handle),
        displayName: this.normalizeDisplayName(input.displayName),
        avatarUrl: input.avatarUrl?.trim() || null,
        bio: input.bio?.trim() || null,
        ownerType,
        ownerUserId,
      }),
    );

    await this.agentPolicyRepository.save(
      this.agentPolicyRepository.create({
        agentId: agent.id,
      }),
    );

    return this.agentRepository.findOneByOrFail({ id: agent.id });
  }

  private async findOtherPendingClaimAgentIds(
    ownerUserId: string,
  ): Promise<Set<string>> {
    const pendingClaims = await this.claimRequestRepository
      .createQueryBuilder('claimRequest')
      .select('claimRequest.agentId', 'agentId')
      .where('claimRequest.status = :status', {
        status: ClaimRequestStatus.Pending,
      })
      .andWhere('claimRequest.agentId IS NOT NULL')
      .andWhere('claimRequest.requestedByUserId <> :ownerUserId', {
        ownerUserId,
      })
      .getRawMany<{ agentId: string | null }>();

    return new Set(
      pendingClaims
        .map((claimRequest) => claimRequest.agentId)
        .filter((agentId): agentId is string => typeof agentId === 'string'),
    );
  }

  private serializeAgentSummary(agent: AgentEntity): AgentSummary {
    const summary: AgentSummary = {
      id: agent.id,
      handle: agent.handle,
      displayName: agent.displayName,
      avatarUrl: agent.avatarUrl,
      bio: agent.bio,
      ownerType: agent.ownerType,
      status: agent.status,
    };

    if (agent.policy) {
      summary.safetyPolicy = this.serializeAgentSafetyPolicy(agent);
    }

    return summary;
  }

  private serializePendingClaim(
    claimRequest: ClaimRequestEntity,
  ): PendingClaimSummary {
    return {
      claimRequestId: claimRequest.id,
      agentId: claimRequest.agentId ?? '',
      handle: claimRequest.agent?.handle ?? '',
      displayName: claimRequest.agent?.displayName ?? '',
      status: claimRequest.status,
      requestedAt: claimRequest.createdAt.toISOString(),
      expiresAt: claimRequest.expiresAt.toISOString(),
    };
  }

  private serializeClaimRequestResponse(
    claimRequest: ClaimRequestEntity,
    challengeToken: string,
    fallbackAgentId = '',
  ): ClaimRequestResponse {
    return {
      claimRequest: {
        id: claimRequest.id,
        agentId: claimRequest.agentId ?? fallbackAgentId,
        status: claimRequest.status,
        requestedAt: claimRequest.createdAt.toISOString(),
        expiresAt: claimRequest.expiresAt.toISOString(),
      },
      challengeToken,
    };
  }

  private serializeConnectedAgent(agent: AgentEntity): ConnectedAgentSummary {
    const connection = agent.connection;
    if (!connection) {
      throw new NotFoundException(`Agent ${agent.id} is not connected.`);
    }

    return {
      ...this.serializeAgentSummary(agent),
      protocolVersion: connection.protocolVersion,
      transportMode: connection.transportMode,
      pollingEnabled: connection.pollingEnabled,
      lastSeenAt: connection.lastSeenAt?.toISOString() ?? null,
      lastHeartbeatAt: connection.lastHeartbeatAt?.toISOString() ?? null,
    };
  }

  private async resolveDirectoryActor(
    viewer: AuthenticatedHuman,
    activeAgentId?: string | null,
  ): Promise<{ type: SubjectType; id: string }> {
    const normalizedActiveAgentId = activeAgentId?.trim();

    if (!normalizedActiveAgentId) {
      return {
        type: SubjectType.Human,
        id: viewer.id,
      };
    }

    const agent = await this.agentRepository.findOneBy({
      id: normalizedActiveAgentId,
      ownerType: AgentOwnerType.Human,
      ownerUserId: viewer.id,
    });

    if (!agent) {
      throw new ForbiddenException(
        'Humans may only use owned agents as the Hall actor.',
      );
    }

    return {
      type: SubjectType.Agent,
      id: agent.id,
    };
  }

  private async readDirectoryForActor(actor: {
    type: SubjectType;
    id: string;
  }): Promise<AgentDirectoryResponse> {
    const agents = await this.agentRepository.find({
      where: {
        isPublic: true,
        status: In([
          AgentStatus.Online,
          AgentStatus.Debating,
          AgentStatus.Offline,
        ]),
      },
      relations: {
        policy: true,
      },
      order: {
        status: 'ASC',
        updatedAt: 'DESC',
        createdAt: 'DESC',
      },
    });

    return {
      actor,
      agents: await Promise.all(
        agents.map((agent) => this.serializeDirectoryEntry(agent, actor)),
      ),
    };
  }

  private async serializeDirectoryEntry(
    agent: AgentEntity,
    actor: { type: SubjectType; id: string },
  ): Promise<AgentDirectoryEntry> {
    const [viewerFollowsAgent, agentFollowsViewer, followerCount] =
      await Promise.all([
        this.readAgentFollowState(actor, agent.id),
        this.readAgentFollowState(
          {
            type: SubjectType.Agent,
            id: agent.id,
          },
          actor.id,
          actor.type,
        ),
        this.readAgentFollowerCount(agent.id),
      ]);
    const dmAcceptanceMode =
      agent.policy?.dmAcceptanceMode ?? AgentDmAcceptanceMode.FollowedOnly;
    const requiresMutualFollowForDm = this.readBooleanMetadata(
      agent.profileMetadata,
      'dmRequiresMutualFollow',
    );
    const requiresFollowForDm =
      dmAcceptanceMode === AgentDmAcceptanceMode.FollowedOnly ||
      requiresMutualFollowForDm;
    const blockedReasons = this.buildDirectoryDmBlockedReasons({
      dmAcceptanceMode,
      viewerFollowsAgent,
      agentFollowsViewer,
      requiresFollowForDm,
      requiresMutualFollowForDm,
    });

    return {
      ...this.serializeAgentSummary(agent),
      sourceType: agent.sourceType,
      vendorName: agent.vendorName,
      runtimeName: agent.runtimeName,
      profileTags: agent.profileTags,
      profileMetadata: agent.profileMetadata,
      followerCount,
      relationship: {
        actorType: actor.type,
        actorId: actor.id,
        viewerFollowsAgent,
        agentFollowsViewer,
      },
      dmPolicy: {
        acceptanceMode: dmAcceptanceMode,
        directMessageAllowed:
          dmAcceptanceMode === AgentDmAcceptanceMode.Open ||
          dmAcceptanceMode === AgentDmAcceptanceMode.FollowedOnly,
        requiresFollowForDm,
        requiresMutualFollowForDm,
        blockedReasons,
      },
    };
  }

  private readAgentFollowState(
    follower: { type: SubjectType; id: string },
    targetId: string,
    targetType = SubjectType.Agent,
  ): Promise<boolean> {
    if (
      follower.type !== SubjectType.Agent ||
      targetType !== SubjectType.Agent
    ) {
      return Promise.resolve(false);
    }

    return this.followRepository.exist({
      where: {
        followerType: follower.type,
        followerSubjectId: follower.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: targetId,
        targetAgentId: targetId,
      },
    });
  }

  private readAgentFollowerCount(agentId: string): Promise<number> {
    return this.followRepository.count({
      where: {
        followerType: SubjectType.Agent,
        targetType: FollowTargetType.Agent,
        targetSubjectId: agentId,
        targetAgentId: agentId,
      },
    });
  }

  private buildDirectoryDmBlockedReasons(input: {
    dmAcceptanceMode: AgentDmAcceptanceMode;
    viewerFollowsAgent: boolean;
    agentFollowsViewer: boolean;
    requiresFollowForDm: boolean;
    requiresMutualFollowForDm: boolean;
  }): string[] {
    const reasons: string[] = [];

    if (input.dmAcceptanceMode === AgentDmAcceptanceMode.Closed) {
      reasons.push('Agent safety policy closes direct messages.');
    }

    if (input.dmAcceptanceMode === AgentDmAcceptanceMode.ApprovalRequired) {
      reasons.push(
        'Agent safety policy requires approval before direct messages.',
      );
    }

    if (input.requiresFollowForDm && !input.viewerFollowsAgent) {
      reasons.push(
        'Agent safety policy only allows direct messages from followers.',
      );
    }

    if (input.requiresMutualFollowForDm && !input.agentFollowsViewer) {
      reasons.push('Agent safety policy requires mutual follow.');
    }

    return reasons;
  }

  private readBooleanMetadata(
    metadata: Record<string, unknown>,
    key: string,
  ): boolean {
    return metadata[key] === true;
  }

  private setBooleanMetadata(
    metadata: Record<string, unknown>,
    key: string,
    value: boolean,
  ): Record<string, unknown> {
    return {
      ...metadata,
      [key]: value,
    };
  }

  private serializeAgentSafetyPolicy(
    agent: AgentEntity,
  ): AgentSafetyPolicySummary {
    const dmAcceptanceMode =
      agent.policy?.dmAcceptanceMode ?? AgentDmAcceptanceMode.FollowedOnly;
    const activityLevel = this.resolveAgentActivityLevel(agent.policy);

    return {
      dmPolicyMode: this.mapAcceptanceModeToDmPolicyMode(dmAcceptanceMode),
      requiresMutualFollowForDm: this.readBooleanMetadata(
        agent.profileMetadata,
        'dmRequiresMutualFollow',
      ),
      allowProactiveInteractions: activityLevel !== AgentActivityLevel.Low,
      activityLevel,
    };
  }

  private async readAgentSafetyPolicy(
    agentId: string,
  ): Promise<AgentSafetyPolicySummary> {
    const agent = await this.loadAgentWithPolicy(agentId);
    return this.serializeAgentSafetyPolicy(agent);
  }

  private async loadAgentWithPolicy(agentId: string): Promise<AgentEntity> {
    let agent = await this.agentRepository.findOne({
      where: { id: agentId },
      relations: {
        policy: true,
      },
    });

    if (!agent) {
      throw new NotFoundException(`Agent ${agentId} was not found.`);
    }

    if (agent.policy) {
      return agent;
    }

    await this.agentPolicyRepository.save(
      this.agentPolicyRepository.create({ agentId }),
    );

    agent = await this.agentRepository.findOne({
      where: { id: agentId },
      relations: {
        policy: true,
      },
    });

    if (!agent) {
      throw new NotFoundException(`Agent ${agentId} was not found.`);
    }

    return agent;
  }

  private async assertHumanOwnsAgent(
    ownerUserId: string,
    agentId: string,
    repository: Repository<AgentEntity> = this.agentRepository,
  ): Promise<AgentEntity> {
    const agent = await repository.findOneBy({
      id: agentId,
      ownerType: AgentOwnerType.Human,
      ownerUserId,
    });

    if (!agent) {
      throw new ForbiddenException(
        'Humans may only manage safety policy for owned agents.',
      );
    }

    return agent;
  }

  private parseAgentDmPolicyMode(
    value: unknown,
  ): AgentDmPolicyMode | undefined {
    if (value === undefined) {
      return undefined;
    }

    if (typeof value !== 'string') {
      throw new BadRequestException(
        'dmPolicyMode must be open, followers_only, approval_required, or closed.',
      );
    }

    const normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'open':
      case 'followers_only':
      case 'approval_required':
      case 'closed':
        return normalized;
      default:
        throw new BadRequestException(
          'dmPolicyMode must be open, followers_only, approval_required, or closed.',
        );
    }
  }

  private parseOptionalBooleanField(
    value: unknown,
    fieldName: string,
  ): boolean | undefined {
    if (value === undefined) {
      return undefined;
    }

    if (typeof value !== 'boolean') {
      throw new BadRequestException(`${fieldName} must be a boolean.`);
    }

    return value;
  }

  private parseAgentActivityLevel(
    value: unknown,
  ): AgentActivityLevel | undefined {
    if (value === undefined) {
      return undefined;
    }

    if (typeof value !== 'string') {
      throw new BadRequestException(
        'activityLevel must be low, normal, or high.',
      );
    }

    const normalized = value.trim().toLowerCase();
    if (
      normalized !== 'low' &&
      normalized !== 'normal' &&
      normalized !== 'high'
    ) {
      throw new BadRequestException(
        'activityLevel must be low, normal, or high.',
      );
    }

    return normalized as AgentActivityLevel;
  }

  private resolveAgentActivityLevel(
    policy?: AgentPolicyEntity | null,
  ): AgentActivityLevel {
    if (!policy) {
      return AgentActivityLevel.Normal;
    }
    if (policy.allowProactiveInteractions === false) {
      return AgentActivityLevel.Low;
    }
    return policy.activityLevel ?? AgentActivityLevel.Normal;
  }

  private mapAcceptanceModeToDmPolicyMode(
    value: AgentDmAcceptanceMode,
  ): AgentDmPolicyMode {
    switch (value) {
      case AgentDmAcceptanceMode.Open:
        return 'open';
      case AgentDmAcceptanceMode.FollowedOnly:
        return 'followers_only';
      case AgentDmAcceptanceMode.ApprovalRequired:
        return 'approval_required';
      case AgentDmAcceptanceMode.Closed:
        return 'closed';
    }
  }

  private mapDmPolicyModeToAcceptanceMode(
    value: AgentDmPolicyMode,
  ): AgentDmAcceptanceMode {
    switch (value) {
      case 'open':
        return AgentDmAcceptanceMode.Open;
      case 'followers_only':
        return AgentDmAcceptanceMode.FollowedOnly;
      case 'approval_required':
        return AgentDmAcceptanceMode.ApprovalRequired;
      case 'closed':
        return AgentDmAcceptanceMode.Closed;
    }
  }

  private buildBootstrapPath(claimToken: string): string {
    return `/${this.environment.apiPrefix}/agents/bootstrap?claimToken=${encodeURIComponent(claimToken)}`;
  }

  private buildInvitationCode(claimToken: string): string {
    return createHash('sha256')
      .update(claimToken)
      .digest('hex')
      .substring(0, 12)
      .toUpperCase();
  }

  private async generateInvitationHandle(): Promise<string> {
    while (true) {
      const candidate = `invite-${randomBytes(5).toString('hex')}`;
      const exists = await this.agentRepository.exist({
        where: { handle: candidate },
      });

      if (!exists) {
        return candidate;
      }
    }
  }

  private buildChallengeToken(): string {
    return `claimreq.v1.${randomBytes(24).toString('hex')}`;
  }

  private async expireStaleClaimRequests(
    repository: Repository<ClaimRequestEntity>,
    now = new Date(),
  ): Promise<void> {
    await repository
      .createQueryBuilder()
      .update(ClaimRequestEntity)
      .set({
        status: ClaimRequestStatus.Expired,
      })
      .where('status = :status', {
        status: ClaimRequestStatus.Pending,
      })
      .andWhere('expires_at <= :now', {
        now: now.toISOString(),
      })
      .execute();
  }

  private resolveClaimRequestTtlMs(expiresInMinutes?: number): number {
    if (expiresInMinutes == null) {
      return AgentsService.defaultClaimRequestTtlMinutes * 60 * 1000;
    }

    if (
      !Number.isInteger(expiresInMinutes) ||
      expiresInMinutes < AgentsService.minClaimRequestTtlMinutes ||
      expiresInMinutes > AgentsService.maxClaimRequestTtlMinutes
    ) {
      throw new BadRequestException(
        `expiresInMinutes must be an integer between ${AgentsService.minClaimRequestTtlMinutes} and ${AgentsService.maxClaimRequestTtlMinutes}.`,
      );
    }

    return expiresInMinutes * 60 * 1000;
  }

  private hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  private normalizeHandle(handle: string): string {
    const normalized = handle?.trim().toLowerCase();

    if (!normalized) {
      throw new BadRequestException('handle is required.');
    }

    if (!/^[a-z0-9][a-z0-9-]{1,63}$/.test(normalized)) {
      throw new BadRequestException(
        'handle must be 2-64 characters using lowercase letters, numbers, or hyphens.',
      );
    }

    return normalized;
  }

  private normalizeDisplayName(displayName: string): string {
    const normalized = displayName?.trim();

    if (!normalized) {
      throw new BadRequestException('displayName is required.');
    }

    return normalized;
  }
}
