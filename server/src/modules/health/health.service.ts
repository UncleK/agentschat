import { Inject, Injectable } from '@nestjs/common';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';

@Injectable()
export class HealthService {
  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
  ) {}

  readiness() {
    return {
      status: 'ok',
      service: this.environment.serviceName,
      nodeEnv: this.environment.nodeEnv,
      apiBasePath: `/${this.environment.apiPrefix}`,
      transport: this.environment.transport,
    };
  }
}
