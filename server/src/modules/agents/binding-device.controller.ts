import {
  Body,
  Controller,
  Get,
  Post,
  Param,
  ParseUUIDPipe,
  Headers,
  HttpCode,
  UseGuards,
} from '@nestjs/common';
import { HumanAuthGuard } from '../auth/human-auth.guard';
import { AuthRateLimitGuard } from '../auth/auth-rate-limit.guard';
import { CurrentHuman } from '../auth/current-human.decorator';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { FederationAuthGuard } from '../federation/federation-auth.guard';
import {
  BindingDeviceService,
  type BindingAuthorization,
} from './binding-device.service';

@Controller('binding-devices')
export class BindingDeviceController {
  constructor(private readonly devices: BindingDeviceService) {}
  @Post()
  @UseGuards(FederationAuthGuard, AuthRateLimitGuard)
  start(
    @Headers('authorization') bearer: string,
    @Body() body: { requestId: string; challengeToken: string },
  ) {
    return this.devices.start(
      bearer.slice(7),
      body.requestId,
      body.challengeToken,
    );
  }
  @Get('browser/:code')
  @UseGuards(HumanAuthGuard, AuthRateLimitGuard)
  preview(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('code') code: string,
  ) {
    return this.devices.browserPreview(human, code);
  }
  @Post('browser/:code/approve')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard, AuthRateLimitGuard)
  approve(
    @CurrentHuman() human: AuthenticatedHuman,
    @Param('code') code: string,
    @Body() body: BindingAuthorization,
  ) {
    return this.devices.approve(human, code, body);
  }
  @Post(':id/poll')
  @HttpCode(200)
  @UseGuards(FederationAuthGuard)
  poll(
    @Headers('authorization') bearer: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: { deviceSecret: string },
  ) {
    return this.devices.poll(bearer.slice(7), id, body.deviceSecret);
  }
  @Post(':id/confirm')
  @HttpCode(200)
  @UseGuards(FederationAuthGuard, AuthRateLimitGuard)
  confirm(
    @Headers('authorization') bearer: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body()
    body: {
      deviceSecret: string;
      challengeToken: string;
      authorization: BindingAuthorization;
    },
  ) {
    return this.devices.confirm(
      bearer.slice(7),
      id,
      body.deviceSecret,
      body.challengeToken,
      body.authorization,
    );
  }
}
