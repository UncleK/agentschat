#!/usr/bin/env bash
set -euo pipefail
umask 077
export PATH="${APP_ROOT:-/opt/agents-chat}/runtime/bin:$PATH"

ENV_FILE="${ENV_FILE:-/etc/agents-chat/server.env}"
POSTGRES_BACKUP_DIR="${POSTGRES_BACKUP_DIR:-/opt/agents-chat/backups/postgres}"
MINIO_BACKUP_DIR="${MINIO_BACKUP_DIR:-/opt/agents-chat/backups/minio}"
REPORT_DIR="${REPORT_DIR:-/opt/agents-chat/backups/reports}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
MINIO_CONTAINER_NAME="${MINIO_CONTAINER_NAME:-agents-chat-minio}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

install -d "$POSTGRES_BACKUP_DIR" "$MINIO_BACKUP_DIR" "$REPORT_DIR"
exec 8>"$REPORT_DIR/.backup.lock"
flock -n 8 || { echo 'Another backup is running.' >&2; exit 1; }

# Use the matching client inside this project's database container. No passwords in argv.
docker exec agents-chat-postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom' > "$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump.partial"
docker exec -i agents-chat-postgres pg_restore --list < "$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump.partial" >/dev/null
mv "$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump.partial" "$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump"

minio_data_dir="$(docker inspect "$MINIO_CONTAINER_NAME" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')"
if [[ -z "$minio_data_dir" || ! -d "$minio_data_dir" ]]; then
  echo "Unable to locate MinIO data directory for container $MINIO_CONTAINER_NAME." >&2
  exit 1
fi

# Pause only this project's object store so the filesystem archive is consistent.
minio_paused=false
trap 'if [[ "$minio_paused" == true ]]; then docker unpause "$MINIO_CONTAINER_NAME" >/dev/null; fi' EXIT
docker pause "$MINIO_CONTAINER_NAME" >/dev/null
minio_paused=true
tar -czf "$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz.partial" -C "$minio_data_dir" .
docker unpause "$MINIO_CONTAINER_NAME" >/dev/null
minio_paused=false
tar -tzf "$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz.partial" >/dev/null
mv "$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz.partial" "$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz"
trap - EXIT

find "$POSTGRES_BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
find "$MINIO_BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete

cat >"$REPORT_DIR/latest-backup.txt" <<EOF
timestamp=$TIMESTAMP
postgres_dump=$POSTGRES_BACKUP_DIR/agents-chat-$TIMESTAMP.dump
minio_archive=$MINIO_BACKUP_DIR/minio-$TIMESTAMP.tar.gz
EOF

echo "Backup complete for timestamp $TIMESTAMP"
