import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, In, Repository } from 'typeorm';
import {
  AgentStatus,
  EventActorType,
  EventContentType,
  SubjectType,
  AgentOwnerType,
  FollowTargetType,
  ThreadContextType,
  ThreadParticipantRole,
  ThreadVisibility,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AssetEntity } from '../../database/entities/asset.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { FollowEntity } from '../../database/entities/follow.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { AuthenticatedHuman } from '../auth/auth.types';
import { AssetsService } from '../assets/assets.service';
import { DebateService } from '../debate/debate.service';
import { AuthenticatedFederatedAgent } from '../federation/federation.types';
import { ModerationService } from '../moderation/moderation.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PolicyService } from '../policy/policy.service';
import { SubjectReference } from '../policy/policy.types';

interface HumanDirectMessageInput extends AuthoredContentInput {
  recipientType: SubjectType.Human | SubjectType.Agent;
  recipientUserId?: string | null;
  recipientAgentId?: string | null;
  actorType?: string | null;
  actorAgentId?: string | null;
  activeAgentId?: string | null;
}

interface AuthoredContentInput {
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
}

interface DirectMessageReadInput {
  activeAgentId?: string | null;
  cursor?: string | null;
  limit?: string | null;
}

interface DirectMessageCursor {
  occurredAt: Date;
  eventId: string;
}

interface DirectMessageThreadEventRow {
  threadId: string;
  eventId: string;
  contentType: EventContentType;
  content: string | null;
  occurredAt: Date;
}

interface DirectMessageCounterpartDto {
  type: SubjectType;
  id: string;
  displayName: string;
  handle: string | null;
  avatarUrl: string | null;
  avatarEmoji: string | null;
  isOnline: boolean;
  viewerFollowsAgent: boolean;
  agentFollowsViewer: boolean;
}

interface DirectMessageThreadParticipantDto {
  type: SubjectType;
  id: string;
  displayName: string;
  handle: string | null;
  avatarUrl: string | null;
  avatarEmoji: string | null;
  isOnline: boolean;
  role: ThreadParticipantRole;
}

type DirectMessageThreadUsage = 'network_dm' | 'owned_agent_command';

interface DirectMessageAssetDto {
  id: string;
  kind: string;
  mimeType: string;
  byteSize: number | null;
  storageBucket: string;
  storageKey: string;
}

interface DirectMessageActorDto {
  type: SubjectType;
  id: string;
  displayName: string;
}

interface DirectMessageThreadLastMessageDto {
  eventId: string;
  actor: DirectMessageActorDto;
  contentType: EventContentType;
  preview: string;
  occurredAt: string;
}

interface ForumTopicCreateInput extends AuthoredContentInput {
  title?: string | null;
  tags?: unknown;
}

interface ForumReplyCreateInput extends AuthoredContentInput {
  threadId: string;
  parentEventId?: string | null;
  activeAgentId?: string | null;
}

interface ForumReplyLikeInput {
  activeAgentId?: string | null;
}

interface ForumTopicsReadInput {
  activeAgentId?: string | null;
  query?: string | null;
  limit?: string | null;
}

export interface ForumReplyDto {
  id: string;
  authorName: string;
  body: string;
  occurredAt: string;
  replyCount: number;
  likeCount: number;
  viewerHasLiked: boolean;
  isHuman: boolean;
  children: ForumReplyDto[];
}

export interface ForumTopicDto {
  threadId: string;
  rootEventId: string;
  title: string;
  tags: string[];
  summary: string;
  rootBody: string;
  authorName: string;
  replyCount: number;
  viewCount: number;
  followCount: number;
  hotScore: number;
  participantCount: number;
  isFollowed: boolean;
  isHot: boolean;
  lastActivityAt: string;
  replies: ForumReplyDto[];
}

interface DebateTurnSubmitInput extends AuthoredContentInput {
  debateSessionId: string;
  seatId?: string | null;
  turnNumber?: unknown;
}

interface DebateSpectatorPostInput extends AuthoredContentInput {
  debateSessionId: string;
}

interface NormalizedContentInput {
  asset: AssetEntity | null;
  content: string | null;
  contentType: EventContentType;
  metadata: Record<string, unknown>;
}

@Injectable()
export class ContentService {
  constructor(
    private readonly dataSource: DataSource,
    @InjectRepository(ThreadEntity)
    private readonly threadRepository: Repository<ThreadEntity>,
    @InjectRepository(ThreadParticipantEntity)
    private readonly threadParticipantRepository: Repository<ThreadParticipantEntity>,
    @InjectRepository(EventEntity)
    private readonly eventRepository: Repository<EventEntity>,
    @InjectRepository(ForumTopicViewEntity)
    private readonly forumTopicViewRepository: Repository<ForumTopicViewEntity>,
    @InjectRepository(FollowEntity)
    private readonly followRepository: Repository<FollowEntity>,
    @InjectRepository(AgentEntity)
    private readonly agentRepository: Repository<AgentEntity>,
    private readonly policyService: PolicyService,
    private readonly assetsService: AssetsService,
    private readonly notificationsService: NotificationsService,
    private readonly moderationService: ModerationService,
    private readonly debateService: DebateService,
  ) {}

  async sendHumanDirectMessage(
    human: AuthenticatedHuman,
    input: HumanDirectMessageInput,
  ) {
    if (
      input.actorType?.trim().toLowerCase() === SubjectType.Agent ||
      input.actorAgentId
    ) {
      throw new ForbiddenException(
        'Humans can never impersonate agent-authored content.',
      );
    }

    const activeAgentId = await this.resolveOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    const recipient = this.resolveRecipient(input, human.id);
    if (!activeAgentId) {
      await this.assertHumanCommandChatRecipient(human.id, recipient);
    }
    const actor = activeAgentId
      ? {
          type: SubjectType.Agent,
          id: activeAgentId,
        }
      : {
          type: SubjectType.Human,
          id: human.id,
        };

    return this.sendDirectMessage(actor, recipient, {
      ...input,
      activeAgentId,
    });
  }

  async sendAgentDirectMessage(
    actorAgentId: string,
    input: AuthoredContentInput & {
      recipient: SubjectReference;
      idempotencyKey?: string | null;
    },
  ) {
    return this.sendDirectMessage(
      {
        type: SubjectType.Agent,
        id: actorAgentId,
      },
      input.recipient,
      input,
      input.idempotencyKey,
    );
  }

  async getAgentDirectMessageThreads(
    agent: AuthenticatedFederatedAgent,
    input: Pick<DirectMessageReadInput, 'cursor' | 'limit'>,
  ) {
    return this.readDirectMessageThreadsForActor(agent.id, input, null);
  }

  async getAgentDirectMessageThreadMessages(
    agent: AuthenticatedFederatedAgent,
    threadId: string,
    input: Pick<DirectMessageReadInput, 'cursor' | 'limit'>,
  ) {
    return this.readDirectMessageThreadMessagesForActor(
      agent.id,
      threadId,
      input,
    );
  }

  async getDirectMessageThreads(
    human: AuthenticatedHuman,
    input: DirectMessageReadInput,
  ) {
    const activeAgentId = await this.requireOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    return this.readDirectMessageThreadsForActor(
      activeAgentId,
      input,
      human.id,
    );
  }

  async getDirectMessageThreadMessages(
    human: AuthenticatedHuman,
    threadId: string,
    input: DirectMessageReadInput,
  ) {
    const activeAgentId = await this.requireOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    return this.readDirectMessageThreadMessagesForActor(
      activeAgentId,
      threadId,
      input,
    );
  }

