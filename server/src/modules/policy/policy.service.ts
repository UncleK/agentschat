import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  AgentDmAcceptanceMode,
  FollowTargetType,
  SubjectType,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AgentPolicyEntity } from '../../database/entities/agent-policy.entity';
import { BlockRuleEntity } from '../../database/entities/block-rule.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { UserEntity } from '../../database/entities/user.entity';
import {
  AgentSafetyPolicy,
  HumanSafetyPolicy,
  SubjectReference,
} from './policy.types';

@Injectable()
export class PolicyService {
  constructor(
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(AgentPolicyEntity)
    private readonly agentPolicyRepository: Repository<AgentPolicyEntity>,
    @InjectRepository(BlockRuleEntity)
    private readonly blockRuleRepository: Repository<BlockRuleEntity>,
    @InjectRepository(FollowEntity)
    private readonly followRepository: Repository<FollowEntity>,
  ) {}

  async updateHumanSafetyPolicy(
    userId: string,
    updates: Partial<HumanSafetyPolicy>,
  ): Promise<HumanSafetyPolicy> {
    const user = await this.userRepository.findOneBy({ id: userId });

    if (!user) {
      throw new NotFoundException(`Human ${userId} was not found.`);
    }

    user.blockStrangerHumanDm =
      updates.blockStrangerHumanDm ?? user.blockStrangerHumanDm;
    user.blockStrangerAgentDm =
      updates.blockStrangerAgentDm ?? user.blockStrangerAgentDm;

    await this.userRepository.save(user);

    return this.readHumanSafetyPolicy(user.id);
  }

  async readHumanSafetyPolicy(userId: string): Promise<HumanSafetyPolicy> {
    const user = await this.userRepository.findOneBy({ id: userId });

    if (!user) {
      throw new NotFoundException(`Human ${userId} was not found.`);
    }

    return {
      blockStrangerHumanDm: user.blockStrangerHumanDm,
      blockStrangerAgentDm: user.blockStrangerAgentDm,
    };
  }

  async upsertAgentSafetyPolicy(
    agentId: string,
    updates: Partial<AgentSafetyPolicy>,
  ): Promise<AgentSafetyPolicy> {
    const policy = await this.ensureAgentPolicy(agentId);

    policy.dmAcceptanceMode = updates.dmAcceptanceMode ?? policy.dmAcceptanceMode;
    policy.allowOutboundDm = updates.allowOutboundDm ?? policy.allowOutboundDm;
    policy.allowProactiveInteractions =
      updates.allowProactiveInteractions ?? policy.allowProactiveInteractions;

    await this.agentPolicyRepository.save(policy);

    return this.readAgentSafetyPolicy(agentId);
  }

  async readAgentSafetyPolicy(agentId: string): Promise<AgentSafetyPolicy> {
    const policy = await this.ensureAgentPolicy(agentId);

    return {
      dmAcceptanceMode: policy.dmAcceptanceMode,
      allowOutboundDm: policy.allowOutboundDm,
      allowProactiveInteractions: policy.allowProactiveInteractions,
    };
  }

  async createBlockRule(
    scope: SubjectReference,
    blocked: SubjectReference,
    reason?: string,
  ): Promise<BlockRuleEntity> {
    await this.ensureSubjectExists(scope);
    await this.ensureSubjectExists(blocked);

    return this.blockRuleRepository.save(
      this.blockRuleRepository.create({
        ...this.bindScopeSubject(scope),
        ...this.bindBlockedSubject(blocked),
        reason: reason?.trim() || null,
      }),
    );
  }

  async assertDirectMessageAllowed(input: {
    actor: SubjectReference;
    recipient: SubjectReference;
  }): Promise<void> {
    await this.ensureRecipientHasNotBlockedActor(input.recipient, input.actor);

    if (input.actor.type === SubjectType.Agent) {
      const senderPolicy = await this.ensureAgentPolicy(input.actor.id);

      if (!senderPolicy.allowOutboundDm) {
        throw new ForbiddenException(
          'Agent safety policy blocks outbound direct messages.',
        );
      }
    }

    if (input.recipient.type === SubjectType.Human) {
      await this.assertHumanRecipientAllowsDirectMessage(
        input.recipient.id,
        input.actor,
      );
      return;
    }

    await this.assertAgentRecipientAllowsDirectMessage(
      input.recipient.id,
      input.actor,
    );
  }

  private async assertHumanRecipientAllowsDirectMessage(
    recipientUserId: string,
    actor: SubjectReference,
  ): Promise<void> {
    const policy = await this.readHumanSafetyPolicy(recipientUserId);

    if (
      actor.type === SubjectType.Human &&
      actor.id !== recipientUserId &&
      policy.blockStrangerHumanDm
    ) {
      throw new ForbiddenException(
        'Human safety policy blocks stranger human direct messages.',
      );
    }

    if (
      actor.type === SubjectType.Agent &&
      policy.blockStrangerAgentDm &&
      !(await this.isFollowingAgent(recipientUserId, actor.id))
    ) {
      throw new ForbiddenException(
        'Human safety policy blocks stranger agent direct messages.',
      );
    }
  }

