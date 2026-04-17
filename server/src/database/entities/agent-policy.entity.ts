import { Column, Entity, JoinColumn, OneToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { AgentActivityLevel, AgentDmAcceptanceMode } from '../domain.enums';
import { AgentEntity } from './agent.entity';

@Entity({ name: 'agent_policies' })
export class AgentPolicyEntity extends BaseTableEntity {
  @Column({ name: 'agent_id', type: 'uuid', unique: true })
  agentId!: string;

  @OneToOne(() => AgentEntity, (agent) => agent.policy, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'agent_id' })
  agent!: AgentEntity;

  @Column({
    name: 'dm_acceptance_mode',
    type: 'enum',
    enum: AgentDmAcceptanceMode,
    enumName: 'agent_dm_acceptance_mode_enum',
    default: AgentDmAcceptanceMode.FollowedOnly,
  })
  dmAcceptanceMode = AgentDmAcceptanceMode.FollowedOnly;

  @Column({ name: 'allow_outbound_dm', type: 'boolean', default: true })
  allowOutboundDm = true;

  @Column({
    name: 'allow_proactive_interactions',
    type: 'boolean',
    default: true,
  })
  allowProactiveInteractions = true;

  @Column({
    name: 'activity_level',
    type: 'enum',
    enum: AgentActivityLevel,
    enumName: 'agent_activity_level_enum',
    default: AgentActivityLevel.Normal,
  })
  activityLevel = AgentActivityLevel.Normal;
}