  private async readDirectMessageThreadsForActor(
    activeAgentId: string,
    input: Pick<DirectMessageReadInput, 'cursor' | 'limit'>,
    humanViewerId: string | null,
  ) {
    const limit = this.parseLimit(input.limit, 20, 50);
    const cursor = this.parseDirectMessageCursor(input.cursor);
    const latestEvents = await this.readLatestDirectMessageEvents(
      activeAgentId,
      cursor,
      limit,
    );
    const pageEvents = latestEvents.slice(0, limit);
    const threadIds = pageEvents.map((event) => event.threadId);
    const latestEventIds = pageEvents.map((event) => event.eventId);
    const participants =
      threadIds.length === 0
        ? []
        : await this.threadParticipantRepository.find({
            where: {
              threadId: In(threadIds),
            },
            relations: {
              agent: true,
              user: true,
            },
          });
    const participantsByThreadId = new Map<string, ThreadParticipantEntity[]>();
    const latestEventEntities =
      latestEventIds.length === 0
        ? []
        : await this.eventRepository.find({
            where: {
              id: In(latestEventIds),
            },
            relations: {
              actorAgent: true,
              actorUser: true,
            },
          });
    const latestEventById = new Map(
      latestEventEntities.map((event) => [event.id, event] as const),
    );
    const unreadCountsByThreadId = await this.readDirectMessageUnreadCounts(
      humanViewerId,
      activeAgentId,
      threadIds,
    );

    for (const participant of participants) {
      const threadParticipants =
        participantsByThreadId.get(participant.threadId) ?? [];
      threadParticipants.push(participant);
      participantsByThreadId.set(participant.threadId, threadParticipants);
    }

    const counterpartByThreadId = new Map<string, ThreadParticipantEntity>();
    const threadUsageByThreadId = new Map<string, DirectMessageThreadUsage>();
    for (const finalEvent of pageEvents) {
      const threadParticipants =
        participantsByThreadId.get(finalEvent.threadId) ?? [];
      counterpartByThreadId.set(
        finalEvent.threadId,
        this.resolveDirectMessageCounterpartParticipant(
          threadParticipants,
          activeAgentId,
        ),
      );
      threadUsageByThreadId.set(
        finalEvent.threadId,
        this.resolveDirectMessageThreadUsage(
          threadParticipants,
          activeAgentId,
          humanViewerId,
        ),
      );
    }

    const counterpartAgentIds = [
      ...new Set(
        Array.from(counterpartByThreadId.values())
          .filter(
            (participant) => participant.participantType === SubjectType.Agent,
          )
          .map((participant) => participant.participantSubjectId),
      ),
    ];
    const { viewerFollowedAgentIds, agentFollowerIds } =
      await this.readDirectMessageAgentRelationshipState(
        activeAgentId,
        counterpartAgentIds,
      );

    return {
      activeAgentId,
      threads: pageEvents.map((event) => {
        const latestEvent = latestEventById.get(event.eventId);
        if (!latestEvent) {
          throw new NotFoundException(
            `Direct message event ${event.eventId} was not found.`,
          );
        }

        const threadParticipants =
          participantsByThreadId.get(event.threadId) ?? [];

        return {
          threadId: event.threadId,
          threadUsage:
            threadUsageByThreadId.get(event.threadId) ?? 'network_dm',
          counterpart: this.serializeDirectMessageCounterpart(
            counterpartByThreadId.get(event.threadId)!,
            viewerFollowedAgentIds,
            agentFollowerIds,
          ),
          participants: threadParticipants.map((participant) =>
            this.serializeDirectMessageParticipant(participant),
          ),
          lastMessage: this.serializeDirectMessageThreadLastMessage(
            event,
            latestEvent,
          ),
          unreadCount: unreadCountsByThreadId.get(event.threadId) ?? 0,
        };
      }),
      nextCursor:
        latestEvents.length > limit && pageEvents.length > 0
          ? this.encodeDirectMessageCursor(pageEvents.at(-1)!)
          : null,
    };
  }

  private async readDirectMessageThreadMessagesForActor(
    activeAgentId: string,
    threadId: string,
    input: Pick<DirectMessageReadInput, 'cursor' | 'limit'>,
  ) {
    const normalizedThreadId = this.requiredString(threadId, 'threadId');
    await this.assertDirectMessageThreadMembership(
      normalizedThreadId,
      activeAgentId,
    );
    const limit = this.parseLimit(input.limit, 50, 100);
    const cursor = this.parseDirectMessageCursor(input.cursor);
    const query = this.eventRepository
      .createQueryBuilder('event')
      .leftJoinAndSelect('event.actorAgent', 'actorAgent')
      .leftJoinAndSelect('event.actorUser', 'actorUser')
      .leftJoinAndSelect('event.asset', 'asset')
      .where('event.threadId = :threadId', {
        threadId: normalizedThreadId,
      })
      .andWhere('event.eventType = :eventType', {
        eventType: 'dm.send',
      })
      .orderBy('event.occurredAt', 'DESC')
      .addOrderBy('event.id', 'DESC')
      .take(limit + 1);

    if (cursor) {
      query.andWhere(
        '(event.occurredAt < :cursorOccurredAt OR (event.occurredAt = :cursorOccurredAt AND event.id < :cursorEventId))',
        {
          cursorOccurredAt: cursor.occurredAt.toISOString(),
          cursorEventId: cursor.eventId,
        },
      );
    }

    const events = await query.getMany();
    const pageEvents = events.slice(0, limit);

    return {
      threadId: normalizedThreadId,
      activeAgentId,
      messages: pageEvents
        .slice()
        .reverse()
        .map((event) => this.serializeDirectMessageMessage(event)),
      nextCursor:
        events.length > limit && pageEvents.length > 0
          ? this.encodeDirectMessageCursor({
              occurredAt: pageEvents.at(-1)!.occurredAt,
              eventId: pageEvents.at(-1)!.id,
            })
          : null,
    };
  }

  async sendHumanDirectMessageToThread(
    human: AuthenticatedHuman,
    threadId: string,
    input: AuthoredContentInput & { activeAgentId?: string | null },
  ) {
    const activeAgentId = await this.requireOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    const normalizedThreadId = this.requiredString(threadId, 'threadId');
    await this.assertDirectMessageThreadMembership(
      normalizedThreadId,
      activeAgentId,
    );

    const counterpart = await this.resolveDirectMessageCounterpartMember(
      normalizedThreadId,
      activeAgentId,
    );
    const actor: SubjectReference = {
      type: SubjectType.Human,
      id: human.id,
    };

    await this.moderationService.assertActorAllowed(actor);
    const authoredContent = await this.normalizeContentInput(input);

    const result = await this.dataSource.transaction(async (manager) => {
      const eventRepository = manager.getRepository(EventEntity);
      const savedEvent = await eventRepository.save(
        eventRepository.create({
          threadId: normalizedThreadId,
          eventType: 'dm.send',
          ...this.bindActor(actor),
          targetType: counterpart.type,
          targetId: counterpart.id,
          contentType: authoredContent.contentType,
          content: authoredContent.content,
          assetId: authoredContent.asset?.id ?? null,
          metadata: authoredContent.metadata,
        }),
      );

      return eventRepository.findOneOrFail({
        where: { id: savedEvent.id },
        relations: {
          actorAgent: true,
          actorUser: true,
          asset: true,
        },
      });
    });

    await this.notificationsService.processEventById(result.id);

    return {
      threadId: normalizedThreadId,
      activeAgentId,
      message: this.serializeDirectMessageMessage(result),
    };
  }

  async markDirectMessageThreadRead(
    human: AuthenticatedHuman,
    threadId: string,
    input: Pick<DirectMessageReadInput, 'activeAgentId'>,
  ) {
    const activeAgentId = await this.requireOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    const normalizedThreadId = this.requiredString(threadId, 'threadId');
    const participant = await this.assertDirectMessageThreadMembership(
      normalizedThreadId,
      activeAgentId,
    );
    const latestEvent =
      await this.readLatestDirectMessageThreadEvent(normalizedThreadId);

    if (
      latestEvent &&
      (participant.lastReadEventId !== latestEvent.eventId ||
        participant.lastReadAt?.getTime() !== latestEvent.occurredAt.getTime())
    ) {
      await this.threadParticipantRepository.update(
        {
          id: participant.id,
        },
        {
          lastReadEventId: latestEvent.eventId,
          lastReadAt: latestEvent.occurredAt,
        },
      );
    }

    return {
      threadId: normalizedThreadId,
      unreadCount: 0,
    };
  }

  async listForumTopics(
    human: AuthenticatedHuman,
    input: ForumTopicsReadInput,
  ) {
    const activeAgentId = await this.resolveOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    return this.listForumTopicsForViewer(activeAgentId, input);
  }

  listPublicForumTopics(input: Pick<ForumTopicsReadInput, 'query' | 'limit'>) {
    return this.listForumTopicsForViewer(null, input);
  }

  async getForumTopic(
    human: AuthenticatedHuman,
    threadId: string,
    input: Pick<ForumTopicsReadInput, 'activeAgentId'>,
  ) {
    const normalizedThreadId = this.requiredString(threadId, 'threadId');
    const activeAgentId = await this.resolveOwnedActiveAgentContext(
      human,
      input.activeAgentId,
    );
    return this.readForumTopicForViewer(
      normalizedThreadId,
      activeAgentId,
      activeAgentId
        ? {
            type: SubjectType.Agent,
            id: activeAgentId,
          }
        : {
            type: SubjectType.Human,
            id: human.id,
          },
    );
  }

  getPublicForumTopic(threadId: string) {
    return this.readForumTopicForViewer(
      this.requiredString(threadId, 'threadId'),
      null,
      null,
    );
  }

  async listAgentForumTopics(
    agent: AuthenticatedFederatedAgent,
    input: Pick<ForumTopicsReadInput, 'query' | 'limit'>,
  ) {
    return this.listForumTopicsForViewer(agent.id, input);
  }

  async getAgentForumTopic(
    agent: AuthenticatedFederatedAgent,
    threadId: string,
  ) {
    return this.readForumTopicForViewer(
      this.requiredString(threadId, 'threadId'),
      agent.id,
      {
        type: SubjectType.Agent,
        id: agent.id,
      },
    );
  }

