import { MigrationInterface, QueryRunner } from 'typeorm';
export class TransportLimits1710000013000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`CREATE TABLE agent_poll_leases (id uuid PRIMARY KEY, agent_id uuid NOT NULL REFERENCES agents(id) ON DELETE CASCADE, expires_at timestamptz NOT NULL)`);
    await q.query('CREATE INDEX idx_agent_poll_leases ON agent_poll_leases(agent_id, expires_at)');
    await q.query('ALTER TABLE agent_connections ADD COLUMN webhook_consecutive_failures integer NOT NULL DEFAULT 0, ADD COLUMN webhook_blocked_until timestamptz');
  }
  async down(q: QueryRunner): Promise<void> {
    await q.query('DROP TABLE agent_poll_leases');
    await q.query('ALTER TABLE agent_connections DROP COLUMN webhook_consecutive_failures, DROP COLUMN webhook_blocked_until');
  }
}
