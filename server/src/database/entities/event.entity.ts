import { Check, Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { EventActorType, EventContentType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { AssetEntity } from './asset.entity';
import { ThreadEntity } from './thread.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'events' })
@Index('IDX_events_thread_created_at', ['threadId', 'createdAt'])
@Index('IDX_events_thread_occurred_at_id', ['threadId', 'occurredAt', 'id'])
@Index('IDX_events_idempotency_key_unique', ['idempotencyKey'], {
  unique: true,
})
@Check(
  'CHK_events_actor_binding',
  `(("actor_type" = 'human' AND "actor_user_id" IS NOT NULL AND "actor_agent_id" IS NULL) OR ("actor_type" = 'agent' AND "actor_agent_id" IS NOT NULL AND "actor_user_id" IS NULL) OR ("actor_type" = 'system' AND "actor_user_id" IS NULL AND "actor_agent_id" IS NULL))`,
)
export class EventEntity extends BaseTableEntity {
  @Column({ name: 'thread_id', type: 'uuid' })
  threadId!: string;

  @ManyToOne(() => ThreadEntity, (thread) => thread.events, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'thread_id' })
  thread!: ThreadEntity;

  @Column({ name: 'event_type', type: 'varchar', length: 120 })
  eventType!: string;

  @Column({
    name: 'actor_type',
    type: 'enum',
    enum: EventActorType,
    enumName: 'event_actor_type_enum',
  })
  actorType!: EventActorType;

  @Column({ name: 'actor_user_id', type: 'uuid', nullable: true })
  actorUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'actor_user_id' })
  actorUser: UserEntity | null = null;

  @Column({ name: 'actor_agent_id', type: 'uuid', nullable: true })
  actorAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, (agent) => agent.authoredEvents, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'actor_agent_id' })
  actorAgent: AgentEntity | null = null;

  @Column({ name: 'target_type', type: 'varchar', length: 64, nullable: true })
  targetType: string | null = null;

  @Column({ name: 'target_id', type: 'uuid', nullable: true })
  targetId: string | null = null;

  @Column({ name: 'asset_id', type: 'uuid', nullable: true })
  assetId: string | null = null;

  @ManyToOne(() => AssetEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'asset_id' })
  asset: AssetEntity | null = null;

  @Column({
    name: 'content_type',
    type: 'enum',
    enum: EventContentType,
    enumName: 'event_content_type_enum',
    default: EventContentType.None,
  })
  contentType = EventContentType.None;

  @Column({ type: 'text', nullable: true })
  content: string | null = null;

  @Column({ name: 'metadata', type: 'jsonb', default: () => "'{}'::jsonb" })
  metadata: Record<string, unknown> = {};

  @Column({ name: 'parent_event_id', type: 'uuid', nullable: true })
  parentEventId: string | null = null;

  @Column({
    name: 'idempotency_key',
    type: 'varchar',
    length: 255,
    nullable: true,
  })
  idempotencyKey: string | null = null;

  @Column({
    name: 'occurred_at',
    type: 'timestamptz',
    default: () => 'CURRENT_TIMESTAMP',
  })
  occurredAt!: Date;
}
