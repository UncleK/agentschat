import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddAssetIngestionAndEventAssetReference1710000003000
  implements MigrationInterface
{
  name = 'AddAssetIngestionAndEventAssetReference1710000003000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TYPE "asset_kind_enum" AS ENUM ('image')`,
    );
    await queryRunner.query(
      `CREATE TYPE "asset_upload_status_enum" AS ENUM ('pending', 'uploaded')`,
    );
    await queryRunner.query(
      `CREATE TYPE "asset_moderation_status_enum" AS ENUM ('pending', 'approved', 'rejected')`,
    );

    await queryRunner.query(`
      CREATE TABLE "assets" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "kind" "asset_kind_enum" NOT NULL,
        "created_by_user_id" uuid,
        "original_file_name" character varying(255) NOT NULL,
        "mime_type" character varying(160) NOT NULL,
        "upload_status" "asset_upload_status_enum" NOT NULL DEFAULT 'pending',
        "moderation_status" "asset_moderation_status_enum" NOT NULL DEFAULT 'pending',
        "moderation_reason" character varying(255),
        "storage_bucket" character varying(255) NOT NULL,
        "storage_key" character varying(512) NOT NULL,
        "byte_size" integer,
        "upload_url_expires_at" TIMESTAMPTZ NOT NULL,
        "completed_at" TIMESTAMPTZ,
        "metadata" jsonb NOT NULL DEFAULT '{}'::jsonb,
        CONSTRAINT "PK_assets_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_assets_created_by_user_id" FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_assets_storage_key_unique" ON "assets" ("storage_key")`,
    );

    await queryRunner.query(`
      ALTER TABLE "events"
      ADD COLUMN IF NOT EXISTS "asset_id" uuid
    `);
    await queryRunner.query(`
      ALTER TABLE "events"
      ADD CONSTRAINT "FK_events_asset_id"
      FOREIGN KEY ("asset_id") REFERENCES "assets"("id") ON DELETE SET NULL
    `);
    await queryRunner.query(
      `CREATE INDEX "IDX_events_asset_id" ON "events" ("asset_id")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_events_asset_id"`,
    );
    await queryRunner.query(`
      ALTER TABLE "events"
      DROP CONSTRAINT IF EXISTS "FK_events_asset_id"
    `);
    await queryRunner.query(`
      ALTER TABLE "events"
      DROP COLUMN IF EXISTS "asset_id"
    `);

    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_assets_storage_key_unique"`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS "assets"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "asset_moderation_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "asset_upload_status_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "asset_kind_enum"`);
  }
}
