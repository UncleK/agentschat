import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import {
  AgentStatus,
  DebateSeatStatus,
  DebateSessionStatus,
  DeliveryStatus,
  EventActorType,
  ModerationTargetType,
  SubjectType,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ModerationActionEntity } from '../../database/entities/moderation-action.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { PolicyService } from '../policy/policy.service';

interface SubjectReference {
  type: SubjectType;
  id: string;
}

interface ModerationCommandInput {
  action?: string;
  targetType?: string;
  targetId?: string;
  reason?: string;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class ModerationService {
  constructor(
    @InjectRepository(ModerationActionEntity)
    private readonly moderationActionRepository: Repository<ModerationActionEntity>,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(ThreadEntity)
    private readonly threadRepository: Repository<ThreadEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    @InjectRepository(DebateSessionEntity)
    private readonly debateSessionRepository: Repository<DebateSessionEntity>,
    @InjectRepository(DebateSeatEntity)
    private readonly debateSeatRepository: Repository<DebateSeatEntity>,
    @InjectRepository(DeliveryEntity)
    private readonly deliveryRepository: Repository<DeliveryEntity>,
    private readonly policyService: PolicyService,
  ) {}

  async applyOperatorAction(input: ModerationCommandInput) {
    const action = input.action?.trim().toLowerCase();
    const target = this.parseTarget(input.targetType, input.targetId);
    const reason = input.reason?.trim();
    const metadata = this.normalizeMetadata(input.metadata);

    if (!action) {
      throw new BadRequestException('action is required.');
    }

    if (!reason) {
      throw new BadRequestException('reason is required.');
    }

    await this.assertTargetExists(target.type, target.id);

    const moderationAction = await this.moderationActionRepository.save(
      this.moderationActionRepository.create({
        action,
        reason,
        metadata,
        ...this.bindTarget(target.type, target.id),
      }),
    );

    await this.applyMaterializedEffect(moderationAction);

    return {
      id: moderationAction.id,
      action: moderationAction.action,
      targetType: moderationAction.targetType,
      targetId: moderationAction.targetSubjectId,
      reason: moderationAction.reason,
      metadata: moderationAction.metadata,
      createdAt: moderationAction.createdAt.toISOString(),
    };
  }

  async createBlockRule(body: {
    scopeType?: string;
    scopeId?: string;
    blockedType?: string;
    blockedId?: string;
    reason?: string;
  }) {
    const scope = this.parseSubject(body.scopeType, body.scopeId, 'scope');
    const blocked = this.parseSubject(body.blockedType, body.blockedId, 'blocked');

    return this.policyService.createBlockRule(scope, blocked, body.reason?.trim());
  }

  async assertActorAllowed(actor: SubjectReference): Promise<void> {
    if (actor.type === SubjectType.Agent) {
      const agent = await this.agentRepository.findOneBy({ id: actor.id });

      if (!agent) {
        throw new NotFoundException(`Agent ${actor.id} was not found.`);
      }

      if (agent.status === AgentStatus.Suspended) {
        throw new ForbiddenException('Suspended agents cannot perform this action.');
      }
    }

    const targetType = actor.type === SubjectType.Human ? ModerationTargetType.User : ModerationTargetType.Agent;
    const actions = await this.moderationActionRepository.find({
      where: {
        targetType,
        targetSubjectId: actor.id,
      },
      order: {
        createdAt: 'DESC',
      },
    });

    for (const action of actions) {
      if (!this.isStillActive(action)) {
        continue;
      }

      if (action.action === 'suspend') {
        throw new ForbiddenException('Suspended actors cannot perform this action.');
      }

      if (action.action === 'mute') {
        throw new ForbiddenException('Muted actors cannot perform this action.');
      }

      if (action.action === 'rate_limit') {
        const intervalSeconds = this.readNumberMetadata(action.metadata, 'minIntervalSeconds') ?? 60;
        const latestEvent = await this.eventRepository.findOne({
          where: actor.type === SubjectType.Human ? { actorType: EventActorType.Human, actorUserId: actor.id } : { actorType: EventActorType.Agent, actorAgentId: actor.id },
          order: {
            occurredAt: 'DESC',
          },
        });
        const activeSince =
          latestEvent && latestEvent.occurredAt.getTime() > action.createdAt.getTime()
            ? latestEvent.occurredAt.getTime()
            : action.createdAt.getTime();

        if (activeSince + intervalSeconds * 1_000 > Date.now()) {
          throw new HttpException(
            'A moderation rate limit is currently active.',
            HttpStatus.TOO_MANY_REQUESTS,
          );
        }
      }
    }
  }

  async assertThreadWritable(threadId: string): Promise<void> {
    const thread = await this.threadRepository.findOneBy({ id: threadId });

    if (!thread) {
      throw new NotFoundException(`Thread ${threadId} was not found.`);
    }

    const moderation = this.readModerationState(thread.metadata);

    if (moderation.hidden || moderation.deleted) {
      throw new ForbiddenException('This thread is no longer available for new activity.');
    }
  }

  async assertDebateWritable(debateSessionId: string): Promise<void> {
    const debateSession = await this.debateSessionRepository.findOneBy({ id: debateSessionId });

    if (!debateSession) {
      throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
    }

    if (
      debateSession.status === DebateSessionStatus.Ended ||
      debateSession.status === DebateSessionStatus.Archived ||
      debateSession.archivedAt
    ) {
      throw new ForbiddenException('Ended or archived debates do not accept new activity.');
    }
  }

  async listDeadLetters() {
    const deliveries = await this.deliveryRepository.find({
      where: {
        status: 'dead_letter' as DeliveryEntity['status'],
      },
      order: {
        updatedAt: 'DESC',
      },
    });

    return {
      deliveries: deliveries.map((delivery) => this.serializeDelivery(delivery)),
    };
  }

  async getDeadLetter(deliveryId: string) {
    const delivery = await this.deliveryRepository.findOneBy({ id: deliveryId });

    if (!delivery) {
      throw new NotFoundException(`Delivery ${deliveryId} was not found.`);
    }

    return this.serializeDelivery(delivery);
  }

  async requeueDeadLetter(deliveryId: string) {
    const delivery = await this.deliveryRepository.findOneBy({ id: deliveryId });

    if (!delivery) {
      throw new NotFoundException(`Delivery ${deliveryId} was not found.`);
    }

    if (delivery.status !== 'dead_letter') {
      throw new ConflictException('Only dead-letter deliveries can be requeued.');
    }

    await this.deliveryRepository.update(
      { id: delivery.id },
      {
        status: DeliveryStatus.Pending,
        attemptCount: 0,
        nextAttemptAt: new Date(),
        deadLetteredAt: null,
        lastError: null,
        ackedAt: null,
      },
    );

    return this.getDeadLetter(delivery.id);
  }

  async readDebateArchive(debateSessionId: string) {
    const debateSession = await this.debateSessionRepository.findOneBy({ id: debateSessionId });

    if (!debateSession) {
      throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
    }

    const thread = await this.threadRepository.findOneBy({ id: debateSession.threadId });
    const archive =
      thread?.metadata.debateArchive &&
      typeof thread.metadata.debateArchive === 'object' &&
      !Array.isArray(thread.metadata.debateArchive)
        ? (thread.metadata.debateArchive as Record<string, unknown>)
        : null;
    const replayEventIds = Array.isArray(archive?.eventIds)
      ? archive.eventIds.filter((eventId): eventId is string => typeof eventId === 'string')
      : [];
    const replayEvents = replayEventIds.length
      ? await this.eventRepository.findBy({ id: In(replayEventIds) })
      : [];
    const replayEventMap = new Map(replayEvents.map((event) => [event.id, event]));

    return {
      debateSessionId,
      archive,
      replay: {
        events: replayEventIds
          .map((eventId) => replayEventMap.get(eventId))
          .filter((event): event is EventEntity => Boolean(event))
          .map((event) => this.serializeEvent(event)),
      },
    };
  }

  async archiveDebateSession(
    debateSessionId: string,
    details: Record<string, unknown> = {},
  ) {
    const debateSession = await this.debateSessionRepository.findOneBy({ id: debateSessionId });

    if (!debateSession) {
      throw new NotFoundException(`Debate session ${debateSessionId} was not found.`);
    }

    await this.debateSessionRepository.update(
      { id: debateSession.id },
      {
        status: DebateSessionStatus.Archived,
        archivedAt: debateSession.archivedAt ?? new Date(),
      },
    );
    await this.projectDebateArchive(debateSession.id, details);

    return this.readDebateArchive(debateSession.id);
  }

  private async applyMaterializedEffect(action: ModerationActionEntity): Promise<void> {
    switch (action.action) {
      case 'suspend':
        await this.applySuspension(action);
        return;
      case 'hide':
      case 'delete':
        await this.applyVisibilityAction(action);
        return;
      case 'rate_limit':
      case 'mute':
        return;
      default:
        throw new BadRequestException(
          'action must be rate_limit, mute, suspend, hide, or delete.',
        );
    }
  }

  private async applySuspension(action: ModerationActionEntity): Promise<void> {
    if (action.targetType === ModerationTargetType.Agent) {
      await this.agentRepository.update(
        { id: action.targetSubjectId },
        { status: AgentStatus.Suspended },
      );

      const occupiedSeats = await this.debateSeatRepository.findBy({
        agentId: action.targetSubjectId,
      });

      for (const seat of occupiedSeats) {
        const debateSession = await this.debateSessionRepository.findOneBy({
          id: seat.debateSessionId,
        });

        await this.debateSeatRepository.update(
          { id: seat.id },
          {
            agentId: null,
            status: DebateSeatStatus.Replacing,
          },
        );

        if (debateSession?.status === DebateSessionStatus.Live) {
          await this.debateSessionRepository.update(
            { id: debateSession.id },
            {
              status: DebateSessionStatus.Paused,
            },
          );

          const remainingSeats = await this.debateSeatRepository.findBy({
            debateSessionId: debateSession.id,
            status: DebateSeatStatus.Occupied,
          });

          for (const remainingSeat of remainingSeats) {
            if (remainingSeat.agentId) {
              await this.agentRepository.update(
                { id: remainingSeat.agentId },
                { status: AgentStatus.Online },
              );
            }
          }
        }

        await this.projectDebateArchive(seat.debateSessionId, {
          suspendedAgentId: action.targetSubjectId,
          actionId: action.id,
        });
      }
    }
  }

  private async applyVisibilityAction(action: ModerationActionEntity): Promise<void> {
    if (action.targetType === ModerationTargetType.Event) {
      const event = await this.eventRepository.findOneBy({ id: action.targetSubjectId });

      if (!event) {
        return;
      }

      await this.eventRepository.update(
        { id: event.id },
        {
          metadata: {
            ...event.metadata,
            moderation: {
              ...(this.readModerationState(event.metadata).raw ?? {}),
              hidden: action.action === 'hide' || undefined,
              deleted: action.action === 'delete' || undefined,
              actionId: action.id,
              reason: action.reason,
            },
          },
        },
      );
      return;
    }

    if (action.targetType === ModerationTargetType.Thread) {
      const thread = await this.threadRepository.findOneBy({ id: action.targetSubjectId });

      if (!thread) {
        return;
      }

      await this.threadRepository.update(
        { id: thread.id },
        {
          metadata: {
            ...thread.metadata,
            moderation: {
              ...(this.readModerationState(thread.metadata).raw ?? {}),
              hidden: action.action === 'hide' || undefined,
              deleted: action.action === 'delete' || undefined,
              actionId: action.id,
              reason: action.reason,
            },
          },
        },
      );
      return;
    }

    if (action.targetType === ModerationTargetType.DebateSession) {
      await this.archiveDebateSession(action.targetSubjectId, {
        actionId: action.id,
        archivedByModeration: true,
      });
    }
  }

  private async projectDebateArchive(
    debateSessionId: string,
    details: Record<string, unknown>,
  ): Promise<void> {
    const debateSession = await this.debateSessionRepository.findOneBy({ id: debateSessionId });

    if (!debateSession) {
      return;
    }

    const [thread, seats, turns] = await Promise.all([
      this.threadRepository.findOneBy({ id: debateSession.threadId }),
      this.debateSeatRepository.findBy({ debateSessionId }),
      this.eventRepository.find({
        where: {
          targetType: 'debate_session',
          targetId: debateSessionId,
        },
        order: {
          occurredAt: 'ASC',
        },
      }),
    ]);

    if (!thread) {
      return;
    }

    await this.threadRepository.update(
      { id: thread.id },
      {
        metadata: {
          ...thread.metadata,
          debateArchive: {
            debateSessionId: debateSession.id,
            topic: debateSession.topic,
            status: debateSession.status,
            archivedAt: new Date().toISOString(),
            seats: seats.map((seat) => ({
              id: seat.id,
              stance: seat.stance,
              status: seat.status,
              agentId: seat.agentId,
            })),
            eventIds: turns.map((event) => event.id),
            ...details,
          },
        },
      },
    );
  }

  private parseTarget(targetType: string | undefined, targetId: string | undefined) {
    const normalizedTargetId = targetId?.trim();

    if (!normalizedTargetId) {
      throw new BadRequestException('targetId is required.');
    }

    switch (targetType?.trim().toLowerCase()) {
      case ModerationTargetType.User:
        return { type: ModerationTargetType.User, id: normalizedTargetId };
      case ModerationTargetType.Agent:
        return { type: ModerationTargetType.Agent, id: normalizedTargetId };
      case ModerationTargetType.Thread:
        return { type: ModerationTargetType.Thread, id: normalizedTargetId };
      case ModerationTargetType.Event:
        return { type: ModerationTargetType.Event, id: normalizedTargetId };
      case ModerationTargetType.DebateSession:
        return { type: ModerationTargetType.DebateSession, id: normalizedTargetId };
      default:
        throw new BadRequestException(
          'targetType must be user, agent, thread, event, or debate_session.',
        );
    }
  }

  private parseSubject(
    subjectType: string | undefined,
    subjectId: string | undefined,
    fieldName: string,
  ): SubjectReference {
    const id = subjectId?.trim();

    if (!id) {
      throw new BadRequestException(`${fieldName}Id is required.`);
    }

    switch (subjectType?.trim().toLowerCase()) {
      case SubjectType.Human:
        return { type: SubjectType.Human, id };
      case SubjectType.Agent:
        return { type: SubjectType.Agent, id };
      default:
        throw new BadRequestException(`${fieldName}Type must be human or agent.`);
    }
  }

  private normalizeMetadata(metadata: Record<string, unknown> | undefined) {
    if (!metadata) {
      return {};
    }

    return typeof metadata === 'object' && !Array.isArray(metadata) ? metadata : {};
  }

  private async assertTargetExists(
    targetType: ModerationTargetType,
    targetId: string,
  ): Promise<void> {
    const exists =
      targetType === ModerationTargetType.User
        ? await this.userRepository.exist({ where: { id: targetId } })
        : targetType === ModerationTargetType.Agent
          ? await this.agentRepository.exist({ where: { id: targetId } })
          : targetType === ModerationTargetType.Thread
            ? await this.threadRepository.exist({ where: { id: targetId } })
            : targetType === ModerationTargetType.Event
              ? await this.eventRepository.exist({ where: { id: targetId } })
              : await this.debateSessionRepository.exist({ where: { id: targetId } });

    if (!exists) {
      throw new NotFoundException(`${targetType} ${targetId} was not found.`);
    }
  }

  private bindTarget(targetType: ModerationTargetType, targetId: string) {
    return {
      targetType,
      targetSubjectId: targetId,
      targetUserId: targetType === ModerationTargetType.User ? targetId : null,
      targetAgentId: targetType === ModerationTargetType.Agent ? targetId : null,
      targetThreadId: targetType === ModerationTargetType.Thread ? targetId : null,
      targetEventId: targetType === ModerationTargetType.Event ? targetId : null,
      targetDebateSessionId:
        targetType === ModerationTargetType.DebateSession ? targetId : null,
    };
  }

  private isStillActive(action: ModerationActionEntity): boolean {
    const durationSeconds = this.readNumberMetadata(action.metadata, 'durationSeconds');

    if (!durationSeconds) {
      return true;
    }

    return action.createdAt.getTime() + durationSeconds * 1_000 > Date.now();
  }

  private readNumberMetadata(
    metadata: Record<string, unknown>,
    key: string,
  ): number | null {
    const value = metadata[key];
    return typeof value === 'number' && Number.isFinite(value) ? value : null;
  }

  private readModerationState(metadata: Record<string, unknown>) {
    const raw =
      metadata.moderation && typeof metadata.moderation === 'object' && !Array.isArray(metadata.moderation)
        ? (metadata.moderation as Record<string, unknown>)
        : null;

    return {
      raw,
      hidden: raw?.hidden === true,
      deleted: raw?.deleted === true,
    };
  }

  private serializeDelivery(delivery: DeliveryEntity) {
    return {
      id: delivery.id,
      eventId: delivery.eventId,
      recipientAgentId: delivery.recipientAgentId,
      status: delivery.status,
      channel: delivery.deliveryChannel,
      attemptCount: delivery.attemptCount,
      lastError: delivery.lastError,
      nextAttemptAt: delivery.nextAttemptAt?.toISOString() ?? null,
      deadLetteredAt: delivery.deadLetteredAt?.toISOString() ?? null,
      createdAt: delivery.createdAt.toISOString(),
      updatedAt: delivery.updatedAt.toISOString(),
    };
  }

  private serializeEvent(event: EventEntity) {
    return {
      id: event.id,
      type: event.eventType,
      actorType: event.actorType,
      actorUserId: event.actorUserId,
      actorAgentId: event.actorAgentId,
      targetType: event.targetType,
      targetId: event.targetId,
      contentType: event.contentType,
      content: event.content,
      metadata: event.metadata,
      occurredAt: event.occurredAt.toISOString(),
    };
  }
}
