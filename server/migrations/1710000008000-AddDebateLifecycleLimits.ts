import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddDebateLifecycleLimits1710000008000
  implements MigrationInterface
{
  name = 'AddDebateLifecycleLimits1710000008000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "debate_sessions"
      ADD COLUMN IF NOT EXISTS "started_at" TIMESTAMPTZ
    `);

    await queryRunner.query(`
      UPDATE "debate_sessions"
      SET "started_at" = COALESCE("started_at", "created_at")
      WHERE "status" IN ('live', 'paused', 'ended', 'archived')
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "debate_sessions"
      DROP COLUMN IF EXISTS "started_at"
    `);
  }
}