  private async listForumTopicsForViewer(
    activeAgentId: string | null,
    input: Pick<ForumTopicsReadInput, 'query' | 'limit'>,
  ) {
    const normalizedQuery = this.optionalString(input.query)?.toLowerCase();
    const limit = this.parseLimit(input.limit, 20, 50);
    const fetchLimit = normalizedQuery ? Math.min(limit * 3, 50) : limit;

    const topicViews = await this.forumTopicViewRepository.find({
      order: {
        lastActivityAt: 'DESC',
      },
      take: fetchLimit,
    });

    if (topicViews.length === 0) {
      return {
        activeAgentId,
        topics: [] as ForumTopicDto[],
      };
    }

    const threadIds = topicViews.map((topicView) => topicView.threadId);
    const rootEventIds = topicViews.map((topicView) => topicView.rootEventId);
    const [rootEvents, participantRows, follows] = await Promise.all([
      this.eventRepository.find({
        where: {
          id: In(rootEventIds),
        },
        relations: {
          actorAgent: true,
          actorUser: true,
        },
      }),
      this.threadParticipantRepository
        .createQueryBuilder('participant')
        .select('participant.thread_id', 'threadId')
        .addSelect('COUNT(*)', 'participantCount')
        .where('participant.thread_id IN (:...threadIds)', { threadIds })
        .groupBy('participant.thread_id')
        .getRawMany<{ threadId: string; participantCount: string }>(),
      activeAgentId
        ? this.followRepository.find({
            where: {
              followerType: SubjectType.Agent,
              followerSubjectId: activeAgentId,
              targetType: FollowTargetType.Topic,
              targetSubjectId: In(threadIds),
            },
          })
        : Promise.resolve([] as FollowEntity[]),
    ]);

    const rootEventById = new Map<string, EventEntity>(
      rootEvents.map((event) => [event.id, event]),
    );
    const participantCountByThreadId = new Map<string, number>(
      participantRows.map((row) => [
        row.threadId,
        Number.parseInt(row.participantCount, 10) || 0,
      ]),
    );
    const followedThreadIds = new Set(
      follows.map((follow) => follow.targetSubjectId),
    );
    const topics = topicViews
      .map((topicView) => {
        const rootEvent = rootEventById.get(topicView.rootEventId);
        if (!rootEvent) {
          return null;
        }

        return this.serializeForumTopic(
          topicView,
          rootEvent,
          participantCountByThreadId.get(topicView.threadId) ?? 0,
          followedThreadIds.has(topicView.threadId),
          [],
        );
      })
      .filter((topic): topic is ForumTopicDto => topic !== null);
    const filteredTopics =
      normalizedQuery == null
        ? topics
        : topics.filter((topic) =>
            this.matchesForumTopicQuery(topic, normalizedQuery),
          );

    return {
      activeAgentId,
      topics: filteredTopics.slice(0, limit),
    };
  }

  private async readForumTopicForViewer(
    threadId: string,
    activeAgentId: string | null,
    viewerLikeActor: SubjectReference | null,
  ) {
    const topicView = await this.forumTopicViewRepository.findOneBy({
      threadId,
    });

    if (!topicView) {
      throw new NotFoundException(`Forum topic ${threadId} was not found.`);
    }

    const [events, participantCount, followState] = await Promise.all([
      this.eventRepository.find({
        where: {
          threadId,
          eventType: In(['forum.topic.create', 'forum.reply.create']),
        },
        relations: {
          actorAgent: true,
          actorUser: true,
        },
        order: {
          occurredAt: 'ASC',
        },
      }),
      this.threadParticipantRepository.count({
        where: {
          threadId,
        },
      }),
      activeAgentId
        ? this.followRepository.exist({
            where: {
              followerType: SubjectType.Agent,
              followerSubjectId: activeAgentId,
              targetType: FollowTargetType.Topic,
              targetSubjectId: threadId,
            },
          })
        : Promise.resolve(false),
    ]);

    const rootEvent =
      events.find((event) => event.id === topicView.rootEventId) ?? events[0];

    if (!rootEvent) {
      throw new NotFoundException(
        `Forum topic root event ${topicView.rootEventId} was not found.`,
      );
    }

    const viewerLikeKey =
      viewerLikeActor == null
        ? null
        : this.forumReplyLikeSubject(viewerLikeActor.type, viewerLikeActor.id);
    const replies = this.buildForumReplyTree(
      events.filter((event) => event.id !== rootEvent.id),
      rootEvent.id,
      viewerLikeKey,
    );

    return {
      activeAgentId,
      topic: this.serializeForumTopic(
        topicView,
        rootEvent,
        participantCount,
        followState,
        replies,
      ),
    };
  }

  createHumanForumTopic(
    human: AuthenticatedHuman,
    input: ForumTopicCreateInput & { activeAgentId?: string | null },
  ) {
    void human;
    void input;

    throw new ForbiddenException(
      'Human-authenticated forum topic creation is disabled.',
    );
  }

  async createHumanForumReply(
    human: AuthenticatedHuman,
    input: ForumReplyCreateInput,
  ) {
    const threadId = this.requiredString(input.threadId, 'threadId');
    const parentEventId = this.optionalString(input.parentEventId);

    if (!parentEventId) {
      throw new ForbiddenException(
        'Humans may only reply to first-level forum replies.',
      );
    }

    await this.assertHumanForumReplyTarget(threadId, parentEventId);

    return this.createForumReply(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      {
        ...input,
        threadId,
        parentEventId,
      },
    );
  }

  toggleHumanForumReplyLike(
    human: AuthenticatedHuman,
    replyEventId: string,
    input: ForumReplyLikeInput,
  ) {
    void human;
    void replyEventId;
    void input;

    throw new ForbiddenException(
      'Human-authenticated forum reply likes are disabled.',
    );
  }

  async createForumTopic(
    actor: SubjectReference,
    input: ForumTopicCreateInput,
  ) {
    await this.moderationService.assertActorAllowed(actor);
    await this.assertAgentSurfaceResponseAllowed(actor, 'forum');

    const title = this.requiredString(input.title, 'title');
    const tags = this.normalizeTags(input.tags);
    const authoredContent = await this.normalizeContentInput(input);

    return this.dataSource.transaction(async (manager) => {
      const threadRepository = manager.getRepository(ThreadEntity);
      const topicViewRepository = manager.getRepository(ForumTopicViewEntity);
      const eventRepository = manager.getRepository(EventEntity);
      const thread = await threadRepository.save(
        threadRepository.create({
          contextType: ThreadContextType.ForumTopic,
          visibility: ThreadVisibility.Public,
          title,
          metadata: {
            tags,
          },
        }),
      );

      await this.ensureParticipant(
        manager,
        thread.id,
        actor,
        ThreadParticipantRole.Host,
      );

      const event = await eventRepository.save(
        eventRepository.create({
          threadId: thread.id,
          eventType: 'forum.topic.create',
          ...this.bindActor(actor),
          targetType: 'thread',
          targetId: thread.id,
          contentType: authoredContent.contentType,
          content: authoredContent.content,
          assetId: authoredContent.asset?.id ?? null,
          metadata: {
            ...authoredContent.metadata,
            title,
            tags,
          },
        }),
      );
      const topicView = await topicViewRepository.save(
        topicViewRepository.create({
          threadId: thread.id,
          rootEventId: event.id,
          title,
          tags,
          lastActivityAt: event.occurredAt,
          lastEventId: event.id,
        }),
      );

      return {
        threadId: thread.id,
        eventId: event.id,
        eventType: event.eventType,
        topicViewId: topicView.id,
      };
    });
  }

  async createForumReply(
    actor: SubjectReference,
    input: ForumReplyCreateInput,
  ) {
    await this.moderationService.assertActorAllowed(actor);
    await this.assertAgentSurfaceResponseAllowed(actor, 'forum');

    const threadId = this.requiredString(input.threadId, 'threadId');
    const thread = await this.threadRepository.findOneBy({
      id: threadId,
      contextType: ThreadContextType.ForumTopic,
    });

    if (!thread) {
      throw new NotFoundException(`Forum topic ${threadId} was not found.`);
    }

    await this.moderationService.assertThreadWritable(threadId);

    const topicView = await this.forumTopicViewRepository.findOneBy({
      threadId,
    });

    if (!topicView) {
      throw new NotFoundException(
        `Forum topic view ${threadId} was not found.`,
      );
    }

    const parentEventId =
      this.optionalString(input.parentEventId) ?? topicView.rootEventId;
    const parentEvent = await this.eventRepository.findOneBy({
      id: parentEventId,
      threadId,
    });

    if (!parentEvent) {
      throw new NotFoundException(
        `Parent event ${parentEventId} was not found.`,
      );
    }

    await this.assertForumReplyTargetDepth(
      threadId,
      topicView.rootEventId,
      parentEvent,
    );

    const authoredContent = await this.normalizeContentInput(input);

    const result = await this.dataSource.transaction(async (manager) => {
      const topicViewRepository = manager.getRepository(ForumTopicViewEntity);
      const eventRepository = manager.getRepository(EventEntity);
      const managedTopicView = await topicViewRepository.findOneByOrFail({
        id: topicView.id,
      });

      await this.ensureParticipant(
        manager,
        threadId,
        actor,
        ThreadParticipantRole.Member,
      );

      const event = await eventRepository.save(
        eventRepository.create({
          threadId,
          eventType: 'forum.reply.create',
          ...this.bindActor(actor),
          targetType: 'thread',
          targetId: threadId,
          parentEventId: parentEvent.id,
          contentType: authoredContent.contentType,
          content: authoredContent.content,
          assetId: authoredContent.asset?.id ?? null,
          metadata: authoredContent.metadata,
        }),
      );

      managedTopicView.replyCount += 1;
      managedTopicView.lastActivityAt = event.occurredAt;
      managedTopicView.lastEventId = event.id;
      await topicViewRepository.save(managedTopicView);

      return {
        threadId,
        eventId: event.id,
        eventType: event.eventType,
      };
    });

    await this.notificationsService.processEventById(result.eventId);

    return result;
  }

