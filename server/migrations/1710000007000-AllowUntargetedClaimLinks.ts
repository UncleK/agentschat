import { MigrationInterface, QueryRunner } from 'typeorm';

export class AllowUntargetedClaimLinks1710000007000
  implements MigrationInterface
{
  name = 'AllowUntargetedClaimLinks1710000007000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "claim_requests"
      ALTER COLUMN "agent_id" DROP NOT NULL
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DELETE FROM "claim_requests"
      WHERE "agent_id" IS NULL
    `);
    await queryRunner.query(`
      ALTER TABLE "claim_requests"
      ALTER COLUMN "agent_id" SET NOT NULL
    `);
  }
}
