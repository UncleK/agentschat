import { Check, Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { SubjectType, ThreadParticipantRole } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { ThreadEntity } from './thread.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'thread_participants' })
@Index(
  'IDX_thread_participants_identity',
  ['threadId', 'participantType', 'participantSubjectId'],
  {
    unique: true,
  },
)
@Check(
  'CHK_thread_participants_subject_binding',
  `(("participant_type" = 'human' AND "user_id" IS NOT NULL AND "agent_id" IS NULL AND "participant_subject_id" = "user_id") OR ("participant_type" = 'agent' AND "agent_id" IS NOT NULL AND "user_id" IS NULL AND "participant_subject_id" = "agent_id"))`,
)
export class ThreadParticipantEntity extends BaseTableEntity {
  @Column({ name: 'thread_id', type: 'uuid' })
  threadId!: string;

  @ManyToOne(() => ThreadEntity, (thread) => thread.participants, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'thread_id' })
  thread!: ThreadEntity;

  @Column({
    name: 'participant_type',
    type: 'enum',
    enum: SubjectType,
    enumName: 'subject_type_enum',
  })
  participantType!: SubjectType;

  @Column({ name: 'participant_subject_id', type: 'uuid' })
  participantSubjectId!: string;

  @Column({ name: 'user_id', type: 'uuid', nullable: true })
  userId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: UserEntity | null = null;

  @Column({ name: 'agent_id', type: 'uuid', nullable: true })
  agentId: string | null = null;

  @ManyToOne(() => AgentEntity, (agent) => agent.threadParticipations, {
    nullable: true,
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'agent_id' })
  agent: AgentEntity | null = null;

  @Column({
    type: 'enum',
    enum: ThreadParticipantRole,
    enumName: 'thread_participant_role_enum',
    default: ThreadParticipantRole.Member,
  })
  role = ThreadParticipantRole.Member;

  @Column({ name: 'last_read_event_id', type: 'uuid', nullable: true })
  lastReadEventId: string | null = null;

  @Column({ name: 'last_read_at', type: 'timestamptz', nullable: true })
  lastReadAt: Date | null = null;
}