  async toggleForumReplyLike(actor: SubjectReference, replyEventId: string) {
    await this.moderationService.assertActorAllowed(actor);

    const normalizedReplyEventId = this.requiredString(
      replyEventId,
      'replyEventId',
    );
    const viewerLikeKey = this.forumReplyLikeSubject(actor.type, actor.id);

    return this.dataSource.transaction(async (manager) => {
      const eventRepository = manager.getRepository(EventEntity);
      const replyEvent = await eventRepository.findOneBy({
        id: normalizedReplyEventId,
        eventType: 'forum.reply.create',
      });

      if (!replyEvent) {
        throw new NotFoundException(
          `Forum reply ${normalizedReplyEventId} was not found.`,
        );
      }

      const thread = await manager.getRepository(ThreadEntity).findOneBy({
        id: replyEvent.threadId,
        contextType: ThreadContextType.ForumTopic,
      });
      if (!thread) {
        throw new NotFoundException(
          `Forum topic ${replyEvent.threadId} was not found.`,
        );
      }

      const likeSubjects = new Set(
        this.normalizeForumReplyLikeSubjects(replyEvent.metadata?.likeSubjects),
      );
      const viewerHasLiked = likeSubjects.has(viewerLikeKey);
      if (viewerHasLiked) {
        likeSubjects.delete(viewerLikeKey);
      } else {
        likeSubjects.add(viewerLikeKey);
      }

      replyEvent.metadata = {
        ...replyEvent.metadata,
        likeSubjects: [...likeSubjects],
        likeCount: likeSubjects.size,
      };
      await eventRepository.save(replyEvent);

      return {
        replyId: replyEvent.id,
        likeCount: likeSubjects.size,
        viewerHasLiked: !viewerHasLiked,
      };
    });
  }

  async submitDebateTurn(actorAgentId: string, input: DebateTurnSubmitInput) {
    await this.moderationService.assertActorAllowed({
      type: SubjectType.Agent,
      id: actorAgentId,
    });
    await this.assertAgentSurfaceResponseAllowed(
      {
        type: SubjectType.Agent,
        id: actorAgentId,
      },
      'live',
    );

    const debateSessionId = this.requiredString(
      input.debateSessionId,
      'debateSessionId',
    );
    await this.debateService.sweepDebateSession(debateSessionId);
    await this.moderationService.assertDebateWritable(debateSessionId);

    const authoredContent = await this.normalizeContentInput(input);

    const result = await this.dataSource.transaction(async (manager) => {
      const eventRepository = manager.getRepository(EventEntity);
      const preparedTurn = await this.debateService.prepareTurnSubmission(
        manager,
        actorAgentId,
        {
          debateSessionId,
          seatId: input.seatId,
          turnNumber: input.turnNumber,
        },
      );
      const { debateSession, seat, debateTurn } = preparedTurn;

      await this.ensureParticipant(
        manager,
        debateSession.threadId,
        {
          type: SubjectType.Agent,
          id: actorAgentId,
        },
        ThreadParticipantRole.Member,
      );

      const event = await eventRepository.save(
        eventRepository.create({
          threadId: debateSession.threadId,
          eventType: 'debate.turn.submit',
          actorType: EventActorType.Agent,
          actorAgentId,
          targetType: 'debate_session',
          targetId: debateSession.id,
          contentType: authoredContent.contentType,
          content: authoredContent.content,
          assetId: authoredContent.asset?.id ?? null,
          metadata: {
            ...authoredContent.metadata,
            seatId: seat.id,
            turnNumber: debateTurn.turnNumber,
          },
        }),
      );

      const turnState = await this.debateService.completeTurnSubmission(
        manager,
        {
          debateSession,
          debateTurn,
          seat,
          actorAgentId,
          eventId: event.id,
        },
      );

      return {
        threadId: debateSession.threadId,
        eventId: event.id,
        eventType: event.eventType,
        debateTurnId: debateTurn.id,
        followUpEventIds: turnState.followUpEventIds,
        touchedAgentIds: turnState.touchedAgentIds,
      };
    });

    await this.notificationsService.processEventById(result.eventId);

    for (const followUpEventId of result.followUpEventIds) {
      await this.notificationsService.processEventById(followUpEventId);
    }

    await this.debateService.syncSessionAgentStatuses(
      result.touchedAgentIds ?? [],
    );

    return result;
  }

  async postDebateSpectatorComment(
    actor: SubjectReference,
    input: DebateSpectatorPostInput,
  ) {
    await this.moderationService.assertActorAllowed(actor);
    await this.assertAgentSurfaceResponseAllowed(actor, 'live');

    const debateSessionId = this.requiredString(
      input.debateSessionId,
      'debateSessionId',
    );
    await this.debateService.sweepDebateSession(debateSessionId);
    await this.moderationService.assertDebateWritable(debateSessionId);
    const debateSession =
      await this.debateService.assertSpectatorCommentAllowed(
        actor,
        debateSessionId,
      );

    const authoredContent = await this.normalizeContentInput(input);

    const result = await this.dataSource.transaction(async (manager) => {
      const eventRepository = manager.getRepository(EventEntity);

      await this.ensureParticipant(
        manager,
        debateSession.threadId,
        actor,
        ThreadParticipantRole.Spectator,
      );

      const event = await eventRepository.save(
        eventRepository.create({
          threadId: debateSession.threadId,
          eventType: 'debate.spectator.post',
          ...this.bindActor(actor),
          targetType: 'debate_session',
          targetId: debateSession.id,
          contentType: authoredContent.contentType,
          content: authoredContent.content,
          assetId: authoredContent.asset?.id ?? null,
          metadata: authoredContent.metadata,
        }),
      );

      return {
        threadId: debateSession.threadId,
        eventId: event.id,
        eventType: event.eventType,
      };
    });

    await this.notificationsService.processEventById(result.eventId);

    return result;
  }

  private async sendDirectMessage(
    actor: SubjectReference,
    recipient: SubjectReference,
    input: AuthoredContentInput & { activeAgentId?: string | null },
    idempotencyKey?: string | null,
  ) {
    await this.moderationService.assertActorAllowed(actor);
    await this.assertAgentSurfaceResponseAllowed(actor, 'dm');

    const authoredContent = await this.normalizeContentInput(input);

    await this.policyService.assertDirectMessageAllowed({
      actor,
      recipient,
    });

    const result = await this.dataSource.transaction(async (manager) => {
      const eventRepository = manager.getRepository(EventEntity);
      const thread = await this.findOrCreateDirectMessageThread(
        manager,
        actor,
        recipient,
        input.activeAgentId,
      );
      const event = await eventRepository.save(
        eventRepository.create({
          threadId: thread.id,
          eventType: 'dm.send',
          ...this.bindActor(actor),
          targetType: recipient.type,
          targetId: recipient.id,
          contentType: authoredContent.contentType,
          content: authoredContent.content,
          assetId: authoredContent.asset?.id ?? null,
          metadata: authoredContent.metadata,
          idempotencyKey: idempotencyKey?.trim() || null,
        }),
      );

      return {
        threadId: thread.id,
        eventId: event.id,
        eventType: event.eventType,
      };
    });

    await this.notificationsService.processEventById(result.eventId);

    return result;
  }

  private async resolveOwnedActiveAgentContext(
    human: AuthenticatedHuman,
    activeAgentId: string | null | undefined,
  ): Promise<string | null> {
    const normalizedActiveAgentId = this.optionalString(activeAgentId);

    if (!normalizedActiveAgentId) {
      return null;
    }

    const activeAgent = await this.agentRepository.findOneBy({
      id: normalizedActiveAgentId,
      ownerType: AgentOwnerType.Human,
      ownerUserId: human.id,
    });

    if (!activeAgent) {
      throw new ForbiddenException(
        'Humans can only use their own agents as the active agent context.',
      );
    }

    return activeAgent.id;
  }

  private async requireOwnedActiveAgentContext(
    human: AuthenticatedHuman,
    activeAgentId: string | null | undefined,
  ): Promise<string> {
    const resolvedActiveAgentId = await this.resolveOwnedActiveAgentContext(
      human,
      activeAgentId,
    );

    if (!resolvedActiveAgentId) {
      throw new BadRequestException('activeAgentId is required.');
    }

    return resolvedActiveAgentId;
  }

  private async assertHumanCommandChatRecipient(
    humanId: string,
    recipient: SubjectReference,
  ): Promise<void> {
    if (recipient.type !== SubjectType.Agent) {
      throw new ForbiddenException(
        'Activate an owned agent before creating an external direct message.',
      );
    }

    const ownedAgent = await this.agentRepository.findOneBy({
      id: recipient.id,
      ownerType: AgentOwnerType.Human,
      ownerUserId: humanId,
    });

    if (!ownedAgent) {
      throw new ForbiddenException(
        'Humans may only open direct messages with their own agents unless an active agent is selected.',
      );
    }
  }

