#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
release_init
REPO_DIR="${REPO_DIR:-$APP_ROOT/repo}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-agents-chat}"
USE_PREBUILT_WEB="false"
GIT_REF="" SOURCE_DIR="" RELEASE_ID=""
usage() { echo 'Usage: deploy-release.sh (--git-ref REF | --source-dir PATH) [--release-id ID] [--use-prebuilt-web]'; }
while (( $# )); do
  case "$1" in
    --git-ref|--source-dir|--release-id)
      (( $# >= 2 )) || { usage >&2; exit 1; }
      case "$1" in --git-ref) GIT_REF="$2";; --source-dir) SOURCE_DIR="$2";; --release-id) RELEASE_ID="$2";; esac
      shift 2;;
    --use-prebuilt-web) USE_PREBUILT_WEB=true; shift;;
    -h|--help) usage; exit 0;;
    *) usage >&2; exit 1;;
  esac
done
[[ "$(id -u)" == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -n "$GIT_REF" && -z "$SOURCE_DIR" || -z "$GIT_REF" && -n "$SOURCE_DIR" ]] || { usage >&2; exit 1; }
[[ "$USE_PREBUILT_WEB" != true || -n "$SOURCE_DIR" ]] || { echo 'Prebuilt Web requires --source-dir.' >&2; exit 1; }
release_lock
require_file "$ENV_FILE"
require_file "$WEB_ENV_FILE"
RELEASE_ID="${RELEASE_ID:-$(date +%Y%m%d%H%M%S)-release}"
validate_release_id "$RELEASE_ID"
RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"
[[ ! -e "$RELEASE_DIR" && ! -L "$RELEASE_DIR" ]] || { echo 'Release already exists.' >&2; exit 1; }
PREVIOUS_RELEASE="$(readlink -f "$CURRENT_LINK" 2>/dev/null || true)"
CONFIG_CHANGED=false
CURRENT_CHANGED=false
RECOVERY_DIR="$RELEASE_DIR/.deployment-before"
recover_failed_release() {
  local result="$?" recovery_failed=0
  (( result != 0 )) || return 0
  trap - EXIT
  set +e
  [[ ! -d "$RELEASE_DIR" ]] || touch "$RELEASE_DIR/.release-failed"
  if [[ "$CURRENT_CHANGED" == true ]]; then
    if [[ -n "$PREVIOUS_RELEASE" ]]; then atomic_switch "$PREVIOUS_RELEASE" || recovery_failed=1
    elif [[ "$(readlink -f "$CURRENT_LINK" 2>/dev/null)" == "$RELEASE_DIR" ]]; then rm -f -- "$CURRENT_LINK"; fi
  fi
  if [[ "$CONFIG_CHANGED" == true ]]; then restore_configuration "$RECOVERY_DIR" || recovery_failed=1; fi
  if [[ "$CURRENT_CHANGED" == true ]]; then
    if [[ -n "$PREVIOUS_RELEASE" ]]; then restart_application "$PREVIOUS_RELEASE" || recovery_failed=1
    else systemctl stop agents-chat-web.service agents-chat-api.service || recovery_failed=1; reload_proxy || recovery_failed=1; fi
  elif [[ "$CONFIG_CHANGED" == true && -f "$CADDY_FILE" ]]; then reload_proxy || recovery_failed=1; fi
  if (( recovery_failed )); then echo 'Release failed; automatic recovery was incomplete. Inspect systemd and Caddy before retrying.' >&2
  else echo 'Release failed; previous application/configuration restored. Database migrations were not reversed.' >&2; fi
  exit "$result"
}
trap recover_failed_release EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
install -d -o "$APP_USER" -g "$APP_USER" "$RELEASES_DIR" "$RELEASE_DIR"
if [[ -n "$GIT_REF" ]]; then
  sudo -u "$APP_USER" git -C "$REPO_DIR" fetch --all --tags --prune
  archive_ref="$GIT_REF"
  if sudo -u "$APP_USER" git -C "$REPO_DIR" rev-parse --verify --quiet "origin/${GIT_REF}^{commit}" >/dev/null; then archive_ref="origin/$GIT_REF"; fi
  sudo -u "$APP_USER" git -C "$REPO_DIR" rev-parse --verify "${archive_ref}^{commit}" > "$RELEASE_DIR/.source-commit"
  sudo -u "$APP_USER" git -C "$REPO_DIR" archive "$archive_ref" | tar -xf - -C "$RELEASE_DIR"
else
  [[ -d "$SOURCE_DIR" ]] || { echo 'Source directory not found.' >&2; exit 1; }
  SOURCE_DIR="$(realpath "$SOURCE_DIR")"
  [[ "$RELEASE_DIR/" != "$SOURCE_DIR/"* ]] || { echo 'Release directory cannot be inside the source directory.' >&2; exit 1; }
  tar --exclude=.release-ready --exclude=.release-failed --exclude=.deployment-before --exclude=.previous-release --exclude=.git --exclude=.playwright-cli --exclude=.sisyphus --exclude=output --exclude=.local-archive \
    --exclude=app/.dart_tool --exclude=app/.flutter-plugins-dependencies --exclude=app/build \
    --exclude=web/node_modules --exclude=web/.next --exclude='*/.env' --exclude='*/.env.*' \
    --exclude=server/node_modules --exclude=server/dist --exclude=server/coverage -cf - -C "$SOURCE_DIR" . | tar -xf - -C "$RELEASE_DIR"
  if [[ "$USE_PREBUILT_WEB" == true ]]; then require_file "$SOURCE_DIR/web/.next/deploy-build.json"; cp -a "$SOURCE_DIR/web/.next" "$RELEASE_DIR/web/.next"; fi
