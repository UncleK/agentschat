import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, In, Repository } from 'typeorm';
import {
  EventActorType,
  EventContentType,
  SubjectType,
  AgentOwnerType,
  ThreadContextType,
  ThreadParticipantRole,
  ThreadVisibility,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { AssetEntity } from '../../database/entities/asset.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { ThreadParticipantEntity } from '../../database/entities/thread-participant.entity';
import { ThreadEntity } from '../../database/entities/thread.entity';
import { AuthenticatedHuman } from '../auth/auth.types';
import { AssetsService } from '../assets/assets.service';
import { DebateService } from '../debate/debate.service';
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

interface ForumTopicCreateInput extends AuthoredContentInput {
  title?: string | null;
  tags?: unknown;
}

interface ForumReplyCreateInput extends AuthoredContentInput {
  threadId: string;
  parentEventId?: string | null;
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
    if (input.actorType?.trim().toLowerCase() === SubjectType.Agent || input.actorAgentId) {
      throw new ForbiddenException(
        'Humans can never impersonate agent-authored content.',
      );
    }

    if (input.activeAgentId) {
      const isOwner = await this.agentRepository.exist({
        where: {
          id: input.activeAgentId,
          ownerType: AgentOwnerType.Human,
          ownerUserId: human.id,
        },
      });

      if (!isOwner) {
        throw new ForbiddenException(
          'Humans can only use their own agents as the active agent context.',
        );
      }
    }

    return this.sendDirectMessage(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      this.resolveRecipient(input, human.id),
      input,
    );
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

  async createForumTopic(
    actor: SubjectReference,
    input: ForumTopicCreateInput,
  ) {
    await this.moderationService.assertActorAllowed(actor);

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

      await this.ensureParticipant(manager, thread.id, actor, ThreadParticipantRole.Host);

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

    const threadId = this.requiredString(input.threadId, 'threadId');
    const thread = await this.threadRepository.findOneBy({
      id: threadId,
      contextType: ThreadContextType.ForumTopic,
    });

    if (!thread) {
      throw new NotFoundException(`Forum topic ${threadId} was not found.`);
    }

    await this.moderationService.assertThreadWritable(threadId);

    const topicView = await this.forumTopicViewRepository.findOneBy({ threadId });

    if (!topicView) {
      throw new NotFoundException(`Forum topic view ${threadId} was not found.`);
    }

    const parentEventId =
      this.optionalString(input.parentEventId) ?? topicView.rootEventId;
    const parentEvent = await this.eventRepository.findOneBy({
      id: parentEventId,
      threadId,
    });

    if (!parentEvent) {
      throw new NotFoundException(`Parent event ${parentEventId} was not found.`);
    }

    const authoredContent = await this.normalizeContentInput(input);

    const result = await this.dataSource.transaction(async (manager) => {
      const topicViewRepository = manager.getRepository(ForumTopicViewEntity);
      const eventRepository = manager.getRepository(EventEntity);
      const managedTopicView = await topicViewRepository.findOneByOrFail({
        id: topicView.id,
      });

      await this.ensureParticipant(manager, threadId, actor, ThreadParticipantRole.Member);

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

  async submitDebateTurn(actorAgentId: string, input: DebateTurnSubmitInput) {
    await this.moderationService.assertActorAllowed({
      type: SubjectType.Agent,
      id: actorAgentId,
    });

    const debateSessionId = this.requiredString(input.debateSessionId, 'debateSessionId');
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

      const turnState = await this.debateService.completeTurnSubmission(manager, {
        debateSession,
        debateTurn,
        seat,
        actorAgentId,
        eventId: event.id,
      });

      return {
        threadId: debateSession.threadId,
        eventId: event.id,
        eventType: event.eventType,
        debateTurnId: debateTurn.id,
        followUpEventIds: turnState.followUpEventIds,
      };
    });

    await this.notificationsService.processEventById(result.eventId);

    for (const followUpEventId of result.followUpEventIds) {
      await this.notificationsService.processEventById(followUpEventId);
    }

    return result;
  }

  async postDebateSpectatorComment(
    actor: SubjectReference,
    input: DebateSpectatorPostInput,
  ) {
    await this.moderationService.assertActorAllowed(actor);

    const debateSessionId = this.requiredString(input.debateSessionId, 'debateSessionId');
    await this.debateService.sweepDebateSession(debateSessionId);
    await this.moderationService.assertDebateWritable(debateSessionId);
    const debateSession = await this.debateService.assertSpectatorCommentAllowed(
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

    const authoredContent = await this.normalizeContentInput(input);

    await this.policyService.assertDirectMessageAllowed({
      actor,
      recipient,
    });

    const result = await this.dataSource.transaction(async (manager) => {
      const eventRepository = manager.getRepository(EventEntity);
      const thread = await this.findOrCreateDirectMessageThread(manager, actor, recipient, input.activeAgentId);
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
      throw new BadRequestException('assetId is only supported for image content.');
    }

    if (this.optionalString(input.caption)) {
      throw new BadRequestException('caption is only supported for image content.');
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
    const participantRepository = manager.getRepository(ThreadParticipantEntity);
    const existingParticipant = await participantRepository.findOneBy({
      threadId,
      participantType: subject.type,
      participantSubjectId: subject.id,
    });

    if (existingParticipant) {
      const nextRole = this.mergeParticipantRole(existingParticipant.role, role);

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
    const participantRepository = manager.getRepository(ThreadParticipantEntity);

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
    const candidateThreadIds = actorParticipations.map((participation) => participation.threadId);

    if (candidateThreadIds.length > 0) {
      const candidateThreads = await manager.getRepository(ThreadEntity).findBy({
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

    await participantRepository.save([...coreParticipants, ...ownerParticipants]);

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

  private resolveRecipient(input: HumanDirectMessageInput, humanId: string): SubjectReference {
    if (input.recipientType === SubjectType.Human) {
      const recipientUserId = this.optionalString(input.recipientUserId);

      if (!recipientUserId) {
        throw new BadRequestException('recipientUserId is required for human recipients.');
      }

      if (recipientUserId === humanId) {
        throw new BadRequestException('Self direct messages are not supported.');
      }

      return {
        type: SubjectType.Human,
        id: recipientUserId,
      };
    }

    if (input.recipientType === SubjectType.Agent) {
      const recipientAgentId = this.optionalString(input.recipientAgentId);

      if (!recipientAgentId) {
        throw new BadRequestException('recipientAgentId is required for agent recipients.');
      }

      return {
        type: SubjectType.Agent,
        id: recipientAgentId,
      };
    }

    throw new BadRequestException('recipientType must be either human or agent.');
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
      case EventContentType.Text:
        return EventContentType.Text;
      case EventContentType.Markdown:
        return EventContentType.Markdown;
      case EventContentType.Code:
        return EventContentType.Code;
      case EventContentType.Image:
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
      throw new BadRequestException('metadata must be an object when provided.');
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
