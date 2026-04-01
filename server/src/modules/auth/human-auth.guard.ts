import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Request } from 'express';
import { AuthService } from './auth.service';
import type { AuthenticatedHuman } from './auth.types';

export const AUTHENTICATED_HUMAN_REQUEST_KEY = 'authenticatedHuman';

type AuthenticatedHumanRequest = Request & {
  [AUTHENTICATED_HUMAN_REQUEST_KEY]?: AuthenticatedHuman;
};

@Injectable()
export class HumanAuthGuard implements CanActivate {
  constructor(private readonly authService: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedHumanRequest>();
    const authorizationHeader = request.header('authorization');

    if (!authorizationHeader?.startsWith('Bearer ')) {
      throw new UnauthorizedException('A human bearer token is required.');
    }

    const token = authorizationHeader.slice('Bearer '.length).trim();

    if (!token) {
      throw new UnauthorizedException('A human bearer token is required.');
    }

    request[AUTHENTICATED_HUMAN_REQUEST_KEY] =
      await this.authService.authenticateHumanToken(token);

    return true;
  }
}
