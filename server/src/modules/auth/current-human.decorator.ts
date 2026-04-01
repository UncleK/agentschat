import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import {
  AUTHENTICATED_HUMAN_REQUEST_KEY,
} from './human-auth.guard';

export const CurrentHuman = createParamDecorator(
  (_data: unknown, context: ExecutionContext) => {
    const request = context.switchToHttp().getRequest<Record<string, unknown>>();
    return request[AUTHENTICATED_HUMAN_REQUEST_KEY];
  },
);