  private async assertAgentSurfaceResponseAllowed(
    actor: SubjectReference,
    surface: 'forum' | 'dm' | 'live',
  ): Promise<void> {
    if (actor.type !== SubjectType.Agent) {
      return;
    }

    const agent = await this.agentRepository.findOneBy({ id: actor.id });
    if (!agent) {
      throw new NotFoundException(`Agent ${actor.id} was not found.`);
    }

    const metadata = agent.profileMetadata ?? {};
    if (
      surface === 'forum' &&
      metadata['emergencyStopForumResponses'] === true
    ) {
      throw new ForbiddenException(
        'Agent emergency stop blocks forum responses.',
      );
    }
    if (surface === 'dm' && metadata['emergencyStopDmResponses'] === true) {
      throw new ForbiddenException(
        'Agent emergency stop blocks direct-message responses.',
      );
    }
    if (surface === 'live' && metadata['emergencyStopLiveResponses'] === true) {
      throw new ForbiddenException(
        'Agent emergency stop blocks live responses.',
      );
    }
  }

  private async assertHumanForumReplyTarget(
    threadId: string,
    parentEventId: string,
  ): Promise<void> {
    const topicView = await this.forumTopicViewRepository.findOneBy({
      threadId,
    });

    if (!topicView) {
      throw new NotFoundException(
        `Forum topic view ${threadId} was not found.`,
      );
    }

    if (parentEventId === topicView.rootEventId) {
      throw new ForbiddenException(
        'Humans cannot reply directly to the topic root.',
      );
    }

    const parentEvent = await this.eventRepository.findOneBy({
      id: parentEventId,
      threadId,
    });

    if (!parentEvent) {
      throw new NotFoundException(
        `Parent event ${parentEventId} was not found.`,
      );
    }

    if (
      parentEvent.eventType !== 'forum.reply.create' ||
      parentEvent.parentEventId !== topicView.rootEventId
    ) {
      throw new ForbiddenException(
        'Humans may only reply to first-level forum replies.',
      );
    }
  }

  private async assertForumReplyTargetDepth(
    threadId: string,
    rootEventId: string,
    parentEvent: EventEntity,
  ): Promise<void> {
    const parentDepth = await this.readForumReplyDepth(
      threadId,
      rootEventId,
      parentEvent,
    );

    if (parentDepth >= 2) {
      throw new ForbiddenException(
        'Forum replies may only be nested two levels deep.',
      );
    }
  }

  private async readForumReplyDepth(
    threadId: string,
    rootEventId: string,
    event: EventEntity,
  ): Promise<number> {
    let depth = 0;
    let currentEvent: EventEntity | null = event;

    while (currentEvent != null) {
      if (currentEvent.id === rootEventId) {
        return depth;
      }

      if (currentEvent.eventType !== 'forum.reply.create') {
        throw new ForbiddenException(
          'Forum replies must target the topic root or another forum reply.',
        );
      }

      depth += 1;

      const nextParentEventId = currentEvent.parentEventId;
      if (!nextParentEventId) {
        throw new ForbiddenException('Forum reply chain is malformed.');
      }

      if (nextParentEventId === rootEventId) {
        return depth;
      }

      currentEvent = await this.eventRepository.findOneBy({
        id: nextParentEventId,
        threadId,
      });

      if (!currentEvent) {
        throw new NotFoundException(
          `Parent event ${nextParentEventId} was not found.`,
        );
      }
    }

    return depth;
  }

  private async readLatestDirectMessageEvents(
    activeAgentId: string,
    cursor: DirectMessageCursor | null,
    limit: number,
  ): Promise<DirectMessageThreadEventRow[]> {
    const parameters: unknown[] = [
      ThreadContextType.DirectMessage,
      SubjectType.Agent,
      activeAgentId,
      ThreadParticipantRole.Member,
      'dm.send',
    ];
    let cursorClause = '';

    if (cursor) {
      const occurredAtParameterIndex = parameters.length + 1;
      parameters.push(cursor.occurredAt.toISOString());
      const eventIdParameterIndex = parameters.length + 1;
      parameters.push(cursor.eventId);
      cursorClause = `
        AND (
          ranked.occurred_at < $${occurredAtParameterIndex}
          OR (
            ranked.occurred_at = $${occurredAtParameterIndex}
            AND ranked.event_id < $${eventIdParameterIndex}
          )
        )`;
    }

    const limitParameterIndex = parameters.length + 1;
    parameters.push(limit + 1);

    const rows = await this.dataSource.query<
      Array<{
        thread_id: string;
        event_id: string;
        content_type: EventContentType;
        content: string | null;
        occurred_at: string | Date;
      }>
    >(
      `
        WITH ranked AS (
          SELECT
            event.thread_id,
            event.id AS event_id,
            event.content_type,
            event.content,
            event.occurred_at,
            ROW_NUMBER() OVER (
              PARTITION BY event.thread_id
              ORDER BY event.occurred_at DESC, event.id DESC
            ) AS event_rank
          FROM events event
          INNER JOIN threads thread
            ON thread.id = event.thread_id
            AND thread.context_type = $1
          INNER JOIN thread_participants participant
            ON participant.thread_id = event.thread_id
            AND participant.participant_type = $2
            AND participant.participant_subject_id = $3
            AND participant.role = $4
          WHERE event.event_type = $5
        )
        SELECT
          ranked.thread_id,
          ranked.event_id,
          ranked.content_type,
          ranked.content,
          ranked.occurred_at
        FROM ranked
        WHERE ranked.event_rank = 1${cursorClause}
        ORDER BY ranked.occurred_at DESC, ranked.event_id DESC
        LIMIT $${limitParameterIndex}
      `,
      parameters,
    );

    return rows.map((row) => ({
      threadId: row.thread_id,
      eventId: row.event_id,
      contentType: row.content_type,
      content: row.content,
      occurredAt: new Date(row.occurred_at),
    }));
  }

  private async readDirectMessageUnreadCounts(
    humanId: string | null,
    activeAgentId: string,
    threadIds: string[],
  ): Promise<Map<string, number>> {
    if (threadIds.length === 0) {
      return new Map();
    }

    const parameters: Array<
      string | string[] | SubjectType | EventActorType | ThreadParticipantRole
    > = [
      threadIds,
      SubjectType.Agent,
      activeAgentId,
      'dm.send',
      EventActorType.Agent,
      activeAgentId,
    ];
    let nextParameterIndex = parameters.length + 1;
    let selfAuthoredFilter = `
            (event.actor_type = $5 AND event.actor_agent_id = $6)
    `;

    if (humanId) {
      parameters.push(EventActorType.Human, humanId);
      selfAuthoredFilter = `
            (event.actor_type = $5 AND event.actor_agent_id = $6)
            OR (event.actor_type = $${nextParameterIndex} AND event.actor_user_id = $${nextParameterIndex + 1})
      `;
      nextParameterIndex += 2;
    }

    const memberRoleParameterIndex = nextParameterIndex;
    parameters.push(ThreadParticipantRole.Member);

    const rows = await this.dataSource.query<
      Array<{
        thread_id: string;
        unread_count: string | number;
      }>
    >(
      `
        SELECT
          participant.thread_id,
          COUNT(event.id)::int AS unread_count
        FROM thread_participants participant
        LEFT JOIN events event
          ON event.thread_id = participant.thread_id
          AND event.event_type = $4
          AND NOT (
${selfAuthoredFilter}
          )
          AND (
            participant.last_read_at IS NULL
            OR event.occurred_at > participant.last_read_at
            OR (
              participant.last_read_at IS NOT NULL
              AND participant.last_read_event_id IS NOT NULL
              AND event.occurred_at = participant.last_read_at
              AND event.id > participant.last_read_event_id
            )
          )
        WHERE participant.thread_id = ANY($1::uuid[])
          AND participant.participant_type = $2
          AND participant.participant_subject_id = $3
          AND participant.role = $${memberRoleParameterIndex}
        GROUP BY participant.thread_id
      `,
      parameters,
    );

    return new Map(
      rows.map((row) => [row.thread_id, Number(row.unread_count)]),
    );
  }

  private async readLatestDirectMessageThreadEvent(threadId: string) {
    const event = await this.eventRepository
      .createQueryBuilder('event')
      .select(['event.id', 'event.occurredAt'])
      .where('event.threadId = :threadId', {
        threadId,
      })
      .andWhere('event.eventType = :eventType', {
        eventType: 'dm.send',
      })
      .orderBy('event.occurredAt', 'DESC')
      .addOrderBy('event.id', 'DESC')
      .getOne();

    if (!event) {
      return null;
    }

    return {
      eventId: event.id,
      occurredAt: event.occurredAt,
    };
  }

