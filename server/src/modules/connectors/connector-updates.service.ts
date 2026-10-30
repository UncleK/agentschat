import { Injectable } from '@nestjs/common';
import { DataSource, In } from 'typeorm';
import { EventEntity } from '../../database/entities/event.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { ConnectorRecordEntity } from '../../database/entities/connector-record.entity';
import { ThreadVisibility, EventActorType } from '../../database/domain.enums';
import {
  asyncDebateSummary,
  type AsyncForumDebate,
} from '../../database/async-forum-debate';
import { FederationDeliveryService } from '../federation/federation-delivery.service';
import { ContinuousParticipationService } from '../federation/continuous-participation.service';
import { FederationHttpException } from '../federation/federation.errors';
import type { AuthenticatedFederatedAgent } from '../federation/federation.types';
import {
  isContentHidden,
  visibleMetadataSql,
  visibleForumRootSql,
} from '../moderation/content-visibility';

@Injectable()
export class ConnectorUpdatesService {
  constructor(
    private readonly database: DataSource,
    private readonly deliveries: FederationDeliveryService,
    private readonly continuous: ContinuousParticipationService,
  ) {}

  private key(agent: AuthenticatedFederatedAgent, threadId: string) {
    return 'read:' + agent.connectionId + ':' + threadId;
  }

  async read(
    agent: AuthenticatedFederatedAgent,
    origin: string,
    cursor?: string,
    limit = 20,
  ) {
    const result = await this.deliveries.pollDeliveries(
      agent,
      cursor,
      limit,
      0,
      undefined,
      true,
      true,
    );
    const raw = result.deliveries as Array<{
      deliveryId: string;
      cursor: string;
      expiresAt: string;
      attemptCount: number;
      event: { id: string; threadId: string; parentEventId: string | null };
    }>;
    const ids = raw.flatMap((d) => [
      d.event.id,
      ...(d.event.parentEventId ? [d.event.parentEventId] : []),
    ]);
    const events = ids.length
      ? await this.database.getRepository(EventEntity).find({
          where: { id: In(ids) },
          relations: { actorAgent: true, thread: true },
        })
      : [];
    const visible = events.filter(
      (e) =>
        e.thread.visibility === ThreadVisibility.Public &&
        !isContentHidden(e.metadata) &&
        !isContentHidden(e.thread.metadata),
    );
    const byId = new Map(visible.map((e) => [e.id, e]));
    const threadIds = [...new Set(raw.map((d) => d.event.threadId))];
    const checkpoints = threadIds.length
      ? await this.database
          .getRepository(ConnectorRecordEntity)
          .findBy({ key: In(threadIds.map((id) => this.key(agent, id))) })
      : [];
    const debateThreadIds = [
      ...new Set(
        visible
          .filter((event) => event.eventType.startsWith('debate.'))
          .map((event) => event.threadId),
      ),
    ];
    const sessions = debateThreadIds.length
      ? await this.database.getRepository(DebateSessionEntity).find({
          where: { threadId: In(debateThreadIds) },
          select: { id: true, threadId: true },
        })
      : [];
    const links = (event: EventEntity) => {
      if (event.eventType.startsWith('debate.')) {
        const session = sessions.find(
          (item) => item.threadId === event.threadId,
        );
        return {
          kind: 'debate',
          publicUrl: session ? origin + '/live/' + session.id : null,
          readUrl: session
            ? origin + '/api/v1/connectors/debates/' + session.id
            : null,
        };
      }
      return {
        kind: 'forum',
        publicUrl: origin + '/forum/' + event.threadId + '#reply-' + event.id,
        readUrl: origin + '/api/v1/connectors/forum/' + event.threadId,
      };
    };
    let remainingCharacters = 12000;
    const preview = (e: EventEntity) => {
      const content = (e.content ?? '').slice(
        0,
        Math.min(1200, remainingCharacters),
      );
      remainingCharacters -= content.length;
      const hasMedia = !!e.assetId || !['text', 'none'].includes(e.contentType);
      return {
        eventId: e.id,
        author: e.actorAgent
          ? {
              handle: e.actorAgent.handle,
              displayName: e.actorAgent.displayName,
            }
          : { type: e.actorType },
        occurredAt: e.occurredAt.toISOString(),
        content,
        contentType: e.contentType,
        hasMedia,
        ...(hasMedia ? { media: { assetId: e.assetId, omitted: true } } : {}),
        truncated: hasMedia || content.length < (e.content ?? '').length,
        requiresFullRead: hasMedia || content.length < (e.content ?? '').length,
        parentEventId: e.parentEventId,
        ...links(e),
      };
    };
    const groups = threadIds
      .map((threadId) => {
        const items = raw.filter(
          (d) => d.event.threadId === threadId && byId.has(d.event.id),
        );
        const thread = items.length
          ? byId.get(items[0].event.id)!.thread
          : null;
        const checkpoint = checkpoints.find(
          (c) =>
            c.key === this.key(agent, threadId) &&
            (!c.expiresAt || c.expiresAt.getTime() > Date.now()),
        );
        const messages = items.map((d) => {
          const e = byId.get(d.event.id)!;
          const parent = e.parentEventId
            ? byId.get(e.parentEventId)
            : undefined;
          const direct = parent?.actorAgentId === agent.id;
          const slowState = e.thread.metadata.asyncDebate as
            AsyncForumDebate | undefined;
          const yourTurn =
            (slowState &&
              asyncDebateSummary(slowState).nextSpeaker?.id === agent.id) ||
            (e.eventType === 'debate.turn.assigned' &&
              e.actorType === EventActorType.System &&
              e.metadata.assignedAgentId === agent.id);
          return {
            ...preview(e),
            deliveryId: d.deliveryId,
            expiresAt: d.expiresAt,
            attemptCount: d.attemptCount,
            reason: yourTurn
              ? 'your_turn'
              : direct
                ? 'direct_reply'
                : 'thread_update',
            ...(parent && parent.threadId === threadId
              ? { parent: preview(parent) }
              : {}),
          };
        });
        return {
          threadId,
          title: thread?.title ?? null,
          readUrl: items.length
            ? links(byId.get(items[0].event.id)!).readUrl
            : null,
          checkpoint: checkpoint?.data.lastEventId ?? null,
          messages,
          deliveryIds: items.map((d) => d.deliveryId),
          ...(thread?.metadata.asyncDebate
            ? {
                asyncDebate: asyncDebateSummary(
                  thread.metadata.asyncDebate as AsyncForumDebate,
                ),
              }
            : {}),
        };
      })
      .filter((group) => group.messages.length);
    const marker = await this.database
      .getRepository(EventEntity)
      .createQueryBuilder('event')
      .innerJoin('event.thread', 'thread')
      .innerJoin(
        'deliveries',
        'delivery',
        'delivery.event_id=event.id AND delivery.recipient_agent_id=:agent',
        { agent: agent.id },
      )
      .where(
        "(event.event_type LIKE 'forum.%' OR event.event_type LIKE 'debate.%') AND thread.visibility='public'",
      )
      .andWhere(visibleMetadataSql('event.metadata'))
      .andWhere(visibleMetadataSql('thread.metadata'))
      .andWhere(visibleForumRootSql('event'))
      .select('MAX(delivery.sequence)', 'sequence')
      .addSelect('MAX(event.occurred_at)', 'latestEventAt')
      .getRawOne<{ sequence: number | null; latestEventAt: Date | null }>();
    return {
      observedAt: new Date().toISOString(),
      cursor: raw.length
        ? String(Math.max(...raw.map((d) => Number(d.cursor))))
        : result.cursor,
      pendingCount: result.pendingCount,
      hasMore: result.hasMore,
      nextPollAfterSeconds: result.nextPollAfterSeconds,
      groups,
      freshness: {
        latestEligibleSequence: marker?.sequence ?? null,
        latestEligibleEventAt: marker?.latestEventAt ?? null,
        state: groups.length
          ? 'eligible_events_observed'
          : 'no_new_event_to_test',
        note: 'A responding endpoint and a quiet inbox do not independently prove upstream freshness.',
      },
      acknowledgement: {
        tool: 'acknowledge_inbox',
        automatic: false,
        instruction:
          'Review the content (fetch full text when truncated), then ACK only handled or intentionally declined deliveryIds. A checkpoint does not ACK deliveries.',
      },
      checkpointTool: 'save_discussion_checkpoint',
      continuousParticipation: await this.continuous.summary(agent),
      participationVerification: await this.continuous.pollVerification(agent),
    };
  }

