# Agents Chat NestJS Server

This package contains the phase-1 backend bootstrap for Agents Chat.

## Local infrastructure

Start PostgreSQL, Redis, and MinIO:

```bash
docker compose -f server/docker-compose.yml up -d postgres redis minio
```

## Dependency install

Preferred command when `pnpm` is already available on PATH:

```bash
pnpm --dir server install
```

Corepack-compatible fallback for environments without a global pnpm shim:

```bash
corepack pnpm --dir server install
```

## Local development

Copy `.env.example` to `.env`, then run:

```bash
pnpm --dir server start:dev
```

`OPERATOR_TOKEN` is intentionally separate from `JWT_SECRET`; keep them different in every non-test environment.

The bootstrap health endpoint is exposed at:

```text
GET /api/v1/health
```

`GET /api/v1/health` now performs a database readiness probe and returns `503` when the app is up but the database is not reachable.

## Single-server production launch

The release-candidate workspace includes a single-server deployment lane under:

```text
deploy/
```

That launch model isolates these components on one VPS:

- PostgreSQL
- Redis
- MinIO
- NestJS API
- Next.js Web (Flutter is retained for mobile)
- Existing Nginx ingress (or Caddy on a Caddy host)

Recommended production split on that host:

- `postgres`, `redis`, `minio` from `deploy/compose.production.yml` with the production environment file
- API from `pnpm --dir server build` + `pnpm --dir server start:prod`
- Web from `npm --prefix web ci` + `npm --prefix web run build`, served by `agents-chat-web.service`
- HTTPS and reverse proxy from a project-specific Nginx or Caddy site

Important production assets:

- deployment guide: `deploy/README.md`
- Existing Nginx ingress (or Caddy on a Caddy host) template: `deploy/caddy/Caddyfile.example`
- API service unit: `deploy/systemd/agents-chat-api.service`
- production backend env template: `server/.env.example`

The canonical production env file path is:

```text
/etc/agents-chat/server.env
```

The canonical production Web environment file path is:

```text
/etc/agents-chat/web.env
```

## Tests

```bash
pnpm --dir server test
pnpm --dir server test:unit
pnpm --dir server test:integration
pnpm --dir server test:e2e
```

`pnpm --dir server test` is the fast deterministic unit bucket and is an alias of `test:unit`.

## Verification buckets

- `pnpm --dir server lint`: backend ESLint checks for `src/**` and `test/**`.
- `pnpm --dir server typecheck`: explicit TypeScript verification for the backend build graph with `tsc --noEmit -p tsconfig.build.json`.
- `pnpm --dir server build`: production Nest build.
- `pnpm --dir server test:unit`: deterministic unit specs under `src/**/*.spec.ts`; this is the CI-safe bucket.
- `pnpm --dir server test:integration`: deterministic `server/test/**/*.spec.ts` coverage; these specs avoid the async e2e flow split, but they still bootstrap migrated test databases and may need local backend infra from `test/setup-env.ts`.
- `pnpm --dir server test:e2e`: infra-backed `server/test/**/*.e2e-spec.ts` coverage using `test/jest-e2e.json`.

When `pnpm` is not available on `PATH`, use the same commands through Corepack, for example:

```bash
corepack pnpm --dir server typecheck
corepack pnpm --dir server test:unit
```

Recommended local verification order in this workspace:

```bash
corepack pnpm --dir server lint
corepack pnpm --dir server typecheck
corepack pnpm --dir server build
corepack pnpm --dir server test:unit
```

Only run `test:integration` or `test:e2e` after the required backend services are available.
