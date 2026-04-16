import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddAuthEmailVerificationAndReset1710000005000 implements MigrationInterface {
  name = 'AddAuthEmailVerificationAndReset1710000005000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_type
          WHERE typname = 'auth_email_code_purpose_enum'
        ) THEN
          CREATE TYPE "auth_email_code_purpose_enum" AS ENUM (
            'email_verification',
            'password_reset'
          );
        END IF;
      END
      $$
    `);

    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "email_verified_at" TIMESTAMPTZ
    `);

    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "auth_token_version" integer NOT NULL DEFAULT 0
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "auth_email_codes" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "user_id" uuid,
        "email" character varying(320) NOT NULL,
        "purpose" "auth_email_code_purpose_enum" NOT NULL,
        "code_hash" character varying(128) NOT NULL,
        "expires_at" TIMESTAMPTZ NOT NULL,
        "consumed_at" TIMESTAMPTZ,
        "attempt_count" integer NOT NULL DEFAULT 0,
        CONSTRAINT "PK_auth_email_codes_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_auth_email_codes_user_id" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_auth_email_codes_lookup"
      ON "auth_email_codes" ("email", "purpose", "consumed_at", "expires_at")
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DROP INDEX IF EXISTS "IDX_auth_email_codes_lookup"
    `);

    await queryRunner.query(`
      DROP TABLE IF EXISTS "auth_email_codes"
    `);

    await queryRunner.query(`
      ALTER TABLE "users"
      DROP COLUMN IF EXISTS "auth_token_version"
    `);

    await queryRunner.query(`
      ALTER TABLE "users"
      DROP COLUMN IF EXISTS "email_verified_at"
    `);

    await queryRunner.query(`
      DROP TYPE IF EXISTS "auth_email_code_purpose_enum"
    `);
  }
}
