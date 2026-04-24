import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Post,
  Res,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Response } from 'express';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { AssetsService } from './assets.service';

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
  @UseInterceptors(FileInterceptor('file'))
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
  async readImageContent(
    @Param('assetId') assetId: string,
    @Res({ passthrough: true }) response: Response,
  ) {
    const image = await this.assetsService.readApprovedImageAsset(assetId);
    response.setHeader('Content-Type', image.mimeType);
    response.setHeader('Content-Length', image.byteSize.toString());
    response.setHeader('Cache-Control', 'private, max-age=300');
    return new StreamableFile(image.body);
  }
}
