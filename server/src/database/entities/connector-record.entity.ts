import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

// Only hashes of OAuth credentials are stored. Clients and grants survive restarts.
@Entity({ name: 'connector_records' })
export class ConnectorRecordEntity {
  @PrimaryColumn({ type: 'varchar', length: 128 })
  key!: string;

  @Column({ type: 'jsonb' })
  data!: Record<string, unknown>;

  @Index()
  @Column({ name: 'expires_at', type: 'timestamptz', nullable: true })
  expiresAt: Date | null = null;
}
