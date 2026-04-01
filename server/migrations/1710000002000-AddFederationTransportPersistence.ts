import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddFederationTransportPersistence1710000002000
  implements MigrationInterface
{
  name = 'AddFederationTransportPersistence1710000002000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TYPE "federation_action_status_enum" AS ENUM ('accepted', 'processing', 'succeeded', 'rejected', 'failed')`,
    );

    await queryRunner.query(`
      CREATE TABLE "federation_actions" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "updated_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "agent_id" uuid NOT NULL,
        "action_type" character varying(120) NOT NULL,
        "status" "federation_action_status_enum" NOT NULL DEFAULT 'accepted',
        "idempotency_key" character varying(255) NOT NULL,
        "request_hash" character varying(128) NOT NULL,
        "payload" jsonb NOT NULL DEFAULT '{}'::jsonb,
        "result_payload" jsonb NOT NULL DEFAULT '{}'::jsonb,
        "error_payload" jsonb,
        "thread_id" uuid,
        "event_id" uuid,
        "accepted_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
        "processing_started_at" TIMESTAMPTZ,
        "completed_at" TIMESTAMPTZ,
        CONSTRAINT "PK_federation_actions_id" PRIMARY KEY ("id"),
        CONSTRAINT "FK_federation_actions_agent_id" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_federation_actions_thread_id" FOREIGN KEY ("thread_id") REFERENCES "threads"("id") ON DELETE SET NULL,
        CONSTRAINT "FK_federation_actions_event_id" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE SET NULL
      )
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_federation_actions_agent_idempotency_unique" ON "federation_actions" ("agent_id", "idempotency_key")`,
    );

    await queryRunner.query(`
      ALTER TABLE "agent_connections"
      ADD COLUMN IF NOT EXISTS "webhook_secret" character varying(512)
    `);

    await queryRunner.query(`
      ALTER TABLE "deliveries"
      ADD COLUMN IF NOT EXISTS "sequence" integer
    `);
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      ADD COLUMN IF NOT EXISTS "replay_expires_at" TIMESTAMPTZ
    `);
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      ADD COLUMN IF NOT EXISTS "dead_lettered_at" TIMESTAMPTZ
    `);

    await queryRunner.query(`
      WITH ranked_deliveries AS (
        SELECT id,
          ROW_NUMBER() OVER (
            PARTITION BY recipient_agent_id
            ORDER BY created_at ASC, id ASC
          ) AS sequence,
          COALESCE(next_attempt_at, created_at + INTERVAL '1 day') AS replay_expires_at
        FROM deliveries
      )
      UPDATE deliveries AS delivery
      SET sequence = ranked_deliveries.sequence,
          replay_expires_at = ranked_deliveries.replay_expires_at
      FROM ranked_deliveries
      WHERE delivery.id = ranked_deliveries.id
    `);

    await queryRunner.query(`
      ALTER TABLE "deliveries"
      ALTER COLUMN "sequence" SET NOT NULL
    `);
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      ALTER COLUMN "replay_expires_at" SET NOT NULL
    `);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_deliveries_recipient_sequence_unique" ON "deliveries" ("recipient_agent_id", "sequence")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_deliveries_recipient_sequence_unique"`,
    );
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      DROP COLUMN IF EXISTS "dead_lettered_at"
    `);
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      DROP COLUMN IF EXISTS "replay_expires_at"
    `);
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      DROP COLUMN IF EXISTS "sequence"
    `);
    await queryRunner.query(`
      ALTER TABLE "agent_connections"
      DROP COLUMN IF EXISTS "webhook_secret"
    `);

    await queryRunner.query(
      `DROP INDEX IF EXISTS "IDX_federation_actions_agent_idempotency_unique"`,
    );
    await queryRunner.query(`DROP TABLE IF EXISTS "federation_actions"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "federation_action_status_enum"`);
  }
}
