import {
  Body,
  Controller,
  Delete,
  Get,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { FollowService } from './follow.service';

interface FollowMutationBody {
  targetType?: string;
  targetId?: string;
  actorType?: string;
  actorAgentId?: string | null;
}

@Controller('follows')
@UseGuards(HumanAuthGuard)
export class FollowController {
  constructor(private readonly followService: FollowService) {}

  @Post()
  async follow(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: FollowMutationBody,
  ) {
    const actor = await this.followService.resolveHumanActor(
      human,
      body.actorType,
      body.actorAgentId,
    );
    const target = this.followService.parseTarget(body.targetType, body.targetId);

    return this.followService.follow(actor, target);
  }

  @Get('state')
  async readState(
    @CurrentHuman() human: AuthenticatedHuman,
    @Query('targetType') targetType?: string,
    @Query('targetId') targetId?: string,
    @Query('actorType') actorType?: string,
    @Query('actorAgentId') actorAgentId?: string,
  ) {
    const actor = await this.followService.resolveHumanActor(
      human,
      actorType,
      actorAgentId,
    );
    const target = this.followService.parseTarget(targetType, targetId);

    return this.followService.readState(actor, target);
  }

  @Delete()
  async unfollow(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: FollowMutationBody,
  ) {
    const actor = await this.followService.resolveHumanActor(
      human,
      body.actorType,
      body.actorAgentId,
    );
    const target = this.followService.parseTarget(body.targetType, body.targetId);

    return this.followService.unfollow(actor, target);
  }

  @Get()
  async followViaQueryAlias(
    @CurrentHuman() human: AuthenticatedHuman,
    @Query('targetType') targetType?: string,
    @Query('targetId') targetId?: string,
    @Query('actorType') actorType?: string,
    @Query('actorAgentId') actorAgentId?: string,
  ) {
    const actor = await this.followService.resolveHumanActor(
      human,
      actorType,
      actorAgentId,
    );
    const target = this.followService.parseTarget(targetType, targetId);

    return this.followService.readState(actor, target);
  }
}
