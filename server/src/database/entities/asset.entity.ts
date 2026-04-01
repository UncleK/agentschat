import { Column, Entity, Index, JoinColumn, ManyToOne } from 'typeorm';
import { BaseTableEntity } from '../base.entity';
import {
  AssetKind,
  AssetModerationStatus,
  AssetUploadStatus,
} from '../domain.enums';
import { UserEntity } from './user.entity';

@Entity({ name: 'assets' })
@Index('IDX_assets_storage_key_unique', ['storageKey'], { unique: true })
export class AssetEntity extends BaseTableEntity {
  @Column({
    type: 'enum',
    enum: AssetKind,
    enumName: 'asset_kind_enum',
  })
  kind!: AssetKind;

  @Column({ name: 'created_by_user_id', type: 'uuid', nullable: true })
  createdByUserId: string | null = null;

  @ManyToOne(() => UserEntity, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'created_by_user_id' })
  createdByUser: UserEntity | null = null;

  @Column({ name: 'original_file_name', type: 'varchar', length: 255 })
  originalFileName!: string;

  @Column({ name: 'mime_type', type: 'varchar', length: 160 })
  mimeType!: string;

  @Column({
    name: 'upload_status',
    type: 'enum',
    enum: AssetUploadStatus,
    enumName: 'asset_upload_status_enum',
    default: AssetUploadStatus.Pending,
  })
  uploadStatus = AssetUploadStatus.Pending;

  @Column({
    name: 'moderation_status',
    type: 'enum',
    enum: AssetModerationStatus,
    enumName: 'asset_moderation_status_enum',
    default: AssetModerationStatus.Pending,
  })
  moderationStatus = AssetModerationStatus.Pending;

  @Column({ name: 'moderation_reason', type: 'varchar', length: 255, nullable: true })
  moderationReason: string | null = null;

  @Column({ name: 'storage_bucket', type: 'varchar', length: 255 })
  storageBucket!: string;

  @Column({ name: 'storage_key', type: 'varchar', length: 512 })
  storageKey!: string;

  @Column({ name: 'byte_size', type: 'integer', nullable: true })
  byteSize: number | null = null;

  @Column({ name: 'upload_url_expires_at', type: 'timestamptz' })
  uploadUrlExpiresAt!: Date;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt: Date | null = null;

  @Column({ name: 'metadata', type: 'jsonb', default: () => "'{}'::jsonb" })
  metadata: Record<string, unknown> = {};
}
