import {
  Body,
  Controller,
  Get,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { SubjectType } from '../../database/domain.enums';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { ContentService } from '../content/content.service';
import { DebateService } from './debate.service';

interface CreateDebateBody {
  topic?: string | null;
  proStance?: string | null;
  conStance?: string | null;
  proAgentId?: string | null;
  conAgentId?: string | null;
  freeEntry?: boolean;
}

interface PauseDebateBody {
  reason?: string | null;
}

interface ReplacementSeatBody {
  seatId?: string | null;
  agentId?: string | null;
}

interface SpectatorCommentBody {
  contentType?: string | null;
  content?: string | null;
  caption?: string | null;
  assetId?: string | null;
  asset_id?: string | null;
  metadata?: Record<string, unknown>;
}

@Controller('debates')
export class DebateController {
  constructor(
    private readonly debateService: DebateService,
    private readonly contentService: ContentService,
  ) {}

  @Get()
  listDebates(@Query('limit') limit?: string) {
    const parsedLimit =
      limit != null && /^\d+$/.test(limit) ? Number.parseInt(limit, 10) : 12;
    return this.debateService.listDebates(
      Math.min(Math.max(parsedLimit, 1), 24),
    );
  }

  @Post()
  @UseGuards(HumanAuthGuard)
  createDebate(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: CreateDebateBody,
  ) {
    return this.debateService.createHumanHostedDebate(human, body);
  }

  @Post(':debateSessionId/start')
  @UseGuards(HumanAuthGuard)
  startDebate(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('debateSessionId') debateSessionId: string,
  ) {
    return this.debateService.startDebate(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      debateSessionId,
    );
  }

  @Post(':debateSessionId/pause')
  @UseGuards(HumanAuthGuard)
  pauseDebate(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('debateSessionId') debateSessionId: string,
    @Body() body: PauseDebateBody,
  ) {
    return this.debateService.pauseDebate(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      debateSessionId,
      body.reason,
    );
  }

  @Post(':debateSessionId/replacements')
  @UseGuards(HumanAuthGuard)
  assignReplacement(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('debateSessionId') debateSessionId: string,
    @Body() body: ReplacementSeatBody,
  ) {
    return this.debateService.assignReplacementSeat(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      {
        debateSessionId,
        seatId: body.seatId,
        agentId: body.agentId,
      },
    );
  }

  @Post(':debateSessionId/resume')
  @UseGuards(HumanAuthGuard)
  resumeDebate(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('debateSessionId') debateSessionId: string,
  ) {
    return this.debateService.resumeDebate(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      debateSessionId,
    );
  }

  @Post(':debateSessionId/end')
  @UseGuards(HumanAuthGuard)
  endDebate(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('debateSessionId') debateSessionId: string,
  ) {
    return this.debateService.endDebate(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      debateSessionId,
    );
  }

  @Post(':debateSessionId/spectator-comments')
  @UseGuards(HumanAuthGuard)
  postSpectatorComment(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('debateSessionId') debateSessionId: string,
    @Body() body: SpectatorCommentBody,
  ) {
    return this.contentService.postDebateSpectatorComment(
      {
        type: SubjectType.Human,
        id: human.id,
      },
      {
        debateSessionId,
        ...body,
      },
    );
  }

  @Get(':debateSessionId/archive')
  getDebateArchive(
    @Param('debateSessionId', new ParseUUIDPipe()) debateSessionId: string,
  ) {
    return this.debateService.getDebateArchive(debateSessionId);
  }

  @Get(':debateSessionId')
  getDebate(
    @Param('debateSessionId', new ParseUUIDPipe()) debateSessionId: string,
  ) {
    return this.debateService.getDebate(debateSessionId);
  }
}
