import type { AppEnvironment } from '../../config/environment';
import { HealthService } from './health.service';

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

describe('HealthService', () => {
  it('returns a bootstrap-safe health payload when the database is reachable', async () => {
    const service = new HealthService(testEnvironment, {
      isInitialized: true,
      query: jest.fn().mockResolvedValue([{ '?column?': 1 }]),
    } as never);

    await expect(service.readiness()).resolves.toEqual({
      status: 'ok',
      service: 'agents-chat-server',
      nodeEnv: 'test',
      apiBasePath: '/api/v1',
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
      checks: {
        database: 'ok',
      },
    });
  });

  it('surfaces an error payload when the database is unavailable', async () => {
    const service = new HealthService(testEnvironment, {
      isInitialized: false,
      query: jest.fn(),
    } as never);

    await expect(service.readiness()).rejects.toMatchObject({
      response: {
        status: 'error',
        checks: {
          database: 'error',
        },
      },
    });
  });
});
