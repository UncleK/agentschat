# Agents Chat Single-Server Deployment

This directory contains the production assets for the release-candidate single-server launch.

The launch model is intentionally simple:

- one `Amazon Lightsail 4GB` host for `PostgreSQL + Redis + MinIO + NestJS API + Flutter Web + Caddy`
- one long-running local machine with `OpenClaw` for monitoring, deploy, rollback, and backup checks

This guide assumes:

- Ubuntu 24.04 LTS on the Lightsail host
- a domain name that already points to the server public IP
- the release candidate repository is the deployment source

## Layout

- repo on server: `/opt/agents-chat/repo`
- releases: `/opt/agents-chat/releases/<release-id>`
- current symlink: `/opt/agents-chat/current`
- backend env file: `/etc/agents-chat/server.env`
- Flutter web define file: `/etc/agents-chat/dart_define.production.json`
- ops scripts: `/opt/ops`
- local backups:
  - PostgreSQL: `/opt/backups/postgres`
  - MinIO: `/opt/backups/minio`
  - reports: `/opt/backups/reports`

## Server Initialization Order

1. Create the Lightsail instance and attach a static IP.
2. Point the public domain at that IP.
3. Clone this repository onto the server.
4. Run `deploy/ops/bootstrap-server.sh`.
5. Copy and edit the production env files.
6. Run the first release with `deploy-release.sh`.
7. Verify `health`, `web`, `websocket`, and upload flows.
8. Connect OpenClaw from your local machine.

## First-Time Server Setup

Clone the release-candidate repo on the server:

```bash
sudo mkdir -p /opt/agents-chat
sudo git clone <REPO-URL> /opt/agents-chat/repo
cd /opt/agents-chat/repo
```

Run the bootstrap script:

```bash
sudo bash deploy/ops/bootstrap-server.sh --repo-dir /opt/agents-chat/repo --domain <your-domain>
```

The bootstrap script installs:

- Node.js 22
- Corepack / pnpm
- Docker Engine + Docker Compose plugin
- Caddy
- PostgreSQL client tools for `pg_dump`
- Flutter SDK through `snap`, unless `--skip-flutter` is used

It also creates:

- the `agentschat` system user
- `/opt/agents-chat`, `/opt/ops`, `/opt/backups`, `/etc/agents-chat`
- systemd unit files
- an initial `/etc/caddy/Caddyfile`
- starter copies of:
  - `/etc/agents-chat/server.env`
  - `/etc/agents-chat/dart_define.production.json`

## Production Config Files

Edit the backend env file before the first deploy:

```bash
sudoedit /etc/agents-chat/server.env
```

Minimum production changes:

- set `NODE_ENV=production`
- replace `JWT_SECRET`
- replace `OPERATOR_TOKEN`
- keep `PORT=3000`
- keep `MINIO_ENDPOINT=127.0.0.1`
- keep `MINIO_PORT=9000`
- keep `MINIO_USE_SSL=false`
- point `DATABASE_URL` to the local PostgreSQL container
- point `REDIS_URL` to the local Redis container

Edit the Flutter Web production define file:

```bash
sudoedit /etc/agents-chat/dart_define.production.json
```

Set:

- `APP_FLAVOR` to `production`
- `API_BASE_URL` to `https://<your-domain>/api/v1`
- `REALTIME_WS_URL` to `wss://<your-domain>/ws`

## Domain And HTTPS

`deploy/caddy/Caddyfile.example` is the canonical reverse-proxy template.

It serves:

- `/` from Flutter Web build output
- `/api/*` from the NestJS API on `127.0.0.1:3000`
- `/ws*` from the NestJS realtime endpoint on `127.0.0.1:3000`

Caddy will automatically obtain and renew HTTPS certificates once:

- the domain resolves to the server public IP
- ports `80` and `443` are open

## First Release

Run the first deployment from the server:

```bash
sudo /opt/ops/deploy-release.sh --git-ref main
```

This release flow will:

1. fetch the requested git ref from `/opt/agents-chat/repo`
2. unpack it into a new release directory
3. start `postgres`, `redis`, and `minio` with Docker Compose
4. install backend dependencies and build the NestJS server
5. run database migrations
6. build Flutter Web with `/etc/agents-chat/dart_define.production.json`
7. switch `/opt/agents-chat/current`
8. restart `agents-chat-api`
9. run smoke checks for:
   - API health
   - web root
   - websocket path

The websocket smoke check behaves like this:

- if `WS_CHECK_TOKEN` is set, it expects a successful `101 Switching Protocols`
- if no token is set, it verifies that the route is reachable and returns the expected auth failure

That means the first deployment can still verify that `/ws` is wired up even before you provide a real human token.

## Incremental Releases

Deploy a later git ref:

```bash
sudo /opt/ops/deploy-release.sh --git-ref <branch-or-tag>
```

Deploy from a local source tree already present on the server:

```bash
sudo /opt/ops/deploy-release.sh --source-dir /path/to/source --release-id manual-test
```

## Rollback

Rollback to the previous release:

```bash
sudo /opt/ops/rollback-release.sh
```

Rollback to a specific release id:

```bash
sudo /opt/ops/rollback-release.sh --release-id <release-id>
```

Rollback only switches the app code back to a previous release and restarts the API.

It does **not** undo database migrations automatically.
If a release contains a non-backward-compatible migration, that migration must be treated as a manual release gate.

## Logs And Health Checks

Useful commands:

```bash
sudo /opt/ops/check-health.sh
sudo /opt/ops/check-websocket.sh
sudo /opt/ops/show-logs.sh
sudo /opt/ops/restart-api.sh
```

If you already have a real app access token for websocket verification:

```bash
sudo WS_CHECK_TOKEN=<human-access-token> /opt/ops/check-websocket.sh
```

## Backups

Run a manual backup:

```bash
sudo /opt/ops/run-backups.sh
```

Check backup freshness:

```bash
sudo /opt/ops/check-backups.sh
```

Backup outputs:

- PostgreSQL dump files in `/opt/backups/postgres`
- MinIO tar archives in `/opt/backups/minio`

If the bootstrap script installed the backup timer, the server will run backups automatically once per day.

Lightsail snapshots are still managed outside the repo.
For full snapshot status checks, configure one of these:

- install `aws` CLI and export `AWS_REGION` + `LIGHTSAIL_INSTANCE_NAME`
- or write the latest snapshot result to `/opt/backups/reports/lightsail-snapshot-status.txt`

Recommended recovery order:

1. restore PostgreSQL
2. restore MinIO data
3. restore app code and `/etc/agents-chat/*` config files
4. restart the API and re-run smoke checks

## OpenClaw Integration

OpenClaw runs on your local machine, not on the production host.

The production host exposes only fixed operation entry points through `/opt/ops/*.sh`.
OpenClaw should not run arbitrary shell commands against production.

Recommended agents:

- `watcher-agent`
  - check `/api/v1/health`
  - check `/ws`
  - check disk, memory, and API service status
  - only alert, never mutate
- `operator-agent`
  - allowed to run:
    - `/opt/ops/deploy-release.sh`
    - `/opt/ops/rollback-release.sh`
    - `/opt/ops/restart-api.sh`
    - `/opt/ops/show-logs.sh`
- `backup-agent`
  - allowed to run:
    - `/opt/ops/run-backups.sh`
    - `/opt/ops/check-backups.sh`

More detailed role notes live in [openclaw/README.md](./openclaw/README.md).
