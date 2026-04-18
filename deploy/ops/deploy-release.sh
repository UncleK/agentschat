#!/usr/bin/env bash
set -euo pipefail

APP_USER="${APP_USER:-agentschat}"
APP_ROOT="${APP_ROOT:-/opt/agents-chat}"
RELEASES_DIR="${RELEASES_DIR:-$APP_ROOT/releases}"
CURRENT_LINK="${CURRENT_LINK:-$APP_ROOT/current}"
REPO_DIR="${REPO_DIR:-$APP_ROOT/repo}"
ENV_FILE="${ENV_FILE:-/etc/agents-chat/server.env}"
DART_DEFINE_FILE="${DART_DEFINE_FILE:-/etc/agents-chat/dart_define.production.json}"
OPS_DIR="${OPS_DIR:-/opt/ops}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-agents-chat}"
SMOKE_RETRIES="${SMOKE_RETRIES:-15}"
SMOKE_DELAY_SECONDS="${SMOKE_DELAY_SECONDS:-2}"
PUBLIC_EDGE_WS_RETRIES="${PUBLIC_EDGE_WS_RETRIES:-3}"
PUBLIC_EDGE_WS_DELAY_SECONDS="${PUBLIC_EDGE_WS_DELAY_SECONDS:-3}"
PUBLIC_EDGE_WS_REQUIRED="${PUBLIC_EDGE_WS_REQUIRED:-false}"
GIT_REF=""
SOURCE_DIR=""
RELEASE_ID=""

discover_caddy_domain() {
  if [[ ! -f /etc/caddy/Caddyfile ]]; then
    return
  fi

  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    /\{/ {
      candidate=$1
      sub(/,+$/, "", candidate)
      if (candidate != "" && candidate != "{") {
        print candidate
        exit
      }
    }
  ' /etc/caddy/Caddyfile
}

usage() {
  cat <<'EOF'
Usage:
  deploy-release.sh --git-ref <ref>
  deploy-release.sh --source-dir <path> [--release-id <id>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-ref)
      GIT_REF="$2"
      shift 2
      ;;
    --source-dir)
      SOURCE_DIR="$2"
      shift 2
      ;;
    --release-id)
      RELEASE_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [[ -n "$GIT_REF" && -n "$SOURCE_DIR" ]]; then
  echo "Choose either --git-ref or --source-dir, not both." >&2
  exit 1
fi

if [[ -z "$GIT_REF" && -z "$SOURCE_DIR" ]]; then
  echo "One of --git-ref or --source-dir is required." >&2
  exit 1
fi

timestamp="$(date +%Y%m%d%H%M%S)"
if [[ -n "$GIT_REF" ]]; then
  safe_ref="$(echo "$GIT_REF" | tr '/:@' '---')"
  RELEASE_ID="${RELEASE_ID:-$timestamp-$safe_ref}"
else
  RELEASE_ID="${RELEASE_ID:-$timestamp-manual}"
fi

RELEASE_DIR="$RELEASES_DIR/$RELEASE_ID"

require_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "Required file missing: $path" >&2
    exit 1
  fi
}

retry_command() {
  local attempts="$1"
  local delay_seconds="$2"
  local description="$3"
  shift 3

  local attempt=1
  local exit_code=0
  while true; do
    set +e
    "$@"
    exit_code=$?
    set -e

    if (( exit_code == 0 )); then
      return 0
    fi

    if (( attempt >= attempts )); then
      echo "$description failed after $attempt attempts." >&2
      return "$exit_code"
    fi

    echo "$description failed (attempt $attempt/$attempts). Retrying in ${delay_seconds}s..." >&2
    sleep "$delay_seconds"
    attempt=$((attempt + 1))
  done
}

run_local_static_web_smoke() {
  local caddy_domain="${1:-}"

  if [[ -n "$caddy_domain" ]]; then
    curl -fsS -H "Host: $caddy_domain" http://127.0.0.1/ >/dev/null
    return
  fi

  curl -fsS http://127.0.0.1/ >/dev/null
}

run_local_websocket_smoke() {
  local caddy_domain="${1:-}"

  if [[ -n "$caddy_domain" ]]; then
    env \
      WS_CHECK_URL="wss://$caddy_domain/ws" \
      WS_CHECK_CONNECT_HOST="127.0.0.1" \
      WS_CHECK_CONNECT_PORT="443" \
      WS_CHECK_HOST_HEADER="$caddy_domain" \
      "$OPS_DIR/check-websocket.sh"
    return
  fi

  env \
    WS_CHECK_URL="ws://127.0.0.1:3000/ws" \
    "$OPS_DIR/check-websocket.sh"
}

run_public_edge_websocket_smoke() {
  local caddy_domain="$1"

  env \
    WS_CHECK_URL="wss://$caddy_domain/ws" \
    "$OPS_DIR/check-websocket.sh"
}

checkout_release() {
  if [[ -n "$GIT_REF" ]]; then
    local archive_ref="$GIT_REF"

    if [[ ! -d "$REPO_DIR/.git" ]]; then
      echo "Git repository not found at $REPO_DIR" >&2
      exit 1
    fi

    git -C "$REPO_DIR" fetch --all --tags --prune

    if ! git -C "$REPO_DIR" rev-parse --verify --quiet "${archive_ref}^{commit}" >/dev/null; then
      if git -C "$REPO_DIR" rev-parse --verify --quiet "origin/${archive_ref}^{commit}" >/dev/null; then
        archive_ref="origin/$archive_ref"
      else
        echo "Git ref not found after fetch: $GIT_REF" >&2
        exit 1
      fi
    fi

    git -C "$REPO_DIR" archive "$archive_ref" | tar -xf - -C "$RELEASE_DIR"
  else
    if [[ ! -d "$SOURCE_DIR" ]]; then
      echo "Source directory not found: $SOURCE_DIR" >&2
      exit 1
    fi

    tar --exclude=.git -cf - -C "$SOURCE_DIR" . | tar -xf - -C "$RELEASE_DIR"
  fi

  chown -R "$APP_USER:$APP_USER" "$RELEASE_DIR"
}

