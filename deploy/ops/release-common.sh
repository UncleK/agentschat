#!/usr/bin/env bash
# Shared release transaction utilities. No commands run merely by sourcing this file.
release_init() {
  APP_USER="${APP_USER:-agentschat}"
  APP_ROOT="${APP_ROOT:-/opt/agents-chat}"
  RELEASES_DIR="${RELEASES_DIR:-$APP_ROOT/releases}"
  CURRENT_LINK="${CURRENT_LINK:-$APP_ROOT/current}"
  ENV_FILE="${ENV_FILE:-/etc/agents-chat/server.env}"
  WEB_ENV_FILE="${WEB_ENV_FILE:-/etc/agents-chat/web.env}"
  OPS_DIR="${OPS_DIR:-/opt/ops}"
  SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
  CADDY_FILE="${CADDY_FILE:-/etc/caddy/Caddyfile}"
  if [[ -z "${APP_DOMAIN:-}" && -f "$(dirname "$WEB_ENV_FILE")/domain" ]]; then APP_DOMAIN="$(cat "$(dirname "$WEB_ENV_FILE")/domain")"; fi
  SMOKE_RETRIES="${SMOKE_RETRIES:-15}"
  SMOKE_DELAY_SECONDS="${SMOKE_DELAY_SECONDS:-2}"
  HEALTHCHECK_URL="${HEALTHCHECK_URL:-http://127.0.0.1:3000/api/v1/health}"
  [[ "$CURRENT_LINK" == /* && "$RELEASES_DIR" == /* ]] || { echo 'Release paths must be absolute.' >&2; return 1; }
  [[ ! -e "$CURRENT_LINK" || -L "$CURRENT_LINK" ]] || { echo 'Current path is not a symlink; refusing to overwrite it.' >&2; return 1; }
}
require_file() { [[ -f "$1" ]] || { echo "Required file missing: $1" >&2; return 1; }; }
validate_release_id() { [[ "$1" =~ ^[a-zA-Z0-9._-]+$ && "$1" != '.' && "$1" != '..' ]] || { echo 'Invalid release id.' >&2; return 1; }; }
release_lock() {
  mkdir -p "$APP_ROOT"
  exec 9>"$APP_ROOT/.release.lock"
  flock -n 9 || { echo 'Another deploy or rollback is in progress.' >&2; return 1; }
}
atomic_switch() {
  local target="$1" temporary="$CURRENT_LINK.next.$$"
  [[ ! -e "$temporary" && ! -L "$temporary" ]] || return 1
  ln -s "$target" "$temporary" || return
  if ! mv -Tf -- "$temporary" "$CURRENT_LINK"; then rm -f -- "$temporary"; return 1; fi
}
atomic_install() {
  local source="$1" target="$2" temporary="$2.next.$$"
  install -m 0644 "$source" "$temporary" || return
  mv -f -- "$temporary" "$target"
}
retry_command() {
  local attempts="$1" delay="$2" description="$3" attempt=1 result=0
  shift 3
  while true; do
    if "$@"; then return 0; else result=$?; fi
    if (( attempt >= attempts )); then echo "$description failed after $attempt attempts." >&2; return "$result"; fi
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}
discover_caddy_domain() {
  if [[ -n "${APP_DOMAIN:-}" ]]; then printf '%s\n' "$APP_DOMAIN"; return; fi
  [[ -f "$CADDY_FILE" ]] || return 0
  awk '/^[[:space:]]*#/ { next } /^[[:space:]]*[A-Za-z0-9][A-Za-z0-9.-]*[[:space:]]*\{/ { print $1; exit }' "$CADDY_FILE"
}
validate_domain() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || { echo 'Set APP_DOMAIN to a single DNS hostname (without scheme or port).' >&2; return 1; }; }
prepare_caddy() {
  local release="$1" target="$2" domain
  domain="$(discover_caddy_domain)"
  validate_domain "$domain"
  sed "s/__APP_DOMAIN__/$domain/g" "$release/deploy/caddy/Caddyfile.example" > "$target"
  caddy validate --config "$target" --adapter caddyfile
}
snapshot_configuration() {
  local snapshot="$1" release="$2" file unit
  mkdir -p "$snapshot/systemd" "$snapshot/ops"
  if [[ -f "$CADDY_FILE" ]]; then cp -a "$CADDY_FILE" "$snapshot/Caddyfile"; else touch "$snapshot/no-caddy"; fi
  for unit in agents-chat-api.service agents-chat-web.service agents-chat-backup.service agents-chat-backup.timer; do
    if [[ -f "$SYSTEMD_DIR/$unit" ]]; then cp -a "$SYSTEMD_DIR/$unit" "$snapshot/systemd/$unit"; else touch "$snapshot/systemd/$unit.missing"; fi
  done
  for file in "$release/deploy/ops/"*.sh; do
    file="$(basename "$file")"
    if [[ -f "$OPS_DIR/$file" ]]; then cp -a "$OPS_DIR/$file" "$snapshot/ops/$file"; else touch "$snapshot/ops/$file.missing"; fi
  done
}
restore_configuration() {
  local snapshot="$1" file unit failed=0
  if [[ -f "$snapshot/Caddyfile" ]]; then atomic_install "$snapshot/Caddyfile" "$CADDY_FILE" || failed=1; elif [[ -f "$snapshot/no-caddy" ]]; then rm -f -- "$CADDY_FILE" || failed=1; fi
  for unit in agents-chat-api.service agents-chat-web.service agents-chat-backup.service agents-chat-backup.timer; do
    if [[ -f "$snapshot/systemd/$unit" ]]; then atomic_install "$snapshot/systemd/$unit" "$SYSTEMD_DIR/$unit" || failed=1; elif [[ -f "$snapshot/systemd/$unit.missing" ]]; then rm -f -- "$SYSTEMD_DIR/$unit" || failed=1; fi
  done
  for file in "$snapshot/ops/"*; do
    [[ -f "$file" ]] || continue
    if [[ "$file" == *.missing ]]; then rm -f -- "$OPS_DIR/$(basename "${file%.missing}")" || failed=1; else install -m 0755 "$file" "$OPS_DIR/$(basename "$file")" || failed=1; fi
  done
  systemctl daemon-reload || failed=1
  return "$failed"
}
install_release_configuration() {
  local release="$1" caddy_next="$2" unit temp
  mkdir -p "$OPS_DIR" "$SYSTEMD_DIR"
  install -m 0755 "$release/deploy/ops/"*.sh "$OPS_DIR/"
  for unit in agents-chat-api.service agents-chat-web.service agents-chat-backup.service agents-chat-backup.timer; do
    [[ -f "$release/deploy/systemd/$unit" ]] || continue
    temp="$release/$unit.rendered"
    # Literal replacement via environment avoids shell interpolation of configured paths.
    APP_ROOT="$APP_ROOT" APP_USER="$APP_USER" ENV_FILE="$ENV_FILE" WEB_ENV_FILE="$WEB_ENV_FILE" OPS_DIR="$OPS_DIR" node - "$release/deploy/systemd/$unit" "$temp" <<'NODE'
const fs=require('node:fs');let text=fs.readFileSync(process.argv[2],'utf8');
for(const [a,b] of [['/opt/agents-chat',process.env.APP_ROOT],['/etc/agents-chat/server.env',process.env.ENV_FILE],['/etc/agents-chat/web.env',process.env.WEB_ENV_FILE],['/opt/ops',process.env.OPS_DIR],['User=agentschat','User='+process.env.APP_USER],['Group=agentschat','Group='+process.env.APP_USER]])text=text.split(a).join(b);
fs.writeFileSync(process.argv[3],text);
NODE
    atomic_install "$temp" "$SYSTEMD_DIR/$unit"
  done
  atomic_install "$caddy_next" "$CADDY_FILE"
  systemctl daemon-reload
}
restart_application() {
  local release="$1" failed=0
  systemctl restart agents-chat-api.service || failed=1
  if [[ -f "$release/web/.next/standalone/server.js" ]]; then systemctl restart agents-chat-web.service || failed=1; else systemctl stop agents-chat-web.service || failed=1; fi
  systemctl reload caddy || failed=1
  return "$failed"
}
smoke_application() {
  local release="$1" domain response
  retry_command "$SMOKE_RETRIES" "$SMOKE_DELAY_SECONDS" 'API readiness' bash "$OPS_DIR/check-health.sh" "$HEALTHCHECK_URL"
  domain="$(discover_caddy_domain)"
  validate_domain "$domain"
  if [[ -f "$release/web/.next/standalone/server.js" ]]; then
    retry_command "$SMOKE_RETRIES" "$SMOKE_DELAY_SECONDS" 'Native Web readiness' curl -fsS --max-time 15 http://127.0.0.1:3100/llms.txt >/dev/null
    response="$(curl -fsS --max-time 15 --resolve "$domain:443:127.0.0.1" "https://$domain/")" || return
    [[ "$response" == *'A world beyond'* && "$response" != *'flutter_bootstrap.js'* ]] || { echo 'Native Web HTML check failed.' >&2; return 1; }
    curl -fsS --max-time 15 --resolve "$domain:443:127.0.0.1" "https://$domain/api/v1/health" | jq -e '.status == "ok"' >/dev/null || return
    curl -fsS --max-time 15 http://127.0.0.1:3100/api/openapi.json >/dev/null || return
  else
    curl -fsS --max-time 15 --resolve "$domain:443:127.0.0.1" "https://$domain/" >/dev/null || return
  fi
  env WS_CHECK_URL="wss://$domain/ws" WS_CHECK_CONNECT_HOST=127.0.0.1 WS_CHECK_CONNECT_PORT=443 WS_CHECK_HOST_HEADER="$domain" bash "$OPS_DIR/check-websocket.sh"
}
