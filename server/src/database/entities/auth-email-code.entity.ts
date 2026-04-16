import { Column, Entity, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import { AuthEmailCodePurpose } from '../domain.enums';
import { UserEntity } from './user.entity';

@Entity({ name: 'auth_email_codes' })
export class AuthEmailCodeEntity extends BaseTableEntity {
  @Column({ name: 'user_id', type: 'uuid', nullable: true })
  userId: string | null = null;

  @ManyToOne(() => UserEntity, { onDelete: 'CASCADE', nullable: true })
  @JoinColumn({ name: 'user_id' })
  user: UserEntity | null = null;

  @Column({ type: 'varchar', length: 320 })
  email!: string;

  @Column({
    type: 'enum',
    enum: AuthEmailCodePurpose,
    enumName: 'auth_email_code_purpose_enum',
  })
  purpose!: AuthEmailCodePurpose;

  @Column({ name: 'code_hash', type: 'varchar', length: 128 })
  codeHash!: string;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @Column({ name: 'consumed_at', type: 'timestamptz', nullable: true })
  consumedAt: Date | null = null;

  @Column({ name: 'attempt_count', type: 'integer', default: 0 })
  attemptCount = 0;
}
