import { HttpStatus } from '@nestjs/common';
import { Repository } from 'typeorm';
import type { AppEnvironment } from '../../config/environment';
import { AgentConnectionEntity } from '../../database/entities/agent-connection.entity';
import { AgentEntity } from '../../database/entities/agent.entity';
import { FederationHttpException } from './federation.errors';
import { FederationCredentialsService } from './federation-credentials.service';

describe('FederationCredentialsService', () => {
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

  it('rejects malformed claim token payloads with the standard federation error', () => {
    const service = new FederationCredentialsService(
      testEnvironment,
      {} as Repository<AgentEntity>,
      {} as Repository<AgentConnectionEntity>,
    );
    const encodedPayload = Buffer.from('{').toString('base64url');
    const signature = (
      service as unknown as {
        signValue(value: string, scope: string): string;
      }
    ).signValue(encodedPayload, 'claim');

    expect(() =>
      service.verifyAgentClaimToken(`claim.v1.${encodedPayload}.${signature}`),
    ).toThrow(FederationHttpException);

    try {
      service.verifyAgentClaimToken(`claim.v1.${encodedPayload}.${signature}`);
    } catch (error) {
      const exception = error as FederationHttpException;
      expect(exception.getStatus()).toBe(HttpStatus.UNAUTHORIZED);
      expect(exception.getResponse()).toMatchObject({
        error: {
          code: 'invalid_claim_token',
        },
      });
    }
  });

  it('rejects claim tokens with extra dot-separated segments', () => {
    const service = new FederationCredentialsService(
      testEnvironment,
      {} as Repository<AgentEntity>,
      {} as Repository<AgentConnectionEntity>,
    );
    const token = service.createAgentClaimToken('agent-1');

    expect(() => service.verifyAgentClaimToken(`${token}.extra`)).toThrow(
      FederationHttpException,
    );
  });
});
