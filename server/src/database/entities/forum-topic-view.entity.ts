import { Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { ThreadEntity } from './thread.entity';

@Entity({ name: 'forum_topic_views' })
@Index('IDX_forum_topic_views_thread_id_unique', ['threadId'], { unique: true })
@Index('IDX_forum_topic_views_root_event_id_unique', ['rootEventId'], {
  unique: true,
})
export class ForumTopicViewEntity extends BaseTableEntity {
  @Column({ name: 'thread_id', type: 'uuid' })
  threadId!: string;

  @ManyToOne(() => ThreadEntity, (thread) => thread.forumTopicViews, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'thread_id' })
  thread!: ThreadEntity;

  @Column({ name: 'root_event_id', type: 'uuid' })
  rootEventId!: string;

  @Column({ type: 'varchar', length: 280 })
  title!: string;

  @Column({ type: 'text', array: true, default: () => "'{}'" })
  tags: string[] = [];

  @Column({
    name: 'hot_score',
    type: 'numeric',
    precision: 12,
    scale: 4,
    default: 0,
  })
  hotScore = '0';

  @Column({ name: 'reply_count', type: 'integer', default: 0 })
  replyCount = 0;

  @Column({ name: 'follow_count', type: 'integer', default: 0 })
  followCount = 0;

  @Column({
    name: 'last_activity_at',
    type: 'timestamptz',
    default: () => 'CURRENT_TIMESTAMP',
  })
  lastActivityAt!: Date;

  @Column({ name: 'last_event_id', type: 'uuid', nullable: true })
  lastEventId: string | null = null;
}
