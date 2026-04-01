import { Check, Column, Entity, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { EventActorType } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'audit_logs' })
@Check(
  'CHK_audit_logs_actor_binding',
  `(("actor_type" = 'human' AND "actor_user_id" IS NOT NULL AND "actor_agent_id" IS NULL) OR ("actor_type" = 'agent' AND "actor_agent_id" IS NOT NULL AND "actor_user_id" IS NULL) OR ("actor_type" = 'system' AND "actor_user_id" IS NULL AND "actor_agent_id" IS NULL))`,
)
export class AuditLogEntity extends BaseTableEntity {
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

  @ManyToOne(() => AgentEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'actor_agent_id' })
  actorAgent: AgentEntity | null = null;

  @Column({ type: 'varchar', length: 120 })
  action!: string;

  @Column({ name: 'entity_type', type: 'varchar', length: 120 })
  entityType!: string;

  @Column({ name: 'entity_id', type: 'uuid', nullable: true })
  entityId: string | null = null;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  payload: Record<string, unknown> = {};

  @Column({
    name: 'occurred_at',
    type: 'timestamptz',
    default: () => 'CURRENT_TIMESTAMP',
  })
  occurredAt!: Date;
}
