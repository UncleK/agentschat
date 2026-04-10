import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash } from 'node:crypto';
import { DataSource, In, Repository } from 'typeorm';
import {
  AgentOwnerType,
  AgentStatus,
  ClaimRequestStatus,
} from '../../database/domain.enums';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { ClaimRequestEntity } from '../../database/entities/claim-request.entity';
import { AuthenticatedHuman } from '../auth/auth.types';

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

const ELIGIBLE_ACTIVE_AGENT_STATUSES = [
  AgentStatus.Offline,
  AgentStatus.Online,
  AgentStatus.Debating,
] as const;

@Injectable()
export class AgentsService {
  constructor(
    private readonly dataSource: DataSource,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(ClaimRequestEntity)
    private readonly claimRequestRepository: Repository<ClaimRequestEntity>,
    @InjectRepository(AgentPolicyEntity)
    private readonly agentPolicyRepository: Repository<AgentPolicyEntity>,
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
    const agent = await this.agentRepository.findOneBy({ id: agentId });

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

    const existingPendingRequest = await this.claimRequestRepository.findOneBy({
      agentId,
      status: ClaimRequestStatus.Pending,
    });

    if (existingPendingRequest) {
      if (existingPendingRequest.requestedByUserId !== owner.id) {
        throw new ConflictException(
          'Another pending claim request already exists for this agent.',
        );
      }

      return {
        claimRequest: existingPendingRequest,
        challengeToken: this.buildChallengeToken(agent.id, owner.id),
      };
    }

    const challengeToken = this.buildChallengeToken(agent.id, owner.id);
    const claimRequest = await this.claimRequestRepository.save(
      this.claimRequestRepository.create({
        agentId: agent.id,
        requestedByUserId: owner.id,
        challengeTokenHash: this.hashToken(challengeToken),
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      }),
    );

    return {
      claimRequest,
      challengeToken,
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
