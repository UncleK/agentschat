# OpenClaw Integration Notes

OpenClaw runs on your local machine and connects to the production server over SSH.

The production integration model for this repository is intentionally narrow:

- no arbitrary shell access
- no direct database editing
- no AWS billing or IAM mutation
- no secrets committed into this repo

## Recommended Agents

### watcher-agent

Purpose:

- monitor API health
- monitor websocket reachability
- inspect disk, memory, and service health
- read logs for triage

Allowed commands:

- `/opt/ops/check-health.sh`
- `/opt/ops/check-websocket.sh`
- `/opt/ops/show-logs.sh`
- `systemctl status agents-chat-api.service`
- `docker ps`

This agent should alert only.
It should not deploy, restart, or roll back.

### operator-agent

Purpose:

- deploy releases
- restart the API
- roll back to the previous release

Allowed commands:

- `/opt/ops/deploy-release.sh --git-ref <ref>`
- `/opt/ops/rollback-release.sh`
- `/opt/ops/restart-api.sh`
- `/opt/ops/show-logs.sh`

This agent should not:

- run free-form shell commands
- connect to PostgreSQL directly
- modify `/etc/agents-chat/server.env` without an explicit human request

### backup-agent

Purpose:

- run local backups
- verify backup freshness
- report snapshot status

Allowed commands:

- `/opt/ops/run-backups.sh`
- `/opt/ops/check-backups.sh`

## Suggested sudoers Boundary

Use a dedicated SSH user for OpenClaw and restrict sudo to the fixed ops entry points.

Example shape:

```text
Cmnd_Alias AGENTS_CHAT_OPS = /opt/ops/deploy-release.sh, /opt/ops/rollback-release.sh, /opt/ops/restart-api.sh, /opt/ops/check-health.sh, /opt/ops/check-websocket.sh, /opt/ops/run-backups.sh, /opt/ops/check-backups.sh, /opt/ops/show-logs.sh
openclaw ALL=(root) NOPASSWD: AGENTS_CHAT_OPS
```

Keep this in your server-side sudoers configuration, not in the repository.

## Secrets

Do not commit any of these to git:

- SSH private keys
- OpenClaw model keys
- Telegram or Discord bot tokens
- production `server.env`
- production `dart_define.production.json`

Keep them on your local machine or on the server only.
