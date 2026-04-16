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
  randomInt,
  scrypt as scryptCallback,
  timingSafeEqual,
} from 'node:crypto';
import { promisify } from 'node:util';
import { FindOptionsWhere, IsNull, MoreThan, Repository } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import {
  AuthEmailCodePurpose,
  AuthProvider,
} from '../../database/domain.enums';
import { AuthEmailCodeEntity } from '../../database/entities/auth-email-code.entity';
import { UserEntity } from '../../database/entities/user.entity';
import { AgentsService } from '../agents/agents.service';
import { AuthEmailDeliveryService } from './auth-email-delivery.service';
import { AuthenticatedHuman, HumanTokenPayload } from './auth.types';

const scrypt = promisify(scryptCallback);

export interface AuthOperationResponse {
  message: string;
}

export interface AuthSessionBootstrapResponse {
  user: {
    id: string;
    email: string;
    username: string;
    displayName: string;
    authProvider: AuthProvider;
    avatarUrl: string | null;
    emailVerified: boolean;
  };
  session: {
    authenticated: true;
  };
  recommendedActiveAgentId: string | null;
}

@Injectable()
export class AuthService {
  private readonly tokenLifetimeMs = 7 * 24 * 60 * 60 * 1000;
  private readonly emailCodeLength = 6;
  private readonly maxEmailCodeAttempts = 5;
  private agentsService: AgentsService | null = null;

