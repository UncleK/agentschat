import type { Repository } from 'typeorm';
import type { AppEnvironment } from '../../config/environment';
import {
  AssetKind,
  AssetModerationStatus,
  AssetUploadStatus,
} from '../../database/domain.enums';
import type { AssetEntity } from '../../database/entities/asset.entity';
import { AssetStorageService } from './asset-storage.service';
import { AssetsService } from './assets.service';
import { ImageModerationService } from './image-moderation.service';

function buildEnvironment(): AppEnvironment {
  return {
    nodeEnv: 'test',
    serviceName: 'agents-chat-server',
    port: 3000,
    apiPrefix: 'api/v1',
    auth: {
      jwtSecret: 'test-secret',
      operatorToken: 'test-operator-token',
      emailVerificationCodeTtlSeconds: 600,
      passwordResetCodeTtlSeconds: 900,
      emailCodeCooldownSeconds: 60,
    },
    mail: {
      deliveryMode: 'log',
      fromAddress: 'Agents Chat <test@example.com>',
      resendApiKey: null,
    },
    database: {
      url: 'postgres://agents_chat:agents_chat@localhost:5432/agents_chat',
    },
    redis: {
      url: 'redis://localhost:6379',
    },
    presence: {
      staleAfterSeconds: 180,
      sweepIntervalSeconds: 30,
    },
    minio: {
      endpoint: 'localhost',
      port: 9000,
      useSsl: false,
      accessKey: 'minioadmin',
      secretKey: 'minioadmin',
      bucket: 'agents-chat-local',
    },
    speech: {
      agentCantSecret: 'test-agent-cant-secret',
      pythonBin: 'python',
      modelSize: 'small',
      device: 'cpu',
      computeType: 'int8',
      timeoutMs: 90_000,
      maxUploadBytes: 10 * 1024 * 1024,
      maxDurationSeconds: 60,
      ffmpegBin: 'ffmpeg',
      modelDir: null,
    },
    transport: {
      appRealtime: {
        transport: 'websocket',
        path: '/ws',
      },
      federation: {
        transport: 'http',
        claimPath: '/api/v1/agents/claim',
        actionsPath: '/api/v1/actions',
        pollingPath: '/api/v1/deliveries/poll',
        acksPath: '/api/v1/acks',
      },
    },
  };
}

describe('AssetsService', () => {
  it('creates approved generated audio assets and stores bytes under the audio prefix', async () => {
    const savedAsset = {
      id: 'asset-1',
      kind: AssetKind.Audio,
      createdByUserId: null,
      originalFileName: 'message.wav',
      mimeType: 'audio/wav',
      uploadStatus: AssetUploadStatus.Uploaded,
      moderationStatus: AssetModerationStatus.Approved,
      moderationReason: null,
      storageBucket: 'agents-chat-local',
      storageKey: 'audio/generated/message.wav',
      byteSize: 4,
      uploadUrlExpiresAt: new Date('2026-04-25T00:00:00.000Z'),
      completedAt: new Date('2026-04-25T00:00:00.000Z'),
      metadata: {
        codec: 'agentscant',
      },
    } as AssetEntity;
    const assetRepository = {
      create: jest.fn((value: object) => value),
      save: jest.fn().mockResolvedValue(savedAsset),
    } as unknown as Repository<AssetEntity>;
    const assetStorageService = {
      writeObject: jest.fn().mockResolvedValue(undefined),
    } as unknown as AssetStorageService;
    const imageModerationService = {
      moderate: jest.fn(),
    } as unknown as ImageModerationService;
    const service = new AssetsService(
      buildEnvironment(),
      assetRepository,
      assetStorageService,
      imageModerationService,
    );

    const result = await service.createGeneratedAudioAsset({
      fileName: 'message.wav',
      mimeType: 'audio/wav',
      bytes: Buffer.from([1, 2, 3, 4]),
      metadata: {
        codec: 'agentscant',
      },
    });

    expect(assetStorageService.writeObject).toHaveBeenCalledWith(
      expect.objectContaining({
        bucket: 'agents-chat-local',
        mimeType: 'audio/wav',
        body: Buffer.from([1, 2, 3, 4]),
        key: expect.stringMatching(/^audio\//),
      }),
    );
    expect(assetRepository.save).toHaveBeenCalledWith(
      expect.objectContaining({
        kind: AssetKind.Audio,
        uploadStatus: AssetUploadStatus.Uploaded,
        moderationStatus: AssetModerationStatus.Approved,
        byteSize: 4,
      }),
    );
    expect(result).toBe(savedAsset);
  });

  it('reads approved audio assets through the generalized asset reader', async () => {
    const storedAsset = {
      id: 'asset-1',
      kind: AssetKind.Audio,
      createdByUserId: null,
      originalFileName: 'message.wav',
      mimeType: 'audio/wav',
      uploadStatus: AssetUploadStatus.Uploaded,
      moderationStatus: AssetModerationStatus.Approved,
      moderationReason: null,
      storageBucket: 'agents-chat-local',
      storageKey: 'audio/generated/message.wav',
      byteSize: 4,
      uploadUrlExpiresAt: new Date('2026-04-25T00:00:00.000Z'),
      completedAt: new Date('2026-04-25T00:00:00.000Z'),
      metadata: {},
    } as AssetEntity;
    const assetRepository = {
      findOneBy: jest.fn().mockResolvedValue(storedAsset),
    } as unknown as Repository<AssetEntity>;
    const assetStorageService = {
      readObject: jest.fn().mockResolvedValue({
        body: Buffer.from([1, 2, 3, 4]),
        mimeType: 'audio/wav',
        byteSize: 4,
      }),
    } as unknown as AssetStorageService;
    const imageModerationService = {
      moderate: jest.fn(),
    } as unknown as ImageModerationService;
    const service = new AssetsService(
      buildEnvironment(),
      assetRepository,
      assetStorageService,
      imageModerationService,
    );

    const result = await service.readApprovedAudioAsset('asset-1');

    expect(assetRepository.findOneBy).toHaveBeenCalledWith({ id: 'asset-1' });
    expect(assetStorageService.readObject).toHaveBeenCalledWith({
      bucket: 'agents-chat-local',
      key: 'audio/generated/message.wav',
    });
    expect(result).toEqual({
      asset: storedAsset,
      body: Buffer.from([1, 2, 3, 4]),
      mimeType: 'audio/wav',
      byteSize: 4,
    });
  });
});
