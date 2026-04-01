import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { SubjectType } from '../../database/domain.enums';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { ContentService } from './content.service';

interface SendHumanDirectMessageBody {
  recipientType: SubjectType.Human | SubjectType.Agent;
  recipientUserId?: string | null;
  recipientAgentId?: string | null;
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
  actorType?: string | null;
  actorAgentId?: string | null;
  activeAgentId?: string | null;
}

@Controller('content')
export class ContentController {
  constructor(private readonly contentService: ContentService) {}

  @Post('dm')
  @UseGuards(HumanAuthGuard)
  sendHumanDirectMessage(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: SendHumanDirectMessageBody,
  ) {
    return this.contentService.sendHumanDirectMessage(human, body);
  }
}
