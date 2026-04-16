import {
  Check,
  Column,
  Entity,
  JoinColumn,
  ManyToOne,
  OneToMany,
  OneToOne,
} from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { AgentOwnerType, AgentStatus } from '../domain.enums';
import { AgentConnectionEntity } from './agent-connection.entity';
import { AgentPolicyEntity } from './agent-policy.entity';
import { DeliveryEntity } from './delivery.entity';
import { EventEntity } from './event.entity';
import { ThreadParticipantEntity } from './thread-participant.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'agents' })
@Check(
  'CHK_agents_owner_binding',
  `(("owner_type" = 'human' AND "owner_user_id" IS NOT NULL) OR ("owner_type" = 'self' AND "owner_user_id" IS NULL))`,
)
export class AgentEntity extends BaseTableEntity {
  @Column({ type: 'varchar', length: 64, unique: true, update: false })
  handle!: string;

  @Column({ name: 'display_name', type: 'varchar', length: 120 })
  displayName!: string;

  @Column({ name: 'avatar_url', type: 'varchar', length: 1024, nullable: true })
  avatarUrl: string | null = null;

  @Column({ type: 'text', nullable: true })
  bio: string | null = null;

  @Column({
    name: 'owner_type',
    type: 'enum',
    enum: AgentOwnerType,
    enumName: 'agent_owner_type_enum',
  })
  ownerType!: AgentOwnerType;

  @Column({ name: 'owner_user_id', type: 'uuid', nullable: true })
  ownerUserId: string | null = null;

  @ManyToOne(() => UserEntity, (user) => user.ownedAgents, { nullable: true })
  @JoinColumn({ name: 'owner_user_id' })
  ownerUser?: UserEntity | null;

  @Column({
    type: 'enum',
    enum: AgentStatus,
    enumName: 'agent_status_enum',
    default: AgentStatus.Offline,
  })
  status = AgentStatus.Offline;

  @Column({ name: 'source_type', type: 'varchar', length: 64, nullable: true })
  sourceType: string | null = null;

  @Column({ name: 'vendor_name', type: 'varchar', length: 128, nullable: true })
  vendorName: string | null = null;

  @Column({
    name: 'runtime_name',
    type: 'varchar',
    length: 128,
    nullable: true,
  })
  runtimeName: string | null = null;

  @Column({ name: 'is_public', type: 'boolean', default: true })
  isPublic = true;

  @Column({
    name: 'profile_tags',
    type: 'text',
    array: true,
    default: () => "'{}'",
  })
  profileTags: string[] = [];

  @Column({
    name: 'profile_metadata',
    type: 'jsonb',
    default: () => "'{}'::jsonb",
  })
  profileMetadata: Record<string, unknown> = {};

  @Column({ name: 'last_seen_at', type: 'timestamptz', nullable: true })
  lastSeenAt: Date | null = null;

  @OneToOne(() => AgentPolicyEntity, (policy) => policy.agent)
  policy?: AgentPolicyEntity;

  @OneToOne(() => AgentConnectionEntity, (connection) => connection.agent)
  connection?: AgentConnectionEntity;

  @OneToMany(() => ThreadParticipantEntity, (participant) => participant.agent)
  threadParticipations?: ThreadParticipantEntity[];

  @OneToMany(() => EventEntity, (event) => event.actorAgent)
  authoredEvents?: EventEntity[];

  @OneToMany(() => DeliveryEntity, (delivery) => delivery.recipientAgent)
  deliveries?: DeliveryEntity[];
}
