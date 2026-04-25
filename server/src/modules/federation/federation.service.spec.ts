import { QueryFailedError, Repository } from 'typeorm';
import {
  ConnectionTransportMode,
  FederationActionStatus,
} from '../../database/domain.enums';
import { FederationActionEntity } from '../../database/entities/federation-action.entity';
import type { AppEnvironment } from '../../config/environment';
import { FederationHttpException } from './federation.errors';
import { FederationService } from './federation.service';

describe('FederationService', () => {
  const testEnvironment: AppEnvironment = {
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
      agentCantSecret: 'dev-agent-cant-secret',
      pythonBin: 'python',
      modelSize: 'small',
      device: 'cpu',
      computeType: 'int8',
      timeoutMs: 90000,
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

  function createService(
    federationActionRepository: Repository<FederationActionEntity>,
    requestHash: string,
  ) {
    const agentRepository = {
      findOneBy: jest.fn().mockResolvedValue({
        id: 'agent-1',
        status: 'online',
      }),
      save: jest.fn().mockImplementation(async (value: unknown) => value),
    } as unknown as Repository<never>;
    const agentConnectionRepository = {
      findOneBy: jest.fn().mockResolvedValue({
        id: 'connection-1',
        agentId: 'agent-1',
      }),
      save: jest.fn().mockImplementation(async (value: unknown) => value),
    } as unknown as Repository<never>;

    return new FederationService(
      testEnvironment,
      {} as never,
      agentRepository,
      agentConnectionRepository,
      federationActionRepository,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      {
        hashValue: jest.fn().mockReturnValue(requestHash),
      } as never,
      {} as never,
    );
  }

  it('returns the existing action when the idempotency insert loses a unique-key race', async () => {
    const existingAction = {
      id: 'action-1',
      actionType: 'dm.send',
      status: FederationActionStatus.Accepted,
      acceptedAt: new Date('2026-04-09T00:00:00.000Z'),
      processingStartedAt: null,
      completedAt: null,
      threadId: null,
      eventId: null,
      resultPayload: {},
      errorPayload: null,
      requestHash: 'hash:dm',
      idempotencyKey: 'same-key',
      agentId: 'agent-1',
    } as FederationActionEntity;
    const federationActionRepository = {
      findOneBy: jest
        .fn()
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce(existingAction),
      create: jest.fn((value: object) => value),
      save: jest.fn().mockRejectedValue(
        new QueryFailedError('INSERT', [], {
          code: '23505',
          constraint: 'IDX_federation_actions_agent_idempotency_unique',
        }),
      ),
    } as unknown as Repository<FederationActionEntity>;
    const service = createService(federationActionRepository, 'hash:dm');

    await expect(
      service.submitAction(
        {
          id: 'agent-1',
          handle: 'agent',
          connectionId: 'connection-1',
          transportMode: ConnectionTransportMode.Polling,
          pollingEnabled: true,
        },
        'same-key',
        {
          type: 'dm.send',
          payload: {},
        },
      ),
    ).resolves.toMatchObject({
      created: false,
      action: {
        id: 'action-1',
      },
    });
  });

  it('returns 409 when the recovered idempotent action payload does not match', async () => {
    const federationActionRepository = {
      findOneBy: jest.fn().mockResolvedValueOnce(null).mockResolvedValueOnce({
        id: 'action-1',
        requestHash: 'hash:other',
      }),
      create: jest.fn((value: object) => value),
      save: jest.fn().mockRejectedValue(
        new QueryFailedError('INSERT', [], {
          code: '23505',
          constraint: 'IDX_federation_actions_agent_idempotency_unique',
        }),
      ),
    } as unknown as Repository<FederationActionEntity>;
    const service = createService(federationActionRepository, 'hash:dm');

    await expect(
      service.submitAction(
        {
          id: 'agent-1',
          handle: 'agent',
          connectionId: 'connection-1',
          transportMode: ConnectionTransportMode.Polling,
          pollingEnabled: true,
        },
        'same-key',
        {
          type: 'dm.send',
          payload: {},
        },
      ),
    ).rejects.toBeInstanceOf(FederationHttpException);
  });
});
