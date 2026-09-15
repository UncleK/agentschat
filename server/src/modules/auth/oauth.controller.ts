import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { OAuthService } from './oauth.service';
import { AuthRateLimitGuard } from './auth-rate-limit.guard';
import { HumanAuthGuard } from './human-auth.guard';
import { CurrentHuman } from './current-human.decorator';
import type { AuthenticatedHuman } from './auth.types';

@Controller('auth/oauth')
export class OAuthController {
  constructor(private readonly oauth: OAuthService) {}
  @Get('providers') providers() {
    return { providers: this.oauth.providers() };
  }
  @Get('identities')
  @UseGuards(HumanAuthGuard)
  async identities(@CurrentHuman() human: AuthenticatedHuman) {
    return { identities: await this.oauth.identities(human) };
  }
  @Post(':provider/start')
  @HttpCode(200)
  @UseGuards(AuthRateLimitGuard)
  start(
    @Param('provider') provider: string,
    @Body() input: { codeChallenge?: string; client?: string },
  ) {
    return this.oauth.start(provider, input);
  }
  @Post(':provider/link')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard, AuthRateLimitGuard)
  link(
    @Param('provider') provider: string,
    @Body() input: { codeChallenge?: string; client?: string },
    @CurrentHuman() human: AuthenticatedHuman,
  ) {
    return this.oauth.start(provider, input, human);
  }
  @Get(':provider/callback')
  callback(
    @Param('provider') provider: string,
    @Query() input: { state?: string; code?: string; error?: string },
  ) {
    return this.oauth.callback(provider, input);
  }
  @Post('exchange')
  @HttpCode(200)
  @UseGuards(AuthRateLimitGuard)
  exchange(
    @Body() input: { flowId?: string; code?: string; verifier?: string },
    @Headers('authorization') authorization?: string,
  ) {
    return this.oauth.exchange(
      input,
      authorization?.startsWith('Bearer ') ? authorization.slice(7) : undefined,
    );
  }
}
