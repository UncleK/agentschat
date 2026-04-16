import { NotImplementedException, UnauthorizedException } from '@nestjs/common';
/* eslint-disable @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-return, @typescript-eslint/require-await */
import { ModuleRef } from '@nestjs/core';
import { Repository } from 'typeorm';
import {
  AuthEmailCodePurpose,
  AuthProvider,
} from '../../database/domain.enums';
import { AuthEmailCodeEntity } from '../../database/entities/auth-email-code.entity';
import { UserEntity } from '../../database/entities/user.entity';
import type { AppEnvironment } from '../../config/environment';
import { AuthEmailDeliveryService } from './auth-email-delivery.service';
import { AuthenticatedHuman } from './auth.types';
import { AuthService } from './auth.service';

type PrivateAuthService = AuthService & {
  hashPassword(password: string): Promise<string>;
  signHumanToken(user: UserEntity): string;
  signValue(value: string): string;
};

describe('AuthService', () => {
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
      fromAddress: 'Agents Chat <no-reply@example.com>',
      resendApiKey: null,
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
    const harness = createHarness();
    const encodedPayload = Buffer.from('{').toString('base64url');
    const signature = harness.service.signValue(encodedPayload);

    await expect(
      harness.service.authenticateHumanToken(
        `v1.${encodedPayload}.${signature}`,
      ),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('rejects human tokens with extra dot-separated segments', async () => {
    const harness = createHarness();
    const encodedPayload = Buffer.from(
      JSON.stringify({
        kind: 'human',
        sub: 'user-1',
        exp: Date.now() + 60_000,
      }),
    ).toString('base64url');
    const signature = harness.service.signValue(encodedPayload);

    await expect(
      harness.service.authenticateHumanToken(
        `v1.${encodedPayload}.${signature}.extra`,
      ),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('treats a corrupted stored password hash as invalid credentials', async () => {
    const harness = createHarness();
    harness.addUser({
      id: 'user-1',
      email: 'owner@example.com',
      username: 'owner_user',
      displayName: 'Owner',
      authProvider: AuthProvider.Email,
      passwordHash: 'broken-salt:short',
    });

    await expect(
      harness.service.loginWithEmail({
        email: 'owner@example.com',
        password: 'password123',
      }),
    ).rejects.toThrow(UnauthorizedException);
  });

  it('keeps external-provider login disabled until real provider verification exists', () => {
    const harness = createHarness();

    expect(() =>
      harness.service.loginWithExternalProvider({
        provider: AuthProvider.Google,
        email: 'google-user@example.com',
        displayName: 'Google User',
        providerSubject: 'google-subject-1',
      }),
    ).toThrow(NotImplementedException);
  });

  it('normalizes username availability checks and reports taken usernames without throwing', async () => {
    const harness = createHarness();
    harness.addUser({
      id: 'user-1',
      email: 'owner@example.com',
      username: 'owner_user',
      displayName: 'Owner',
      authProvider: AuthProvider.Email,
    });

    await expect(
      harness.service.readUsernameAvailability('@owner_user'),
    ).resolves.toEqual({
      normalizedUsername: 'owner_user',
      available: false,
      message: 'Username @owner_user is already taken.',
    });

    await expect(
      harness.service.readUsernameAvailability('@fresh_user'),
    ).resolves.toEqual({
      normalizedUsername: 'fresh_user',
      available: true,
      message: 'Username is available.',
    });
  });

  it('resets the password, verifies the email, and invalidates previously issued tokens', async () => {
    const harness = createHarness();
    const user = harness.addUser({
      id: 'user-1',
      email: 'owner@example.com',
      username: 'owner_user',
      displayName: 'Owner',
      authProvider: AuthProvider.Email,
      passwordHash: await harness.service.hashPassword('password123'),
    });
    const oldToken = harness.service.signHumanToken(user);

    await expect(
      harness.service.requestPasswordResetCode({
        email: 'owner@example.com',
      }),
    ).resolves.toEqual({
      message:
        'If an email/password account exists for this address, a password reset code has been sent.',
    });

    expect(harness.passwordResetCode).toMatch(/^\d{6}$/);

    await expect(
      harness.service.confirmPasswordReset({
        email: 'owner@example.com',
        code: harness.passwordResetCode!,
        newPassword: 'newpassword123',
      }),
    ).resolves.toEqual({
      message: 'Password updated. Sign in with your new password.',
    });

    expect(user.authTokenVersion).toBe(1);
    expect(user.emailVerifiedAt).toBeInstanceOf(Date);

    await expect(
      harness.service.authenticateHumanToken(oldToken),
    ).rejects.toThrow(UnauthorizedException);

    await expect(
      harness.service.loginWithEmail({
        email: 'owner@example.com',
        password: 'newpassword123',
      }),
    ).resolves.toMatchObject({
      user: {
        id: 'user-1',
        emailVerified: true,
      },
    });
  });

  it('sends and confirms a 6-digit email verification code for the current email account', async () => {
    const harness = createHarness();
    const user = harness.addUser({
      id: 'user-1',
      email: 'owner@example.com',
      username: 'owner_user',
      displayName: 'Owner',
      authProvider: AuthProvider.Email,
      passwordHash: await harness.service.hashPassword('password123'),
    });

    await expect(
      harness.service.requestEmailVerificationCode(
        authenticatedHumanFromUser(user),
      ),
    ).resolves.toEqual({
      message: 'Verification code sent to owner@example.com.',
    });

    expect(harness.verificationCode).toMatch(/^\d{6}$/);

    await expect(
      harness.service.confirmEmailVerificationCode(
        authenticatedHumanFromUser(user),
        { code: harness.verificationCode! },
      ),
    ).resolves.toEqual({
      message: 'Email verified.',
    });

    expect(user.emailVerifiedAt).toBeInstanceOf(Date);
  });

  it('keeps password reset requests generic when the email account does not exist', async () => {
    const harness = createHarness();

    await expect(
      harness.service.requestPasswordResetCode({
        email: 'missing@example.com',
      }),
    ).resolves.toEqual({
      message:
        'If an email/password account exists for this address, a password reset code has been sent.',
    });

    expect(harness.passwordResetCode).toBeNull();
    expect(harness.mailer.sendPasswordResetCode).not.toHaveBeenCalled();
  });

  function createHarness() {
    const usersById = new Map<string, UserEntity>();
    const usersByEmail = new Map<string, UserEntity>();
    let savedCode: AuthEmailCodeEntity | null = null;
    let passwordResetCode: string | null = null;
    let verificationCode: string | null = null;

    const mailer = {
      assertInteractiveDeliveryAvailable: jest.fn(),
      sendPasswordResetCode: jest.fn(async ({ code }: { code: string }) => {
        passwordResetCode = code;
      }),
      sendEmailVerificationCode: jest.fn(async ({ code }: { code: string }) => {
        verificationCode = code;
      }),
    } as unknown as AuthEmailDeliveryService & {
      sendPasswordResetCode: jest.Mock;
      sendEmailVerificationCode: jest.Mock;
    };

    const userRepository = {
      create: jest.fn((input: Partial<UserEntity>) => {
        const entity = new UserEntity();
        Object.assign(entity, {
          authTokenVersion: 0,
          avatarUrl: null,
          emailVerifiedAt: null,
          passwordHash: null,
          ...input,
        });
        return entity;
      }),
      save: jest.fn(async (input: UserEntity) => {
        input.id ??= `user-${usersById.size + 1}`;
        input.authTokenVersion ??= 0;
        input.avatarUrl ??= null;
        input.emailVerifiedAt ??= null;
        usersById.set(input.id, input);
        usersByEmail.set(input.email, input);
        return input;
      }),
      findOneBy: jest.fn(
        async (
          criteria: Partial<Record<'id' | 'email' | 'username', string>>,
        ) => {
          if (criteria.id) {
            return usersById.get(criteria.id) ?? null;
          }
          if (criteria.email) {
            return usersByEmail.get(criteria.email) ?? null;
          }
          if (criteria.username) {
            for (const user of usersById.values()) {
              if (user.username === criteria.username) {
                return user;
              }
            }
          }
          return null;
        },
      ),
    } as unknown as Repository<UserEntity>;

    const codeRepository = {
      create: jest.fn((input: Partial<AuthEmailCodeEntity>) => {
        const entity = new AuthEmailCodeEntity();
        Object.assign(entity, {
          id: savedCode?.id ?? 'code-1',
          attemptCount: 0,
          consumedAt: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          ...input,
        });
        return entity;
      }),
      save: jest.fn(
        async (input: AuthEmailCodeEntity | AuthEmailCodeEntity[]) => {
          if (Array.isArray(input)) {
            if (input.length > 0) {
              savedCode = input[input.length - 1];
            }
            return input;
          }
          input.id ??= 'code-1';
          input.createdAt ??= new Date();
          input.updatedAt = new Date();
          savedCode = input;
          return input;
        },
      ),
      findOne: jest.fn(
        async ({
          where,
        }: {
          where: {
            email?: string;
            purpose?: AuthEmailCodePurpose;
            userId?: string;
          };
        }) => {
          if (!savedCode) {
            return null;
          }

          if (where.email && savedCode.email !== where.email) {
            return null;
          }
          if (where.purpose && savedCode.purpose !== where.purpose) {
            return null;
          }
          if (where.userId && savedCode.userId !== where.userId) {
            return null;
          }
          if (savedCode.consumedAt != null) {
            return null;
          }
          if (savedCode.expiresAt.getTime() <= Date.now()) {
            return null;
          }

          return savedCode;
        },
      ),
      find: jest.fn(
        async ({
          where,
        }: {
          where: {
            email?: string;
            purpose?: AuthEmailCodePurpose;
            userId?: string;
          };
        }) => {
          const found = await (
            codeRepository.findOne as unknown as (input: {
              where: {
                email?: string;
                purpose?: AuthEmailCodePurpose;
                userId?: string;
              };
            }) => Promise<AuthEmailCodeEntity | null>
          )({ where });
          return found ? [found] : [];
        },
      ),
      delete: jest.fn(async ({ id }: { id: string }) => {
        if (savedCode?.id === id) {
          savedCode = null;
        }
      }),
    } as unknown as Repository<AuthEmailCodeEntity>;

    const service = new AuthService(
      { get: jest.fn() } as unknown as ModuleRef,
      testEnvironment,
      userRepository,
      codeRepository,
      mailer,
    ) as PrivateAuthService;

    return {
      service,
      mailer: mailer as AuthEmailDeliveryService & {
        sendPasswordResetCode: jest.Mock;
        sendEmailVerificationCode: jest.Mock;
      },
      addUser(
        input: Partial<UserEntity> &
          Pick<
            UserEntity,
            'id' | 'email' | 'username' | 'displayName' | 'authProvider'
          >,
      ) {
        const user = new UserEntity();
        Object.assign(user, {
          avatarUrl: null,
          emailVerifiedAt: null,
          authTokenVersion: 0,
          passwordHash: null,
          ...input,
        });
        usersById.set(user.id, user);
        usersByEmail.set(user.email, user);
        return user;
      },
      get savedCode() {
        return savedCode;
      },
      get passwordResetCode() {
        return passwordResetCode;
      },
      get verificationCode() {
        return verificationCode;
      },
    };
  }

  function authenticatedHumanFromUser(user: UserEntity): AuthenticatedHuman {
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      displayName: user.displayName,
      authProvider: user.authProvider,
      avatarUrl: user.avatarUrl,
      emailVerified: user.emailVerifiedAt != null,
    };
  }
});
