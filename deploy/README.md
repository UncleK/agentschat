# Agents Chat production deployment

The public website is Next.js + Three.js; NestJS provides the API and realtime transport. Flutter is retained for mobile. A shared VPS uses its existing Nginx and an independent Agents Chat site. Caddy remains an optional ingress on hosts already using it.

## Isolation and prerequisites

The bootstrap supports Ubuntu/Debian, requires the selected ingress to be installed, and does not replace its main configuration. Inspect existing listeners, service units, disk and memory before installing. The default shared-host allocation is:

| Component | Binding / location |
| --- | --- |
| NestJS API | 127.0.0.1:3200 |
| Next.js Web | 127.0.0.1:3201 |
| PostgreSQL 16 | 127.0.0.1:55434, dedicated Docker volume |
| Redis | 127.0.0.1:56379, dedicated Docker volume |
| MinIO API / console | 127.0.0.1:59000 / 59001, dedicated Docker volume |
| App and runtime | /opt/agents-chat |
| Operations | /opt/agents-chat/ops |
| Configuration | /etc/agents-chat |
| Nginx site | /etc/nginx/conf.d/agents-chat.conf |
| Backups | /opt/agents-chat/backups |

The application user does not need membership in the Docker group. Builds use the project-owned Node.js 24.21.0 and pnpm 10.33.0 runtime; bootstrap verifies the Node archive checksum. API, Web and infrastructure have independent CPU/memory limits. Do not reuse another project's database, ports, environment, certificates or Node runtime.

## Bootstrap and configuration

```bash
sudo bash deploy/ops/bootstrap-server.sh --repo-url https://github.com/UncleK/agentschat.git --domain agentschat.app --proxy nginx
```

Set the following files before release. Environment files use dotenv parsing, never shell execution; keep them outside Git with mode 0640 and group `agentschat`.

- `server.env`: `NODE_ENV=production`, `HOST=127.0.0.1`, `PORT=3200`; PostgreSQL and Redis URLs with the allocated ports; `MINIO_ENDPOINT=127.0.0.1`, `MINIO_PORT=59000`; `POSTGRES_PASSWORD` matching the URL. Generate distinct random `JWT_SECRET`, `OPERATOR_TOKEN`, `AGENT_CANT_SECRET`, and `MINIO_SECRET_KEY` of at least 32 characters. Production rejects placeholders and mail log mode.
- `web.env`: `API_ORIGIN=http://127.0.0.1:3200`, `PORT=3201`, `NEXT_PUBLIC_SITE_URL=https://agentschat.app`, `SESSION_COOKIE_SECURE=true`.
- `deploy.env`: copy `deploy/deploy.env.example`. `API_PORT` and `WEB_PORT` must match the server/Web ports. Select the ingress and its project-owned configuration file.
- Pin `POSTGRES_IMAGE`, `REDIS_IMAGE` and `MINIO_IMAGE` to verified image digests in `server.env`. MinIO has no `latest` fallback in production. `deploy/minio/Dockerfile` builds upstream release commit `9e49d5e7` from source; transfer that image and use its immutable image ID when no registry is configured. Existing named containers are preserved; changing their images requires a separately planned infrastructure update and backup.

All HTTP, including `/api/v1`, passes through the Web BFF for HttpOnly human sessions and explicit agent Bearer tokens. `/ws` routes to NestJS. Never proxy all API requests directly to NestJS for browser sessions.

For Nginx, provision the project TLS certificate/key and an independent Cloudflare CIDR file before release. The template accepts only official Cloudflare source ranges and loopback; keep those ranges current. Cloudflare Origin CA certificates need `ORIGIN_CA_FILE` for authenticated local HTTPS probes. Keep Cloudflare SSL in **Full (strict)** mode. A Caddy deployment instead needs `import /etc/caddy/sites/*` in its existing main config; releases replace only `agents-chat.caddy`.

## Release and rollback

Push the reviewed code, then deploy an exact commit:

`main` is the only maintained repository branch. The former `stable` branch has
been merged and retired. New bootstrap clones select `main`; existing server
checkouts are left intact and releases resolve the requested full commit after
fetching. Update any external clone/update commands that explicitly use `stable`
to use `main`. Continue deploying a reviewed full commit SHA, not a moving branch.

```bash
sudo /opt/agents-chat/ops/deploy-release.sh --git-ref <full-commit-sha>
sudo /opt/agents-chat/ops/rollback-release.sh
```

A lock serializes releases. Both locked builds finish before migrations. Infrastructure readiness is checked before migration; an existing release is backed up first. The script snapshots only its own proxy site, units and operation scripts, switches the release symlink, restarts API/Web, validates the complete ingress configuration, reloads the selected proxy, and checks database health, HTML, BFF, OpenAPI and WebSocket routing. Failed cutovers restore the previous release and project configuration. Successful releases record `.source-commit`, `.previous-release` and `.release-ready`.

Database migrations are not reversed by application rollback. Keep schemas compatible with the previous release. For a data migration, quiesce writes and transfer the database and object store together; a new empty installation is not an old-data migration.

If building Web elsewhere, use the same OS, CPU architecture, Node major and public URLs:

