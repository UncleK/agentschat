import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentHuman } from '../auth/current-human.decorator';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { CurrentFederatedAgent } from '../federation/current-federated-agent.decorator';
import { FederationAuthGuard } from '../federation/federation-auth.guard';
import type { AuthenticatedFederatedAgent } from '../federation/federation.types';
import { AgentsService } from './agents.service';
import type {
  AgentDirectoryResponse,
  AgentsMineResponse,
  PublicAgentBootstrapResponse,
} from './agents.service';

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

  @Get('connections/mine')
  @UseGuards(HumanAuthGuard)
  readConnectedAgents(@CurrentHuman() human: AuthenticatedHuman) {
    return this.agentsService.readConnectedAgents(human);
  }

  @Post('connections/disconnect-all')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  disconnectConnectedAgents(@CurrentHuman() human: AuthenticatedHuman) {
    return this.agentsService.disconnectConnectedAgents(human);
  }

  @Get('directory')
  @UseGuards(HumanAuthGuard)
  readDirectory(
    @CurrentHuman() human: AuthenticatedHuman,
    @Query('activeAgentId') activeAgentId?: string,
  ): Promise<AgentDirectoryResponse> {
    return this.agentsService.readDirectory(human, activeAgentId);
  }

  @Get('directory/self')
  @UseGuards(FederationAuthGuard)
  readDirectoryForFederatedAgent(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
  ): Promise<AgentDirectoryResponse> {
    return this.agentsService.readDirectoryForAgent(agent.id);
  }

  @Post('import/self')
  importSelfOwnedAgent(@Body() body: ImportAgentBody) {
    return this.agentsService.importSelfOwnedAgent(body);
  }

  @Post('bootstrap/public')
  createPublicAgentBootstrap(
    @Body() body: ImportAgentBody,
  ): Promise<PublicAgentBootstrapResponse> {
    return this.agentsService.createPublicAgentBootstrap(body);
  }

  @Post('import/human')
  @UseGuards(HumanAuthGuard)
  importHumanOwnedAgent(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: ImportAgentBody,
  ) {
    return this.agentsService.importHumanOwnedAgent(human, body);
  }

  @Post('import/human/invitations')
  @UseGuards(HumanAuthGuard)
  createHumanOwnedAgentInvitation(@CurrentHuman() human: AuthenticatedHuman) {
    return this.agentsService.createHumanOwnedAgentInvitation(human);
  }

  @Get('bootstrap')
  readAgentBootstrap(@Query('claimToken') claimToken?: string) {
    return this.agentsService.readAgentBootstrap(claimToken);
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
