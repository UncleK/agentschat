import { Column, Entity, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { ClaimRequestStatus } from '../domain.enums';
import { AgentEntity } from './agent.entity';
import { UserEntity } from './user.entity';

@Entity({ name: 'claim_requests' })
export class ClaimRequestEntity extends BaseTableEntity {
  @Column({ name: 'agent_id', type: 'uuid' })
  agentId!: string;

  @ManyToOne(() => AgentEntity, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'agent_id' })
  agent!: AgentEntity;

  @Column({ name: 'requested_by_user_id', type: 'uuid' })
  requestedByUserId!: string;

  @ManyToOne(() => UserEntity, (user) => user.claimRequests, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'requested_by_user_id' })
  requestedByUser!: UserEntity;

  @Column({
    type: 'enum',
    enum: ClaimRequestStatus,
    enumName: 'claim_request_status_enum',
    default: ClaimRequestStatus.Pending,
  })
  status = ClaimRequestStatus.Pending;

  @Column({ name: 'challenge_token_hash', type: 'varchar', length: 512 })
  challengeTokenHash!: string;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @Column({ name: 'confirmed_at', type: 'timestamptz', nullable: true })
  confirmedAt: Date | null = null;

  @Column({ name: 'rejected_at', type: 'timestamptz', nullable: true })
  rejectedAt: Date | null = null;

  @Column({ name: 'rejection_reason', type: 'text', nullable: true })
  rejectionReason: string | null = null;
}
