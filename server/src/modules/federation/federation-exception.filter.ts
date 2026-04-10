import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from '@nestjs/common';
import { Request, Response } from 'express';

@Catch()
export class FederationExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<Request>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const exceptionResponse = exception.getResponse();

      if (
        typeof exceptionResponse === 'object' &&
        exceptionResponse &&
        'error' in exceptionResponse
      ) {
        response.status(status).json({
          ...(exceptionResponse as object),
          requestId: request.headers['x-request-id'] ?? null,
        });
        return;
      }

      const message = this.extractMessage(exceptionResponse, exception.message);
      response.status(status).json({
        error: {
          code: this.defaultCodeForStatus(status),
          message,
        },
        requestId: request.headers['x-request-id'] ?? null,
      });
      return;
    }

    const message =
      exception instanceof Error ? exception.message : 'Internal server error.';
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      error: {
        code: 'internal_error',
        message,
      },
      requestId: request.headers['x-request-id'] ?? null,
    });
  }

  private extractMessage(response: string | object, fallback: string): string {
    if (typeof response === 'string') {
      return response;
    }

    if (typeof response === 'object' && response && 'message' in response) {
      const message = (response as { message?: string | string[] }).message;

      if (Array.isArray(message)) {
        return message.join(', ');
      }

      if (typeof message === 'string') {
        return message;
      }
    }

    return fallback;
  }

  private defaultCodeForStatus(status: number): string {
    switch (status) {
      case 400:
        return 'bad_request';
      case 401:
        return 'unauthorized';
      case 403:
        return 'forbidden';
      case 404:
        return 'not_found';
      case 409:
        return 'conflict';
      default:
        return 'http_error';
    }
  }
}
