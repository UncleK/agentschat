import {
  Check,
  Column,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  OneToMany,
} from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { DebateSessionStatus, SubjectType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { DebateSeatEntity } from './debate-seat.entity';
import { DebateTurnEntity } from './debate-turn.entity';
import { ThreadEntity } from './thread.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'debate_sessions' })
@Index('IDX_debate_sessions_thread_id_unique', ['threadId'], { unique: true })
@Check(
  'CHK_debate_sessions_host_binding',
  `(("host_type" = 'human' AND "host_user_id" IS NOT NULL AND "host_agent_id" IS NULL) OR ("host_type" = 'agent' AND "host_agent_id" IS NOT NULL AND "host_user_id" IS NULL))`,
)
export class DebateSessionEntity extends BaseTableEntity {
  @Column({ name: 'thread_id', type: 'uuid' })
  threadId!: string;

  @ManyToOne(() => ThreadEntity, (thread) => thread.debateSessions, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'thread_id' })
  thread!: ThreadEntity;

  @Column({ type: 'varchar', length: 280 })
  topic!: string;

  @Column({ name: 'pro_stance', type: 'varchar', length: 280 })
  proStance!: string;

  @Column({ name: 'con_stance', type: 'varchar', length: 280 })
  conStance!: string;

  @Column({
    name: 'host_type',
    type: 'enum',
    enum: SubjectType,
    enumName: 'subject_type_enum',
  })
  hostType!: SubjectType;

  @Column({ name: 'host_user_id', type: 'uuid', nullable: true })
  hostUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'host_user_id' })
  hostUser: UserEntity | null = null;

  @Column({ name: 'host_agent_id', type: 'uuid', nullable: true })
  hostAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'host_agent_id' })
  hostAgent: AgentEntity | null = null;

  @Column({
    type: 'enum',
    enum: DebateSessionStatus,
    enumName: 'debate_session_status_enum',
    default: DebateSessionStatus.Pending,
  })
  status = DebateSessionStatus.Pending;

  @Column({ name: 'free_entry', type: 'boolean', default: false })
  freeEntry = false;

  @Column({ name: 'human_host_allowed', type: 'boolean', default: true })
  humanHostAllowed = true;

  @Column({ name: 'current_turn_number', type: 'integer', default: 1 })
  currentTurnNumber = 1;

  @Column({ name: 'started_at', type: 'timestamptz', nullable: true })
  startedAt: Date | null = null;

  @Column({ name: 'archived_at', type: 'timestamptz', nullable: true })
  archivedAt: Date | null = null;

  @OneToMany(() => DebateSeatEntity, (seat) => seat.debateSession)
  seats?: DebateSeatEntity[];

  @OneToMany(() => DebateTurnEntity, (turn) => turn.debateSession)
  turns?: DebateTurnEntity[];
}
