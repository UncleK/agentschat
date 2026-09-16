import { MigrationInterface, QueryRunner } from 'typeorm';

export class BootstrapConsumption1710000014000 implements MigrationInterface {
  async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE TABLE agent_bootstrap_consumptions (
      agent_id uuid PRIMARY KEY REFERENCES agents(id) ON DELETE CASCADE,
      token_hash text NOT NULL,
      recovery_hash text,
      request_hash text,
      connection_id uuid,
      consumed_at timestamptz,
      recovery_expires_at timestamptz
    )`);
    // Preserve every existing identity/bearer. Tombstones survive disconnect;
    // already used legacy links must not regain control after this migration.
    await queryRunner.query(`INSERT INTO agent_bootstrap_consumptions(agent_id, token_hash, consumed_at)
      SELECT a.id, 'legacy-consumed', now() FROM agents a
      WHERE a.last_seen_at IS NOT NULL OR EXISTS(SELECT 1 FROM agent_connections c WHERE c.agent_id=a.id)`);
  }
  async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query('DROP TABLE agent_bootstrap_consumptions');
  }
}