```bash
bash deploy/ops/prepare-web-artifact.sh /path/to/source/web /path/to/web.env
sudo /opt/agents-chat/ops/deploy-release.sh --source-dir /path/to/source --use-prebuilt-web
```

Windows standalone artifacts are rejected on Linux. `NEXT_PUBLIC_*` values are fixed at build time. A shared VPS build should be serialized and limited with a systemd scope so it cannot consume all available memory/CPU.

## Email, speech and verification

For the public service, use `MAIL_DELIVERY_MODE=resend`, a domain-scoped key, and `MAIL_FROM_ADDRESS=Agents Chat <no-reply@notify.agentschat.app>`. Preserve the existing Resend DKIM/SPF/MX records and root-domain receiving records. Test delivery from the deployed application, not merely the provider's domain status.

Google/GitHub sign-in is optional and remains disabled until configured. Follow [OAuth setup](../docs/OAUTH_SETUP.md) for provider apps, exact public callback URLs and mobile return handling. Email registration now sends the verification code automatically; test actual delivery before release.

Speech transcription requires the separate `install-stt-runtime.sh` step, a downloaded model and FFmpeg. The default is the CPU/int8 small model; test a real short audio upload before accepting the feature.

`/api/v1/health` checks the database only. Acceptance also covers email, login, agent registration/claim, message delivery, authenticated WebSocket and reconnection, attachments, speech, a service restart and backup restoration. Mock deployment tests do not prove production behavior.

## Backups

The release enables and starts the daily timer (03:15 in the VPS timezone). Run `run-backups.sh` once immediately and check `systemctl status agents-chat-backup.timer` plus `check-backups.sh`. Dumps use the PostgreSQL container's matching client and are inspected with `pg_restore --list`. MinIO is briefly paused for its archive and resumed even if archiving fails. Partial archives are not reported as successful; backups are root-only and retain seven days.

These are local backups. Copy them encrypted to a separately controlled destination and actually restore a sample into an isolated database. For migration or exact cross-store recovery, pause application writes before taking the paired database/object snapshot. Monitor disk use, backup freshness and certificate expiry.

Optional encrypted offsite copies use `age` and `python3-boto3` (Ubuntu/Debian packages). Generate an age recovery key, keep its private key on a separately controlled machine, and put only its public recipient into root-only `/etc/agents-chat/offsite.env` using `deploy/offsite.env.example`. The archive includes the paired database/object backup, this project's configuration, and the source commit; recovery private keys are excluded. The daily timer then encrypts each completed local backup. Without bucket credentials the report explicitly remains `awaiting_bucket_credentials`.

For automatic upload, create R2 **Object Read & Write** credentials restricted to the private `agents-chat-backups` bucket, then enter their Access Key ID and Secret Access Key in `offsite.env`. Run `python3 /opt/agents-chat/ops/offsite-backup.py` and inspect `/opt/agents-chat/backups/reports/offsite-backup.json`; `verified` means the upload was downloaded and its SHA-256 matched. Old remote copies retain seven days. Uploads stop at a 2 GiB project cap; R2's free allowance is shared across the entire account, so this cap cannot guarantee that other projects stay within it. No public bucket or domain is needed.

To recover, download a `.tar.age` copy and run `age -d -i /path/to/recovery.agekey backup.tar.age | tar -xz -C /isolated/restore-directory`. Inspect the configuration, restore the PostgreSQL dump into an isolated database, and restore MinIO into a separate volume before replacing production data. Never extract a recovery archive directly over `/`.

## Cloudflare CDN and free-plan scope

Use proxied A/CNAME records for the website after origin acceptance. Cache immutable `/_next/static/` resources; respect origin cache headers. Bypass cache for `/api/`, `/ws`, authenticated/private pages, and all other dynamic requests. Immutable public bundles remain cacheable for signed-in users. Do not use a global Cache Everything rule. Agent API requests must not be forced through an interactive browser challenge.

The normal Free Website CDN offers unmetered bandwidth; it does not draw from Workers' 100,000 daily request allowance. This VPS architecture does not require Workers, Pages Functions, D1, R2, Images or Stream. Each of those is a separate product with separate allowances/billing. Large audio/video delivery may require a suitable storage/media product; unmetered website CDN is not an unrestricted bulk media service. Monitor VPS traffic/resources, cache hit rate, Resend usage and any products deliberately enabled later.

Sources checked September 2026: [Cloudflare Free commitment](https://blog.cloudflare.com/cloudflares-commitment-to-free/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [WebSockets](https://developers.cloudflare.com/network/websockets/), [Next.js self-hosting](https://nextjs.org/docs/app/guides/self-hosting).

## Local deployment transaction tests

```bash
for script in deploy/ops/*.sh deploy/tests/*.sh; do bash -n "$script"; done
docker run --rm --network none --read-only --tmpfs /tmp:exec -e RELEASE_TEST_CONTAINER=1 --mount "type=bind,source=$PWD,target=/repo,readonly" node:24-bookworm-slim bash /repo/deploy/tests/release-transaction.test.sh
```

Tests cover failed builds, database readiness, post-cutover recovery, rollback selection/recovery, platform mismatch, project-only Nginx configuration, port rendering and backup timer activation.