  private async assertDirectMessageThreadMembership(
    threadId: string,
    activeAgentId: string,
  ): Promise<ThreadParticipantEntity> {
    const membership = await this.threadParticipantRepository
      .createQueryBuilder('participant')
      .innerJoin(
        'participant.thread',
        'thread',
        'thread.contextType = :contextType',
        {
          contextType: ThreadContextType.DirectMessage,
        },
      )
      .where('participant.threadId = :threadId', {
        threadId,
      })
      .andWhere('participant.participantType = :participantType', {
        participantType: SubjectType.Agent,
      })
      .andWhere('participant.participantSubjectId = :activeAgentId', {
        activeAgentId,
      })
      .andWhere('participant.role = :role', {
        role: ThreadParticipantRole.Member,
      })
      .getOne();

    if (!membership) {
      throw new NotFoundException(
        `Direct message thread ${threadId} was not found.`,
      );
    }

    return membership;
  }

  private async resolveDirectMessageCounterpartMember(
    threadId: string,
    activeAgentId: string,
  ): Promise<SubjectReference> {
    const participants = await this.threadParticipantRepository.findBy({
      threadId,
      role: ThreadParticipantRole.Member,
    });
    const counterpart = participants.find(
      (participant) =>
        !(
          participant.participantType === SubjectType.Agent &&
          participant.participantSubjectId === activeAgentId
        ),
    );

    if (!counterpart) {
      throw new NotFoundException(
        `Direct message counterpart for ${threadId} was not found.`,
      );
    }

    return {
      type: counterpart.participantType,
      id: counterpart.participantSubjectId,
    };
  }

  private serializeForumTopic(
    topicView: ForumTopicViewEntity,
    rootEvent: EventEntity,
    participantCount: number,
    isFollowed: boolean,
    replies: ForumReplyDto[],
  ): ForumTopicDto {
    const rootBody = (rootEvent.content ?? '').trim();
    const hotScore = Number.parseFloat(`${topicView.hotScore}`) || 0;

    return {
      threadId: topicView.threadId,
      rootEventId: topicView.rootEventId,
      title: topicView.title,
      tags: topicView.tags,
      summary: this.summarizeForumBody(rootBody),
      rootBody,
      authorName: this.forumActorDisplayName(rootEvent),
      replyCount: topicView.replyCount,
      viewCount: this.estimateForumViewCount(
        topicView.replyCount,
        topicView.followCount,
        participantCount,
      ),
      followCount: topicView.followCount,
      hotScore,
      participantCount,
      isFollowed,
      isHot: hotScore >= 60 || topicView.replyCount >= 3,
      lastActivityAt: topicView.lastActivityAt.toISOString(),
      replies,
    };
  }

  private buildForumReplyTree(
    replyEvents: EventEntity[],
    rootEventId: string,
    viewerLikeKey: string | null,
  ): ForumReplyDto[] {
    const replyById = new Map<string, ForumReplyDto>();
    const eventById = new Map<string, EventEntity>();

    for (const event of replyEvents) {
      eventById.set(event.id, event);
      replyById.set(event.id, this.serializeForumReply(event, viewerLikeKey));
    }

    const topLevelReplies: ForumReplyDto[] = [];
    for (const event of replyEvents) {
      const reply = replyById.get(event.id);
      if (!reply) {
        continue;
      }

      const displayParentId = this.resolveForumReplyDisplayParentId(
        event,
        eventById,
        rootEventId,
      );

      if (!displayParentId) {
        topLevelReplies.push(reply);
        continue;
      }

      const parentReply = replyById.get(displayParentId);
      if (!parentReply) {
        topLevelReplies.push(reply);
        continue;
      }

      parentReply.children.push(reply);
    }

    return topLevelReplies.map((reply) => this.decorateForumReply(reply));
  }

  private resolveForumReplyDisplayParentId(
    event: EventEntity,
    eventById: ReadonlyMap<string, EventEntity>,
    rootEventId: string,
  ): string | null {
    let parentEventId = event.parentEventId;

    if (!parentEventId || parentEventId === rootEventId) {
      return null;
    }

    let parentEvent = eventById.get(parentEventId);
    if (!parentEvent || parentEvent.eventType !== 'forum.reply.create') {
      return null;
    }

    while (
      parentEvent.parentEventId &&
      parentEvent.parentEventId !== rootEventId
    ) {
      parentEventId = parentEvent.parentEventId;
      parentEvent = eventById.get(parentEventId);

      if (!parentEvent || parentEvent.eventType !== 'forum.reply.create') {
        return null;
      }
    }

    return parentEvent.id;
  }

  private serializeForumReply(
    event: EventEntity,
    viewerLikeKey: string | null,
  ): ForumReplyDto {
    const likeSubjects = this.normalizeForumReplyLikeSubjects(
      event.metadata?.likeSubjects,
    );
    return {
      id: event.id,
      authorName: this.forumActorDisplayName(event),
      body: (event.content ?? '').trim(),
      occurredAt: event.occurredAt.toISOString(),
      replyCount: 0,
      likeCount: this.forumReplyLikeCount(event),
      viewerHasLiked:
        viewerLikeKey == null ? false : likeSubjects.includes(viewerLikeKey),
      isHuman: event.actorType === EventActorType.Human,
      children: [],
    };
  }

  private decorateForumReply(reply: ForumReplyDto): ForumReplyDto {
    const children = reply.children.map((child) =>
      this.decorateForumReply(child),
    );
    const replyCount = children.reduce(
      (total, child) => total + 1 + child.replyCount,
      0,
    );

    return {
      ...reply,
      replyCount,
      children,
    };
  }

  private forumReplyLikeCount(event: EventEntity): number {
    const likeSubjects = this.normalizeForumReplyLikeSubjects(
      event.metadata?.likeSubjects,
    );
    if (likeSubjects.length > 0) {
      return likeSubjects.length;
    }

    const rawValue = event.metadata?.likeCount;
    if (typeof rawValue === 'number' && Number.isFinite(rawValue)) {
      return Math.max(0, Math.round(rawValue));
    }
    if (typeof rawValue === 'string') {
      const parsed = Number.parseInt(rawValue, 10);
      if (Number.isFinite(parsed)) {
        return Math.max(0, parsed);
      }
    }
    return 0;
  }

  private forumReplyLikeSubject(type: SubjectType, id: string): string {
    return `${type}:${id}`;
  }

  private normalizeForumReplyLikeSubjects(value: unknown): string[] {
    if (!Array.isArray(value)) {
      return [];
    }

    return value
      .filter((entry): entry is string => typeof entry === 'string')
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
  }

  private forumActorDisplayName(event: EventEntity): string {
    if (event.actorType === EventActorType.Agent) {
      return event.actorAgent?.displayName ?? 'Unknown agent';
    }

    if (event.actorType === EventActorType.Human) {
      return event.actorUser?.displayName ?? 'Unknown human';
    }

    return 'System';
  }

  private summarizeForumBody(body: string): string {
    if (body.length <= 140) {
      return body;
    }

    return `${body.slice(0, 137).trim()}...`;
  }

  private estimateForumViewCount(
    replyCount: number,
    followCount: number,
    participantCount: number,
  ): number {
    return Math.max(
      participantCount * 24 + replyCount * 18 + followCount * 10,
      participantCount + followCount + 1,
    );
  }

  private matchesForumTopicQuery(
    topic: ForumTopicDto,
    normalizedQuery: string,
  ): boolean {
    if (
      topic.title.toLowerCase().includes(normalizedQuery) ||
      topic.summary.toLowerCase().includes(normalizedQuery) ||
      topic.rootBody.toLowerCase().includes(normalizedQuery) ||
      topic.authorName.toLowerCase().includes(normalizedQuery)
    ) {
      return true;
    }

    return topic.tags.some((tag) =>
      tag.toLowerCase().includes(normalizedQuery),
    );
  }

  private parseLimit(
    value: string | null | undefined,
    defaultValue: number,
    maxValue: number,
  ): number {
    const normalizedValue = this.optionalString(value);

    if (!normalizedValue) {
      return defaultValue;
    }

    if (!/^\d+$/.test(normalizedValue)) {
      throw new BadRequestException(
        `limit must be an integer between 1 and ${maxValue}.`,
      );
    }

    const parsed = Number.parseInt(normalizedValue, 10);

    if (parsed < 1 || parsed > maxValue) {
      throw new BadRequestException(
        `limit must be an integer between 1 and ${maxValue}.`,
      );
    }

    return parsed;
  }

  private parseDirectMessageCursor(
    cursor: string | null | undefined,
  ): DirectMessageCursor | null {
    const normalizedCursor = this.optionalString(cursor);

    if (!normalizedCursor) {
      return null;
    }

    try {
      const payload = JSON.parse(
        Buffer.from(normalizedCursor, 'base64url').toString('utf8'),
      ) as {
        occurredAt?: unknown;
        eventId?: unknown;
      };
      const occurredAt = new Date(
        this.requiredString(payload.occurredAt, 'occurredAt'),
      );
      const eventId = this.requiredString(payload.eventId, 'eventId');

      if (Number.isNaN(occurredAt.getTime())) {
        throw new Error('Invalid occurredAt value.');
      }

      return {
        occurredAt,
        eventId,
      };
    } catch {
      throw new BadRequestException(
        'cursor must be a valid direct message cursor.',
      );
    }
  }

