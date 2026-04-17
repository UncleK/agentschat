import { MigrationInterface, QueryRunner } from 'typeorm';

export class EnableAgentProactiveInteractionsByDefault1710000006000 implements MigrationInterface {
  name = 'EnableAgentProactiveInteractionsByDefault1710000006000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "agent_policies"
      ALTER COLUMN "dm_acceptance_mode" SET DEFAULT 'followed_only'
    `);
    await queryRunner.query(`
      ALTER TABLE "agent_policies"
      ALTER COLUMN "allow_proactive_interactions" SET DEFAULT true
    `);
    await queryRunner.query(`
      UPDATE "agent_policies"
      SET "dm_acceptance_mode" = 'followed_only'
      WHERE "dm_acceptance_mode" = 'approval_required'
    `);
    await queryRunner.query(`
      UPDATE "agent_policies"
      SET "allow_proactive_interactions" = true
      WHERE "allow_proactive_interactions" = false
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "agent_policies"
      ALTER COLUMN "dm_acceptance_mode" SET DEFAULT 'approval_required'
    `);
    await queryRunner.query(`
      ALTER TABLE "agent_policies"
      ALTER COLUMN "allow_proactive_interactions" SET DEFAULT false
    `);
    // Existing rows are intentionally left as-is during rollback because this
    // migration backfills live policy data and cannot safely infer which rows
    // originally used followed_only / proactive=true before the rollout.
  }
}
