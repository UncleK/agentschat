import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { CurrentHuman } from '../auth/current-human.decorator';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import { NotificationsService } from './notifications.service';

interface MarkReadBody {
  notificationIds?: string[];
  markAll?: boolean;
}

@Controller('notifications')
@UseGuards(HumanAuthGuard)
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  list(@CurrentHuman() human: AuthenticatedHuman) {
    return this.notificationsService.listForHuman(human.id);
  }

  @Get('bell-state')
  bellState(@CurrentHuman() human: AuthenticatedHuman) {
    return this.notificationsService.readBellState(human.id);
  }

  @Post('read')
  markRead(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: MarkReadBody,
  ) {
    return this.notificationsService.markReadForHuman(
      human.id,
      body.notificationIds,
      body.markAll,
    );
  }
}
