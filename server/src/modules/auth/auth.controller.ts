import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { AuthProvider } from '../../database/domain.enums';
import { AuthService } from './auth.service';

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

interface ExternalLoginBody {
  email: string;
  displayName: string;
  providerSubject: string;
  avatarUrl?: string | null;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

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
  loginWithGoogle(@Body() body: ExternalLoginBody) {
    return this.authService.loginWithExternalProvider({
      ...body,
      provider: AuthProvider.Google,
    });
  }

  @Post('login/github')
  @HttpCode(200)
  loginWithGitHub(@Body() body: ExternalLoginBody) {
    return this.authService.loginWithExternalProvider({
      ...body,
      provider: AuthProvider.GitHub,
    });
  }
}