  private async assertAgentRecipientAllowsDirectMessage(
    recipientAgentId: string,
    actor: SubjectReference,
  ): Promise<void> {
    const policy = await this.ensureAgentPolicy(recipientAgentId);

    if (policy.dmAcceptanceMode === AgentDmAcceptanceMode.Closed) {
      throw new ForbiddenException('Agent safety policy closes direct messages.');
    }

    if (policy.dmAcceptanceMode === AgentDmAcceptanceMode.ApprovalRequired) {
      throw new ForbiddenException(
        'Agent safety policy requires approval before direct messages.',
      );
    }

    if (
      policy.dmAcceptanceMode === AgentDmAcceptanceMode.FollowedOnly &&
      !(await this.isFollowingAgentActor(actor, recipientAgentId))
    ) {
      throw new ForbiddenException(
        'Agent safety policy only allows direct messages from followers.',
      );
    }
  }

  private async ensureRecipientHasNotBlockedActor(
    recipient: SubjectReference,
    actor: SubjectReference,
  ): Promise<void> {
    const blocked = await this.blockRuleRepository.findOneBy({
      scopeType: recipient.type,
      scopeSubjectId: recipient.id,
      blockedType: actor.type,
      blockedSubjectId: actor.id,
    });

    if (blocked) {
      throw new ForbiddenException('A block rule prevents this direct message.');
    }
  }

  private async isFollowingAgentActor(
    actor: SubjectReference,
    recipientAgentId: string,
  ): Promise<boolean> {
    if (actor.type === SubjectType.Human) {
      return this.followRepository.exist({
        where: {
          followerType: SubjectType.Human,
          followerSubjectId: actor.id,
          followerUserId: actor.id,
          targetType: FollowTargetType.Agent,
          targetSubjectId: recipientAgentId,
          targetAgentId: recipientAgentId,
        },
      });
    }

    return this.followRepository.exist({
      where: {
        followerType: SubjectType.Agent,
        followerSubjectId: actor.id,
        followerAgentId: actor.id,
        targetType: FollowTargetType.Agent,
        targetSubjectId: recipientAgentId,
        targetAgentId: recipientAgentId,
      },
    });
  }

  private async isFollowingAgent(
    humanUserId: string,
    agentId: string,
  ): Promise<boolean> {
    return this.followRepository.exist({
      where: {
        followerType: SubjectType.Human,
        followerSubjectId: humanUserId,
        followerUserId: humanUserId,
        targetType: FollowTargetType.Agent,
        targetSubjectId: agentId,
        targetAgentId: agentId,
      },
    });
  }

  private async ensureAgentPolicy(agentId: string): Promise<AgentPolicyEntity> {
    await this.ensureSubjectExists({ type: SubjectType.Agent, id: agentId });

    const existingPolicy = await this.agentPolicyRepository.findOneBy({ agentId });

    if (existingPolicy) {
      return existingPolicy;
    }

    return this.agentPolicyRepository.save(
      this.agentPolicyRepository.create({ agentId }),
    );
  }

  private async ensureSubjectExists(subject: SubjectReference): Promise<void> {
    if (subject.type === SubjectType.Human) {
      const exists = await this.userRepository.exist({ where: { id: subject.id } });

      if (!exists) {
        throw new NotFoundException(`Human ${subject.id} was not found.`);
      }

      return;
    }

    const exists = await this.agentRepository.exist({ where: { id: subject.id } });

    if (!exists) {
      throw new NotFoundException(`Agent ${subject.id} was not found.`);
    }
  }

  private bindScopeSubject(subject: SubjectReference) {
    if (subject.type === SubjectType.Human) {
      return {
        scopeType: SubjectType.Human,
        scopeSubjectId: subject.id,
        scopeUserId: subject.id,
        scopeAgentId: null,
      };
    }

    return {
      scopeType: SubjectType.Agent,
      scopeSubjectId: subject.id,
      scopeUserId: null,
      scopeAgentId: subject.id,
    };
  }

  private bindBlockedSubject(subject: SubjectReference) {
    if (subject.type === SubjectType.Human) {
      return {
        blockedType: SubjectType.Human,
        blockedSubjectId: subject.id,
        blockedUserId: subject.id,
        blockedAgentId: null,
      };
    }

    return {
      blockedType: SubjectType.Agent,
      blockedSubjectId: subject.id,
      blockedUserId: null,
      blockedAgentId: subject.id,
    };
  }
}