fi
require_file "$RELEASE_DIR/web/package-lock.json"
chown -R "$APP_USER:$APP_USER" "$RELEASE_DIR"
prepare_caddy "$RELEASE_DIR" "$RELEASE_DIR/Caddyfile.next"
# Finish both builds before touching the live schema, service definitions, or release pointer.
sudo -u "$APP_USER" env "PATH=$PATH" bash -se -- "$RELEASE_DIR" <<'BUILD'
cd "$1/server"
env NODE_ENV=development npm_config_production=false pnpm install --frozen-lockfile
pnpm build
BUILD
if [[ "$USE_PREBUILT_WEB" == true ]]; then
  node --env-file="$WEB_ENV_FILE" - "$RELEASE_DIR/web/.next/deploy-build.json" <<'VERIFY'
const fs=require('node:fs'),manifest=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const expected={platform:process.platform,arch:process.arch,nodeMajor:process.versions.node.split('.')[0],siteUrl:process.env.NEXT_PUBLIC_SITE_URL||'',agentOrigin:process.env.NEXT_PUBLIC_AGENT_SERVER_ORIGIN||''};
for(const [key,value] of Object.entries(expected))if(manifest[key]!==value)throw new Error('Prebuilt Web '+key+' mismatch; build on the target platform with its public URLs.');
VERIFY
else
  sudo -u "$APP_USER" env "PATH=$PATH" bash "$RELEASE_DIR/deploy/ops/prepare-web-artifact.sh" "$RELEASE_DIR/web" "$WEB_ENV_FILE"
fi
require_file "$RELEASE_DIR/server/dist/src/main.js"
require_file "$RELEASE_DIR/web/.next/standalone/server.js"
install -d "$RELEASE_DIR/web/.next/standalone/.next/static" "$RELEASE_DIR/web/.next/standalone/public"
cp -a "$RELEASE_DIR/web/.next/static/." "$RELEASE_DIR/web/.next/standalone/.next/static/"
cp -a "$RELEASE_DIR/web/public/." "$RELEASE_DIR/web/.next/standalone/public/"
chown -R "$APP_USER:$APP_USER" "$RELEASE_DIR/web/.next"
# Existing containers are preserved. Fresh/partial installations use the explicit production compose file.
if docker inspect agents-chat-postgres agents-chat-redis agents-chat-minio >/dev/null 2>&1; then
  docker start agents-chat-postgres agents-chat-redis agents-chat-minio >/dev/null
else
  docker compose --env-file "$ENV_FILE" --project-name "$COMPOSE_PROJECT_NAME" -f "$RELEASE_DIR/deploy/compose.production.yml" up -d postgres redis minio
fi
retry_command "${INFRA_RETRIES:-60}" "${INFRA_DELAY_SECONDS:-2}" 'PostgreSQL readiness' docker exec agents-chat-postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
retry_command "${INFRA_RETRIES:-30}" "${INFRA_DELAY_SECONDS:-2}" 'Redis readiness' docker exec agents-chat-redis redis-cli ping
minio_port="$(node --env-file="$ENV_FILE" -p 'process.env.MINIO_PORT || 59000')"
retry_command "${INFRA_RETRIES:-30}" "${INFRA_DELAY_SECONDS:-2}" 'MinIO readiness' curl -fsS --max-time 5 "http://127.0.0.1:$minio_port/minio/health/ready"
if [[ -n "$PREVIOUS_RELEASE" ]]; then bash "$SCRIPT_DIR/run-backups.sh"; fi
sudo -u "$APP_USER" env "PATH=$PATH" bash -se -- "$RELEASE_DIR" "$ENV_FILE" <<'MIGRATE'
cd "$1/server"
node --env-file="$2" --require ts-node/register --require tsconfig-paths/register ./node_modules/typeorm/cli.js migration:run -d ./src/database/typeorm.data-source.ts
MIGRATE
printf '%s\n' "$PREVIOUS_RELEASE" > "$RELEASE_DIR/.previous-release"
snapshot_configuration "$RECOVERY_DIR" "$RELEASE_DIR"
CONFIG_CHANGED=true
install_release_configuration "$RELEASE_DIR" "$RELEASE_DIR/Caddyfile.next"
CURRENT_CHANGED=true
atomic_switch "$RELEASE_DIR"
restart_application "$RELEASE_DIR"
smoke_application "$RELEASE_DIR"
systemctl enable agents-chat-api.service agents-chat-web.service >/dev/null
systemctl enable --now agents-chat-backup.timer >/dev/null
cp -a "$CADDY_FILE" "$RELEASE_DIR/Caddyfile.deployed"
date -u +%FT%TZ > "$RELEASE_DIR/.release-ready"
trap - EXIT INT TERM
echo "Release deployed: $RELEASE_ID"
