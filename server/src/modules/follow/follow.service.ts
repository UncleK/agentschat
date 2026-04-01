import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import {
  AgentStatus,
  FollowTargetType,
  SubjectType,
  ThreadContextType,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { BlockRuleEntity } from '../../database/entities/block-rule.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { AuthenticatedHuman } from '../auth/auth.types';

interface SubjectReference {
  type: SubjectType;
  id: string;
}

interface FollowTargetReference {
  type: FollowTargetType;
  id: string;
}

@Injectable()
export class FollowService {
  constructor(
    @InjectRepository(FollowEntity)
    private readonly followRepository: Repository<FollowEntity>,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(ThreadEntity)
    private readonly threadRepository: Repository<ThreadEntity>,
    @InjectRepository(DebateSessionEntity)
    private readonly debateSessionRepository: Repository<DebateSessionEntity>,
    @InjectRepository(ForumTopicViewEntity)
    private readonly forumTopicViewRepository: Repository<ForumTopicViewEntity>,
    @InjectRepository(BlockRuleEntity)
    private readonly blockRuleRepository: Repository<BlockRuleEntity>,
  ) {}

  async follow(actor: SubjectReference, target: FollowTargetReference) {
    await this.assertActorExists(actor);
    await this.assertTargetExists(target);
    await this.assertFollowAllowed(actor, target);

    const existingFollow = await this.followRepository.findOneBy({
      followerType: actor.type,
      followerSubjectId: actor.id,
      targetType: target.type,
      targetSubjectId: target.id,
    });

    if (!existingFollow) {
      await this.followRepository.insert(this.buildFollowInsert(actor, target));

      if (target.type === FollowTargetType.Topic) {
        await this.forumTopicViewRepository.increment({ threadId: target.id }, 'followCount', 1);
      }
    }

    return this.buildFollowState(actor, target, true);
  }

  async unfollow(actor: SubjectReference, target: FollowTargetReference) {
    await this.assertActorExists(actor);
    await this.assertTargetExists(target);

    const existingFollow = await this.followRepository.findOneBy({
      followerType: actor.type,
      followerSubjectId: actor.id,
      targetType: target.type,
      targetSubjectId: target.id,
    });

    if (existingFollow) {
      await this.followRepository.delete({ id: existingFollow.id });

      if (target.type === FollowTargetType.Topic) {
        const topicView = await this.forumTopicViewRepository.findOneBy({ threadId: target.id });

        if (topicView?.followCount) {
          await this.forumTopicViewRepository.decrement({ threadId: target.id }, 'followCount', 1);
        }
      }
    }

    return this.buildFollowState(actor, target, false);
  }

  async readState(actor: SubjectReference, target: FollowTargetReference) {
    await this.assertActorExists(actor);
    await this.assertTargetExists(target);

    const following = await this.followRepository.exist({
      where: {
        followerType: actor.type,
        followerSubjectId: actor.id,
        targetType: target.type,
        targetSubjectId: target.id,
      },
    });

    return this.buildFollowState(actor, target, following);
  }

  async resolveHumanActor(
    human: AuthenticatedHuman,
    actorType: string | undefined,
    actorAgentId: string | null | undefined,
  ): Promise<SubjectReference> {
    const normalizedActorType = actorType?.trim().toLowerCase();

    if (!normalizedActorType || normalizedActorType === SubjectType.Human) {
      return {
        type: SubjectType.Human,
        id: human.id,
      };
    }

    if (normalizedActorType !== SubjectType.Agent) {
      throw new BadRequestException('actorType must be human or agent.');
    }

    const agentId = actorAgentId?.trim();

    if (!agentId) {
      throw new BadRequestException('actorAgentId is required when actorType is agent.');
    }

    const agent = await this.agentRepository.findOneBy({ id: agentId });

    if (!agent) {
      throw new NotFoundException(`Agent ${agentId} was not found.`);
    }

    if (agent.ownerUserId !== human.id) {
      throw new ForbiddenException('Humans may only act through agents they own.');
    }

    return {
      type: SubjectType.Agent,
      id: agent.id,
    };
  }

  parseTarget(targetType: string | undefined, targetId: string | undefined): FollowTargetReference {
    const normalizedTargetId = targetId?.trim();

    if (!normalizedTargetId) {
      throw new BadRequestException('targetId is required.');
    }

    switch (targetType?.trim().toLowerCase()) {
      case FollowTargetType.Agent:
        return { type: FollowTargetType.Agent, id: normalizedTargetId };
      case FollowTargetType.Topic:
        return { type: FollowTargetType.Topic, id: normalizedTargetId };
      case FollowTargetType.Debate:
        return { type: FollowTargetType.Debate, id: normalizedTargetId };
      default:
        throw new BadRequestException('targetType must be agent, topic, or debate.');
    }
  }

  private async assertActorExists(actor: SubjectReference): Promise<void> {
    if (actor.type === SubjectType.Human) {
      const exists = await this.userRepository.exist({ where: { id: actor.id } });

      if (!exists) {
        throw new NotFoundException(`Human ${actor.id} was not found.`);
      }

      return;
    }

    const agent = await this.agentRepository.findOneBy({ id: actor.id });

    if (!agent) {
      throw new NotFoundException(`Agent ${actor.id} was not found.`);
    }

    if (agent.status === AgentStatus.Suspended) {
      throw new ForbiddenException('Suspended agents cannot follow targets.');
    }
  }

  private async assertTargetExists(target: FollowTargetReference): Promise<void> {
    if (target.type === FollowTargetType.Agent) {
      const exists = await this.agentRepository.exist({ where: { id: target.id } });

      if (!exists) {
        throw new NotFoundException(`Agent ${target.id} was not found.`);
      }

      return;
    }

    if (target.type === FollowTargetType.Topic) {
      const exists = await this.threadRepository.exist({
        where: {
          id: target.id,
          contextType: ThreadContextType.ForumTopic,
        },
      });

      if (!exists) {
        throw new NotFoundException(`Forum topic ${target.id} was not found.`);
      }

      return;
    }

    const exists = await this.debateSessionRepository.exist({ where: { id: target.id } });

    if (!exists) {
      throw new NotFoundException(`Debate ${target.id} was not found.`);
    }
  }

  private async assertFollowAllowed(
    actor: SubjectReference,
    target: FollowTargetReference,
  ): Promise<void> {
    if (target.type !== FollowTargetType.Agent) {
      return;
    }

    if (actor.type === SubjectType.Agent && actor.id === target.id) {
      throw new ConflictException('Agents cannot follow themselves.');
    }

    const blockedEitherWay = await Promise.all([
      this.blockRuleRepository.exist({
        where: {
          scopeType: actor.type,
          scopeSubjectId: actor.id,
          blockedType: SubjectType.Agent,
          blockedSubjectId: target.id,
        },
      }),
      this.blockRuleRepository.exist({
        where: {
          scopeType: SubjectType.Agent,
          scopeSubjectId: target.id,
          blockedType: actor.type,
          blockedSubjectId: actor.id,
        },
      }),
    ]);

    if (blockedEitherWay.some(Boolean)) {
      throw new ForbiddenException('A block rule prevents this follow relationship.');
    }
  }

  private buildFollowInsert(actor: SubjectReference, target: FollowTargetReference) {
    return {
      followerType: actor.type,
      followerSubjectId: actor.id,
      followerUserId: actor.type === SubjectType.Human ? actor.id : null,
      followerAgentId: actor.type === SubjectType.Agent ? actor.id : null,
      targetType: target.type,
      targetSubjectId: target.id,
      targetAgentId: target.type === FollowTargetType.Agent ? target.id : null,
      targetThreadId: target.type === FollowTargetType.Topic ? target.id : null,
      targetDebateSessionId: target.type === FollowTargetType.Debate ? target.id : null,
    };
  }

  private buildFollowState(
    actor: SubjectReference,
    target: FollowTargetReference,
    following: boolean,
  ) {
    return {
      actorType: actor.type,
      actorId: actor.id,
      targetType: target.type,
      targetId: target.id,
      following,
    };
  }
}
