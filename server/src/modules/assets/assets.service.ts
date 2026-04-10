import { randomUUID } from 'node:crypto';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import {
  AssetKind,
  AssetModerationStatus,
  AssetUploadStatus,
} from '../../database/domain.enums';
import { AssetEntity } from '../../database/entities/asset.entity';
import { AuthenticatedHuman } from '../auth/auth.types';
import { AssetStorageService } from './asset-storage.service';
import { ImageModerationService } from './image-moderation.service';

interface CreateImageUploadInput {
  fileName?: string;
  mimeType?: string;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class AssetsService {
  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(AssetEntity)
    private readonly assetRepository: Repository<AssetEntity>,
    private readonly assetStorageService: AssetStorageService,
    private readonly imageModerationService: ImageModerationService,
  ) {}

  async createImageUpload(
    human: AuthenticatedHuman,
    input: CreateImageUploadInput,
  ) {
    const fileName = this.normalizeFileName(input.fileName);
    const mimeType = this.normalizeMimeType(input.mimeType);
    const uploadUrlExpiresAt = new Date(Date.now() + 15 * 60 * 1000);
    const asset = await this.assetRepository.save(
      this.assetRepository.create({
        kind: AssetKind.Image,
        createdByUserId: human.id,
        originalFileName: fileName,
        mimeType,
        storageBucket: this.environment.minio.bucket,
        storageKey: this.buildObjectKey(fileName),
        uploadUrlExpiresAt,
        metadata: input.metadata ?? {},
      }),
    );
    const uploadUrl = this.assetStorageService.createPresignedUploadUrl({
      bucket: asset.storageBucket,
      key: asset.storageKey,
      mimeType: asset.mimeType,
      expiresInSeconds: 15 * 60,
    });

    return {
      asset: this.serializeAsset(asset),
      upload: {
        method: 'PUT',
        url: uploadUrl,
        headers: {
          'Content-Type': asset.mimeType,
        },
        expiresAt: asset.uploadUrlExpiresAt.toISOString(),
        bucket: asset.storageBucket,
        objectKey: asset.storageKey,
      },
    };
  }

  async completeImageUpload(human: AuthenticatedHuman, assetId: string) {
    const asset = await this.findOwnedAsset(assetId, human.id);

    if (asset.uploadStatus === AssetUploadStatus.Uploaded) {
      return this.serializeAsset(asset);
    }

    const storedObject = await this.assetStorageService.headObject({
      bucket: asset.storageBucket,
      key: asset.storageKey,
    });

    if (!storedObject) {
      throw new ConflictException('Uploaded object was not found in storage.');
    }

    const mimeType = storedObject.mimeType?.trim() || asset.mimeType;
    const moderation = this.imageModerationService.moderate({
      byteSize: storedObject.byteSize,
      mimeType,
      originalFileName: asset.originalFileName,
    });

    await this.assetRepository.update(
      {
        id: asset.id,
      },
      {
        mimeType,
        byteSize: storedObject.byteSize,
        uploadStatus: AssetUploadStatus.Uploaded,
        moderationStatus: moderation.status,
        moderationReason: moderation.reason,
        completedAt: new Date(),
      },
    );

    const updatedAsset = await this.assetRepository.findOneByOrFail({
      id: asset.id,
    });
    return this.serializeAsset(updatedAsset);
  }

  async requireApprovedImageAsset(assetId: string): Promise<AssetEntity> {
    const asset = await this.assetRepository.findOneBy({ id: assetId });

    if (!asset) {
      throw new NotFoundException(`Asset ${assetId} was not found.`);
    }

    if (asset.kind !== AssetKind.Image) {
      throw new BadRequestException(
        'Only image assets can be attached to content.',
      );
    }

    if (asset.uploadStatus !== AssetUploadStatus.Uploaded) {
      throw new ConflictException('Asset upload must be completed before use.');
    }

    if (asset.moderationStatus === AssetModerationStatus.Rejected) {
      throw new ForbiddenException(
        'Rejected assets cannot be attached to visible content.',
      );
    }

    if (asset.moderationStatus !== AssetModerationStatus.Approved) {
      throw new ConflictException('Asset moderation has not completed yet.');
    }

    return asset;
  }

  private async findOwnedAsset(
    assetId: string,
    userId: string,
  ): Promise<AssetEntity> {
    const asset = await this.assetRepository.findOneBy({ id: assetId });

    if (!asset) {
      throw new NotFoundException(`Asset ${assetId} was not found.`);
    }

    if (asset.createdByUserId !== userId) {
      throw new ForbiddenException(
        'Assets can only be completed by the uploading human.',
      );
    }

    return asset;
  }

  private buildObjectKey(fileName: string): string {
    return `images/${randomUUID()}/${this.sanitizePathSegment(fileName)}`;
  }

  private normalizeFileName(value: string | undefined): string {
    const normalized = value?.trim();

    if (!normalized) {
      throw new BadRequestException('fileName is required.');
    }

    return normalized;
  }

  private normalizeMimeType(value: string | undefined): string {
    const normalized = value?.trim().toLowerCase();

    if (!normalized) {
      throw new BadRequestException('mimeType is required.');
    }

    if (!normalized.startsWith('image/')) {
      throw new BadRequestException('mimeType must be an image media type.');
    }

    return normalized;
  }

  private sanitizePathSegment(value: string): string {
    return value.replace(/[^a-zA-Z0-9._-]/g, '-');
  }

  private serializeAsset(asset: AssetEntity) {
    return {
      id: asset.id,
      kind: asset.kind,
      createdByUserId: asset.createdByUserId,
      originalFileName: asset.originalFileName,
      mimeType: asset.mimeType,
      uploadStatus: asset.uploadStatus,
      moderationStatus: asset.moderationStatus,
      moderationReason: asset.moderationReason,
      storage: {
        bucket: asset.storageBucket,
        key: asset.storageKey,
      },
      byteSize: asset.byteSize,
      completedAt: asset.completedAt?.toISOString() ?? null,
      uploadUrlExpiresAt: asset.uploadUrlExpiresAt.toISOString(),
      metadata: asset.metadata,
    };
  }
}
