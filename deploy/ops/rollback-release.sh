#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/agents-chat}"
RELEASES_DIR="${RELEASES_DIR:-$APP_ROOT/releases}"
CURRENT_LINK="${CURRENT_LINK:-$APP_ROOT/current}"
TARGET_RELEASE=""

usage() {
  cat <<'EOF'
Usage:
  rollback-release.sh [--release-id <release-id>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-id)
      TARGET_RELEASE="$2"
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

if [[ ! -L "$CURRENT_LINK" ]]; then
  echo "Current release symlink not found: $CURRENT_LINK" >&2
  exit 1
fi

current_release="$(basename "$(readlink -f "$CURRENT_LINK")")"

if [[ -z "$TARGET_RELEASE" ]]; then
  mapfile -t release_ids < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

  previous_release=""
  for release_id in "${release_ids[@]}"; do
    if [[ "$release_id" == "$current_release" ]]; then
      break
    fi
    previous_release="$release_id"
  done

  if [[ -z "$previous_release" ]]; then
    echo "No previous release found to roll back to." >&2
    exit 1
  fi

  TARGET_RELEASE="$previous_release"
fi

target_dir="$RELEASES_DIR/$TARGET_RELEASE"
if [[ ! -d "$target_dir" ]]; then
  echo "Target release not found: $target_dir" >&2
  exit 1
fi

ln -sfn "$target_dir" "$CURRENT_LINK"
systemctl restart agents-chat-api.service
/opt/ops/check-health.sh

cat <<EOF
Rollback complete.
Current release: $TARGET_RELEASE
Note: database migrations were not rolled back automatically.
EOF
