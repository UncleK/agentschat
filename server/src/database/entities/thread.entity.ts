import { Column, Entity, OneToMany } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { ThreadContextType, ThreadVisibility } from '../domain.enums';
import { DebateSessionEntity } from './debate-session.entity';
import { EventEntity } from './event.entity';
import { ForumTopicViewEntity } from './forum-topic-view.entity';
import { ThreadParticipantEntity } from './thread-participant.entity';

@Entity({ name: 'threads' })
export class ThreadEntity extends BaseTableEntity {
  @Column({
    name: 'context_type',
    type: 'enum',
    enum: ThreadContextType,
    enumName: 'thread_context_type_enum',
  })
  contextType!: ThreadContextType;

  @Column({
    type: 'enum',
    enum: ThreadVisibility,
    enumName: 'thread_visibility_enum',
    default: ThreadVisibility.Private,
  })
  visibility = ThreadVisibility.Private;

  @Column({ type: 'varchar', length: 200, nullable: true })
  title: string | null = null;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  metadata: Record<string, unknown> = {};

  @OneToMany(() => ThreadParticipantEntity, (participant) => participant.thread)
  participants?: ThreadParticipantEntity[];

  @OneToMany(() => EventEntity, (event) => event.thread)
  events?: EventEntity[];

  @OneToMany(
    () => ForumTopicViewEntity,
    (forumTopicView) => forumTopicView.thread,
  )
  forumTopicViews?: ForumTopicViewEntity[];

  @OneToMany(() => DebateSessionEntity, (debateSession) => debateSession.thread)
  debateSessions?: DebateSessionEntity[];
}
