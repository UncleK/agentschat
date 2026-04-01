import { randomUUID } from 'node:crypto';
import { Client } from 'pg';
import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from '../../../src/database/typeorm.config';

export async function createDomainTestDataSource(): Promise<DataSource> {
  const testDatabaseUrl = buildTestDatabaseUrl();

  await recreateDatabase(testDatabaseUrl);

  const dataSource = new DataSource(
    buildDataSourceOptions(testDatabaseUrl, 'test'),
  );
  await dataSource.initialize();
  await dataSource.runMigrations();

  return dataSource;
}

export async function destroyDomainTestDataSource(
  dataSource: DataSource | undefined,
): Promise<void> {
  if (!dataSource) {
    return;
  }

  const databaseUrl = String(dataSource.options.url);

  if (dataSource.isInitialized) {
    await dataSource.destroy();
  }

  await dropDatabase(databaseUrl);
}

function buildTestDatabaseUrl(): string {
  const sourceUrl = new URL(process.env.DATABASE_URL!);
  const databaseName = `agents_chat_domain_test_${randomUUID().replace(/-/g, '')}`;

  sourceUrl.pathname = `/${databaseName}`;

  return sourceUrl.toString();
}

async function recreateDatabase(databaseUrl: string): Promise<void> {
  const adminUrl = new URL(databaseUrl);
  adminUrl.pathname = '/postgres';

  const client = new Client({
    connectionString: adminUrl.toString(),
  });

  await client.connect();

  try {
    await client.query(
      `DROP DATABASE IF EXISTS ${quoteIdentifier(getDatabaseName(databaseUrl))} WITH (FORCE)`,
    );
    await client.query(
      `CREATE DATABASE ${quoteIdentifier(getDatabaseName(databaseUrl))}`,
    );
  } finally {
    await client.end();
  }
}

async function dropDatabase(databaseUrl: string): Promise<void> {
  const adminUrl = new URL(databaseUrl);
  adminUrl.pathname = '/postgres';

  const client = new Client({
    connectionString: adminUrl.toString(),
  });

  await client.connect();

  try {
    await client.query(
      `DROP DATABASE IF EXISTS ${quoteIdentifier(getDatabaseName(databaseUrl))} WITH (FORCE)`,
    );
  } finally {
    await client.end();
  }
}

function getDatabaseName(databaseUrl: string): string {
  return new URL(databaseUrl).pathname.replace(/^\//, '');
}

function quoteIdentifier(value: string): string {
  return `"${value.replace(/"/g, '""')}"`;
}
