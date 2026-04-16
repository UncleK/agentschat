import {
  Inject,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';

@Injectable()
export class AuthEmailDeliveryService {
  private readonly logger = new Logger(AuthEmailDeliveryService.name);

  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  isInteractiveDeliveryAvailable(): boolean {
    if (this.environment.mail.deliveryMode === 'disabled') {
      return false;
    }

    if (this.environment.mail.deliveryMode === 'log') {
      return true;
    }

    return (
      this.environment.mail.fromAddress.trim().length > 0 &&
      this.environment.mail.resendApiKey != null
    );
  }

  assertInteractiveDeliveryAvailable(): void {
    if (!this.isInteractiveDeliveryAvailable()) {
      throw new ServiceUnavailableException(
        'Email delivery is not configured yet.',
      );
    }
  }

  async sendEmailVerificationCode(input: {
    to: string;
    code: string;
    expiresInMinutes: number;
  }): Promise<void> {
    await this.deliver({
      to: input.to,
      subject: 'Verify your Agents Chat email',
      text:
        `Your Agents Chat verification code is ${input.code}. ` +
        `It expires in ${input.expiresInMinutes} minutes.`,
    });
  }

  async sendPasswordResetCode(input: {
    to: string;
    code: string;
    expiresInMinutes: number;
  }): Promise<void> {
    await this.deliver({
      to: input.to,
      subject: 'Reset your Agents Chat password',
      text:
        `Your Agents Chat password reset code is ${input.code}. ` +
        `It expires in ${input.expiresInMinutes} minutes.`,
    });
  }

  private async deliver(message: {
    to: string;
    subject: string;
    text: string;
  }): Promise<void> {
    switch (this.environment.mail.deliveryMode) {
      case 'disabled':
        throw new ServiceUnavailableException(
          'Email delivery is not configured yet.',
        );
      case 'log':
        if (this.environment.nodeEnv !== 'test') {
          this.logger.log(
            `Mail log mode -> to=${message.to} subject="${message.subject}" text="${message.text}"`,
          );
        }
        return;
      case 'resend':
        await this.deliverWithResend(message);
        return;
    }
  }

  private async deliverWithResend(message: {
    to: string;
    subject: string;
    text: string;
  }): Promise<void> {
    const apiKey = this.environment.mail.resendApiKey;
    const fromAddress = this.environment.mail.fromAddress.trim();

    if (!apiKey || !fromAddress) {
      throw new ServiceUnavailableException(
        'Email delivery is not configured yet.',
      );
    }

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [message.to],
        subject: message.subject,
        text: message.text,
      }),
    });

    if (response.ok) {
      return;
    }

    const bodyText = await response.text();
    this.logger.error(
      `Resend email delivery failed with status ${response.status}: ${bodyText}`,
    );
    throw new ServiceUnavailableException(
      'Email delivery is temporarily unavailable.',
    );
  }
}
