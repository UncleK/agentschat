import { MigrationInterface, QueryRunner } from 'typeorm';
import { DEFAULT_DELIVERY_RETENTION_MS } from '../src/database/delivery-policy';

export class DurableAgentInboxes1710000017000 implements MigrationInterface {
  name = 'DurableAgentInboxes1710000017000';

  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      'ALTER TABLE deliveries ADD COLUMN webhook_attempt_count integer NOT NULL DEFAULT 0',
    );
    await queryRunner.query(
      'CREATE INDEX "IDX_deliveries_retention" ON deliveries (status, replay_expires_at)',
    );
    const retentionMs = Number(
      process.env.DELIVERY_RETENTION_MS ?? DEFAULT_DELIVERY_RETENTION_MS,
    );
    if (!Number.isSafeInteger(retentionMs) || retentionMs <= 0)
      throw new Error('DELIVERY_RETENTION_MS must be a positive integer.');

    // Restore only unattempted public polling notifications affected by the
    // old short window. Keep IDs, sequence and creation time for client dedup.
    await queryRunner.query(
      `UPDATE deliveries d
       SET status = 'pending', next_attempt_at = now(),
           replay_expires_at = d.created_at + ($1 * interval '1 millisecond'),
           dead_lettered_at = NULL, last_error = NULL
       FROM events e JOIN threads t ON t.id = e.thread_id
       WHERE d.event_id = e.id AND t.visibility = 'public'
         AND (e.event_type LIKE 'forum.%' OR e.event_type LIKE 'debate.%')
         AND e.metadata->'moderation'->>'hidden' IS DISTINCT FROM 'true'
         AND e.metadata->'moderation'->>'deleted' IS DISTINCT FROM 'true'
         AND t.metadata->'moderation'->>'hidden' IS DISTINCT FROM 'true'
         AND t.metadata->'moderation'->>'deleted' IS DISTINCT FROM 'true'
         AND d.delivery_channel = 'polling' AND d.attempt_count = 0
         AND d.acked_at IS NULL AND d.status IN ('pending', 'dead_letter')
         AND d.replay_expires_at <= d.created_at + interval '16 minutes'
         AND d.created_at + ($1 * interval '1 millisecond') > now()`,
      [retentionMs],
    );
  }

  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP INDEX "IDX_deliveries_retention"');
    await queryRunner.query(
      'ALTER TABLE deliveries DROP COLUMN webhook_attempt_count',
    );
  }
}
