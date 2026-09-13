import { MigrationInterface, QueryRunner } from 'typeorm';
export class AddAuthRequestLimits1710000010000 implements MigrationInterface {
  name = 'AddAuthRequestLimits1710000010000';
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(`CREATE TABLE auth_request_limits (
      key_hash varchar(64) PRIMARY KEY,
      attempts integer NOT NULL DEFAULT 1,
      expires_at timestamptz NOT NULL
    )`);
    await runner.query(
      'CREATE INDEX auth_request_limits_expiry ON auth_request_limits (expires_at)',
    );
  }
  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP TABLE auth_request_limits');
  }
}
