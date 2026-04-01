import { Check, Column, Entity, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { ModerationTargetType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { DebateSessionEntity } from './debate-session.entity';
import { EventEntity } from './event.entity';
import { ThreadEntity } from './thread.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'moderation_actions' })
@Check(
  'CHK_moderation_actions_target_binding',
  `(("target_type" = 'user' AND "target_user_id" IS NOT NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_event_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_user_id") OR ("target_type" = 'agent' AND "target_agent_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_thread_id" IS NULL AND "target_event_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_agent_id") OR ("target_type" = 'thread' AND "target_thread_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_agent_id" IS NULL AND "target_event_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_thread_id") OR ("target_type" = 'event' AND "target_event_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_event_id") OR ("target_type" = 'debate_session' AND "target_debate_session_id" IS NOT NULL AND "target_user_id" IS NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_event_id" IS NULL AND "target_subject_id" = "target_debate_session_id"))`,
)
export class ModerationActionEntity extends BaseTableEntity {
  @Column({ type: 'varchar', length: 64 })
  action!: string;

  @Column({
    name: 'target_type',
    type: 'enum',
    enum: ModerationTargetType,
    enumName: 'moderation_target_type_enum',
  })
  targetType!: ModerationTargetType;

  @Column({ name: 'target_subject_id', type: 'uuid' })
  targetSubjectId!: string;

  @Column({ name: 'target_user_id', type: 'uuid', nullable: true })
  targetUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'target_user_id' })
  targetUser: UserEntity | null = null;

  @Column({ name: 'target_agent_id', type: 'uuid', nullable: true })
  targetAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'target_agent_id' })
  targetAgent: AgentEntity | null = null;

  @Column({ name: 'target_thread_id', type: 'uuid', nullable: true })
  targetThreadId: string | null = null;

  @ManyToOne(() => ThreadEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'target_thread_id' })
  targetThread: ThreadEntity | null = null;

  @Column({ name: 'target_event_id', type: 'uuid', nullable: true })
  targetEventId: string | null = null;

  @ManyToOne(() => EventEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'target_event_id' })
  targetEvent: EventEntity | null = null;

  @Column({ name: 'target_debate_session_id', type: 'uuid', nullable: true })
  targetDebateSessionId: string | null = null;

  @ManyToOne(() => DebateSessionEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'target_debate_session_id' })
  targetDebateSession: DebateSessionEntity | null = null;

  @Column({ name: 'actor_user_id', type: 'uuid', nullable: true })
  actorUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'actor_user_id' })
  actorUser: UserEntity | null = null;

  @Column({ type: 'text' })
  reason!: string;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  metadata: Record<string, unknown> = {};
}
