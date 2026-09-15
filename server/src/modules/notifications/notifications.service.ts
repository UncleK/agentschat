import { enqueueDelivery } from '../../database/enqueue-delivery';
import {
  inTransaction,
  transactionalRepository,
  afterCommit,
} from '../../database/transaction-context';
import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  In,
  IsNull,
  QueryFailedError,
  Repository,
  SelectQueryBuilder,
} from 'typeorm';
import {
  AgentOwnerType,
  ThreadParticipantRole,
  EventActorType,
  FollowTargetType,
  SubjectType,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { DebateSeatEntity } from '../../database/entities/debate-seat.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { DeliveryEntity } from '../../database/entities/delivery.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { NotificationEntity } from '../../database/entities/notification.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { RealtimeService } from '../realtime/realtime.service';

interface NotificationRecipient {
  type: SubjectType;
  id: string;
  kind: string;
}

@Injectable()
export class NotificationsService {
  private readonly replayWindowMs = 15 * 60 * 1000;

  constructor(
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    @InjectRepository(NotificationEntity)
    private readonly notificationRepository: Repository<NotificationEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    @InjectRepository(FollowEntity)
    private readonly followRepository: Repository<FollowEntity>,
    @InjectRepository(DebateSessionEntity)
    private readonly debateSessionRepository: Repository<DebateSessionEntity>,
    @InjectRepository(DebateSeatEntity)
    private readonly debateSeatRepository: Repository<DebateSeatEntity>,
    @InjectRepository(ThreadParticipantEntity)
    private readonly threadParticipantRepository: Repository<ThreadParticipantEntity>,
    @InjectRepository(DeliveryEntity)
    private readonly deliveryRepository: Repository<DeliveryEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
    private readonly realtimeService: RealtimeService,
  ) {
    this.agentRepository = transactionalRepository(this.agentRepository);
    this.notificationRepository = transactionalRepository(
      this.notificationRepository,
    );
    this.eventRepository = transactionalRepository(this.eventRepository);
    this.followRepository = transactionalRepository(this.followRepository);
    this.debateSessionRepository = transactionalRepository(
      this.debateSessionRepository,
    );
    this.debateSeatRepository = transactionalRepository(
      this.debateSeatRepository,
    );
    this.threadParticipantRepository = transactionalRepository(
      this.threadParticipantRepository,
    );
    this.deliveryRepository = transactionalRepository(this.deliveryRepository);
    this.agentConnectionRepository = transactionalRepository(
      this.agentConnectionRepository,
    );
  }

  async processEventById(eventId: string): Promise<void> {
    const event = await this.eventRepository.findOneBy({ id: eventId });

    if (!event) {
      throw new NotFoundException(`Event ${eventId} was not found.`);
    }

    await this.processEvent(event);
  }

  async processEvent(event: EventEntity): Promise<void> {
    await inTransaction(
      this.eventRepository.manager.connection,
      async (manager) => {
        await manager.query(
          'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
          [`notification:${event.id}`],
        );
        await this.processEventRecipients(event);
      },
    );
  }

  private async processEventRecipients(event: EventEntity): Promise<void> {
    const recipients = await this.collectRecipients(event);
    const uniqueRecipients = new Map<string, NotificationRecipient>();

    for (const recipient of recipients) {
      if (
        event.actorType === EventActorType.Human &&
        event.actorUserId === recipient.id
      ) {
        continue;
      }

      if (
        event.actorType === EventActorType.Agent &&
        event.actorAgentId === recipient.id
      ) {
        continue;
      }

      uniqueRecipients.set(
        `${recipient.type}:${recipient.id}:${recipient.kind}`,
        recipient,
      );
    }

    for (const recipient of [...uniqueRecipients.values()].sort((a, b) =>
      a.id.localeCompare(b.id),
    )) {
      const notification = await this.upsertNotification(recipient, event);

      if (recipient.type === SubjectType.Human) {
        const bellState = await this.readBellState(recipient.id);

        afterCommit(() =>
          this.realtimeService.emitToHuman(recipient.id, {
            type: 'notification.created',
            notification: this.serializeNotification(notification),
            bell: bellState,
          }),
        );

        continue;
      }

      await this.enqueueEventForAgent(event, recipient.id);
    }
  }

  async listForHuman(userId: string) {
    const notifications = await this.constrainCurrentDmAccess(
      this.notificationRepository
        .createQueryBuilder('notification')
        .where('notification.recipient_type = :recipientType', {
          recipientType: SubjectType.Human,
        })
        .andWhere('notification.recipient_subject_id = :userId', { userId }),
      userId,
    )
      .orderBy('notification.created_at', 'DESC')
      .getMany();

    return {
      notifications: notifications.map((notification) =>
        this.serializeNotification(notification),
      ),
    };
  }

  async readBellState(userId: string) {
    const unreadCount = await this.constrainCurrentDmAccess(
      this.notificationRepository
        .createQueryBuilder('notification')
        .where('notification.recipient_type = :recipientType', {
          recipientType: SubjectType.Human,
        })
        .andWhere('notification.recipient_subject_id = :userId', { userId })
        .andWhere('notification.read_at IS NULL'),
      userId,
    ).getCount();

    return {
      hasUnread: unreadCount > 0,
      unreadCount,
    };
  }

  async markReadForHuman(
    userId: string,
    notificationIds: string[] | undefined,
    markAll: boolean | undefined,
  ) {
    const now = new Date();

    if (markAll) {
      await this.notificationRepository
        .createQueryBuilder()
        .update(NotificationEntity)
        .set({ readAt: now })
        .where('recipient_type = :recipientType', {
          recipientType: SubjectType.Human,
        })
        .andWhere('recipient_subject_id = :recipientSubjectId', {
          recipientSubjectId: userId,
        })
        .andWhere('read_at IS NULL')
        .execute();
    } else {
      const ids = [
        ...new Set(
          (notificationIds ?? []).map((id) => id.trim()).filter(Boolean),
        ),
      ];

      if (ids.length > 0) {
        const readableNotifications = await this.notificationRepository.findBy({
          id: In(ids),
          recipientType: SubjectType.Human,
          recipientSubjectId: userId,
          readAt: IsNull(),
        });

        if (readableNotifications.length > 0) {
          for (const notification of readableNotifications) {
            await this.notificationRepository
              .createQueryBuilder()
              .update(NotificationEntity)
              .set({ readAt: now })
              .where('id = :id', { id: notification.id })
              .andWhere('recipient_type = :recipientType', {
                recipientType: SubjectType.Human,
              })
              .andWhere('recipient_subject_id = :recipientSubjectId', {
                recipientSubjectId: userId,
              })
              .execute();
          }
        }
      }
    }

    const bellState = await this.readBellState(userId);

    this.realtimeService.emitToHuman(userId, {
      type: 'notifications.read',
      bell: bellState,
    });

    return bellState;
  }

  private async collectRecipients(
    event: EventEntity,
  ): Promise<NotificationRecipient[]> {
    switch (event.eventType) {
      case 'claim.requested':
        return event.targetId
          ? [
              {
                type: SubjectType.Agent,
                id: event.targetId,
                kind: 'claim.requested',
              },
            ]
          : [];
      case 'dm.send':
        return this.collectDirectMessageRecipients(event);
      case 'forum.reply.create':
        return this.collectForumReplyRecipients(event);
      case 'debate.create':
      case 'debate.ready_to_start':
      case 'debate.started':
      case 'debate.paused':
      case 'debate.resumed':
      case 'debate.ended':
      case 'debate.turn.assigned':
      case 'debate.turn.missed':
      case 'debate.seat.replacement_needed':
      case 'debate.seat.replaced':
      case 'debate.turn.submit':
      case 'debate.spectator.post':
        return this.collectDebateRecipients(event);
      default:
        return [];
    }
  }

  private async collectDirectMessageRecipients(
    event: EventEntity,
  ): Promise<NotificationRecipient[]> {
    const participants = await this.threadParticipantRepository.findBy({
      threadId: event.threadId,
    });

    const members = participants.filter(
      (participant) => participant.role === ThreadParticipantRole.Member,
    );
    const agentIds = members
      .filter(
        (participant) => participant.participantType === SubjectType.Agent,
      )
      .map((participant) => participant.participantSubjectId);
    const ownedAgents =
      agentIds.length === 0
        ? []
        : await this.agentRepository.findBy({
            id: In(agentIds),
            ownerType: AgentOwnerType.Human,
          });
    return [
      ...members.map((participant) => ({
        type: participant.participantType,
        id: participant.participantSubjectId,
        kind: 'dm.received',
      })),
      ...ownedAgents
        .filter((agent) => agent.ownerUserId != null)
        .map((agent) => ({
          type: SubjectType.Human,
          id: agent.ownerUserId!,
          kind: 'dm.received',
        })),
    ];
  }

  private constrainCurrentDmAccess(
    query: SelectQueryBuilder<NotificationEntity>,
    userId: string,
  ): SelectQueryBuilder<NotificationEntity> {
    return query.andWhere(
      `(
      notification.kind <> 'dm.received'
      OR EXISTS (
        SELECT 1 FROM thread_participants member
        WHERE member.thread_id = notification.thread_id AND member.role = 'member'
          AND member.participant_type = 'human' AND member.participant_subject_id = :dmViewerId
      )
      OR EXISTS (
        SELECT 1 FROM thread_participants member
        JOIN agents agent ON agent.id = member.participant_subject_id
        WHERE member.thread_id = notification.thread_id AND member.role = 'member'
          AND member.participant_type = 'agent' AND agent.owner_type = 'human'
          AND agent.owner_user_id = :dmViewerId
      )
    )`,
      { dmViewerId: userId },
    );
  }

  private async collectForumReplyRecipients(
    event: EventEntity,
  ): Promise<NotificationRecipient[]> {
    const [followers, participants] = await Promise.all([
      this.followRepository.findBy({
        targetType: FollowTargetType.Topic,
        targetSubjectId: event.threadId,
      }),
      this.threadParticipantRepository.findBy({
        threadId: event.threadId,
      }),
    ]);

    return [
      ...followers.map((follow) => ({
        type: follow.followerType,
        id: follow.followerSubjectId,
        kind: 'forum.reply',
      })),
      ...participants.map((participant) => ({
        type: participant.participantType,
        id: participant.participantSubjectId,
        kind: 'forum.reply',
      })),
    ];
  }

  private async collectDebateRecipients(
    event: EventEntity,
  ): Promise<NotificationRecipient[]> {
    if (!event.targetId) {
      return [];
    }

    const [follows, participants, debateSession, seats] = await Promise.all([
      this.followRepository.findBy({
        targetType: FollowTargetType.Debate,
        targetSubjectId: event.targetId,
      }),
      this.threadParticipantRepository.findBy({
        threadId: event.threadId,
      }),
      this.debateSessionRepository.findOneBy({
        id: event.targetId,
      }),
      this.debateSeatRepository.findBy({
        debateSessionId: event.targetId,
      }),
    ]);

    const followedAgentIds = new Set<string>();
    if (
      debateSession?.hostType === SubjectType.Agent &&
      debateSession.hostAgentId
    ) {
      followedAgentIds.add(debateSession.hostAgentId);
    }
    for (const seat of seats) {
      if (seat.agentId) {
        followedAgentIds.add(seat.agentId);
      }
    }

    const agentFollowers =
      followedAgentIds.size === 0
        ? []
        : await this.followRepository.find({
            where: {
              targetType: FollowTargetType.Agent,
              targetSubjectId: In([...followedAgentIds]),
            },
          });

    return [
      ...follows.map((follow) => ({
        type: follow.followerType,
        id: follow.followerSubjectId,
        kind: 'debate.activity',
      })),
      ...agentFollowers.map((follow) => ({
        type: follow.followerType,
        id: follow.followerSubjectId,
        kind: 'debate.activity',
      })),
      ...participants.map((participant) => ({
        type: participant.participantType,
        id: participant.participantSubjectId,
        kind: 'debate.activity',
      })),
    ];
  }

  private async upsertNotification(
    recipient: NotificationRecipient,
    event: EventEntity,
  ): Promise<NotificationEntity> {
    const existing = await this.notificationRepository.findOneBy({
      recipientType: recipient.type,
      recipientSubjectId: recipient.id,
      eventId: event.id,
      kind: recipient.kind,
    });

    if (existing) {
      return existing;
    }

    const saved = await this.notificationRepository.save(
      this.notificationRepository.create({
        recipientType: recipient.type,
        recipientSubjectId: recipient.id,
        recipientUserId:
          recipient.type === SubjectType.Human ? recipient.id : null,
        recipientAgentId:
          recipient.type === SubjectType.Agent ? recipient.id : null,
        kind: recipient.kind,
        eventId: event.id,
        threadId: event.threadId,
        payload: {
          eventType: event.eventType,
          actorType: event.actorType,
          actorUserId: event.actorUserId,
          actorAgentId: event.actorAgentId,
          targetType: event.targetType,
          targetId: event.targetId,
          contentType: event.contentType,
          content: event.content,
          metadata: event.metadata,
          occurredAt: event.occurredAt.toISOString(),
        },
      }),
    );
    // Reload scalar foreign keys: initialized nullable relation fields can clear
    // them on the entity returned by save even though the stored row is correct.
    return this.notificationRepository.findOneByOrFail({ id: saved.id });
  }

  private async enqueueEventForAgent(
    event: EventEntity,
    recipientAgentId: string,
  ): Promise<void> {
    await enqueueDelivery(
      this.deliveryRepository.manager.connection,
      event.id,
      recipientAgentId,
      this.replayWindowMs,
    );
  }

  private serializeNotification(notification: NotificationEntity) {
    return {
      id: notification.id,
      kind: notification.kind,
      eventId: notification.eventId,
      threadId: notification.threadId,
      payload: notification.payload,
      readAt: notification.readAt?.toISOString() ?? null,
      createdAt: notification.createdAt.toISOString(),
    };
  }

  private isUniqueConstraintViolation(
    error: unknown,
    constraintName: string,
  ): boolean {
    if (!(error instanceof QueryFailedError)) {
      return false;
    }

    const driverError = error.driverError as
      { code?: string; constraint?: string } | undefined;

    return (
      driverError?.code === '23505' && driverError.constraint === constraintName
    );
  }
}
