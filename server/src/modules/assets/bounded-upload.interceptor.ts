import {
  BadRequestException,
  type CallHandler,
  type ExecutionContext,
  Injectable,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Observable } from 'rxjs';

// Multipart metadata is small. Bound parsing as well as the uploaded buffer.
const uploadLimits = {
  fileSize: 10 * 1024 * 1024,
  files: 1,
  fields: 16,
  parts: 18,
  fieldNameSize: 128,
  fieldSize: 4096,
  fieldNestingDepth: 4,
  fieldArrayIndexLimit: 16,
};

@Injectable()
export class BoundedUploadInterceptor extends FileInterceptor('file', {
  limits: uploadLimits,
}) {
  override async intercept(
    context: ExecutionContext,
    next: CallHandler,
  ): Promise<Observable<unknown>> {
    try {
      return await super.intercept(context, next);
    } catch (error: unknown) {
      // Nest 11 does not yet map the new Multer field depth/index errors.
      if (
        error instanceof Error &&
        'code' in error &&
        typeof error.code === 'string' &&
        error.code.startsWith('LIMIT_')
      ) {
        throw new BadRequestException('Invalid multipart fields.');
      }
      throw error;
    }
  }
}