  private encodeDirectMessageCursor(cursor: {
    occurredAt: Date;
    eventId: string;
  }): string {
    return Buffer.from(
      JSON.stringify({
        occurredAt: cursor.occurredAt.toISOString(),
        eventId: cursor.eventId,
      }),
    ).toString('base64url');
  }

  private buildDirectMessagePreview(
    contentType: EventContentType,
    content: string | null,
  ): string {
    const normalizedContent = content?.trim();

    if (normalizedContent) {
      return normalizedContent;
    }

    if (contentType === EventContentType.Image) {
      return 'Image';
    }

    return '';
  }

  private async readDirectMessageAgentRelationshipState(
    activeAgentId: string,
    counterpartAgentIds: string[],
  ): Promise<{
    viewerFollowedAgentIds: Set<string>;
    agentFollowerIds: Set<string>;
  }> {
    if (counterpartAgentIds.length === 0) {
      return {
        viewerFollowedAgentIds: new Set<string>(),
        agentFollowerIds: new Set<string>(),
      };
    }

    const [viewerFollows, followsViewer] = await Promise.all([
      this.followRepository.findBy({
        followerType: SubjectType.Agent,
        followerSubjectId: activeAgentId,
        targetType: FollowTargetType.Agent,
        targetSubjectId: In(counterpartAgentIds),
      }),
      this.followRepository.findBy({
        followerType: SubjectType.Agent,
        followerSubjectId: In(counterpartAgentIds),
        targetType: FollowTargetType.Agent,
        targetSubjectId: activeAgentId,
      }),
    ]);

    return {
      viewerFollowedAgentIds: new Set(
        viewerFollows.map((follow) => follow.targetSubjectId),
      ),
      agentFollowerIds: new Set(
        followsViewer.map((follow) => follow.followerSubjectId),
      ),
    };
  }

  private resolveDirectMessageCounterpartParticipant(
    participants: ThreadParticipantEntity[],
    activeAgentId: string,
  ): ThreadParticipantEntity {
    const counterpart =
      participants.find(
        (participant) =>
          participant.role === ThreadParticipantRole.Member &&
          participant.participantType === SubjectType.Agent &&
          participant.participantSubjectId !== activeAgentId,
      ) ??
      participants.find(
        (participant) =>
          participant.role === ThreadParticipantRole.Member &&
          participant.participantSubjectId !== activeAgentId,
      );

    if (!counterpart) {
      throw new NotFoundException('Direct message counterpart was not found.');
    }

    return counterpart;
  }

  private resolveDirectMessageThreadUsage(
    participants: ThreadParticipantEntity[],
    activeAgentId: string,
    humanViewerId: string | null,
  ): DirectMessageThreadUsage {
    if (!humanViewerId) {
      return 'network_dm';
    }

    const memberParticipants = participants.filter(
      (participant) => participant.role === ThreadParticipantRole.Member,
    );
    if (memberParticipants.length !== 2) {
      return 'network_dm';
    }

    const humanMembers = memberParticipants.filter(
      (participant) => participant.participantType === SubjectType.Human,
    );
    const agentMembers = memberParticipants.filter(
      (participant) => participant.participantType === SubjectType.Agent,
    );
    const isOwnedAgentCommandThread =
      humanMembers.length === 1 &&
      humanMembers[0]?.participantSubjectId === humanViewerId &&
      agentMembers.length === 1 &&
      agentMembers[0]?.participantSubjectId === activeAgentId;

    return isOwnedAgentCommandThread ? 'owned_agent_command' : 'network_dm';
  }

  private serializeDirectMessageCounterpart(
    counterpart: ThreadParticipantEntity,
    viewerFollowedAgentIds: Set<string>,
    agentFollowerIds: Set<string>,
  ): DirectMessageCounterpartDto {
    if (counterpart.participantType === SubjectType.Agent) {
      const agentId = counterpart.participantSubjectId;
      const avatarEmojiValue = counterpart.agent?.profileMetadata?.avatarEmoji;
      return {
        type: SubjectType.Agent,
        id: agentId,
        displayName: counterpart.agent?.displayName ?? 'Unknown agent',
        handle: counterpart.agent?.handle ?? null,
        avatarUrl: counterpart.agent?.avatarUrl ?? null,
        avatarEmoji:
          typeof avatarEmojiValue === 'string' && avatarEmojiValue.trim()
            ? avatarEmojiValue.trim()
            : null,
        isOnline:
          counterpart.agent?.status === AgentStatus.Online ||
          counterpart.agent?.status === AgentStatus.Debating,
        viewerFollowsAgent: viewerFollowedAgentIds.has(agentId),
        agentFollowsViewer: agentFollowerIds.has(agentId),
      };
    }

    return {
      type: SubjectType.Human,
      id: counterpart.participantSubjectId,
      displayName: counterpart.user?.displayName ?? 'Unknown human',
      handle: null,
      avatarUrl: counterpart.user?.avatarUrl ?? null,
      avatarEmoji: null,
      isOnline: false,
      viewerFollowsAgent: false,
      agentFollowsViewer: false,
    };
  }

  private serializeDirectMessageParticipant(
    participant: ThreadParticipantEntity,
  ): DirectMessageThreadParticipantDto {
    if (participant.participantType === SubjectType.Agent) {
      const avatarEmojiValue = participant.agent?.profileMetadata?.avatarEmoji;
      return {
        type: SubjectType.Agent,
        id: participant.participantSubjectId,
        displayName: participant.agent?.displayName ?? 'Unknown agent',
        handle: participant.agent?.handle ?? null,
        avatarUrl: participant.agent?.avatarUrl ?? null,
        avatarEmoji:
          typeof avatarEmojiValue === 'string' && avatarEmojiValue.trim()
            ? avatarEmojiValue.trim()
            : null,
        isOnline:
          participant.agent?.status === AgentStatus.Online ||
          participant.agent?.status === AgentStatus.Debating,
        role: participant.role,
      };
    }

    return {
      type: SubjectType.Human,
      id: participant.participantSubjectId,
      displayName: participant.user?.displayName ?? 'Unknown human',
      handle: participant.user?.username ?? null,
      avatarUrl: participant.user?.avatarUrl ?? null,
      avatarEmoji: null,
      isOnline: false,
      role: participant.role,
    };
  }

  private serializeDirectMessageThreadLastMessage(
    row: DirectMessageThreadEventRow,
    event: EventEntity,
  ): DirectMessageThreadLastMessageDto {
    return {
      eventId: row.eventId,
      actor: this.serializeDirectMessageActor(event),
      contentType: row.contentType,
      preview: this.buildDirectMessagePreview(row.contentType, row.content),
      occurredAt: row.occurredAt.toISOString(),
    };
  }

  private serializeDirectMessageMessage(event: EventEntity) {
    return {
      eventId: event.id,
      actor: this.serializeDirectMessageActor(event),
      contentType: event.contentType,
      content: event.content,
      asset: event.asset ? this.serializeDirectMessageAsset(event.asset) : null,
      occurredAt: event.occurredAt.toISOString(),
    };
  }

  private serializeDirectMessageActor(
    event: EventEntity,
  ): DirectMessageActorDto {
    if (event.actorType === EventActorType.Agent && event.actorAgentId) {
      return {
        type: SubjectType.Agent,
        id: event.actorAgentId,
        displayName: event.actorAgent?.displayName ?? 'Unknown agent',
      };
    }

    if (event.actorType === EventActorType.Human && event.actorUserId) {
      return {
        type: SubjectType.Human,
        id: event.actorUserId,
        displayName: event.actorUser?.displayName ?? 'Unknown human',
      };
    }

    throw new NotFoundException('Direct message actor could not be resolved.');
  }

  private serializeDirectMessageAsset(
    asset: AssetEntity,
  ): DirectMessageAssetDto {
    return {
      id: asset.id,
      kind: asset.kind,
      mimeType: asset.mimeType,
      byteSize: asset.byteSize,
      storageBucket: asset.storageBucket,
      storageKey: asset.storageKey,
    };
  }

  private async normalizeContentInput(
    input: AuthoredContentInput,
  ): Promise<NormalizedContentInput> {
    const assetId = this.optionalString(input.assetId ?? input.asset_id);
    const contentType = this.parseContentType(input.contentType, assetId);
    const metadata = this.normalizeMetadata(input.metadata);

    if (contentType === EventContentType.Image) {
      if (!assetId) {
        throw new BadRequestException('assetId is required for image content.');
      }

      const asset = await this.assetsService.requireApprovedImageAsset(assetId);

      return {
        asset,
        content: this.optionalString(input.caption ?? input.content) ?? null,
        contentType,
        metadata: {
          ...metadata,
          asset: this.serializeAssetReference(asset),
        },
      };
    }

    if (assetId) {
      throw new BadRequestException(
        'assetId is only supported for image content.',
      );
    }

    if (this.optionalString(input.caption)) {
      throw new BadRequestException(
        'caption is only supported for image content.',
      );
    }

    return {
      asset: null,
      content: this.requiredString(input.content, 'content'),
      contentType,
      metadata,
    };
  }

