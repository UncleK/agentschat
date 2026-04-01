import {
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, IsNull, Repository } from 'typeorm';
import {
  DeliveryChannel,
  DeliveryStatus,
  EventActorType,
  FollowTargetType,
  SubjectType,
} from '../../database/domain.enums';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
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
    @InjectRepository(NotificationEntity)
    private readonly notificationRepository: Repository<NotificationEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    @InjectRepository(FollowEntity)
    private readonly followRepository: Repository<FollowEntity>,
    @InjectRepository(ThreadParticipantEntity)
    private readonly threadParticipantRepository: Repository<ThreadParticipantEntity>,
    @InjectRepository(DeliveryEntity)
    private readonly deliveryRepository: Repository<DeliveryEntity>,
    @InjectRepository(AgentConnectionEntity)
    private readonly agentConnectionRepository: Repository<AgentConnectionEntity>,
    private readonly realtimeService: RealtimeService,
  ) {}

  async processEventById(eventId: string): Promise<void> {
    const event = await this.eventRepository.findOneBy({ id: eventId });

    if (!event) {
      throw new NotFoundException(`Event ${eventId} was not found.`);
    }

    await this.processEvent(event);
  }

  async processEvent(event: EventEntity): Promise<void> {
    const recipients = await this.collectRecipients(event);
    const uniqueRecipients = new Map<string, NotificationRecipient>();

    for (const recipient of recipients) {
      if (event.actorType === EventActorType.Human && event.actorUserId === recipient.id) {
        continue;
      }

      if (event.actorType === EventActorType.Agent && event.actorAgentId === recipient.id) {
        continue;
      }

      uniqueRecipients.set(`${recipient.type}:${recipient.id}:${recipient.kind}`, recipient);
    }

    for (const recipient of uniqueRecipients.values()) {
      const notification = await this.upsertNotification(recipient, event);

      if (recipient.type === SubjectType.Human) {
        const bellState = await this.readBellState(recipient.id);

        this.realtimeService.emitToHuman(recipient.id, {
          type: 'notification.created',
          notification: this.serializeNotification(notification),
          bell: bellState,
        });

        continue;
      }

      await this.enqueueEventForAgent(event, recipient.id);
    }
  }

  async listForHuman(userId: string) {
    const notifications = await this.notificationRepository.find({
      where: {
        recipientType: SubjectType.Human,
        recipientSubjectId: userId,
      },
      order: {
        createdAt: 'DESC',
      },
    });

    return {
      notifications: notifications.map((notification) => this.serializeNotification(notification)),
    };
  }

  async readBellState(userId: string) {
    const unreadCount = await this.notificationRepository
      .createQueryBuilder('notification')
      .where('notification.recipient_type = :recipientType', {
        recipientType: SubjectType.Human,
      })
      .andWhere('notification.recipient_subject_id = :recipientSubjectId', {
        recipientSubjectId: userId,
      })
      .andWhere('notification.read_at IS NULL')
      .getCount();

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
      const ids = [...new Set((notificationIds ?? []).map((id) => id.trim()).filter(Boolean))];

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

  private async collectRecipients(event: EventEntity): Promise<NotificationRecipient[]> {
    switch (event.eventType) {
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

    return participants.map((participant) => ({
      type: participant.participantType,
      id: participant.participantSubjectId,
      kind: 'dm.received',
    }));
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

    const follows = await this.followRepository.findBy({
      targetType: FollowTargetType.Debate,
      targetSubjectId: event.targetId,
    });
    const participants = await this.threadParticipantRepository.findBy({
      threadId: event.threadId,
    });

    return [
      ...follows.map((follow) => ({
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

    return this.notificationRepository.save(
      this.notificationRepository.create({
        recipientType: recipient.type,
        recipientSubjectId: recipient.id,
        recipientUserId: recipient.type === SubjectType.Human ? recipient.id : null,
        recipientAgentId: recipient.type === SubjectType.Agent ? recipient.id : null,
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
  }

  private async enqueueEventForAgent(
    event: EventEntity,
    recipientAgentId: string,
  ): Promise<void> {
    const existing = await this.deliveryRepository.findOneBy({
      eventId: event.id,
      recipientAgentId,
    });

    if (existing) {
      return;
    }

    const [latestDelivery, connection] = await Promise.all([
      this.deliveryRepository.find({
        where: { recipientAgentId },
        order: { sequence: 'DESC' },
        take: 1,
      }),
      this.agentConnectionRepository.findOneBy({ agentId: recipientAgentId }),
    ]);
    const sequence = (latestDelivery[0]?.sequence ?? 0) + 1;

    await this.deliveryRepository.insert({
      eventId: event.id,
      recipientAgentId,
      agentConnectionId: connection?.id ?? null,
      sequence,
      status: DeliveryStatus.Pending,
      deliveryChannel: connection?.pollingEnabled
        ? DeliveryChannel.Polling
        : DeliveryChannel.Webhook,
      attemptCount: 0,
      nextAttemptAt: new Date(),
      replayExpiresAt: new Date(Date.now() + this.replayWindowMs),
      ackedAt: null,
      deadLetteredAt: null,
      lastAttemptAt: null,
      lastError: null,
    });
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
}
