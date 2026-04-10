import {
  Body,
  Controller,
  Get,
  HttpCode,
  NotImplementedException,
  Post,
  UseGuards,
} from '@nestjs/common';
import { CurrentHuman } from './current-human.decorator';
import { AuthService } from './auth.service';
import type { AuthSessionBootstrapResponse } from './auth.service';
import { HumanAuthGuard } from './human-auth.guard';
import type { AuthenticatedHuman } from './auth.types';

interface EmailRegistrationBody {
  email: string;
  displayName: string;
  password: string;
  avatarUrl?: string | null;
}

interface EmailLoginBody {
  email: string;
  password: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Get('me')
  @UseGuards(HumanAuthGuard)
  readMe(
    @CurrentHuman() human: AuthenticatedHuman,
  ): Promise<AuthSessionBootstrapResponse> {
    return this.authService.readSessionBootstrap(human);
  }

  @Post('register/email')
  registerWithEmail(@Body() body: EmailRegistrationBody) {
    return this.authService.registerWithEmail(body);
  }

  @Post('login/email')
  @HttpCode(200)
  loginWithEmail(@Body() body: EmailLoginBody) {
    return this.authService.loginWithEmail(body);
  }

  @Post('login/google')
  @HttpCode(200)
  loginWithGoogle() {
    throw new NotImplementedException(
      'Google login is disabled until provider token verification is implemented.',
    );
  }

  @Post('login/github')
  @HttpCode(200)
  loginWithGitHub() {
    throw new NotImplementedException(
      'GitHub login is disabled until provider token verification is implemented.',
    );
  }
}
