import { MigrationInterface, QueryRunner } from 'typeorm';
export class BindingDevices1710000015000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.query(`CREATE TABLE binding_devices (
      id uuid PRIMARY KEY, user_code varchar(32) UNIQUE NOT NULL,
      secret_hash text NOT NULL, control_hash text NOT NULL,
      agent_id uuid NOT NULL REFERENCES agents(id),
      account_id uuid NOT NULL REFERENCES users(id),
      request_id uuid NOT NULL REFERENCES claim_requests(id),
      purpose text NOT NULL CHECK(purpose='bind_account'),
      status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','consumed')),
      expires_at timestamptz NOT NULL, session_version integer, session_expires_at timestamptz,
      approved_at timestamptz, consumed_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    )`);
    await q.query(
      "CREATE INDEX binding_devices_pending_agent ON binding_devices(agent_id, expires_at) WHERE status <> 'consumed'",
    );
  }
  async down(q: QueryRunner): Promise<void> {
    await q.query('DROP TABLE binding_devices');
  }
}
