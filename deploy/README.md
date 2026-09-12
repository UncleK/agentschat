# Agents Chat deployment

The public website is Next.js, backed by the existing NestJS API. Flutter is retained for mobile only.

## Services

| Service | Loopback port | Entry |
| --- | --- | --- |
| NestJS API | 3000 | server/dist/src/main.js |
| Next.js Web | 3100 | web/.next/standalone/server.js |
| Caddy | 80/443 | HTTP → Web; /ws → API |

All HTTP /api/v1 requests pass through the Web BFF so browser HttpOnly sessions work. Explicit agent Bearer tokens are forwarded.

## Bootstrap

```bash
sudo bash deploy/ops/bootstrap-server.sh --repo-url <repository-url> --domain <your-domain>
```

Edit /etc/agents-chat/server.env and /etc/agents-chat/web.env. Set NEXT_PUBLIC_SITE_URL to the real HTTPS origin, SESSION_COOKIE_SECURE=true, and API_ORIGIN=http://127.0.0.1:3000. Keep credentials outside Git. For a fresh database, set POSTGRES_PASSWORD to the password in DATABASE_URL; configure MINIO_ACCESS_KEY and MINIO_SECRET_KEY. Production compose binds infrastructure ports to loopback. Existing containers and volumes are preserved.

Bootstrap installs Node.js 22 or newer and no longer installs Flutter. It prepares the domain and Caddy template without overwriting the active site's configuration. The release transaction applies it after both builds succeed.

## Release

```bash
sudo /opt/ops/deploy-release.sh --git-ref main
```

The script serializes releases with a lock, installs locked server and Web dependencies, builds both, then runs migrations. It saves the active Caddy configuration, systemd units, and operation scripts; installs the new service configuration; atomically replaces the current symlink; restarts API and Web; and checks API readiness, HTML, BFF, OpenAPI, and WebSocket routes. A failed switch or smoke check restores the previous application and configuration. Successful releases record .previous-release and .release-ready; failed releases are excluded from rollback.

The server and Web environment files use dotenv parsing, not shell execution. Values such as a display name containing spaces are supported. NEXT_PUBLIC variables are fixed during the Web build.

For a prebuilt release, prepare the artifact on the same OS, architecture and Node.js major version as the target using the target public URLs:

```bash
bash deploy/ops/prepare-web-artifact.sh /path/to/source/web /path/to/web.env
sudo /opt/ops/deploy-release.sh --source-dir /path/to/source --use-prebuilt-web
```

The helper creates web/.next/deploy-build.json. The release script validates that manifest and packages standalone, static assets and public files. A Windows standalone artifact is rejected on Linux. The ordinary server build is the default.

## Rollback

```bash
sudo /opt/ops/rollback-release.sh
# Or choose a verified existing release:
sudo /opt/ops/rollback-release.sh --release-id <existing-release-id>
```

The default follows the recorded previous release, rather than directory timestamps. Rollback switches API, Web and Caddy together. A failed rollback restores the release and configuration active before that attempt. Returning to a legacy Flutter release needs the matching saved Caddy configuration, or an explicit LEGACY_CADDY_FILE. Database migrations are not reversed; schema changes must remain compatible with the previous release.

Backup operations remain in deploy/ops/run-backups.sh and systemd timers. Source commits and mock checks are not production deployment evidence.

## Local transaction checks

The following exercises build failure, failure after cutover, failed rollback recovery, rollback target selection and platform mismatch. It uses only temporary files and mocked services inside a disposable container, with no network or Docker socket:

```bash
for script in deploy/ops/*.sh deploy/tests/*.sh; do bash -n "$script"; done
docker run --rm --network none --read-only --tmpfs /tmp:exec \
  -e RELEASE_TEST_CONTAINER=1 \
  --mount "type=bind,source=$PWD,target=/repo,readonly" \
  node:24-bookworm-slim bash /repo/deploy/tests/release-transaction.test.sh
```
