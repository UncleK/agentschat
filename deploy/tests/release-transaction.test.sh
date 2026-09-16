#!/usr/bin/env bash
# Runs inside a disposable Linux container; never contacts Docker or systemd on the host.
set -euo pipefail
[[ "${RELEASE_TEST_CONTAINER:-}" == 1 ]] || { echo 'Run in the documented disposable container.' >&2; exit 1; }
source /repo/deploy/ops/release-common.sh
for headline in 'AI Agent 的社区' 'An AI agent community' 'A world beyond'; do
  native_web_html_is_valid "<html><head><title>Agents Chat</title></head><body><header class=site-header></header><main><h1>$headline</h1></main><script src=/_next/static/app.js></script></body></html>"
done
if native_web_html_is_valid 'A world beyond'; then echo 'Plain text accepted as native Web HTML'; exit 1; fi
if native_web_html_is_valid '<html><title>Agents Chat</title><header class=site-header></header><main><h1>Ready</h1></main><script src=/_next/static/app.js></script><script src=flutter_bootstrap.js></script></html>'; then echo 'Legacy Flutter bootstrap accepted'; exit 1; fi
echo 'PASS: native Web smoke validation accepts translated headlines and rejects missing SSR or legacy bootstrap'
export TEST_ROOT="$(mktemp -d)"
trap 'result=$?; if (( result )); then cat "$TEST_ROOT/"*.log >&2; fi; rm -rf -- "$TEST_ROOT"' EXIT
export APP_ROOT="$TEST_ROOT/app" APP_USER=root OPS_DIR="$TEST_ROOT/ops" SYSTEMD_DIR="$TEST_ROOT/units" CADDY_FILE="$TEST_ROOT/Caddyfile" APP_DOMAIN=test.example
export ENV_FILE="$TEST_ROOT/server.env" WEB_ENV_FILE="$TEST_ROOT/web.env" SMOKE_RETRIES=1 SMOKE_DELAY_SECONDS=0
export CURRENT_LINK="$APP_ROOT/current" RELEASES_DIR="$APP_ROOT/releases" TEST_LOG="$TEST_ROOT/calls"
touch "$TEST_LOG"
export POSTGRES_BACKUP_DIR="$TEST_ROOT/backups/pg" MINIO_BACKUP_DIR="$TEST_ROOT/backups/minio" REPORT_DIR="$TEST_ROOT/backups/reports"
mkdir -p "$TEST_ROOT/minio"
printf test > "$TEST_ROOT/minio/object"
mkdir -p "$TEST_ROOT/bin" "$OPS_DIR" "$SYSTEMD_DIR" "$RELEASES_DIR/old" "$TEST_ROOT/source/web/public" "$TEST_ROOT/source/server"
cp -a /repo/deploy "$TEST_ROOT/source/deploy"
printf 'DATABASE_URL=postgresql://unused\nMAIL_FROM_ADDRESS=Agents Chat <noreply@example.test>\n' > "$ENV_FILE"
printf 'NEXT_PUBLIC_SITE_URL=https://test.example\n' > "$WEB_ENV_FILE"
printf '{}' > "$TEST_ROOT/source/web/package-lock.json"
printf 'asset' > "$TEST_ROOT/source/web/public/asset.txt"
cat > "$TEST_ROOT/bin/systemctl" <<'MOCK'
#!/bin/bash
printf 'systemctl %s current=%s\n' "$*" "$(readlink "$CURRENT_LINK" || true)" >> "$TEST_LOG"
MOCK
cat > "$TEST_ROOT/bin/caddy" <<'MOCK'
#!/bin/bash
exit 0
MOCK
cat > "$TEST_ROOT/bin/docker" <<'MOCK'
#!/bin/bash
printf 'docker %s\n' "$*" >> "$TEST_LOG"
if [[ "$*" == *'--format'* ]]; then printf '%s/minio\n' "$TEST_ROOT"; fi
if [[ "$*" == *'pg_isready'* && "${FAIL_DATABASE_READY:-}" == 1 ]]; then exit 1; fi
MOCK
cat > "$TEST_ROOT/bin/jq" <<'MOCK'
#!/bin/bash
cat >/dev/null
MOCK
cat > "$TEST_ROOT/bin/curl" <<'MOCK'
#!/bin/bash
[[ "$(basename "$(readlink "$CURRENT_LINK" || true)")" != "${FAIL_SMOKE_RELEASE:-never}" ]] || exit 22
printf '<html><head><title>Agents Chat</title></head><body><header class=site-header></header><main><h1>AI Agent 的社区</h1></main><script src=/_next/static/app.js></script></body></html>{"status":"ok","checks":{"database":"ok"}}'
MOCK
cat > "$TEST_ROOT/bin/sudo" <<'MOCK'
#!/bin/bash
set -eu
shift 2
if [[ "$1" == env ]]; then shift 2; fi
if [[ "$1 $2" == 'bash -se' ]]; then
  input="$(cat)"
  if [[ "$input" == *'migration:run'* ]]; then printf 'migration\n' >> "$TEST_LOG"; exit 0; fi
  [[ "${FAIL_BUILD:-}" != 1 ]] || exit 42
  mkdir -p "$4/server/dist/src"
  touch "$4/server/dist/src/main.js"
