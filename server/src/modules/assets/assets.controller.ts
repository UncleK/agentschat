import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Res,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { BoundedUploadInterceptor } from './bounded-upload.interceptor';
import type { Response } from 'express';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { AssetsService } from './assets.service';
import { byteRange } from './byte-range';

interface CreateUploadBody {
  fileName?: string;
  mimeType?: string;
  metadata?: Record<string, unknown>;
}

@Controller('assets')
export class AssetsController {
  constructor(private readonly assetsService: AssetsService) {}

  @Post('uploads')
  @UseGuards(HumanAuthGuard)
  createUpload(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: CreateUploadBody,
  ) {
    return this.assetsService.createImageUpload(human, body);
  }

  @Post('images')
  @UseGuards(HumanAuthGuard)
  @UseInterceptors(BoundedUploadInterceptor)
  uploadImage(
    @CurrentHuman() human: AuthenticatedHuman,
    @UploadedFile()
    file:
      | {
          originalname?: string;
          mimetype?: string;
          buffer: Buffer;
        }
      | undefined,
    @Body() body: CreateUploadBody,
  ) {
    if (!file?.buffer || file.buffer.byteLength === 0) {
      throw new BadRequestException('file is required.');
    }
    return this.assetsService.uploadImage(human, {
      fileName: body.fileName ?? file.originalname,
      mimeType: body.mimeType ?? file.mimetype,
      metadata: body.metadata,
      bytes: file.buffer,
    });
  }

  @Post(':assetId/complete')
  @UseGuards(HumanAuthGuard)
  completeUpload(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('assetId') assetId: string,
  ) {
    return this.assetsService.completeImageUpload(human, assetId);
  }

  @Get(':assetId/content')
  @UseGuards(HumanAuthGuard)
  async readAssetContent(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('assetId') assetId: string,
    @Headers('range') range: string | undefined,
    @Res({ passthrough: true }) response: Response,
  ) {
    const asset = await this.assetsService.readApprovedAssetForHuman(
      human,
      assetId,
    );
    response.setHeader('Content-Type', asset.mimeType);
    response.setHeader('Content-Length', asset.byteSize.toString());
    response.setHeader('Cache-Control', 'private, max-age=300');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader(
      'Content-Security-Policy',
      "default-src 'none'; sandbox",
    );
    response.setHeader('Accept-Ranges', 'bytes');
    const selection = byteRange(range, asset.byteSize);
    if (selection === 'invalid') {
      response.status(416);
      response.setHeader('Content-Range', `bytes */${asset.byteSize}`);
      response.setHeader('Content-Length', '0');
      return new StreamableFile(Buffer.alloc(0));
    }
    if (selection) {
      response.status(206);
      response.setHeader(
        'Content-Range',
        `bytes ${selection.start}-${selection.end}/${asset.byteSize}`,
      );
      response.setHeader(
        'Content-Length',
        String(selection.end - selection.start + 1),
      );
      return new StreamableFile(
        asset.body.subarray(selection.start, selection.end + 1),
      );
    }
    return new StreamableFile(asset.body);
  }
}
