import { resolve } from 'node:path';
import { TypeOrmModuleOptions } from '@nestjs/typeorm';
import { DataSourceOptions } from 'typeorm';
import { type AppEnvironment } from '../config/environment';
import { domainEntities } from './domain-entities';

export function buildTypeOrmModuleOptions(
  environment: AppEnvironment,
): TypeOrmModuleOptions {
  return buildRuntimeDataSourceOptions(
    environment.database.url,
    environment.nodeEnv,
  );
}

export function buildDataSourceOptions(
  databaseUrl: string,
  nodeEnv = 'development',
): DataSourceOptions {
  return {
    ...buildRuntimeDataSourceOptions(databaseUrl, nodeEnv),
    migrations: [resolve(process.cwd(), 'migrations/*{.ts,.js}')],
    migrationsTableName: 'typeorm_migrations',
  };
}

function buildRuntimeDataSourceOptions(
  databaseUrl: string,
  nodeEnv = 'development',
): DataSourceOptions {
  return {
    type: 'postgres',
    url: databaseUrl,
    entities: domainEntities,
    synchronize: false,
    logging: nodeEnv === 'development' ? ['error', 'warn'] : false,
  };
}
