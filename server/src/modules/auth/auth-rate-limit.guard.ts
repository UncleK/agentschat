import {
  CanActivate,
  ExecutionContext,
  HttpException,
  HttpStatus,
  Inject,
  Injectable,
} from '@nestjs/common';
import { createHmac } from 'node:crypto';
import type { Request, Response } from 'express';
import { DataSource } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';
import type { AuthenticatedHuman } from './auth.types';

@Injectable()
export class AuthRateLimitGuard implements CanActivate {
  private nextCleanup = 0;
  constructor(
    private readonly database: DataSource,
    @Inject(APP_ENVIRONMENT) private readonly environment: AppEnvironment,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<Request & { authenticatedHuman?: AuthenticatedHuman }>();
    const response = context.switchToHttp().getResponse<Response>();
    const route = request.path;
    const registration = route.endsWith('/register/email');
    const confirmation = route.endsWith('/confirm');
    const codeRequest = route.endsWith('/request');
    // Do not trust caller-supplied forwarded IPs. The peer budget also caps work
    // through the BFF; the account budget is shared across every client and process.
    await this.consume(
      `peer:${registration ? 'register' : 'auth'}:${request.socket.remoteAddress || 'unknown'}`,
      registration ? 30 : 180,
      registration ? 3600 : 60,
      response,
    );
    const body = request.body as { email?: unknown } | undefined;
    const email = request.authenticatedHuman?.email ?? body?.email;
    if (typeof email === 'string' && email.trim().length <= 320) {
      await this.consume(
        `account:${route}:${email.trim().toLowerCase()}`,
        confirmation ? 6 : codeRequest ? 5 : 12,
        600,
        response,
      );
    }
    return true;
  }

  private async consume(
    key: string,
    limit: number,
    seconds: number,
    response: Response,
  ): Promise<void> {
    const now = Date.now();
    const bucket = Math.floor(now / (seconds * 1000));
    const expires = (bucket + 1) * seconds * 1000;
    const hash = createHmac('sha256', this.environment.auth.jwtSecret)
      .update(`${key}:${bucket}`)
      .digest('hex');
    const rows = await this.database.query<Array<{ attempts: number }>>(
      `INSERT INTO auth_request_limits (key_hash, attempts, expires_at) VALUES ($1, 1, $2)
       ON CONFLICT (key_hash) DO UPDATE SET attempts = LEAST(auth_request_limits.attempts + 1, $3)
       RETURNING attempts`,
      [hash, new Date(expires), limit + 1],
    );
    if (now >= this.nextCleanup) {
      this.nextCleanup = now + 60000;
      await this.database.query(
        'DELETE FROM auth_request_limits WHERE expires_at < $1',
        [new Date(now)],
      );
    }
    if (rows[0].attempts > limit) {
      response.setHeader(
        'Retry-After',
        Math.max(1, Math.ceil((expires - now) / 1000)),
      );
      throw new HttpException(
        '尝试次数过多，请稍后重试。',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }
}
