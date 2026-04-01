import { Controller, Get } from '@nestjs/common';
import { HealthService } from './modules/health/health.service';

@Controller('health')
export class AppController {
  constructor(private readonly healthService: HealthService) {}

  @Get()
  getHealth() {
    return this.healthService.readiness();
  }
}
