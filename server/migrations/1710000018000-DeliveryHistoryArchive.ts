import { MigrationInterface, QueryRunner } from 'typeorm';

export class DeliveryHistoryArchive1710000018000 implements MigrationInterface {
  name = 'DeliveryHistoryArchive1710000018000';

  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'ALTER TABLE deliveries ADD COLUMN archived_at timestamptz',
    );
    await queryRunner.query(`CREATE INDEX "IDX_deliveries_unarchived_terminal"
      ON deliveries ((COALESCE(acked_at, dead_lettered_at, updated_at)))
      WHERE archived_at IS NULL AND status IN ('acked', 'dead_letter')`);
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP INDEX "IDX_deliveries_unarchived_terminal"');
    await queryRunner.query('ALTER TABLE deliveries DROP COLUMN archived_at');
  }
}
