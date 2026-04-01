import {
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  Req,
  Res,
  UseFilters,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { CurrentFederatedAgent } from './current-federated-agent.decorator';
import { FederationAuthGuard } from './federation-auth.guard';
import { FederationExceptionFilter } from './federation-exception.filter';
import { FederationService } from './federation.service';
import { FederationDeliveryService } from './federation-delivery.service';
import type { AuthenticatedFederatedAgent } from './federation.types';

interface ClaimAgentBody {
  claimToken?: string;
  transportMode?: string;
  webhookUrl?: string | null;
  pollingEnabled?: boolean;
  capabilities?: Record<string, unknown>;
}

interface ActionBody {
  type?: string;
  payload?: Record<string, unknown>;
}

interface AckBody {
  deliveryIds?: string[];
}

@UseFilters(FederationExceptionFilter)
@Controller()
export class FederationController {
  constructor(
    private readonly federationService: FederationService,
    private readonly federationDeliveryService: FederationDeliveryService,
  ) {}

  @Post('agents/claim')
  claimAgent(@Body() body: ClaimAgentBody) {
    return this.federationService.claimAgent(body);
  }

  @Post('actions')
  @HttpCode(202)
  @UseGuards(FederationAuthGuard)
  async submitAction(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Req() request: Request,
    @Res({ passthrough: true }) response: Response,
    @Body() body: ActionBody,
  ) {
    const result = await this.federationService.submitAction(
      agent,
      request.header('idempotency-key'),
      body,
    );

    if (!result.created) {
      response.statusCode = 200;
    }

    return result.action;
  }

  @Get('actions/:id')
  @UseGuards(FederationAuthGuard)
  getAction(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Param('id') actionId: string,
  ) {
    return this.federationService.getAction(agent, actionId);
  }

  @Get('deliveries/poll')
  @UseGuards(FederationAuthGuard)
  pollDeliveries(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Query('cursor') cursor?: string,
    @Query('limit') limit?: string,
    @Query('wait_seconds') waitSeconds?: string,
  ) {
    return this.federationDeliveryService.pollDeliveries(
      agent,
      cursor,
      limit ? Number.parseInt(limit, 10) : undefined,
      waitSeconds ? Number.parseInt(waitSeconds, 10) : undefined,
    );
  }

  @Post('acks')
  @UseGuards(FederationAuthGuard)
  acknowledgeDeliveries(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
    @Body() body: AckBody,
  ) {
    return this.federationDeliveryService.acknowledgeDeliveries(
      agent,
      body.deliveryIds ?? [],
    );
  }

  @Post('agents/token/rotate')
  @HttpCode(200)
  @UseGuards(FederationAuthGuard)
  rotateAgentToken(
    @CurrentFederatedAgent() agent: AuthenticatedFederatedAgent,
  ) {
    return this.federationService.rotateAgentToken(agent);
  }
}
