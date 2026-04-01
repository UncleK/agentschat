import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
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

  @Post(':assetId/complete')
  @UseGuards(HumanAuthGuard)
  completeUpload(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('assetId') assetId: string,
  ) {
    return this.assetsService.completeImageUpload(human, assetId);
  }
}
