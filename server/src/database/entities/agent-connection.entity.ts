import { Column, Entity, JoinColumn, OneToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { ConnectionTransportMode } from '../domain.enums';
import { AgentEntity } from './agent.entity';

@Entity({ name: 'agent_connections' })
export class AgentConnectionEntity extends BaseTableEntity {
  @Column({ name: 'agent_id', type: 'uuid', unique: true })
  agentId!: string;

  @OneToOne(() => AgentEntity, (agent) => agent.connection, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'agent_id' })
  agent!: AgentEntity;

  @Column({ name: 'protocol_version', type: 'varchar', length: 32 })
  protocolVersion!: string;

  @Column({
    name: 'transport_mode',
    type: 'enum',
    enum: ConnectionTransportMode,
    enumName: 'connection_transport_mode_enum',
    default: ConnectionTransportMode.Webhook,
  })
  transportMode = ConnectionTransportMode.Webhook;

  @Column({
    name: 'webhook_url',
    type: 'varchar',
    length: 2048,
    nullable: true,
  })
  webhookUrl: string | null = null;

  @Column({
    name: 'webhook_secret',
    type: 'varchar',
    length: 512,
    nullable: true,
  })
  webhookSecret: string | null = null;

  @Column({
    name: 'webhook_secret_hash',
    type: 'varchar',
    length: 512,
    nullable: true,
  })
  webhookSecretHash: string | null = null;

  @Column({ name: 'polling_enabled', type: 'boolean', default: false })
  pollingEnabled = false;

  @Column({ name: 'token_hash', type: 'varchar', length: 512 })
  tokenHash!: string;

  @Column({ name: 'last_heartbeat_at', type: 'timestamptz', nullable: true })
  lastHeartbeatAt: Date | null = null;

  @Column({ name: 'last_seen_at', type: 'timestamptz', nullable: true })
  lastSeenAt: Date | null = null;

  @Column({ name: 'capabilities', type: 'jsonb', default: () => "'{}'::jsonb" })
  capabilities: Record<string, unknown> = {};
}
