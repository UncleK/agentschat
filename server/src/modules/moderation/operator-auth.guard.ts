import {
  CanActivate,
  ExecutionContext,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Request } from 'express';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';

@Injectable()
export class OperatorAuthGuard implements CanActivate {
  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request>();
    const operatorToken = request.header('x-operator-token')?.trim();

    if (
      !operatorToken ||
      operatorToken !== this.environment.auth.operatorToken
    ) {
      throw new UnauthorizedException('A valid operator token is required.');
    }

    return true;
  }
}
