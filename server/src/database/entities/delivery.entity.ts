import { Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { DeliveryChannel, DeliveryStatus } from '../domain.enums';
import { AgentConnectionEntity } from './agent-connection.entity';
import { AgentEntity } from './agent.entity';
import { EventEntity } from './event.entity';

@Entity({ name: 'deliveries' })
@Index(
  'IDX_deliveries_event_recipient_unique',
  ['eventId', 'recipientAgentId'],
  {
    unique: true,
  },
)
@Index('IDX_deliveries_recipient_sequence_unique', ['recipientAgentId', 'sequence'], {
  unique: true,
})
export class DeliveryEntity extends BaseTableEntity {
  @Column({ name: 'event_id', type: 'uuid' })
  eventId!: string;

  @ManyToOne(() => EventEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'event_id' })
  event!: EventEntity;

  @Column({ name: 'recipient_agent_id', type: 'uuid' })
  recipientAgentId!: string;

  @ManyToOne(() => AgentEntity, (agent) => agent.deliveries, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'recipient_agent_id' })
  recipientAgent!: AgentEntity;

  @Column({ name: 'agent_connection_id', type: 'uuid', nullable: true })
  agentConnectionId: string | null = null;

  @ManyToOne(() => AgentConnectionEntity, {
    nullable: true,
    onDelete: 'SET NULL',
  })
  @JoinColumn({ name: 'agent_connection_id' })
  agentConnection: AgentConnectionEntity | null = null;

  @Column({ type: 'integer' })
  sequence!: number;

  @Column({
    type: 'enum',
    enum: DeliveryStatus,
    enumName: 'delivery_status_enum',
    default: DeliveryStatus.Pending,
  })
  status = DeliveryStatus.Pending;

  @Column({
    name: 'delivery_channel',
    type: 'enum',
    enum: DeliveryChannel,
    enumName: 'delivery_channel_enum',
    default: DeliveryChannel.Webhook,
  })
  deliveryChannel = DeliveryChannel.Webhook;

  @Column({ name: 'attempt_count', type: 'integer', default: 0 })
  attemptCount = 0;

  @Column({ name: 'last_attempt_at', type: 'timestamptz', nullable: true })
  lastAttemptAt: Date | null = null;

  @Column({ name: 'next_attempt_at', type: 'timestamptz', nullable: true })
  nextAttemptAt: Date | null = null;

  @Column({ name: 'acked_at', type: 'timestamptz', nullable: true })
  ackedAt: Date | null = null;

  @Column({ name: 'replay_expires_at', type: 'timestamptz' })
  replayExpiresAt!: Date;

  @Column({ name: 'dead_lettered_at', type: 'timestamptz', nullable: true })
  deadLetteredAt: Date | null = null;

  @Column({ name: 'last_error', type: 'text', nullable: true })
  lastError: string | null = null;
}
