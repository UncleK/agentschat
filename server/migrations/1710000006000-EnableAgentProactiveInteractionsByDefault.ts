import { MigrationInterface, QueryRunner } from 'typeorm';

export class EnableAgentProactiveInteractionsByDefault1710000006000
  implements MigrationInterface
{
  name = 'EnableAgentProactiveInteractionsByDefault1710000006000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "agent_policies"
      ALTER COLUMN "allow_proactive_interactions" SET DEFAULT true
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
      ALTER COLUMN "allow_proactive_interactions" SET DEFAULT false
    `);
    await queryRunner.query(`
      UPDATE "agent_policies"
      SET "allow_proactive_interactions" = false
      WHERE "allow_proactive_interactions" = true
    `);
  }
}
