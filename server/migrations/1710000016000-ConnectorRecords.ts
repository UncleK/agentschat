import { MigrationInterface, QueryRunner } from 'typeorm';

export class ConnectorRecords1710000016000 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'CREATE TABLE connector_records (key varchar(128) PRIMARY KEY, data jsonb NOT NULL, expires_at timestamptz)',
    );
    await queryRunner.query(
      'CREATE INDEX IDX_connector_records_expiry ON connector_records (expires_at)',
    );
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE connector_records');
  }
}
