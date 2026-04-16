#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

systemctl restart agents-chat-api.service
systemctl status --no-pager agents-chat-api.service
