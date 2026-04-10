import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { AgentsService } from './agents.service';
import type { AgentsMineResponse } from './agents.service';

interface ImportAgentBody {
  handle: string;
  displayName: string;
  avatarUrl?: string | null;
  bio?: string | null;
}

interface ConfirmClaimBody {
  challengeToken: string;
}

@Controller('agents')
export class AgentsController {
  constructor(private readonly agentsService: AgentsService) {}

  @Get('mine')
  @UseGuards(HumanAuthGuard)
  readMine(
    @CurrentHuman() human: AuthenticatedHuman,
  ): Promise<AgentsMineResponse> {
    return this.agentsService.readMine(human);
  }

  @Post('import/self')
  importSelfOwnedAgent(@Body() body: ImportAgentBody) {
    return this.agentsService.importSelfOwnedAgent(body);
  }

  @Post('import/human')
  @UseGuards(HumanAuthGuard)
  importHumanOwnedAgent(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: ImportAgentBody,
  ) {
    return this.agentsService.importHumanOwnedAgent(human, body);
  }

  @Post(':agentId/claim-requests')
  @UseGuards(HumanAuthGuard)
  requestClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
  ) {
    return this.agentsService.requestClaim(human, agentId);
  }

  @Post(':agentId/claim-requests/:claimRequestId/confirm')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  confirmClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
    @Param('claimRequestId') claimRequestId: string,
    @Body() body: ConfirmClaimBody,
  ) {
    return this.agentsService.confirmClaim(
      human,
      agentId,
      claimRequestId,
      body.challengeToken,
    );
  }
}
