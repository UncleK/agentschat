import { MigrationInterface, QueryRunner } from 'typeorm';

export class DurableFederationWork1710000012000 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE federation_actions ADD COLUMN lease_owner uuid, ADD COLUMN lease_expires_at timestamptz`);
    // Old processing rows may already have committed effects. Require explicit
    // reconciliation instead of automatically replaying ambiguous legacy work.
    await queryRunner.query(`UPDATE federation_actions SET lease_expires_at = 'infinity' WHERE status = 'processing'`);
    await queryRunner.query(`CREATE INDEX idx_action_recovery ON federation_actions (lease_expires_at, accepted_at) WHERE status IN ('accepted', 'processing')`);
    await queryRunner.query(`CREATE INDEX idx_delivery_outstanding ON deliveries (recipient_agent_id, sequence) WHERE status IN ('pending', 'sent', 'retrying')`);
    await queryRunner.query(`CREATE TABLE event_outbox (
      event_id uuid PRIMARY KEY REFERENCES events(id) ON DELETE CASCADE,
      created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
      lease_owner uuid, lease_expires_at timestamptz, attempts integer NOT NULL DEFAULT 0,
      next_attempt_at timestamptz NOT NULL DEFAULT now(), last_error text
    )`);
    await queryRunner.query(`CREATE INDEX idx_event_outbox_pending ON event_outbox (next_attempt_at, created_at) WHERE completed_at IS NULL`);
    await queryRunner.query(`CREATE FUNCTION agentschat_event_outbox_insert() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN INSERT INTO event_outbox(event_id) VALUES (NEW.id) ON CONFLICT DO NOTHING; RETURN NEW; END $$`);
    await queryRunner.query(`CREATE TRIGGER agentschat_event_outbox AFTER INSERT ON events FOR EACH ROW EXECUTE FUNCTION agentschat_event_outbox_insert()`);
    // No unsolicited historical fanout. Existing gaps are reviewed/backfilled
    // explicitly using event IDs; all new business events are atomic with outbox.
  }
  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TRIGGER agentschat_event_outbox ON events');
    await queryRunner.query('DROP FUNCTION agentschat_event_outbox_insert()');
    await queryRunner.query('DROP TABLE event_outbox');
    await queryRunner.query('DROP INDEX idx_delivery_outstanding');
    await queryRunner.query('DROP INDEX idx_action_recovery');
    await queryRunner.query('ALTER TABLE federation_actions DROP COLUMN lease_owner, DROP COLUMN lease_expires_at');
  }
}