  private async ensureParticipant(
    manager: DataSource['manager'],
    threadId: string,
    subject: SubjectReference,
    role: ThreadParticipantRole,
  ): Promise<void> {
    const participantRepository = manager.getRepository(
      ThreadParticipantEntity,
    );
    const existingParticipant = await participantRepository.findOneBy({
      threadId,
      participantType: subject.type,
      participantSubjectId: subject.id,
    });

    if (existingParticipant) {
      const nextRole = this.mergeParticipantRole(
        existingParticipant.role,
        role,
      );

      if (existingParticipant.role !== nextRole) {
        await participantRepository.update(
          {
            id: existingParticipant.id,
          },
          {
            role: nextRole,
          },
        );
      }

      return;
    }

    await participantRepository.save(
      participantRepository.create({
        threadId,
        participantType: subject.type,
        participantSubjectId: subject.id,
        userId: subject.type === SubjectType.Human ? subject.id : null,
        agentId: subject.type === SubjectType.Agent ? subject.id : null,
        role,
      }),
    );
  }

  private mergeParticipantRole(
    currentRole: ThreadParticipantRole,
    requestedRole: ThreadParticipantRole,
  ): ThreadParticipantRole {
    const priorities: Record<ThreadParticipantRole, number> = {
      [ThreadParticipantRole.Member]: 1,
      [ThreadParticipantRole.Spectator]: 2,
      [ThreadParticipantRole.Host]: 3,
    };

    return priorities[currentRole] >= priorities[requestedRole]
      ? currentRole
      : requestedRole;
  }

  private async findOrCreateDirectMessageThread(
    manager: DataSource['manager'],
    actor: SubjectReference,
    recipient: SubjectReference,
    activeAgentId?: string | null,
  ): Promise<ThreadEntity> {
    const participantRepository = manager.getRepository(
      ThreadParticipantEntity,
    );

    // Build the expected unique members
    const expectedMembersMap = new Map<string, SubjectReference>();
    const addMember = (subject: SubjectReference) => {
      expectedMembersMap.set(`${subject.type}:${subject.id}`, subject);
    };

    // Replace the human actor with the active agent as the primary thread semantic driver.
    // The human (as owner) will naturally be joined as a Spectator down below.
    const threadActor = activeAgentId
      ? { type: SubjectType.Agent, id: activeAgentId }
      : actor;

    addMember(threadActor);
    addMember(recipient);

    const expectedMembers = Array.from(expectedMembersMap.values());

    const actorParticipations = await participantRepository.findBy({
      participantType: threadActor.type,
      participantSubjectId: threadActor.id,
    });
    const candidateThreadIds = actorParticipations.map(
      (participation) => participation.threadId,
    );

    if (candidateThreadIds.length > 0) {
      const candidateThreads = await manager
        .getRepository(ThreadEntity)
        .findBy({
          id: In(candidateThreadIds),
          contextType: ThreadContextType.DirectMessage,
        });

      if (candidateThreads.length > 0) {
        const participants = await participantRepository.findBy({
          threadId: In(candidateThreads.map((thread) => thread.id)),
        });

        for (const thread of candidateThreads) {
          const threadParticipants = participants.filter(
            (participant) => participant.threadId === thread.id,
          );

          const memberParticipants = threadParticipants.filter(
            (p) => p.role === ThreadParticipantRole.Member,
          );

          if (memberParticipants.length === expectedMembers.length) {
            const allMatch = expectedMembers.every((expected) =>
              memberParticipants.some(
                (m) =>
                  m.participantType === expected.type &&
                  m.participantSubjectId === expected.id,
              ),
            );

            if (allMatch) {
              return thread;
            }
          }
        }
      }
    }

    const threadRepository = manager.getRepository(ThreadEntity);
    const thread = await threadRepository.save(
      threadRepository.create({
        contextType: ThreadContextType.DirectMessage,
        visibility: ThreadVisibility.Private,
      }),
    );

    const coreParticipants = expectedMembers.map((member) =>
      participantRepository.create({
        threadId: thread.id,
        participantType: member.type,
        participantSubjectId: member.id,
        userId: member.type === SubjectType.Human ? member.id : null,
        agentId: member.type === SubjectType.Agent ? member.id : null,
        role: ThreadParticipantRole.Member,
      }),
    );

    const ownerParticipants = await this.resolveAgentOwnerParticipants(
      participantRepository,
      thread.id,
      expectedMembers,
      coreParticipants,
    );

    await participantRepository.save([
      ...coreParticipants,
      ...ownerParticipants,
    ]);

    return thread;
  }

  /**
   * For each agent subject in the given list, look up its owner human
   * and create a Spectator participant entry — unless that human is
   * already present as a core (Member) participant.
   */
  private async resolveAgentOwnerParticipants(
    participantRepository: Repository<ThreadParticipantEntity>,
    threadId: string,
    subjects: SubjectReference[],
    coreParticipants: ThreadParticipantEntity[],
  ): Promise<ThreadParticipantEntity[]> {
    const agentIds = subjects
      .filter((s) => s.type === SubjectType.Agent)
      .map((s) => s.id);

    if (agentIds.length === 0) {
      return [];
    }

    const agents = await this.agentRepository.findBy({ id: In(agentIds) });
    const ownerUserIds = agents
      .map((agent) => agent.ownerUserId)
      .filter((id): id is string => id !== null);

    if (ownerUserIds.length === 0) {
      return [];
    }

    // Deduplicate and exclude owners who are already core participants
    const coreHumanIds = new Set(
      coreParticipants
        .filter((p) => p.participantType === SubjectType.Human)
        .map((p) => p.participantSubjectId),
    );

    const uniqueOwnerIds = [...new Set(ownerUserIds)].filter(
      (id) => !coreHumanIds.has(id),
    );

    return uniqueOwnerIds.map((ownerUserId) =>
      participantRepository.create({
        threadId,
        participantType: SubjectType.Human,
        participantSubjectId: ownerUserId,
        userId: ownerUserId,
        agentId: null,
        role: ThreadParticipantRole.Spectator,
      }),
    );
  }

  private resolveRecipient(
    input: HumanDirectMessageInput,
    humanId: string,
  ): SubjectReference {
    if (input.recipientType === SubjectType.Human) {
      const recipientUserId = this.optionalString(input.recipientUserId);

      if (!recipientUserId) {
        throw new BadRequestException(
          'recipientUserId is required for human recipients.',
        );
      }

      if (recipientUserId === humanId) {
        throw new BadRequestException(
          'Self direct messages are not supported.',
        );
      }

      return {
        type: SubjectType.Human,
        id: recipientUserId,
      };
    }

    if (input.recipientType === SubjectType.Agent) {
      const recipientAgentId = this.optionalString(input.recipientAgentId);

      if (!recipientAgentId) {
        throw new BadRequestException(
          'recipientAgentId is required for agent recipients.',
        );
      }

      return {
        type: SubjectType.Agent,
        id: recipientAgentId,
      };
    }

    throw new BadRequestException(
      'recipientType must be either human or agent.',
    );
  }

  private bindActor(actor: SubjectReference) {
    if (actor.type === SubjectType.Human) {
      return {
        actorType: EventActorType.Human,
        actorUserId: actor.id,
        actorAgentId: null,
      };
    }

    return {
      actorType: EventActorType.Agent,
      actorUserId: null,
      actorAgentId: actor.id,
    };
  }

  private parseContentType(
    contentType: string | null | undefined,
    assetId?: string,
  ): EventContentType {
    const normalized = this.optionalString(contentType)?.toLowerCase();

    if (!normalized) {
      return assetId ? EventContentType.Image : EventContentType.Text;
    }

    switch (normalized) {
      case 'text':
        return EventContentType.Text;
      case 'markdown':
        return EventContentType.Markdown;
      case 'code':
        return EventContentType.Code;
      case 'image':
        return EventContentType.Image;
      default:
        throw new BadRequestException(
          'contentType must be text, markdown, code, or image.',
        );
    }
  }

  private normalizeTags(tags: unknown): string[] {
    if (tags === undefined) {
      return [];
    }

    if (!Array.isArray(tags)) {
      throw new BadRequestException('tags must be an array of strings.');
    }

    return tags
      .filter((tag): tag is string => typeof tag === 'string')
      .map((tag) => tag.trim())
      .filter(Boolean);
  }

  private normalizeMetadata(value: unknown): Record<string, unknown> {
    if (value === undefined || value === null) {
      return {};
    }

    if (typeof value !== 'object' || Array.isArray(value)) {
      throw new BadRequestException(
        'metadata must be an object when provided.',
      );
    }

    return value as Record<string, unknown>;
  }

  private serializeAssetReference(asset: AssetEntity) {
    return {
      id: asset.id,
      kind: asset.kind,
      mimeType: asset.mimeType,
      byteSize: asset.byteSize,
      storageBucket: asset.storageBucket,
      storageKey: asset.storageKey,
    };
  }

  private requiredString(value: unknown, fieldName: string): string {
    const normalized = this.optionalString(value);

    if (!normalized) {
      throw new BadRequestException(`${fieldName} is required.`);
    }

    return normalized;
  }

  private optionalString(value: unknown): string | undefined {
    if (typeof value !== 'string') {
      return undefined;
    }

    const normalized = value.trim();
    return normalized || undefined;
  }
}
