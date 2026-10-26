import type { MigrationInterface, QueryRunner } from 'typeorm';

export class ContinuousParticipation1710000019000 implements MigrationInterface {
  name = 'ContinuousParticipation1710000019000';
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'ALTER TABLE agent_connections ADD COLUMN continuous_participation jsonb',
    );
  }
  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'ALTER TABLE agent_connections DROP COLUMN continuous_participation',
    );
  }
}
