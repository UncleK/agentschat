import { Check, Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { SubjectType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { EventEntity } from './event.entity';
import { ThreadEntity } from './thread.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'notifications' })
@Index('IDX_notifications_recipient_read_state', [
  'recipientType',
  'recipientSubjectId',
  'readAt',
])
@Check(
  'CHK_notifications_recipient_binding',
  `(("recipient_type" = 'human' AND "recipient_user_id" IS NOT NULL AND "recipient_agent_id" IS NULL AND "recipient_subject_id" = "recipient_user_id") OR ("recipient_type" = 'agent' AND "recipient_agent_id" IS NOT NULL AND "recipient_user_id" IS NULL AND "recipient_subject_id" = "recipient_agent_id"))`,
)
export class NotificationEntity extends BaseTableEntity {
  @Column({
    name: 'recipient_type',
    type: 'enum',
    enum: SubjectType,
    enumName: 'subject_type_enum',
  })
  recipientType!: SubjectType;

  @Column({ name: 'recipient_subject_id', type: 'uuid' })
  recipientSubjectId!: string;

  @Column({ name: 'recipient_user_id', type: 'uuid', nullable: true })
  recipientUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'recipient_user_id' })
  recipientUser: UserEntity | null = null;

  @Column({ name: 'recipient_agent_id', type: 'uuid', nullable: true })
  recipientAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'recipient_agent_id' })
  recipientAgent: AgentEntity | null = null;

  @Column({ type: 'varchar', length: 120 })
  kind!: string;

  @Column({ name: 'event_id', type: 'uuid', nullable: true })
  eventId: string | null = null;

  @ManyToOne(() => EventEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'event_id' })
  event: EventEntity | null = null;

  @Column({ name: 'thread_id', type: 'uuid', nullable: true })
  threadId: string | null = null;

  @ManyToOne(() => ThreadEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'thread_id' })
  thread: ThreadEntity | null = null;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  payload: Record<string, unknown> = {};

  @Column({ name: 'read_at', type: 'timestamptz', nullable: true })
  readAt: Date | null = null;
}
