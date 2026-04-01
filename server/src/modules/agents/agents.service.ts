import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { createHash } from 'node:crypto';
import { DataSource, Repository } from 'typeorm';
import {
  AgentOwnerType,
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

  async importHumanOwnedAgent(owner: AuthenticatedHuman, input: ImportAgentInput) {
    return this.createAgent(input, AgentOwnerType.Human, owner.id);
  }

  async requestClaim(owner: AuthenticatedHuman, agentId: string) {
    const agent = await this.agentRepository.findOneBy({ id: agentId });

    if (!agent) {
      throw new NotFoundException(`Agent ${agentId} was not found.`);
    }

    if (agent.ownerType === AgentOwnerType.Human) {
      if (agent.ownerUserId === owner.id) {
        throw new ConflictException('This agent is already owned by the requesting human.');
      }

      throw new ConflictException('Human-owned agents must be imported by their owner.');
    }

    const existingPendingRequest = await this.claimRequestRepository.findOneBy({
      agentId,
      status: ClaimRequestStatus.Pending,
    });

    if (existingPendingRequest) {
      if (existingPendingRequest.requestedByUserId !== owner.id) {
        throw new ConflictException('Another pending claim request already exists for this agent.');
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
      throw new NotFoundException(`Claim request ${claimRequestId} was not found.`);
    }

    if (claimRequest.requestedByUserId !== owner.id) {
      throw new ForbiddenException('Claim requests can only be confirmed by the requesting human.');
    }

    if (claimRequest.status !== ClaimRequestStatus.Pending) {
      throw new ConflictException('Only pending claim requests can be confirmed.');
    }

    if (claimRequest.expiresAt.getTime() <= Date.now()) {
      claimRequest.status = ClaimRequestStatus.Expired;
      await this.claimRequestRepository.save(claimRequest);
      throw new ConflictException('The claim request challenge has expired.');
    }

    if (claimRequest.challengeTokenHash !== this.hashToken(challengeToken.trim())) {
      throw new ForbiddenException('The claim challenge confirmation is invalid.');
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

    const updatedAgent = await this.agentRepository.findOneByOrFail({ id: agentId });
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
