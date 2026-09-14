#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
release_init
TARGET_RELEASE=""
while (( $# )); do
  case "$1" in
    --release-id) (( $# >= 2 )) || { echo 'Missing release id.' >&2; exit 1; }; TARGET_RELEASE="$2"; shift 2;;
    -h|--help) echo 'Usage: rollback-release.sh [--release-id ID]'; exit 0;;
    *) echo "Unknown argument: $1" >&2; exit 1;;
  esac
done
[[ "$(id -u)" == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
release_lock
[[ -L "$CURRENT_LINK" ]] || { echo 'Current release symlink is missing.' >&2; exit 1; }
CURRENT_RELEASE="$(readlink -f "$CURRENT_LINK")"
if [[ -z "$TARGET_RELEASE" ]]; then
  require_file "$CURRENT_RELEASE/.previous-release"
  previous="$(cat "$CURRENT_RELEASE/.previous-release")"
  [[ -n "$previous" && -d "$previous" ]] || { echo 'No recorded previous release; specify a verified release id.' >&2; exit 1; }
  [[ "$(dirname "$(realpath "$previous")")" == "$(realpath "$RELEASES_DIR")" ]] || { echo "Recorded previous release is outside RELEASES_DIR." >&2; exit 1; }
  TARGET_RELEASE="$(basename "$previous")"
fi
validate_release_id "$TARGET_RELEASE"
TARGET_DIR="$RELEASES_DIR/$TARGET_RELEASE"
[[ -d "$TARGET_DIR" && ! -L "$TARGET_DIR" && "$TARGET_DIR" != "$CURRENT_RELEASE" ]] || { echo 'Target must be an existing different release directory.' >&2; exit 1; }
[[ ! -f "$TARGET_DIR/.release-failed" ]] || { echo 'Refusing to roll back to a failed deployment.' >&2; exit 1; }
require_file "$TARGET_DIR/server/dist/src/main.js"
RECOVERY_DIR="$APP_ROOT/shared/rollback-$(date +%Y%m%d%H%M%S)-$$"
mkdir -p "$RECOVERY_DIR"
if [[ -f "$TARGET_DIR/web/.next/standalone/server.js" ]]; then
  if [[ -f "$TARGET_DIR/Caddyfile.deployed" ]]; then cp -a "$TARGET_DIR/Caddyfile.deployed" "$RECOVERY_DIR/Caddyfile.target"
  else prepare_caddy "$TARGET_DIR" "$RECOVERY_DIR/Caddyfile.target"; fi
elif [[ -f "$TARGET_DIR/app/build/web/index.html" ]]; then
  if [[ -n "${LEGACY_CADDY_FILE:-}" ]]; then require_file "$LEGACY_CADDY_FILE"; cp -a "$LEGACY_CADDY_FILE" "$RECOVERY_DIR/Caddyfile.target"
  elif [[ -f "$CURRENT_RELEASE/.previous-release" && "$(cat "$CURRENT_RELEASE/.previous-release")" == "$TARGET_DIR" && -f "$CURRENT_RELEASE/.deployment-before/Caddyfile" ]]; then cp -a "$CURRENT_RELEASE/.deployment-before/Caddyfile" "$RECOVERY_DIR/Caddyfile.target"
  elif [[ -f "$TARGET_DIR/Caddyfile.deployed" ]]; then cp -a "$TARGET_DIR/Caddyfile.deployed" "$RECOVERY_DIR/Caddyfile.target"
  else echo 'Provide LEGACY_CADDY_FILE for this legacy rollback; no verified matching configuration is available.' >&2; exit 1; fi
else echo 'Target has neither a complete native Web nor legacy Flutter Web build.' >&2; exit 1; fi
validate_proxy_fragment "$RECOVERY_DIR/Caddyfile.target"
snapshot_configuration "$RECOVERY_DIR/before" "$TARGET_DIR"
CONFIG_CHANGED=false
CURRENT_CHANGED=false
recover_failed_rollback() {
  local result="$?" failed=0
  (( result != 0 )) || return 0
  trap - EXIT
  set +e
  if [[ "$CURRENT_CHANGED" == true ]]; then atomic_switch "$CURRENT_RELEASE" || failed=1; fi
  if [[ "$CONFIG_CHANGED" == true ]]; then restore_configuration "$RECOVERY_DIR/before" || failed=1; fi
  if [[ "$CURRENT_CHANGED" == true ]]; then restart_application "$CURRENT_RELEASE" || failed=1; fi
  if (( failed )); then echo 'Rollback failed and recovery is incomplete; inspect services immediately.' >&2
  else echo 'Rollback failed; restored the release and configuration that were active before this attempt.' >&2; fi
  exit "$result"
}
trap recover_failed_rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
CONFIG_CHANGED=true
install_release_configuration "$TARGET_DIR" "$RECOVERY_DIR/Caddyfile.target"
CURRENT_CHANGED=true
atomic_switch "$TARGET_DIR"
restart_application "$TARGET_DIR"
smoke_application "$TARGET_DIR"
trap - EXIT INT TERM
echo "Rollback complete: $TARGET_RELEASE. Database migrations were not reversed."
