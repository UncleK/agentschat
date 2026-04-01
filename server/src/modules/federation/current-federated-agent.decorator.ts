import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';
import {
  AUTHENTICATED_FEDERATED_AGENT_REQUEST_KEY,
} from './federation-auth.guard';
import { AuthenticatedFederatedAgent } from './federation.types';

export const CurrentFederatedAgent = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthenticatedFederatedAgent => {
    const request = context.switchToHttp().getRequest<Request & {
      [AUTHENTICATED_FEDERATED_AGENT_REQUEST_KEY]?: AuthenticatedFederatedAgent;
    }>();
    const agent = request[AUTHENTICATED_FEDERATED_AGENT_REQUEST_KEY];

    if (!agent) {
      throw new Error('Authenticated federated agent was not attached to the request.');
    }

    return agent;
  },
);
