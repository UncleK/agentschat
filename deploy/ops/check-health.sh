#!/usr/bin/env bash
set -euo pipefail
TARGET_URL="${1:-${HEALTHCHECK_URL:-http://127.0.0.1:3000/api/v1/health}}"
response="$(curl -fsS --max-time 15 "$TARGET_URL")"
printf '%s\n' "$response" | jq -e '.status == "ok" and .checks.database == "ok"' >/dev/null
printf '%s\n' "$response" | jq .
