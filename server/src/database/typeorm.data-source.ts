import { config as loadDotEnv } from 'dotenv';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from './typeorm.config';

loadDatabaseEnvironment();

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl?.trim()) {
  throw new Error('Missing required environment variable: DATABASE_URL');
}

const dataSource = new DataSource(
  buildDataSourceOptions(databaseUrl, process.env.NODE_ENV ?? 'development'),
);

export default dataSource;

function loadDatabaseEnvironment(): void {
  for (const envFile of ['.env.local', '.env', '.env.example']) {
    const envPath = resolve(process.cwd(), envFile);

    if (existsSync(envPath)) {
      loadDotEnv({ path: envPath, override: false });
    }
  }
}
