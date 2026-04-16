#!/usr/bin/env bash
set -euo pipefail

POSTGRES_BACKUP_DIR="${POSTGRES_BACKUP_DIR:-/opt/backups/postgres}"
MINIO_BACKUP_DIR="${MINIO_BACKUP_DIR:-/opt/backups/minio}"
REPORT_DIR="${REPORT_DIR:-/opt/backups/reports}"
MAX_BACKUP_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-30}"
REQUIRE_SNAPSHOT_STATUS="${REQUIRE_SNAPSHOT_STATUS:-false}"

latest_file() {
  local directory="$1"
  find "$directory" -maxdepth 1 -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-
}

check_file_age() {
  local label="$1"
  local path="$2"
  local mtime epoch_now age_hours
  mtime="$(stat -c %Y "$path")"
  epoch_now="$(date +%s)"
  age_hours="$(( (epoch_now - mtime) / 3600 ))"

  echo "$label: $path (${age_hours}h old)"

  if (( age_hours > MAX_BACKUP_AGE_HOURS )); then
    echo "$label is older than ${MAX_BACKUP_AGE_HOURS}h." >&2
    return 1
  fi
}

postgres_file="$(latest_file "$POSTGRES_BACKUP_DIR")"
minio_file="$(latest_file "$MINIO_BACKUP_DIR")"

if [[ -z "$postgres_file" || ! -f "$postgres_file" ]]; then
  echo "No PostgreSQL backup found in $POSTGRES_BACKUP_DIR" >&2
  exit 1
fi

if [[ -z "$minio_file" || ! -f "$minio_file" ]]; then
  echo "No MinIO backup found in $MINIO_BACKUP_DIR" >&2
  exit 1
fi

check_file_age "postgres_backup" "$postgres_file"
check_file_age "minio_backup" "$minio_file"

snapshot_status_file="$REPORT_DIR/lightsail-snapshot-status.txt"
if command -v aws >/dev/null 2>&1 && [[ -n "${AWS_REGION:-}" && -n "${LIGHTSAIL_INSTANCE_NAME:-}" ]]; then
  aws lightsail get-instance-snapshots \
    --region "$AWS_REGION" \
    --query "instanceSnapshots[?fromInstanceName=='${LIGHTSAIL_INSTANCE_NAME}'] | sort_by(@,&createdAt)[-1].{name:name,state:state,createdAt:createdAt}" \
    --output table
elif [[ -f "$snapshot_status_file" ]]; then
  echo "latest_snapshot_status:"
  cat "$snapshot_status_file"
elif [[ "$REQUIRE_SNAPSHOT_STATUS" == "true" ]]; then
  echo "Snapshot status is required but no AWS CLI result or report file is available." >&2
  exit 1
else
  echo "Snapshot status: skipped (configure AWS CLI or write $snapshot_status_file)."
fi
