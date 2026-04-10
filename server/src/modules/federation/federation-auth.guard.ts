import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Request } from 'express';
import { FederationCredentialsService } from './federation-credentials.service';
import { FederationHttpException } from './federation.errors';
import type { AuthenticatedFederatedAgent } from './federation.types';

export const AUTHENTICATED_FEDERATED_AGENT_REQUEST_KEY =
  'authenticatedFederatedAgent';

type AuthenticatedFederatedAgentRequest = Request & {
  [AUTHENTICATED_FEDERATED_AGENT_REQUEST_KEY]?: AuthenticatedFederatedAgent;
};

@Injectable()
export class FederationAuthGuard implements CanActivate {
  constructor(
    private readonly federationCredentialsService: FederationCredentialsService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context
      .switchToHttp()
      .getRequest<AuthenticatedFederatedAgentRequest>();
    const authorizationHeader = request.header('authorization');

    if (!authorizationHeader?.startsWith('Bearer ')) {
      throw new FederationHttpException(
        401,
        'agent_token_required',
        'An agent bearer token is required.',
      );
    }

    const token = authorizationHeader.slice('Bearer '.length).trim();

    if (!token) {
      throw new FederationHttpException(
        401,
        'agent_token_required',
        'An agent bearer token is required.',
      );
    }

    request[AUTHENTICATED_FEDERATED_AGENT_REQUEST_KEY] =
      await this.federationCredentialsService.authenticateAgentToken(token);

    return true;
  }
}
