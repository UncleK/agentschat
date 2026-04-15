import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  NotImplementedException,
  UnauthorizedException,
} from '@nestjs/common';
import { ModuleRef } from '@nestjs/core';
import { InjectRepository } from '@nestjs/typeorm';
import {
  createHmac,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';
import { Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import { AuthProvider } from '../../database/domain.enums';
import { UserEntity } from '../../database/entities/user.entity';
import { AgentsService } from '../agents/agents.service';
import { AuthenticatedHuman, HumanTokenPayload } from './auth.types';

const scrypt = promisify(scryptCallback);

export interface AuthSessionBootstrapResponse {
  user: {
    id: string;
    email: string;
    username: string;
    displayName: string;
    authProvider: AuthProvider;
    avatarUrl: string | null;
  };
  session: {
    authenticated: true;
  };
  recommendedActiveAgentId: string | null;
}

@Injectable()
export class AuthService {
  private readonly tokenLifetimeMs = 7 * 24 * 60 * 60 * 1000;
  private agentsService: AgentsService | null = null;

  constructor(
    private readonly moduleRef: ModuleRef,
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
  ) {}

  async registerWithEmail(input: {
    email: string;
    username: string;
    displayName: string;
    password: string;
    avatarUrl?: string | null;
  }) {
    const email = this.normalizeEmail(input.email);
    const username = this.normalizeUsername(input.username);
    const displayName = this.normalizeDisplayName(input.displayName);
    const password = this.normalizePassword(input.password);

    const [existingEmailUser, existingUsernameUser] = await Promise.all([
      this.userRepository.findOneBy({ email }),
      this.userRepository.findOneBy({ username }),
    ]);

    if (existingEmailUser) {
      throw new ConflictException(
        `A human account already exists for ${email}.`,
      );
    }
    if (existingUsernameUser) {
      throw new ConflictException(`Username @${username} is already taken.`);
    }

    const user = await this.userRepository.save(
      this.userRepository.create({
        email,
        username,
        displayName,
        passwordHash: await this.hashPassword(password),
        authProvider: AuthProvider.Email,
        avatarUrl: input.avatarUrl?.trim() || null,
      }),
    );

    return this.buildAuthResponse(user);
  }

  async readUsernameAvailability(usernameInput?: string | null) {
    try {
      const normalizedUsername = this.normalizeUsername(usernameInput ?? '');
      const existingUser = await this.userRepository.findOneBy({
        username: normalizedUsername,
      });

      return {
        normalizedUsername,
        available: existingUser == null,
        message:
          existingUser == null
            ? 'Username is available.'
            : `Username @${normalizedUsername} is already taken.`,
      };
    } catch (error) {
      if (error instanceof BadRequestException) {
        return {
          normalizedUsername: this.normalizeUsernameCandidate(usernameInput),
          available: false,
          message: error.message,
        };
      }
      throw error;
    }
  }

  async loginWithEmail(input: { email: string; password: string }) {
    const email = this.normalizeEmail(input.email);
    const password = this.normalizePassword(input.password, false);
    const user = await this.userRepository.findOneBy({ email });

    if (
      !user ||
      user.authProvider !== AuthProvider.Email ||
      !user.passwordHash
    ) {
      throw new UnauthorizedException('Invalid email or password.');
    }

    const passwordMatches = await this.verifyPassword(
      password,
      user.passwordHash,
    );

    if (!passwordMatches) {
      throw new UnauthorizedException('Invalid email or password.');
    }

    return this.buildAuthResponse(user);
  }

  loginWithExternalProvider(input: {
    provider: AuthProvider.Google | AuthProvider.GitHub;
    email: string;
    displayName: string;
    providerSubject: string;
    avatarUrl?: string | null;
  }) {
    void input;
    throw new NotImplementedException(
      'External-provider login is disabled until provider token verification is implemented.',
    );
  }

  async authenticateHumanToken(token: string): Promise<AuthenticatedHuman> {
    const payload = this.verifyToken(token);
    const user = await this.userRepository.findOneBy({ id: payload.sub });

    if (!user) {
      throw new UnauthorizedException(
        'Authenticated human account was not found.',
      );
    }

    return this.toAuthenticatedHuman(user);
  }

  async readSessionBootstrap(
    human: AuthenticatedHuman,
  ): Promise<AuthSessionBootstrapResponse> {
    const [user, eligibleOwnedAgents] = await Promise.all([
      this.userRepository.findOneBy({ id: human.id }),
      this.getAgentsService().findEligibleOwnedAgents(human.id),
    ]);

    if (!user) {
      throw new UnauthorizedException(
        'Authenticated human account was not found.',
      );
    }

    return {
      user: this.toAuthSessionUser(user),
      session: {
        authenticated: true,
      },
      recommendedActiveAgentId: eligibleOwnedAgents[0]?.id ?? null,
    };
  }

  private buildAuthResponse(user: UserEntity) {
    return {
      accessToken: this.signHumanToken(user),
      user: this.toAuthenticatedHuman(user),
    };
  }

  private toAuthenticatedHuman(user: UserEntity): AuthenticatedHuman {
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      displayName: user.displayName,
      authProvider: user.authProvider,
    };
  }

  private toAuthSessionUser(
    user: UserEntity,
  ): AuthSessionBootstrapResponse['user'] {
    return {
      id: user.id,
      email: user.email,
      username: user.username,
      displayName: user.displayName,
      authProvider: user.authProvider,
      avatarUrl: user.avatarUrl,
    };
  }

  private getAgentsService(): AgentsService {
    const agentsService =
      this.agentsService ??
      this.moduleRef.get<AgentsService>(AgentsService, {
        strict: false,
      });

    if (!agentsService) {
      throw new Error('AgentsService provider is not available.');
    }

    this.agentsService = agentsService;

    return agentsService;
  }

  private signHumanToken(user: UserEntity): string {
    const payload: HumanTokenPayload = {
      kind: 'human',
      sub: user.id,
      exp: Date.now() + this.tokenLifetimeMs,
    };
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString(
      'base64url',
    );
    const signature = this.signValue(encodedPayload);

    return `v1.${encodedPayload}.${signature}`;
  }

  private verifyToken(token: string): HumanTokenPayload {
    const parts = token.split('.');
    const [version, encodedPayload, signature] = parts;

    if (
      parts.length !== 3 ||
      version !== 'v1' ||
      !encodedPayload ||
      !signature
    ) {
      throw new UnauthorizedException('Malformed human auth token.');
    }

    const expectedSignature = this.signValue(encodedPayload);

    if (
      expectedSignature.length !== signature.length ||
      !timingSafeEqual(
        Buffer.from(expectedSignature, 'utf8'),
        Buffer.from(signature, 'utf8'),
      )
    ) {
      throw new UnauthorizedException('Invalid human auth token signature.');
    }

    let payload: HumanTokenPayload;

    try {
      payload = JSON.parse(
        Buffer.from(encodedPayload, 'base64url').toString('utf8'),
      ) as HumanTokenPayload;
    } catch {
      throw new UnauthorizedException('Malformed human auth token.');
    }

    if (payload.kind !== 'human' || !payload.sub || payload.exp <= Date.now()) {
      throw new UnauthorizedException(
        'Human auth token is expired or invalid.',
      );
    }

    return payload;
  }

  private signValue(value: string): string {
    return createHmac('sha256', this.environment.auth.jwtSecret)
      .update(value)
      .digest('hex');
  }

  private async hashPassword(password: string): Promise<string> {
    const salt = randomBytes(16).toString('hex');
    const derivedKey = (await scrypt(password, salt, 64)) as Buffer;

    return `${salt}:${derivedKey.toString('hex')}`;
  }

  private async verifyPassword(
    password: string,
    storedHash: string,
  ): Promise<boolean> {
    const [salt, expectedHash] = storedHash.split(':');

    if (!salt || !expectedHash) {
      return false;
    }

    const derivedKey = (await scrypt(password, salt, 64)) as Buffer;
    const actualHash = derivedKey.toString('hex');

    if (actualHash.length !== expectedHash.length) {
      return false;
    }

    return timingSafeEqual(
      Buffer.from(actualHash, 'utf8'),
      Buffer.from(expectedHash, 'utf8'),
    );
  }

  private normalizeEmail(email: string): string {
    const normalized = email?.trim().toLowerCase();

    if (!normalized) {
      throw new BadRequestException('email is required.');
    }

    return normalized;
  }

  private normalizeDisplayName(displayName: string): string {
    const normalized = displayName?.trim();

    if (!normalized) {
      throw new BadRequestException('displayName is required.');
    }

    return normalized;
  }

  private normalizeUsername(username: string): string {
    const normalized = this.normalizeUsernameCandidate(username);

    if (!normalized) {
      throw new BadRequestException('username is required.');
    }
    if (normalized.length < 3 || normalized.length > 24) {
      throw new BadRequestException(
        'username must be between 3 and 24 characters long.',
      );
    }
    if (!new RegExp('^[a-z0-9_]+$').test(normalized)) {
      throw new BadRequestException(
        'username may only contain lowercase letters, numbers, and underscores.',
      );
    }

    return normalized;
  }

  private normalizeUsernameCandidate(
    username: string | null | undefined,
  ): string {
    const normalized = username?.trim().toLowerCase() ?? '';
    if (normalized.startsWith('@')) {
      return normalized.substring(1);
    }
    return normalized;
  }

  private normalizePassword(password: string, requireLength = true): string {
    const normalized = password?.trim();

    if (!normalized) {
      throw new BadRequestException('password is required.');
    }

    if (requireLength && normalized.length < 8) {
      throw new BadRequestException(
        'password must be at least 8 characters long.',
      );
    }

    return normalized;
  }
}