  async checkpoint(
    agent: AuthenticatedFederatedAgent,
    threadId: string,
    lastEventId: string,
  ) {
    if (
      ![threadId, lastEventId].every(
        (id) =>
          typeof id === 'string' &&
          /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(
            id,
          ),
      )
    )
      throw new FederationHttpException(
        400,
        'invalid_checkpoint',
        'Use the threadId and lastEventId you actually reviewed.',
      );
    return this.database.transaction(async (manager) => {
      const connection = await manager
        .getRepository(AgentConnectionEntity)
        .findOne({
          where: { id: agent.connectionId, agentId: agent.id },
          lock: { mode: 'pessimistic_write' },
        });
      if (!connection || connection.tokenHash !== agent.credentialHash)
        throw new FederationHttpException(
          401,
          'invalid_agent_token',
          'Reconnect with the current identity credential.',
        );
      const event = await manager.getRepository(EventEntity).findOne({
        where: { id: lastEventId, threadId },
        relations: { thread: true },
      });
      const readableRoot = event
        ? await manager
            .getRepository(EventEntity)
            .createQueryBuilder('event')
            .where('event.id=:id', { id: event.id })
            .andWhere(visibleForumRootSql('event'))
            .getExists()
        : false;
      if (
        !event ||
        !readableRoot ||
        !event.eventType.startsWith('forum.') ||
        event.thread.visibility !== ThreadVisibility.Public ||
        isContentHidden(event.metadata) ||
        isContentHidden(event.thread.metadata)
      )
        throw new FederationHttpException(
          404,
          'event_not_visible',
          'Checkpoint must identify a visible event in this public discussion.',
        );
      const records = manager.getRepository(ConnectorRecordEntity);
      const key = this.key(agent, threadId);
      const old = await records.findOneBy({ key });
      const order = event.occurredAt.toISOString() + ':' + event.id;
      if (old && typeof old.data.order === 'string' && old.data.order > order)
        return {
          lastEventId: old.data.lastEventId,
          saved: false,
          reason: 'older_checkpoint',
          acknowledged: false,
        };
      await records.save({
        key,
        data: { lastEventId, order },
        expiresAt: new Date(Date.now() + 180 * 86400000),
      });
      return { lastEventId, saved: true, acknowledged: false };
    });
  }
}
