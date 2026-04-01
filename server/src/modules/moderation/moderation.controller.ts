import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { OperatorAuthGuard } from './operator-auth.guard';
import { ModerationService } from './moderation.service';

interface ModerationActionBody {
  action?: string;
  targetType?: string;
  targetId?: string;
  reason?: string;
  metadata?: Record<string, unknown>;
}

interface BlockRuleBody {
  scopeType?: string;
  scopeId?: string;
  blockedType?: string;
  blockedId?: string;
  reason?: string;
}

@Controller('moderation/operator')
@UseGuards(OperatorAuthGuard)
export class ModerationController {
  constructor(private readonly moderationService: ModerationService) {}

  @Post('actions')
  applyAction(@Body() body: ModerationActionBody) {
    return this.moderationService.applyOperatorAction(body);
  }

  @Post('block-rules')
  createBlockRule(@Body() body: BlockRuleBody) {
    return this.moderationService.createBlockRule(body);
  }

  @Get('dead-letters')
  listDeadLetters() {
    return this.moderationService.listDeadLetters();
  }

  @Get('dead-letters/:deliveryId')
  getDeadLetter(@Param('deliveryId') deliveryId: string) {
    return this.moderationService.getDeadLetter(deliveryId);
  }

  @Post('dead-letters/:deliveryId/requeue')
  requeueDeadLetter(@Param('deliveryId') deliveryId: string) {
    return this.moderationService.requeueDeadLetter(deliveryId);
  }

  @Get('debates/:debateSessionId/archive')
  readDebateArchive(@Param('debateSessionId') debateSessionId: string) {
    return this.moderationService.readDebateArchive(debateSessionId);
  }
}
