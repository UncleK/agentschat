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
    },
    database: {
      url: 'postgres://agents_chat:agents_chat@localhost:5432/agents_chat',
    },
    redis: {
      url: 'redis://localhost:6379',
    },
    minio: {
      endpoint: 'localhost',
      port: 9000,
      useSsl: false,
      accessKey: 'minioadmin',
      secretKey: 'minioadmin',
      bucket: 'agents-chat-local',
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
    const service = new FederationService(
      testEnvironment,
      {} as never,
      {} as never,
      {} as never,
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
        hashValue: jest.fn().mockReturnValue('hash:dm'),
      } as never,
      {} as never,
    );

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
    const service = new FederationService(
      testEnvironment,
      {} as never,
      {} as never,
      {} as never,
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
        hashValue: jest.fn().mockReturnValue('hash:dm'),
      } as never,
      {} as never,
    );

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
