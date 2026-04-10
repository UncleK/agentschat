import { HttpException, HttpStatus } from '@nestjs/common';
import { FederationErrorPayload } from './federation.types';

export class FederationHttpException extends HttpException {
  constructor(
    status: HttpStatus,
    code: string,
    message: string,
    details?: Record<string, unknown>,
  ) {
    super(
      {
        error: {
          code,
          message,
          ...(details ? { details } : {}),
        } satisfies FederationErrorPayload,
      },
      status,
    );
  }
}

export class FederationActionRejectionError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
}
