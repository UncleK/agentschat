import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash, randomBytes } from 'node:crypto';
import { DataSource, In, Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import {
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

interface ImportAgentInput {
  handle: string;
  displayName: string;
  avatarUrl?: string | null;
  bio?: string | null;
}

export interface AgentSummary {
  id: string;
  handle: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  ownerType: AgentOwnerType;
  status: AgentStatus;
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
export class AgentsService {
  private static readonly humanInvitationTtlMs = 60 * 60 * 1000;

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
  ) {}

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
        profileMetadata: {
          invitationPending: true,
        },
      }),
    );

    await this.agentPolicyRepository.save(
      this.agentPolicyRepository.create({
        agentId: agent.id,
      }),
    );

    const claimToken = this.federationCredentialsService.createAgentClaimToken(
      agent.id,
      AgentsService.humanInvitationTtlMs,
    );
    const expiresAt = new Date(
      Date.now() + AgentsService.humanInvitationTtlMs,
    ).toISOString();

    return {
      invitation: {
        agentId: agent.id,
        code: this.buildInvitationCode(claimToken),
        bootstrapPath: this.buildBootstrapPath(claimToken),
        claimToken,
        expiresAt,
      },
    };
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
      pendingClaims.map((claimRequest) => claimRequest.agentId),
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

    if (connectionIds.length === 0) {
      return {
        disconnectedCount: 0,
      };
    }

    await this.agentConnectionRepository.delete(connectionIds);

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

  async findEligibleOwnedAgents(ownerUserId: string): Promise<AgentEntity[]> {
    return this.agentRepository.find({
      where: {
        ownerType: AgentOwnerType.Human,
        ownerUserId,
        status: In([...ELIGIBLE_ACTIVE_AGENT_STATUSES]),
      },
      order: {
        updatedAt: 'DESC',
        createdAt: 'DESC',
      },
    });
  }

  async requestClaim(owner: AuthenticatedHuman, agentId: string) {
    const result = await this.dataSource.transaction(async (manager) => {
      const agentRepository = manager.getRepository(AgentEntity);
      const claimRequestRepository = manager.getRepository(ClaimRequestEntity);
      const threadRepository = manager.getRepository(ThreadEntity);
      const eventRepository = manager.getRepository(EventEntity);
      const agent = await agentRepository.findOneBy({ id: agentId });

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

      const existingPendingRequest = await claimRequestRepository.findOneBy({
        agentId,
        status: ClaimRequestStatus.Pending,
      });
      const challengeToken = this.buildChallengeToken(agent.id, owner.id);

      if (
        existingPendingRequest &&
        existingPendingRequest.requestedByUserId !== owner.id
      ) {
        throw new ConflictException(
          'Another pending claim request already exists for this agent.',
        );
      }

      const claimRequest =
        existingPendingRequest ??
        (await claimRequestRepository.save(
          claimRequestRepository.create({
            agentId: agent.id,
            requestedByUserId: owner.id,
            challengeTokenHash: this.hashToken(challengeToken),
            expiresAt: new Date(Date.now() + 60 * 60 * 1000),
          }),
        ));
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
      result.claimRequest.agentId,
    );

    return {
      claimRequest: result.claimRequest,
      challengeToken: result.challengeToken,
    };
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
      .andWhere('claimRequest.requestedByUserId <> :ownerUserId', {
        ownerUserId,
      })
      .getRawMany<{ agentId: string }>();

    return new Set(pendingClaims.map((claimRequest) => claimRequest.agentId));
  }

  private serializeAgentSummary(agent: AgentEntity): AgentSummary {
    return {
      id: agent.id,
      handle: agent.handle,
      displayName: agent.displayName,
      avatarUrl: agent.avatarUrl,
      bio: agent.bio,
      ownerType: agent.ownerType,
      status: agent.status,
    };
  }

  private serializePendingClaim(
    claimRequest: ClaimRequestEntity,
  ): PendingClaimSummary {
    return {
      claimRequestId: claimRequest.id,
      agentId: claimRequest.agentId,
      handle: claimRequest.agent.handle,
      displayName: claimRequest.agent.displayName,
      status: claimRequest.status,
      requestedAt: claimRequest.createdAt.toISOString(),
      expiresAt: claimRequest.expiresAt.toISOString(),
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
      agent.policy?.dmAcceptanceMode ?? AgentDmAcceptanceMode.ApprovalRequired;
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

  private buildChallengeToken(agentId: string, userId: string): string {
    return `claim:${agentId}:${userId}`;
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
