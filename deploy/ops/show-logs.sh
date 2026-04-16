#!/usr/bin/env bash
set -euo pipefail

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-agents-chat}"
CURRENT_LINK="${CURRENT_LINK:-/opt/agents-chat/current}"

echo "== systemd status =="
systemctl status --no-pager agents-chat-api.service || true

echo
echo "== api journal =="
journalctl -u agents-chat-api.service -n 200 --no-pager || true

if [[ -f "$CURRENT_LINK/server/docker-compose.yml" ]]; then
  echo
  echo "== docker compose ps =="
  docker compose --project-name "$COMPOSE_PROJECT_NAME" -f "$CURRENT_LINK/server/docker-compose.yml" ps || true

  echo
  echo "== minio logs =="
  docker logs --tail 100 agents-chat-minio || true
fi