  constructor(
    private readonly moduleRef: ModuleRef,
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectRepository(UserEntity)
    private readonly userRepository: Repository<UserEntity>,
    @InjectRepository(AuthEmailCodeEntity)
    private readonly emailCodeRepository: Repository<AuthEmailCodeEntity>,
    private readonly authEmailDeliveryService: AuthEmailDeliveryService,
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

  async requestEmailVerificationCode(
    human: AuthenticatedHuman,
  ): Promise<AuthOperationResponse> {
    this.authEmailDeliveryService.assertInteractiveDeliveryAvailable();

    const user = await this.requireCurrentUser(human);
    this.ensureEmailPasswordUser(
      user,
      'Email verification is only available for email/password accounts.',
    );

    if (user.emailVerifiedAt) {
      return {
        message: 'Email is already verified.',
      };
    }

    const remainingSeconds = await this.readCodeCooldownRemainingSeconds({
      email: user.email,
      purpose: AuthEmailCodePurpose.EmailVerification,
      userId: user.id,
    });

    if (remainingSeconds > 0) {
      throw new BadRequestException(
        `A verification code was already sent. Try again in ${remainingSeconds} seconds.`,
      );
    }

    return this.createAndSendEmailCode({
      user,
      purpose: AuthEmailCodePurpose.EmailVerification,
      ttlSeconds: this.environment.auth.emailVerificationCodeTtlSeconds,
      successMessage: `Verification code sent to ${user.email}.`,
      send: (code, expiresInMinutes) =>
        this.authEmailDeliveryService.sendEmailVerificationCode({
          to: user.email,
          code,
          expiresInMinutes,
        }),
    });
  }

  async confirmEmailVerificationCode(
    human: AuthenticatedHuman,
    input: { code: string },
  ): Promise<AuthOperationResponse> {
    const user = await this.requireCurrentUser(human);
    this.ensureEmailPasswordUser(
      user,
      'Email verification is only available for email/password accounts.',
    );

    if (user.emailVerifiedAt) {
      return {
        message: 'Email is already verified.',
      };
    }

    const emailCode = await this.requireValidEmailCode({
      email: user.email,
      purpose: AuthEmailCodePurpose.EmailVerification,
      userId: user.id,
      code: input.code,
      invalidMessage: 'Invalid or expired verification code.',
    });

    user.emailVerifiedAt = new Date();
    await Promise.all([
      this.userRepository.save(user),
      this.consumeEmailCode(emailCode),
    ]);

    return {
      message: 'Email verified.',
    };
  }

  async requestPasswordResetCode(input: {
    email: string;
  }): Promise<AuthOperationResponse> {
    this.authEmailDeliveryService.assertInteractiveDeliveryAvailable();

    const email = this.normalizeEmail(input.email);
    const genericResponse: AuthOperationResponse = {
      message:
        'If an email/password account exists for this address, a password reset code has been sent.',
    };
    const user = await this.userRepository.findOneBy({ email });

    if (
      !user ||
      user.authProvider !== AuthProvider.Email ||
      !user.passwordHash
    ) {
      return genericResponse;
    }

    const remainingSeconds = await this.readCodeCooldownRemainingSeconds({
      email: user.email,
      purpose: AuthEmailCodePurpose.PasswordReset,
      userId: user.id,
    });

    if (remainingSeconds > 0) {
      return genericResponse;
    }

    await this.createAndSendEmailCode({
      user,
      purpose: AuthEmailCodePurpose.PasswordReset,
      ttlSeconds: this.environment.auth.passwordResetCodeTtlSeconds,
      successMessage: genericResponse.message,
      send: (code, expiresInMinutes) =>
        this.authEmailDeliveryService.sendPasswordResetCode({
          to: user.email,
          code,
          expiresInMinutes,
        }),
    });

    return genericResponse;
  }

  async confirmPasswordReset(input: {
    email: string;
    code: string;
    newPassword: string;
  }): Promise<AuthOperationResponse> {
    const email = this.normalizeEmail(input.email);
    const password = this.normalizePassword(input.newPassword);
    const invalidMessage = 'Invalid or expired password reset code.';
    const user = await this.userRepository.findOneBy({ email });

    if (
      !user ||
      user.authProvider !== AuthProvider.Email ||
      !user.passwordHash
    ) {
      throw new BadRequestException(invalidMessage);
    }

    const emailCode = await this.requireValidEmailCode({
      email,
      purpose: AuthEmailCodePurpose.PasswordReset,
      userId: user.id,
      code: input.code,
      invalidMessage,
    });

    user.passwordHash = await this.hashPassword(password);
    user.authTokenVersion += 1;
    user.emailVerifiedAt ??= new Date();

    await Promise.all([
      this.userRepository.save(user),
      this.consumeEmailCode(emailCode),
    ]);

    return {
      message: 'Password updated. Sign in with your new password.',
    };
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

    if ((payload.ver ?? 0) !== user.authTokenVersion) {
      throw new UnauthorizedException('Human auth token is no longer current.');
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

  private async requireCurrentUser(
    human: AuthenticatedHuman,
  ): Promise<UserEntity> {
    const user = await this.userRepository.findOneBy({ id: human.id });

    if (!user) {
      throw new UnauthorizedException(
        'Authenticated human account was not found.',
      );
    }

    return user;
  }

  private ensureEmailPasswordUser(
    user: UserEntity,
    errorMessage: string,
  ): void {
    if (user.authProvider !== AuthProvider.Email) {
      throw new BadRequestException(errorMessage);
    }
  }

  private async createAndSendEmailCode(input: {
    user: UserEntity;
    purpose: AuthEmailCodePurpose;
    ttlSeconds: number;
    successMessage: string;
    send: (code: string, expiresInMinutes: number) => Promise<void>;
  }): Promise<AuthOperationResponse> {
    const code = this.generateEmailCode();
    const expiresAt = new Date(Date.now() + input.ttlSeconds * 1000);

    await this.invalidateActiveEmailCodes({
      email: input.user.email,
      purpose: input.purpose,
      userId: input.user.id,
    });

    const savedCode = await this.emailCodeRepository.save(
      this.emailCodeRepository.create({
        userId: input.user.id,
        email: input.user.email,
        purpose: input.purpose,
        codeHash: this.hashEmailCode({
          email: input.user.email,
          purpose: input.purpose,
          code,
        }),
        expiresAt,
      }),
    );

    try {
      await input.send(code, this.toExpiryMinutes(input.ttlSeconds));
    } catch (error) {
      await this.emailCodeRepository.delete({ id: savedCode.id });
      throw error;
    }

    return {
      message: input.successMessage,
    };
  }

  private async requireValidEmailCode(input: {
    email: string;
    purpose: AuthEmailCodePurpose;
    userId: string;
    code: string;
    invalidMessage: string;
  }): Promise<AuthEmailCodeEntity> {
    const submittedCode = this.normalizeEmailCode(input.code);
    const emailCode = await this.findActiveEmailCode({
      email: input.email,
      purpose: input.purpose,
      userId: input.userId,
    });

    if (!emailCode) {
      throw new BadRequestException(input.invalidMessage);
    }

    if (emailCode.attemptCount >= this.maxEmailCodeAttempts) {
      await this.consumeEmailCode(emailCode);
      throw new BadRequestException(input.invalidMessage);
    }

    const expectedHash = this.hashEmailCode({
      email: input.email,
      purpose: input.purpose,
      code: submittedCode,
    });

    if (!this.constantTimeMatches(emailCode.codeHash, expectedHash)) {
      await this.recordInvalidCodeAttempt(emailCode);
      throw new BadRequestException(input.invalidMessage);
    }

    return emailCode;
  }

  private async findActiveEmailCode(input: {
    email: string;
    purpose: AuthEmailCodePurpose;
    userId: string;
  }): Promise<AuthEmailCodeEntity | null> {
    return this.emailCodeRepository.findOne({
      where: this.buildActiveEmailCodeWhere(input),
      order: {
        createdAt: 'DESC',
      },
    });
  }

  private async readCodeCooldownRemainingSeconds(input: {
    email: string;
    purpose: AuthEmailCodePurpose;
    userId: string;
  }): Promise<number> {
    const activeCode = await this.findActiveEmailCode(input);

    if (!activeCode) {
      return 0;
    }

    const nextAllowedAt =
      activeCode.createdAt.getTime() +
      this.environment.auth.emailCodeCooldownSeconds * 1000;
    const remainingMs = nextAllowedAt - Date.now();

    if (remainingMs <= 0) {
      return 0;
    }

    return Math.ceil(remainingMs / 1000);
  }

  private async invalidateActiveEmailCodes(input: {
    email: string;
    purpose: AuthEmailCodePurpose;
    userId: string;
  }): Promise<void> {
    const activeCodes = await this.emailCodeRepository.find({
      where: this.buildActiveEmailCodeWhere(input),
    });

    if (activeCodes.length === 0) {
      return;
    }

    const consumedAt = new Date();
    for (const code of activeCodes) {
      code.consumedAt = consumedAt;
    }

    await this.emailCodeRepository.save(activeCodes);
  }

  private buildActiveEmailCodeWhere(input: {
    email: string;
    purpose: AuthEmailCodePurpose;
    userId: string;
  }): FindOptionsWhere<AuthEmailCodeEntity> {
    return {
      email: input.email,
      purpose: input.purpose,
      userId: input.userId,
      consumedAt: IsNull(),
      expiresAt: MoreThan(new Date()),
    };
  }

  private async consumeEmailCode(
    emailCode: AuthEmailCodeEntity,
  ): Promise<void> {
    if (emailCode.consumedAt != null) {
      return;
    }

    emailCode.consumedAt = new Date();
    await this.emailCodeRepository.save(emailCode);
  }

  private async recordInvalidCodeAttempt(
    emailCode: AuthEmailCodeEntity,
  ): Promise<void> {
    emailCode.attemptCount += 1;

    if (emailCode.attemptCount >= this.maxEmailCodeAttempts) {
      emailCode.consumedAt = new Date();
    }

    await this.emailCodeRepository.save(emailCode);
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
      avatarUrl: user.avatarUrl,
      emailVerified: user.emailVerifiedAt != null,
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
      emailVerified: user.emailVerifiedAt != null,
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
      ver: user.authTokenVersion,
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

    if (!this.constantTimeMatches(expectedSignature, signature)) {
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

    if (
      payload.kind !== 'human' ||
      !payload.sub ||
      typeof payload.exp !== 'number' ||
      payload.exp <= Date.now() ||
      (payload.ver !== undefined && !Number.isInteger(payload.ver))
    ) {
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

  private hashEmailCode(input: {
    email: string;
    purpose: AuthEmailCodePurpose;
    code: string;
  }): string {
    return createHmac('sha256', this.environment.auth.jwtSecret)
      .update(`${input.purpose}:${input.email}:${input.code}`)
      .digest('hex');
  }

  private generateEmailCode(): string {
    return randomInt(0, 10 ** this.emailCodeLength)
      .toString()
      .padStart(this.emailCodeLength, '0');
  }

  private toExpiryMinutes(ttlSeconds: number): number {
    return Math.max(1, Math.ceil(ttlSeconds / 60));
  }

  private constantTimeMatches(actual: string, expected: string): boolean {
    if (actual.length !== expected.length) {
      return false;
    }

    return timingSafeEqual(
      Buffer.from(actual, 'utf8'),
      Buffer.from(expected, 'utf8'),
    );
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

    return this.constantTimeMatches(actualHash, expectedHash);
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

  private normalizeEmailCode(code: string): string {
    const normalized = code?.trim().replace(/\s+/g, '') ?? '';

    if (!/^\d{6}$/.test(normalized)) {
      throw new BadRequestException('code must be a 6-digit number.');
    }

    return normalized;
  }
}
