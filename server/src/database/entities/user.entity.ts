import { Check, Column, Entity, OneToMany } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { AuthProvider } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { ClaimRequestEntity } from './claim-request.entity';

@Entity({ name: 'users' })
@Check(
  'CHK_users_auth_identity_binding',
  `(("auth_provider" = 'email' AND "provider_subject" IS NULL) OR ("auth_provider" IN ('google', 'github') AND "provider_subject" IS NOT NULL))`,
)
export class UserEntity extends BaseTableEntity {
  @Column({ type: 'varchar', length: 320, unique: true })
  email!: string;

  @Column({ type: 'varchar', length: 32, unique: true })
  username!: string;

  @Column({ name: 'display_name', type: 'varchar', length: 120 })
  displayName!: string;

  @Column({
    name: 'password_hash',
    type: 'varchar',
    length: 512,
    nullable: true,
  })
  passwordHash: string | null = null;

  @Column({
    name: 'auth_provider',
    type: 'enum',
    enum: AuthProvider,
    enumName: 'auth_provider_enum',
  })
  authProvider!: AuthProvider;

  @Column({
    name: 'provider_subject',
    type: 'varchar',
    length: 255,
    nullable: true,
  })
  providerSubject: string | null = null;

  @Column({ name: 'avatar_url', type: 'varchar', length: 1024, nullable: true })
  avatarUrl: string | null = null;

  @Column({ type: 'varchar', length: 32, default: 'en-US' })
  locale = 'en-US';

  @Column({ name: 'block_stranger_agent_dm', type: 'boolean', default: false })
  blockStrangerAgentDm = false;

  @Column({ name: 'block_stranger_human_dm', type: 'boolean', default: false })
  blockStrangerHumanDm = false;

  @OneToMany(() => AgentEntity, (agent) => agent.ownerUser)
  ownedAgents?: AgentEntity[];

  @OneToMany(
    () => ClaimRequestEntity,
    (claimRequest) => claimRequest.requestedByUser,
  )
  claimRequests?: ClaimRequestEntity[];
}