install_release_assets() {
  install -m 0755 "$RELEASE_DIR/deploy/ops/"*.sh "$OPS_DIR/"
  install -m 0644 "$RELEASE_DIR/deploy/systemd/agents-chat-api.service" /etc/systemd/system/agents-chat-api.service
  install -m 0644 "$RELEASE_DIR/deploy/systemd/agents-chat-backup.service" /etc/systemd/system/agents-chat-backup.service
  install -m 0644 "$RELEASE_DIR/deploy/systemd/agents-chat-backup.timer" /etc/systemd/system/agents-chat-backup.timer
  systemctl daemon-reload
  systemctl enable agents-chat-api.service agents-chat-backup.timer >/dev/null
}

start_infra() {
  local existing_infra=(
    agents-chat-postgres
    agents-chat-redis
    agents-chat-minio
  )

  if docker inspect "${existing_infra[@]}" >/dev/null 2>&1; then
    echo "Reusing existing infra containers."
    docker start "${existing_infra[@]}" >/dev/null 2>&1 || true
    return
  fi

  docker compose \
    --project-name "$COMPOSE_PROJECT_NAME" \
    -f "$RELEASE_DIR/server/docker-compose.yml" \
    up -d postgres redis minio
}

build_backend() {
  sudo -u "$APP_USER" bash -lc "
    set -euo pipefail
    cd '$RELEASE_DIR/server'
    corepack enable
    set -a
    source '$ENV_FILE'
    set +a
    corepack pnpm --dir '$RELEASE_DIR/server' install --frozen-lockfile
    corepack pnpm --dir '$RELEASE_DIR/server' build
    corepack pnpm --dir '$RELEASE_DIR/server' migration:run
  "
}

build_web() {
  if [[ -d "$RELEASE_DIR/app/build/web" ]]; then
    echo "Using prebuilt Flutter web assets from source."
    return
  fi

  sudo -u "$APP_USER" bash -lc "
    set -euo pipefail
    export PATH=\"\$PATH:/snap/bin\"
    if ! command -v flutter >/dev/null 2>&1; then
      echo 'Flutter is not installed and no prebuilt web assets were provided.' >&2
      exit 1
    fi
    cd '$RELEASE_DIR/app'
    flutter config --enable-web >/dev/null
    flutter pub get
    flutter build web --release --dart-define-from-file='$DART_DEFINE_FILE'
  "
}

switch_current() {
  ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"
  chown -h "$APP_USER:$APP_USER" "$CURRENT_LINK"
}

restart_services() {
  systemctl restart agents-chat-api.service
  retry_command \
    "$SMOKE_RETRIES" \
    1 \
    "Waiting for agents-chat-api.service to become active" \
    systemctl is-active --quiet agents-chat-api.service

  systemctl reload caddy >/dev/null 2>&1 || systemctl restart caddy
  retry_command \
    "$SMOKE_RETRIES" \
    1 \
    "Waiting for caddy to become active" \
    systemctl is-active --quiet caddy
}

smoke_checks() {
  local caddy_domain

  retry_command \
    "$SMOKE_RETRIES" \
    "$SMOKE_DELAY_SECONDS" \
    "API health check" \
    "$OPS_DIR/check-health.sh"

  caddy_domain="$(discover_caddy_domain || true)"
  if [[ -n "$caddy_domain" ]]; then
    retry_command \
      "$SMOKE_RETRIES" \
      "$SMOKE_DELAY_SECONDS" \
      "Static web smoke check via local Caddy" \
      run_local_static_web_smoke \
      "$caddy_domain"
    echo "Static web smoke check passed."

    retry_command \
      "$SMOKE_RETRIES" \
      "$SMOKE_DELAY_SECONDS" \
      "WebSocket route check via local Caddy" \
      run_local_websocket_smoke \
      "$caddy_domain"

    if ! retry_command \
      "$PUBLIC_EDGE_WS_RETRIES" \
      "$PUBLIC_EDGE_WS_DELAY_SECONDS" \
      "Public edge WebSocket smoke check" \
      run_public_edge_websocket_smoke \
      "$caddy_domain"; then
      if [[ "$PUBLIC_EDGE_WS_REQUIRED" == "true" ]]; then
        echo "Public edge WebSocket smoke check failed." >&2
        exit 1
      fi

      echo "Warning: public edge WebSocket smoke check failed, but local Caddy and API checks passed." >&2
    fi
    return
  fi

  retry_command \
    "$SMOKE_RETRIES" \
    "$SMOKE_DELAY_SECONDS" \
    "Static web smoke check" \
    run_local_static_web_smoke
  echo "Static web smoke check passed."

  retry_command \
    "$SMOKE_RETRIES" \
    "$SMOKE_DELAY_SECONDS" \
    "WebSocket route check" \
    run_local_websocket_smoke
}

main() {
  require_file "$ENV_FILE"
  require_file "$DART_DEFINE_FILE"
  install -d -o "$APP_USER" -g "$APP_USER" "$RELEASES_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" "$RELEASE_DIR"
  checkout_release
  start_infra
  build_backend
  build_web
  install_release_assets
  switch_current
  restart_services
  smoke_checks
  echo "Release deployed: $RELEASE_ID"
}

main "$@"
