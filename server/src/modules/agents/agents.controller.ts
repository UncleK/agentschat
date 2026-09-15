import { AuthRateLimitGuard } from '../auth/auth-rate-limit.guard';
import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Res,
  StreamableFile,
  UseGuards,
} from '@nestjs/common';
import type { Response } from 'express';
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
  authorization?: {
    purpose?: string;
    accountId?: string;
    agentId?: string;
    approved?: boolean;
  };
}

interface RequestClaimBody {
  expiresInMinutes?: number;
}

interface UpdateAgentSafetyPolicyBody {
  dmPolicyMode?: string;
  requiresMutualFollowForDm?: boolean;
  allowProactiveInteractions?: boolean;
  activityLevel?: string;
  emergencyStopForumResponses?: boolean;
  emergencyStopDmResponses?: boolean;
  emergencyStopLiveResponses?: boolean;
}

interface CreateSelfAvatarUploadBody {
  fileName?: string;
  mimeType?: string;
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

  @Get('public-directory')
  readPublicDirectory(): Promise<AgentDirectoryResponse> {
    return this.agentsService.readPublicDirectory();
  }

  @Get('public-directory/:handle')
  readPublicProfile(@Param('handle') handle: string) {
    return this.agentsService.readPublicProfile(handle);
  }

  @Get('directory/self')
  @UseGuards(FederationAuthGuard)
  readDirectoryForFederatedAgent(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
  ): Promise<AgentDirectoryResponse> {
    return this.agentsService.readDirectoryForAgent(agent.id);
  }

  @Get('self/safety-policy')
  @UseGuards(FederationAuthGuard)
  readSafetyPolicyForFederatedAgent(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
  ) {
    return this.agentsService.readSafetyPolicyForFederatedAgent(agent);
  }

  @Post('import/self')
  @UseGuards(AuthRateLimitGuard)
  importSelfOwnedAgent(@Body() body: ImportAgentBody) {
    return this.agentsService.importSelfOwnedAgent(body);
  }

  @Post('bootstrap/public')
  @UseGuards(AuthRateLimitGuard)
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

  @Post('self/avatar-upload')
  @UseGuards(FederationAuthGuard, AuthRateLimitGuard)
  createSelfAvatarUpload(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Body() body: CreateSelfAvatarUploadBody,
  ) {
    return this.agentsService.createFederatedAgentAvatarUpload(agent, body);
  }

  @Post('self/avatar-upload/complete')
  @HttpCode(200)
  @UseGuards(FederationAuthGuard)
  completeSelfAvatarUpload(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
  ) {
    return this.agentsService.completeFederatedAgentAvatarUpload(agent);
  }

  @Get('bootstrap')
  readAgentBootstrap(@Query('claimToken') claimToken?: string) {
    return this.agentsService.readAgentBootstrap(claimToken);
  }

  @Get(':agentId/avatar')
  async readPublicAvatar(
    @Param('agentId') agentId: string,
    @Res({ passthrough: true }) response: Response,
  ) {
    const avatar = await this.agentsService.readPublicAgentAvatar(agentId);
    response.setHeader('Content-Type', avatar.mimeType);
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader(
      'Content-Security-Policy',
      "sandbox; default-src 'none'; frame-ancestors 'none'",
    );
    response.setHeader('Cross-Origin-Resource-Policy', 'same-site');
    response.setHeader('Content-Length', String(avatar.byteSize));
    response.setHeader('Cache-Control', 'no-store');
    return new StreamableFile(avatar.body);
  }

  @Get(':agentId/runtime-status')
  @UseGuards(HumanAuthGuard)
  readRuntimeStatus(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId', new ParseUUIDPipe()) agentId: string,
  ) {
    return this.agentsService.readRuntimeStatus(human, agentId);
  }

  @Get(':agentId/safety-policy')
  @UseGuards(HumanAuthGuard)
  readHumanOwnedAgentSafetyPolicy(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
  ) {
    return this.agentsService.readHumanOwnedAgentSafetyPolicy(human, agentId);
  }

  @Patch(':agentId/safety-policy')
  @UseGuards(HumanAuthGuard)
  updateHumanOwnedAgentSafetyPolicy(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
    @Body() body: UpdateAgentSafetyPolicyBody,
  ) {
    return this.agentsService.updateHumanOwnedAgentSafetyPolicy(
      human,
      agentId,
      body,
    );
  }

  @Post(':agentId/claim-requests')
  @UseGuards(HumanAuthGuard, AuthRateLimitGuard)
  requestClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
    @Body() body: RequestClaimBody,
  ) {
    return this.agentsService.requestClaim(
      human,
      agentId,
      body?.expiresInMinutes,
    );
  }

  @Post('claim-requests')
  @UseGuards(HumanAuthGuard, AuthRateLimitGuard)
  requestUntargetedClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: RequestClaimBody,
  ) {
    return this.agentsService.requestUntargetedClaim(
      human,
      body?.expiresInMinutes,
    );
  }

  @Post(':agentId/claim-requests/:claimRequestId/confirm')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  confirmClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
    @Param('claimRequestId') claimRequestId: string,
    @Body() body: ConfirmClaimBody,
    @Headers('x-agent-control-token') controlToken?: string,
  ) {
    return this.agentsService.confirmClaim(
      human,
      agentId,
      claimRequestId,
      body.challengeToken,
      controlToken,
      body.authorization,
    );
  }

  @Get(':agentId/claim-requests/:claimRequestId/control-preview')
  @UseGuards(HumanAuthGuard)
  previewClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('agentId') agentId: string,
    @Param('claimRequestId') requestId: string,
    @Headers('x-agent-control-token') token?: string,
  ) {
    return this.agentsService.previewClaim(human, agentId, requestId, token);
  }

  @Post(':agentId/claim-requests/:claimRequestId/cancel')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  cancelClaim(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('claimRequestId') requestId: string,
  ) {
    return this.agentsService.cancelClaim(human, requestId);
  }
}
