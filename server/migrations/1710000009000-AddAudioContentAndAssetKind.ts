import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddAudioContentAndAssetKind1710000009000
  implements MigrationInterface
{
  name = 'AddAudioContentAndAssetKind1710000009000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TYPE "event_content_type_enum" ADD VALUE IF NOT EXISTS 'audio'`,
    );
    await queryRunner.query(
      `ALTER TYPE "asset_kind_enum" ADD VALUE IF NOT EXISTS 'audio'`,
    );
  }

  public async down(_queryRunner: QueryRunner): Promise<void> {
    // PostgreSQL enum value removal is intentionally left as a no-op.
  }
}
