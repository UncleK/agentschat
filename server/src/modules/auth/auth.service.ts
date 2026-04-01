import {
  BadRequestException,
  ConflictException,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import {
  createHmac,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';
import { Repository } from 'typeorm';
import {
  APP_ENVIRONMENT,
  type AppEnvironment,
} from '../../config/environment';
import { AuthProvider } from '../../database/domain.enums';
import { UserEntity } from '../../database/entities/user.entity';
import { AuthenticatedHuman, HumanTokenPayload } from './auth.types';

const scrypt = promisify(scryptCallback);

@Injectable()
export class AuthService {
  private readonly tokenLifetimeMs = 7 * 24 * 60 * 60 * 1000;

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
  ) {}

  async registerWithEmail(input: {
    email: string;
    displayName: string;
    password: string;
    avatarUrl?: string | null;
  }) {
    const email = this.normalizeEmail(input.email);
    const displayName = this.normalizeDisplayName(input.displayName);
    const password = this.normalizePassword(input.password);

    const existingUser = await this.userRepository.findOneBy({ email });

    if (existingUser) {
      throw new ConflictException(`A human account already exists for ${email}.`);
    }

    const user = await this.userRepository.save(
      this.userRepository.create({
        email,
        displayName,
        passwordHash: await this.hashPassword(password),
        authProvider: AuthProvider.Email,
        avatarUrl: input.avatarUrl?.trim() || null,
      }),
    );

    return this.buildAuthResponse(user);
  }

  async loginWithEmail(input: { email: string; password: string }) {
    const email = this.normalizeEmail(input.email);
    const password = this.normalizePassword(input.password, false);
    const user = await this.userRepository.findOneBy({ email });

    if (!user || user.authProvider !== AuthProvider.Email || !user.passwordHash) {
      throw new UnauthorizedException('Invalid email or password.');
    }

    const passwordMatches = await this.verifyPassword(password, user.passwordHash);

    if (!passwordMatches) {
      throw new UnauthorizedException('Invalid email or password.');
    }

    return this.buildAuthResponse(user);
  }

  async loginWithExternalProvider(input: {
    provider: AuthProvider.Google | AuthProvider.GitHub;
    email: string;
    displayName: string;
    providerSubject: string;
    avatarUrl?: string | null;
  }) {
    const email = this.normalizeEmail(input.email);
    const displayName = this.normalizeDisplayName(input.displayName);
    const providerSubject = input.providerSubject?.trim();

    if (!providerSubject) {
      throw new BadRequestException('providerSubject is required.');
    }

    const existingUser = await this.userRepository.findOneBy({ email });

    if (existingUser) {
      if (existingUser.authProvider !== input.provider) {
        throw new ConflictException(
          `The email ${email} is already registered with a different auth provider.`,
        );
      }

      if (existingUser.providerSubject !== providerSubject) {
        throw new UnauthorizedException(
          'The external provider subject does not match the stored account.',
        );
      }

      existingUser.displayName = displayName;
      existingUser.avatarUrl = input.avatarUrl?.trim() || null;

      const updatedUser = await this.userRepository.save(existingUser);
      return this.buildAuthResponse(updatedUser);
    }

    const user = await this.userRepository.save(
      this.userRepository.create({
        email,
        displayName,
        authProvider: input.provider,
        providerSubject,
        avatarUrl: input.avatarUrl?.trim() || null,
      }),
    );

    return this.buildAuthResponse(user);
  }

  async authenticateHumanToken(token: string): Promise<AuthenticatedHuman> {
    const payload = this.verifyToken(token);
    const user = await this.userRepository.findOneBy({ id: payload.sub });

    if (!user) {
      throw new UnauthorizedException('Authenticated human account was not found.');
    }

    return this.toAuthenticatedHuman(user);
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
      displayName: user.displayName,
      authProvider: user.authProvider,
    };
  }

  private signHumanToken(user: UserEntity): string {
    const payload: HumanTokenPayload = {
      kind: 'human',
      sub: user.id,
      exp: Date.now() + this.tokenLifetimeMs,
    };
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signature = this.signValue(encodedPayload);

    return `v1.${encodedPayload}.${signature}`;
  }

  private verifyToken(token: string): HumanTokenPayload {
    const [version, encodedPayload, signature] = token.split('.');

    if (version !== 'v1' || !encodedPayload || !signature) {
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

    const payload = JSON.parse(
      Buffer.from(encodedPayload, 'base64url').toString('utf8'),
    ) as HumanTokenPayload;

    if (payload.kind !== 'human' || !payload.sub || payload.exp <= Date.now()) {
      throw new UnauthorizedException('Human auth token is expired or invalid.');
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

  private normalizePassword(password: string, requireLength = true): string {
    const normalized = password?.trim();

    if (!normalized) {
      throw new BadRequestException('password is required.');
    }

    if (requireLength && normalized.length < 8) {
      throw new BadRequestException('password must be at least 8 characters long.');
    }

    return normalized;
  }
}
