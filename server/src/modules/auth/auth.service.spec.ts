import { NotImplementedException, UnauthorizedException } from '@nestjs/common';
import { ModuleRef } from '@nestjs/core';
import { Repository } from 'typeorm';
import { AuthProvider } from '../../database/domain.enums';
import { UserEntity } from '../../database/entities/user.entity';
import type { AppEnvironment } from '../../config/environment';
import { AuthService } from './auth.service';

describe('AuthService', () => {
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

  it('rejects malformed signed human tokens with a 401 instead of a runtime error', async () => {
    const userRepository = {
      findOneBy: jest.fn(),
    } as unknown as Repository<UserEntity>;
    const service = new AuthService(
      { get: jest.fn() } as unknown as ModuleRef,
      testEnvironment,
      userRepository,
    );
    const encodedPayload = Buffer.from('{').toString('base64url');
    const signature = (
      service as unknown as {
        signValue(value: string): string;
      }
    ).signValue(encodedPayload);

    await expect(
      service.authenticateHumanToken(`v1.${encodedPayload}.${signature}`),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('rejects human tokens with extra dot-separated segments', async () => {
    const userRepository = {
      findOneBy: jest.fn(),
    } as unknown as Repository<UserEntity>;
    const service = new AuthService(
      { get: jest.fn() } as unknown as ModuleRef,
      testEnvironment,
      userRepository,
    );
    const encodedPayload = Buffer.from(
      JSON.stringify({
        kind: 'human',
        sub: 'user-1',
        exp: Date.now() + 60_000,
      }),
    ).toString('base64url');
    const signature = (
      service as unknown as {
        signValue(value: string): string;
      }
    ).signValue(encodedPayload);

    await expect(
      service.authenticateHumanToken(`v1.${encodedPayload}.${signature}.extra`),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('treats a corrupted stored password hash as invalid credentials', async () => {
    const userRepository = {
      findOneBy: jest.fn().mockResolvedValue({
        id: 'user-1',
        email: 'owner@example.com',
        displayName: 'Owner',
        authProvider: AuthProvider.Email,
        passwordHash: 'broken-salt:short',
      }),
    } as unknown as Repository<UserEntity>;
    const service = new AuthService(
      { get: jest.fn() } as unknown as ModuleRef,
      testEnvironment,
      userRepository,
    );

    await expect(
      service.loginWithEmail({
        email: 'owner@example.com',
        password: 'password123',
      }),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('keeps external-provider login disabled until real provider verification exists', () => {
    const userRepository = {
      findOneBy: jest.fn(),
      save: jest.fn(),
      create: jest.fn(),
    } as unknown as Repository<UserEntity>;
    const service = new AuthService(
      { get: jest.fn() } as unknown as ModuleRef,
      testEnvironment,
      userRepository,
    );

    expect(() =>
      service.loginWithExternalProvider({
        provider: AuthProvider.Google,
        email: 'google-user@example.com',
        displayName: 'Google User',
        providerSubject: 'google-subject-1',
      }),
    ).toThrow(NotImplementedException);
  });
});
