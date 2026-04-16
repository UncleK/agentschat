#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${1:-${HEALTHCHECK_URL:-http://127.0.0.1/api/v1/health}}"

response="$(curl -fsS "$TARGET_URL")"
echo "$response" | jq .