else
  mkdir -p "$3/.next/standalone" "$3/.next/static"
  touch "$3/.next/standalone/server.js" "$3/.next/static/bundle.js"
fi
MOCK
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH"
printf '#!/bin/bash\nexit 0\n' > "$TEST_ROOT/source/deploy/ops/check-websocket.sh"
setup_old() {
  mkdir -p "$RELEASES_DIR/old/server/dist/src" "$RELEASES_DIR/old/web/.next/standalone"
  touch "$RELEASES_DIR/old/server/dist/src/main.js" "$RELEASES_DIR/old/web/.next/standalone/server.js"
  cp -a "$TEST_ROOT/source/deploy" "$RELEASES_DIR/old/deploy"
  printf 'old-caddy\n' > "$CADDY_FILE"
  cp "$CADDY_FILE" "$RELEASES_DIR/old/Caddyfile.deployed"
  for unit in agents-chat-api.service agents-chat-web.service agents-chat-backup.service agents-chat-backup.timer; do printf 'old-%s\n' "$unit" > "$SYSTEMD_DIR/$unit"; done
  ln -s "$RELEASES_DIR/old" "$CURRENT_LINK"
}
assert_old() {
  [[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/old" ]]
  [[ "$(cat "$CADDY_FILE")" == old-caddy ]]
  [[ "$(cat "$SYSTEMD_DIR/agents-chat-api.service")" == old-agents-chat-api.service ]]
  [[ "$(cat "$SYSTEMD_DIR/agents-chat-web.service")" == old-agents-chat-web.service ]]
}
setup_old
if FAIL_BUILD=1 bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --release-id build-failed > "$TEST_ROOT/build.log" 2>&1; then echo 'Build failure unexpectedly passed'; exit 1; fi
assert_old
grep -q "Release failed" "$TEST_ROOT/build.log"
! grep -q migration "$TEST_LOG"
echo 'PASS: build failure does not migrate or mutate the live release/configuration'
if FAIL_SMOKE_RELEASE=smoke-failed bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --release-id smoke-failed > "$TEST_ROOT/smoke.log" 2>&1; then echo 'Smoke failure unexpectedly passed'; exit 1; fi
assert_old
[[ -f "$RELEASES_DIR/smoke-failed/.release-failed" ]]
grep -q "restart agents-chat-api.service current=$RELEASES_DIR/old" "$TEST_LOG"
grep -q "restart agents-chat-web.service current=$RELEASES_DIR/old" "$TEST_LOG"
echo 'PASS: post-switch failure restores symlink, Caddy, both units, and restarts both services'
bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --release-id new > "$TEST_ROOT/success.log" 2>&1
[[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/new" && -f "$RELEASES_DIR/new/.release-ready" ]]
[[ "$(cat "$RELEASES_DIR/new/.previous-release")" == "$RELEASES_DIR/old" ]]
cp "$CADDY_FILE" "$TEST_ROOT/new-caddy"
cp "$SYSTEMD_DIR/agents-chat-api.service" "$TEST_ROOT/new-api"
cp "$SYSTEMD_DIR/agents-chat-web.service" "$TEST_ROOT/new-web"
if FAIL_SMOKE_RELEASE=old bash /repo/deploy/ops/rollback-release.sh > "$TEST_ROOT/rollback-failed.log" 2>&1; then echo 'Rollback failure unexpectedly passed'; exit 1; fi
[[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/new" ]]
cmp "$CADDY_FILE" "$TEST_ROOT/new-caddy"
cmp "$SYSTEMD_DIR/agents-chat-api.service" "$TEST_ROOT/new-api"
cmp "$SYSTEMD_DIR/agents-chat-web.service" "$TEST_ROOT/new-web"
echo 'PASS: failed rollback restores the previously active complete release'
if bash /repo/deploy/ops/rollback-release.sh --release-id smoke-failed > "$TEST_ROOT/invalid.log" 2>&1; then echo 'Failed release accepted'; exit 1; fi
bash /repo/deploy/ops/rollback-release.sh > "$TEST_ROOT/rollback.log" 2>&1
[[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/old" ]]
echo 'PASS: default rollback follows recorded previous release and refuses failed releases'
mkdir -p "$TEST_ROOT/source/web/.next/standalone"
printf '{"platform":"win32","arch":"x64","nodeMajor":"24","siteUrl":"https://test.example","agentOrigin":""}' > "$TEST_ROOT/source/web/.next/deploy-build.json"
if bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --use-prebuilt-web --release-id windows > "$TEST_ROOT/platform.log" 2>&1; then echo 'Windows artifact accepted on Linux'; exit 1; fi
[[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/old" ]]
grep -q 'Prebuilt Web platform mismatch' "$TEST_ROOT/platform.log"
echo 'PASS: Windows prebuilt artifact rejected on Linux before cutover'

before_migrations="$(grep -c '^migration$' "$TEST_LOG")"
cp "$CADDY_FILE" "$TEST_ROOT/db-before-site"
cp "$SYSTEMD_DIR/agents-chat-api.service" "$TEST_ROOT/db-before-api"
if INFRA_RETRIES=1 INFRA_DELAY_SECONDS=0 FAIL_DATABASE_READY=1 bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --release-id db-not-ready > "$TEST_ROOT/database.log" 2>&1; then echo 'Unready database accepted'; exit 1; fi
[[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/old" ]]
cmp "$CADDY_FILE" "$TEST_ROOT/db-before-site"
cmp "$SYSTEMD_DIR/agents-chat-api.service" "$TEST_ROOT/db-before-api"
[[ "$(grep -c '^migration$' "$TEST_LOG")" == "$before_migrations" ]]
echo 'PASS: unready database prevents migration and cutover'

cat > "$TEST_ROOT/bin/nginx" <<'MOCK'
#!/bin/bash
printf 'nginx %s\n' "$*" >> "$TEST_LOG"
MOCK
chmod +x "$TEST_ROOT/bin/nginx"
printf 'unrelated nginx configuration\n' > "$TEST_ROOT/unrelated.conf"
cp "$TEST_ROOT/unrelated.conf" "$TEST_ROOT/unrelated.before"
export PROXY_SERVER=nginx API_PORT=3200 WEB_PORT=3201
bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --release-id nginx-new > "$TEST_ROOT/nginx.log" 2>&1
cmp "$TEST_ROOT/unrelated.conf" "$TEST_ROOT/unrelated.before"
grep -q 'proxy_pass http://127.0.0.1:3200' "$CADDY_FILE"
grep -q 'proxy_pass http://127.0.0.1:3201' "$CADDY_FILE"
[[ "$(stat -c %a "$CADDY_FILE")" == 600 ]] || { echo 'Nginx edge secret is readable outside root'; exit 1; }
grep -q 'enable --now agents-chat-backup.timer' "$TEST_LOG"
grep -q 'reload nginx' "$TEST_LOG"
echo 'PASS: isolated nginx site, configured ports and active backup timer'
cp "$CADDY_FILE" "$TEST_ROOT/nginx.before"
if FAIL_SMOKE_RELEASE=nginx-failed bash /repo/deploy/ops/deploy-release.sh --source-dir "$TEST_ROOT/source" --release-id nginx-failed > "$TEST_ROOT/nginx-failed.log" 2>&1; then echo 'Nginx smoke failure accepted'; exit 1; fi
[[ "$(readlink "$CURRENT_LINK")" == "$RELEASES_DIR/nginx-new" ]]
cmp "$CADDY_FILE" "$TEST_ROOT/nginx.before"
[[ "$(stat -c %a "$CADDY_FILE")" == 600 ]]
cmp "$TEST_ROOT/unrelated.conf" "$TEST_ROOT/unrelated.before"
echo 'PASS: failed nginx cutover restores only its own site'
