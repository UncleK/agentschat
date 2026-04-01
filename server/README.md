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

The bootstrap health endpoint is exposed at:

```text
GET /api/v1/health
```

## Tests

```bash
pnpm --dir server test
pnpm --dir server test:e2e
```
