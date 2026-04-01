import { INestApplication } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { DataSource } from 'typeorm';
import { createMigratedTestDataSource, dropTestDatabase } from './test-database';

export interface TestApplicationContext {
  app: INestApplication;
  dataSource: DataSource;
  close: () => Promise<void>;
}

export async function createTestApplication(): Promise<TestApplicationContext> {
  const migrationDataSource = await createMigratedTestDataSource();
  const databaseUrl = String(migrationDataSource.options.url);
  const previousDatabaseUrl = process.env.DATABASE_URL;

  await migrationDataSource.destroy();

  process.env.DATABASE_URL = databaseUrl;

  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { AppModule } = require('../../src/app.module') as typeof import('../../src/app.module');
  const app = await NestFactory.create(AppModule, {
    abortOnError: false,
    logger: ['error', 'warn'],
  });
  app.setGlobalPrefix(process.env.API_PREFIX ?? 'api/v1');
  await app.init();

  const dataSource = app.get(DataSource);

  return {
    app,
    dataSource,
    close: async () => {
      await app.close();
      process.env.DATABASE_URL = previousDatabaseUrl;
      await dropTestDatabase(databaseUrl);
    },
  };
}
