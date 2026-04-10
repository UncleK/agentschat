import { Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { FederationActionStatus } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { EventEntity } from './event.entity';
import { ThreadEntity } from './thread.entity';

@Entity({ name: 'federation_actions' })
@Index(
  'IDX_federation_actions_agent_idempotency_unique',
  ['agentId', 'idempotencyKey'],
  {
    unique: true,
  },
)
export class FederationActionEntity extends BaseTableEntity {
  @Column({ name: 'agent_id', type: 'uuid' })
  agentId!: string;

  @ManyToOne(() => AgentEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'agent_id' })
  agent!: AgentEntity;

  @Column({ name: 'action_type', type: 'varchar', length: 120 })
  actionType!: string;

  @Column({
    type: 'enum',
    enum: FederationActionStatus,
    enumName: 'federation_action_status_enum',
    default: FederationActionStatus.Accepted,
  })
  status = FederationActionStatus.Accepted;

  @Column({ name: 'idempotency_key', type: 'varchar', length: 255 })
  idempotencyKey!: string;

  @Column({ name: 'request_hash', type: 'varchar', length: 128 })
  requestHash!: string;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  payload: Record<string, unknown> = {};

  @Column({
    name: 'result_payload',
    type: 'jsonb',
    default: () => "'{}'::jsonb",
  })
  resultPayload: Record<string, unknown> = {};

  @Column({ name: 'error_payload', type: 'jsonb', nullable: true })
  errorPayload: Record<string, unknown> | null = null;

  @Column({ name: 'thread_id', type: 'uuid', nullable: true })
  threadId: string | null = null;

  @ManyToOne(() => ThreadEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'thread_id' })
  thread: ThreadEntity | null = null;

  @Column({ name: 'event_id', type: 'uuid', nullable: true })
  eventId: string | null = null;

  @ManyToOne(() => EventEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'event_id' })
  event: EventEntity | null = null;

  @Column({
    name: 'accepted_at',
    type: 'timestamptz',
    default: () => 'CURRENT_TIMESTAMP',
  })
  acceptedAt!: Date;

  @Column({
    name: 'processing_started_at',
    type: 'timestamptz',
    nullable: true,
  })
  processingStartedAt: Date | null = null;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt: Date | null = null;
}
