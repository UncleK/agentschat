import {
  Body,
  Controller,
  Get,
  HttpCode,
  NotImplementedException,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentHuman } from './current-human.decorator';
import { AuthService } from './auth.service';
import type { AuthSessionBootstrapResponse } from './auth.service';
import { HumanAuthGuard } from './human-auth.guard';
import type { AuthenticatedHuman } from './auth.types';

interface EmailRegistrationBody {
  email: string;
  username: string;
  displayName: string;
  password: string;
  avatarUrl?: string | null;
}

interface EmailLoginBody {
  email: string;
  password: string;
}

interface EmailVerificationConfirmBody {
  code: string;
}

interface PasswordResetRequestBody {
  email: string;
}

interface PasswordResetConfirmBody {
  email: string;
  code: string;
  newPassword: string;
}

interface UsernameAvailabilityQuery {
  username?: string;
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

  @Get('username-availability')
  readUsernameAvailability(@Query() query: UsernameAvailabilityQuery) {
    return this.authService.readUsernameAvailability(query.username);
  }

  @Post('login/email')
  @HttpCode(200)
  loginWithEmail(@Body() body: EmailLoginBody) {
    return this.authService.loginWithEmail(body);
  }

  @Post('email-verification/request')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  requestEmailVerificationCode(@CurrentHuman() human: AuthenticatedHuman) {
    return this.authService.requestEmailVerificationCode(human);
  }

  @Post('email-verification/confirm')
  @HttpCode(200)
  @UseGuards(HumanAuthGuard)
  confirmEmailVerificationCode(
    @CurrentHuman() human: AuthenticatedHuman,
    @Body() body: EmailVerificationConfirmBody,
  ) {
    return this.authService.confirmEmailVerificationCode(human, body);
  }

  @Post('password-reset/request')
  @HttpCode(200)
  requestPasswordResetCode(@Body() body: PasswordResetRequestBody) {
    return this.authService.requestPasswordResetCode(body);
  }

  @Post('password-reset/confirm')
  @HttpCode(200)
  confirmPasswordReset(@Body() body: PasswordResetConfirmBody) {
    return this.authService.confirmPasswordReset(body);
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
