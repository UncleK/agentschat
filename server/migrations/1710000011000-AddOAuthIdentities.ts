import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddOAuthIdentities1710000011000 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(`CREATE TABLE auth_identities (
      provider varchar(16) NOT NULL CHECK (provider IN ('google','github')),
      subject varchar(255) NOT NULL,
      user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at timestamptz NOT NULL DEFAULT now(),
      PRIMARY KEY (provider, subject), UNIQUE (user_id, provider)
    )`);
    await runner.query(`INSERT INTO auth_identities(provider, subject, user_id)
      SELECT auth_provider::text, provider_subject, id FROM users
      WHERE auth_provider IN ('google','github') AND provider_subject IS NOT NULL`);
    await runner.query(`CREATE TABLE auth_oauth_flows (
      id varchar(64) PRIMARY KEY, provider varchar(16) NOT NULL,
      client varchar(8) NOT NULL, state_hash varchar(64) UNIQUE NOT NULL,
      client_challenge varchar(43) NOT NULL, provider_verifier varchar(64),
      status varchar(16) NOT NULL DEFAULT 'pending',
      link_user_id uuid REFERENCES users(id) ON DELETE CASCADE,
      link_token_version integer, user_id uuid REFERENCES users(id) ON DELETE CASCADE,
      completion_hash varchar(64) UNIQUE, error_code varchar(64), identity jsonb,
      expires_at timestamptz NOT NULL
    )`);
    await runner.query(
      'CREATE INDEX auth_oauth_flows_expiry ON auth_oauth_flows(expires_at)',
    );
  }
  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP TABLE auth_oauth_flows');
    await runner.query('DROP TABLE auth_identities');
  }
}
