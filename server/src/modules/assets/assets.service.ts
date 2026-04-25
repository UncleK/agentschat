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

interface UploadImageInput extends CreateImageUploadInput {
  bytes: Buffer;
}

interface CreateGeneratedAudioAssetInput {
  fileName: string;
  mimeType: string;
  bytes: Buffer;
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
    const mimeType = this.normalizeImageMimeType(input.mimeType);
    const uploadUrlExpiresAt = new Date(Date.now() + 15 * 60 * 1000);
    const asset = await this.assetRepository.save(
      this.assetRepository.create({
        kind: AssetKind.Image,
        createdByUserId: human.id,
        originalFileName: fileName,
        mimeType,
        storageBucket: this.environment.minio.bucket,
        storageKey: this.buildObjectKey(AssetKind.Image, fileName),
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

  async uploadImage(human: AuthenticatedHuman, input: UploadImageInput) {
    const issuedUpload = await this.createImageUpload(human, input);
    const uploadResponse = await fetch(issuedUpload.upload.url, {
      method: issuedUpload.upload.method,
      headers: issuedUpload.upload.headers,
      body: new Uint8Array(input.bytes),
    });
    if (!uploadResponse.ok) {
      throw new ConflictException('Uploading the image to storage failed.');
    }
    return this.completeImageUpload(human, issuedUpload.asset.id);
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

  async createGeneratedAudioAsset(input: CreateGeneratedAudioAssetInput) {
    const fileName = this.normalizeFileName(input.fileName);
    const mimeType = this.normalizeAudioMimeType(input.mimeType);
    const storageKey = this.buildObjectKey(AssetKind.Audio, fileName);
    await this.assetStorageService.writeObject({
      bucket: this.environment.minio.bucket,
      key: storageKey,
      mimeType,
      body: input.bytes,
    });

    const asset = await this.assetRepository.save(
      this.assetRepository.create({
        kind: AssetKind.Audio,
        createdByUserId: null,
        originalFileName: fileName,
        mimeType,
        storageBucket: this.environment.minio.bucket,
        storageKey,
        uploadStatus: AssetUploadStatus.Uploaded,
        moderationStatus: AssetModerationStatus.Approved,
        byteSize: input.bytes.byteLength,
        uploadUrlExpiresAt: new Date(),
        completedAt: new Date(),
        metadata: input.metadata ?? {},
      }),
    );

    return asset;
  }

  async requireApprovedImageAsset(assetId: string): Promise<AssetEntity> {
    return this.requireApprovedAsset(assetId, [AssetKind.Image]);
  }

  async requireApprovedAudioAsset(assetId: string): Promise<AssetEntity> {
    return this.requireApprovedAsset(assetId, [AssetKind.Audio]);
  }

  async requireApprovedAsset(
    assetId: string,
    allowedKinds?: AssetKind[],
  ): Promise<AssetEntity> {
    const asset = await this.assetRepository.findOneBy({ id: assetId });

    if (!asset) {
      throw new NotFoundException(`Asset ${assetId} was not found.`);
    }

    if (allowedKinds && !allowedKinds.includes(asset.kind)) {
      const kindList = allowedKinds.join(', ');
      throw new BadRequestException(
        `Only ${kindList} assets can be attached to this content.`,
      );
    }

    return this.assertApprovedAsset(asset);
  }

  createReadUrl(asset: AssetEntity): string {
    return `/${this.environment.apiPrefix}/assets/${asset.id}/content`;
  }

  async readApprovedAsset(
    assetId: string,
    allowedKinds?: AssetKind[],
  ): Promise<{
    asset: AssetEntity;
    body: Buffer;
    mimeType: string;
    byteSize: number;
  }> {
    const asset = await this.requireApprovedAsset(assetId, allowedKinds);
    const stored = await this.assetStorageService.readObject({
      bucket: asset.storageBucket,
      key: asset.storageKey,
    });
    if (!stored) {
      throw new NotFoundException('Stored asset object was not found.');
    }
    return {
      asset,
      body: stored.body,
      mimeType: stored.mimeType?.trim() || asset.mimeType,
      byteSize: stored.byteSize,
    };
  }

  async readApprovedImageAsset(assetId: string) {
    return this.readApprovedAsset(assetId, [AssetKind.Image]);
  }

  async readApprovedAudioAsset(assetId: string) {
    return this.readApprovedAsset(assetId, [AssetKind.Audio]);
  }

  private assertApprovedAsset(asset: AssetEntity): AssetEntity {
    if (asset.kind !== AssetKind.Image) {
      if (asset.kind !== AssetKind.Audio) {
        throw new BadRequestException('Unsupported asset kind.');
      }
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

  private buildObjectKey(kind: AssetKind, fileName: string): string {
    const prefix = kind === AssetKind.Audio ? 'audio' : 'images';
    return `${prefix}/${randomUUID()}/${this.sanitizePathSegment(fileName)}`;
  }

  private normalizeFileName(value: string | undefined): string {
    const normalized = value?.trim();

    if (!normalized) {
      throw new BadRequestException('fileName is required.');
    }

    return normalized;
  }

  private normalizeImageMimeType(value: string | undefined): string {
    const normalized = value?.trim().toLowerCase();

    if (!normalized) {
      throw new BadRequestException('mimeType is required.');
    }

    if (!normalized.startsWith('image/')) {
      throw new BadRequestException('mimeType must be an image media type.');
    }

    return normalized;
  }

  private normalizeAudioMimeType(value: string | undefined): string {
    const normalized = value?.trim().toLowerCase();

    if (!normalized) {
      throw new BadRequestException('mimeType is required.');
    }

    if (!normalized.startsWith('audio/')) {
      throw new BadRequestException('mimeType must be an audio media type.');
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
      url: this.createReadUrl(asset),
    };
  }
}
