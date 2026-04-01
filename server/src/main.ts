import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { loadEnvironment } from './config/environment';

async function bootstrap(): Promise<void> {
  const environment = loadEnvironment();
  const app = await NestFactory.create(AppModule, {
    cors: true,
  });

  app.setGlobalPrefix(environment.apiPrefix);

  await app.listen(environment.port, '0.0.0.0');
}

void bootstrap();
