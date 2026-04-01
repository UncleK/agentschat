import { Check, Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { SubjectType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'block_rules' })
@Index(
  'IDX_block_rules_scope_target_unique',
  ['scopeType', 'scopeSubjectId', 'blockedType', 'blockedSubjectId'],
  { unique: true },
)
@Check(
  'CHK_block_rules_scope_binding',
  `(("scope_type" = 'human' AND "scope_user_id" IS NOT NULL AND "scope_agent_id" IS NULL AND "scope_subject_id" = "scope_user_id") OR ("scope_type" = 'agent' AND "scope_agent_id" IS NOT NULL AND "scope_user_id" IS NULL AND "scope_subject_id" = "scope_agent_id"))`,
)
@Check(
  'CHK_block_rules_blocked_binding',
  `(("blocked_type" = 'human' AND "blocked_user_id" IS NOT NULL AND "blocked_agent_id" IS NULL AND "blocked_subject_id" = "blocked_user_id") OR ("blocked_type" = 'agent' AND "blocked_agent_id" IS NOT NULL AND "blocked_user_id" IS NULL AND "blocked_subject_id" = "blocked_agent_id"))`,
)
export class BlockRuleEntity extends BaseTableEntity {
  @Column({
    name: 'scope_type',
    type: 'enum',
    enum: SubjectType,
    enumName: 'subject_type_enum',
  })
  scopeType!: SubjectType;

  @Column({ name: 'scope_subject_id', type: 'uuid' })
  scopeSubjectId!: string;

  @Column({ name: 'scope_user_id', type: 'uuid', nullable: true })
  scopeUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'scope_user_id' })
  scopeUser: UserEntity | null = null;

  @Column({ name: 'scope_agent_id', type: 'uuid', nullable: true })
  scopeAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'scope_agent_id' })
  scopeAgent: AgentEntity | null = null;

  @Column({
    name: 'blocked_type',
    type: 'enum',
    enum: SubjectType,
    enumName: 'subject_type_enum',
  })
  blockedType!: SubjectType;

  @Column({ name: 'blocked_subject_id', type: 'uuid' })
  blockedSubjectId!: string;

  @Column({ name: 'blocked_user_id', type: 'uuid', nullable: true })
  blockedUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'blocked_user_id' })
  blockedUser: UserEntity | null = null;

  @Column({ name: 'blocked_agent_id', type: 'uuid', nullable: true })
  blockedAgentId: string | null = null;

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'blocked_agent_id' })
  blockedAgent: AgentEntity | null = null;

  @Column({ type: 'text', nullable: true })
  reason: string | null = null;
}
