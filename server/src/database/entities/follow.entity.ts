import { Check, Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { FollowTargetType, SubjectType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { DebateSessionEntity } from './debate-session.entity';
import { ThreadEntity } from './thread.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'follows' })
@Index(
  'IDX_follows_subject_target_unique',
  ['followerType', 'followerSubjectId', 'targetType', 'targetSubjectId'],
  { unique: true },
)
@Check(
  'CHK_follows_follower_binding',
  `(("follower_type" = 'human' AND "follower_user_id" IS NOT NULL AND "follower_agent_id" IS NULL AND "follower_subject_id" = "follower_user_id") OR ("follower_type" = 'agent' AND "follower_agent_id" IS NOT NULL AND "follower_user_id" IS NULL AND "follower_subject_id" = "follower_agent_id"))`,
)
@Check(
  'CHK_follows_target_binding',
  `(("target_type" = 'agent' AND "target_agent_id" IS NOT NULL AND "target_thread_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_agent_id") OR ("target_type" = 'topic' AND "target_thread_id" IS NOT NULL AND "target_agent_id" IS NULL AND "target_debate_session_id" IS NULL AND "target_subject_id" = "target_thread_id") OR ("target_type" = 'debate' AND "target_debate_session_id" IS NOT NULL AND "target_agent_id" IS NULL AND "target_thread_id" IS NULL AND "target_subject_id" = "target_debate_session_id"))`,
)
export class FollowEntity extends BaseTableEntity {
  @Column({
    name: 'follower_type',
    type: 'enum',
    enum: SubjectType,
    enumName: 'subject_type_enum',
  })
  followerType!: SubjectType;

  @Column({ name: 'follower_subject_id', type: 'uuid' })
  followerSubjectId!: string;

  @Column({ name: 'follower_user_id', type: 'uuid', nullable: true })
  followerUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'follower_user_id' })
  followerUser: UserEntity | null = null;

  @Column({ name: 'follower_agent_id', type: 'uuid', nullable: true })
  followerAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'follower_agent_id' })
  followerAgent: AgentEntity | null = null;

  @Column({
    name: 'target_type',
    type: 'enum',
    enum: FollowTargetType,
    enumName: 'follow_target_type_enum',
  })
  targetType!: FollowTargetType;

  @Column({ name: 'target_subject_id', type: 'uuid' })
  targetSubjectId!: string;

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

  @Column({ name: 'target_debate_session_id', type: 'uuid', nullable: true })
  targetDebateSessionId: string | null = null;

  @ManyToOne(() => DebateSessionEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'target_debate_session_id' })
  targetDebateSession: DebateSessionEntity | null = null;
}
