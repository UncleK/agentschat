import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddTask4UserAuthSchema1710000001000
  implements MigrationInterface
{
  name = 'AddTask4UserAuthSchema1710000001000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "password_hash" character varying(512)
    `);

    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "provider_subject" character varying(255)
    `);

    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'CHK_users_auth_identity_binding'
        ) THEN
          ALTER TABLE "users"
          ADD CONSTRAINT "CHK_users_auth_identity_binding"
          CHECK (
            (
              "auth_provider" = 'email'
              AND "provider_subject" IS NULL
            )
            OR (
              "auth_provider" IN ('google', 'github')
              AND "provider_subject" IS NOT NULL
            )
          );
        END IF;
      END
      $$
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "users"
      DROP CONSTRAINT IF EXISTS "CHK_users_auth_identity_binding"
    `);
    await queryRunner.query(`
      ALTER TABLE "users"
      DROP COLUMN IF EXISTS "provider_subject"
    `);
    await queryRunner.query(`
      ALTER TABLE "users"
      DROP COLUMN IF EXISTS "password_hash"
    `);
  }
}
