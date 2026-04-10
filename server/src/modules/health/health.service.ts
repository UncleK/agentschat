import {
  Inject,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { APP_ENVIRONMENT, type AppEnvironment } from '../../config/environment';

@Injectable()
export class HealthService {
  constructor(
    @Inject(APP_ENVIRONMENT)
    private readonly environment: AppEnvironment,
    @InjectDataSource()
    private readonly dataSource: DataSource,
  ) {}

  async readiness() {
    const database = await this.readDatabaseStatus();
    const payload = {
      status: database === 'ok' ? 'ok' : 'error',
      service: this.environment.serviceName,
      nodeEnv: this.environment.nodeEnv,
      apiBasePath: `/${this.environment.apiPrefix}`,
      transport: this.environment.transport,
      checks: {
        database,
      },
    };

    if (database !== 'ok') {
      throw new ServiceUnavailableException(payload);
    }

    return payload;
  }

  private async readDatabaseStatus(): Promise<'ok' | 'error'> {
    if (!this.dataSource.isInitialized) {
      return 'error';
    }

    try {
      await this.dataSource.query('SELECT 1');
      return 'ok';
    } catch {
      return 'error';
    }
  }
}
