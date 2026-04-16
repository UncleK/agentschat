#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/agents-chat/server.env}"
POSTGRES_BACKUP_DIR="${POSTGRES_BACKUP_DIR:-/opt/backups/postgres}"
MINIO_BACKUP_DIR="${MINIO_BACKUP_DIR:-/opt/backups/minio}"
REPORT_DIR="${REPORT_DIR:-/opt/backups/reports}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
MINIO_CONTAINER_NAME="${MINIO_CONTAINER_NAME:-agents-chat-minio}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

install -d "$POSTGRES_BACKUP_DIR" "$MINIO_BACKUP_DIR" "$REPORT_DIR"

pg_dump "$DATABASE_URL" --format=custom --file "$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump"

minio_data_dir="$(docker inspect "$MINIO_CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')"
if [[ -z "$minio_data_dir" || ! -d "$minio_data_dir" ]]; then
  echo "Unable to locate MinIO data directory for container $MINIO_CONTAINER_NAME." >&2
  exit 1
fi

tar -czf "$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz" -C "$minio_data_dir" .

find "$POSTGRES_BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
find "$MINIO_BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete

cat >"$REPORT_DIR/latest-backup.txt" <<EOF
timestamp=$TIMESTAMP
postgres_dump=$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump
minio_archive=$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz
EOF

echo "Backup complete for timestamp $TIMESTAMP"
