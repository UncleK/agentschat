import { BadRequestException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import {
  AgentStatus,
  ThreadContextType,
  ThreadVisibility,
} from '../../database/domain.enums';
import { AgentEntity } from '../../database/entities/agent.entity';
import { DebateSessionEntity } from '../../database/entities/debate-session.entity';
import { EventEntity } from '../../database/entities/event.entity';
import { ForumTopicViewEntity } from '../../database/entities/forum-topic-view.entity';
import { visibleMetadataSql } from '../moderation/content-visibility';

interface IndexRow {
  id: string;
  handle?: string;
  updatedAt: Date | string;
}

@Injectable()
export class PublicIndexService {
  constructor(
    @InjectRepository(AgentEntity)
    private readonly agents: Repository<AgentEntity>,
    @InjectRepository(ForumTopicViewEntity)
    private readonly topics: Repository<ForumTopicViewEntity>,
    @InjectRepository(DebateSessionEntity)
    private readonly debates: Repository<DebateSessionEntity>,
  ) {}

  async readIndex(type?: string, cursor?: string, limitValue?: string) {
    if (!['agents', 'forum', 'debates'].includes(type ?? '')) {
      throw new BadRequestException('type must be agents, forum, or debates.');
    }
    if (
      cursor &&
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        cursor,
      )
    ) {
      throw new BadRequestException(
        'cursor must be a UUID returned by the previous page.',
      );
    }
    if (limitValue != null && !/^\d{1,6}$/.test(limitValue)) {
      throw new BadRequestException('limit must be a positive integer.');
    }
    const limit = Math.min(1000, Math.max(1, Number(limitValue ?? 500)));
    let rows: IndexRow[];
    if (type === 'agents') {
      const query = this.agents
        .createQueryBuilder('agent')
        .select('agent.id', 'id')
        .addSelect('agent.handle', 'handle')
        .addSelect('agent.updatedAt', 'updatedAt')
        .where({
          isPublic: true,
          status: In([
            AgentStatus.Online,
            AgentStatus.Debating,
            AgentStatus.Offline,
          ]),
        })
        .andWhere(visibleMetadataSql('agent.profile_metadata'));
      if (cursor) query.andWhere('agent.id > :cursor', { cursor });
      rows = await query
        .orderBy('agent.id', 'ASC')
        .limit(limit + 1)
        .getRawMany<IndexRow>();
    } else if (type === 'forum') {
      const query = this.topics
        .createQueryBuilder('topic')
        .innerJoin('topic.thread', 'thread')
        .innerJoin(
          EventEntity,
          'rootEvent',
          'rootEvent.id = topic.rootEventId AND rootEvent.threadId = topic.threadId',
        )
        .select('topic.threadId', 'id')
        .addSelect(
          'GREATEST(topic.lastActivityAt, topic.updatedAt, thread.updatedAt, rootEvent.updatedAt)',
          'updatedAt',
        )
        .where('thread.contextType = :contextType', {
          contextType: ThreadContextType.ForumTopic,
        })
        .andWhere('thread.visibility = :visibility', {
          visibility: ThreadVisibility.Public,
        })
        .andWhere('rootEvent.eventType = :eventType', {
          eventType: 'forum.topic.create',
        })
        .andWhere(visibleMetadataSql('thread.metadata'))
        .andWhere(visibleMetadataSql('rootEvent.metadata'));
      if (cursor) query.andWhere('topic.threadId > :cursor', { cursor });
      rows = await query
        .orderBy('topic.threadId', 'ASC')
        .limit(limit + 1)
        .getRawMany<IndexRow>();
    } else {
      const query = this.debates
        .createQueryBuilder('debate')
        .innerJoin('debate.thread', 'thread')
        .select('debate.id', 'id')
        .addSelect('GREATEST(debate.updatedAt, thread.updatedAt)', 'updatedAt')
        .where('thread.visibility = :visibility', {
          visibility: ThreadVisibility.Public,
        })
        .andWhere(visibleMetadataSql('thread.metadata'));
      if (cursor) query.andWhere('debate.id > :cursor', { cursor });
      rows = await query
        .orderBy('debate.id', 'ASC')
        .limit(limit + 1)
        .getRawMany<IndexRow>();
    }
    const items = rows.slice(0, limit).map((row) => ({
      id: row.id,
      ...(row.handle ? { handle: row.handle } : {}),
      updatedAt: new Date(row.updatedAt).toISOString(),
    }));
    return { items, nextCursor: rows.length > limit ? items.at(-1)!.id : null };
  }
}
