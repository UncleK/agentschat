#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/opt/agents-chat/repo"
REPO_URL=""
APP_DOMAIN=""
SKIP_FLUTTER="false"
APP_USER="agentschat"
APP_ROOT="/opt/agents-chat"
ENV_DIR="/etc/agents-chat"
OPS_DIR="/opt/ops"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-server.sh [--repo-dir PATH] [--repo-url URL] [--domain DOMAIN] [--skip-flutter]

Options:
  --repo-dir PATH    Server-side repository path. Default: /opt/agents-chat/repo
  --repo-url URL     Optional git URL to clone if the repo does not exist yet.
  --domain DOMAIN    Public domain to inject into the Caddyfile.
  --skip-flutter     Skip installing Flutter on the server.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir)
      REPO_DIR="$2"
      shift 2
      ;;
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --domain)
      APP_DOMAIN="$2"
      shift 2
      ;;
    --skip-flutter)
      SKIP_FLUTTER="true"
      shift
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

install_base_packages() {
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    ffmpeg \
    git \
    gnupg \
    jq \
    lsb-release \
    postgresql-client \
    python3 \
    python3-pip \
    python3-venv \
    software-properties-common \
    snapd \
    tar \
    unzip
}

install_node() {
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
  fi

  corepack enable
}

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable
EOF

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  systemctl enable --now docker
}

install_caddy() {
  if ! command -v caddy >/dev/null 2>&1; then
    install -d -m 0755 /etc/apt/keyrings
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /etc/apt/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/deb/debian.any-version.list' > /etc/apt/sources.list.d/caddy-stable.list

    apt-get update
    apt-get install -y caddy
  fi

  systemctl enable --now caddy
}

install_flutter() {
  if [[ "$SKIP_FLUTTER" == "true" ]]; then
    return
  fi

  if command -v flutter >/dev/null 2>&1; then
    return
  fi

  snap install flutter --classic
}

ensure_users_and_dirs() {
  if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd --system --create-home --shell /bin/bash "$APP_USER"
  fi

  usermod -aG docker "$APP_USER"

  install -d -o "$APP_USER" -g "$APP_USER" "$APP_ROOT"
  install -d -o "$APP_USER" -g "$APP_USER" "$APP_ROOT/releases"
  install -d -o "$APP_USER" -g "$APP_USER" "$APP_ROOT/shared"
  install -d -o "$APP_USER" -g "$APP_USER" "$OPS_DIR"
  install -d -o root -g "$APP_USER" -m 0750 "$ENV_DIR"
  install -d -o root -g root /opt/backups
  install -d -o root -g root /opt/backups/postgres
  install -d -o root -g root /opt/backups/minio
  install -d -o root -g root /opt/backups/reports
}

ensure_repo() {
  if [[ -d "$REPO_DIR/.git" ]]; then
    return
  fi

  if [[ -z "$REPO_URL" ]]; then
    echo "Repository not found at $REPO_DIR. Re-run with --repo-url or clone manually." >&2
    exit 1
  fi

  install -d -o "$APP_USER" -g "$APP_USER" "$(dirname "$REPO_DIR")"
  sudo -u "$APP_USER" git clone "$REPO_URL" "$REPO_DIR"
}

install_templates() {
  local deploy_dir="$REPO_DIR/deploy"

  install -m 0644 "$deploy_dir/systemd/agents-chat-api.service" /etc/systemd/system/agents-chat-api.service
  install -m 0644 "$deploy_dir/systemd/agents-chat-backup.service" /etc/systemd/system/agents-chat-backup.service
  install -m 0644 "$deploy_dir/systemd/agents-chat-backup.timer" /etc/systemd/system/agents-chat-backup.timer
  install -m 0755 "$deploy_dir/ops/"*.sh "$OPS_DIR/"

  if [[ ! -f "$ENV_DIR/server.env" ]]; then
    install -m 0640 -o root -g "$APP_USER" "$REPO_DIR/server/.env.example" "$ENV_DIR/server.env"
    sed -i 's/^NODE_ENV=.*/NODE_ENV=production/' "$ENV_DIR/server.env"
    sed -i 's/^MINIO_ENDPOINT=.*/MINIO_ENDPOINT=127.0.0.1/' "$ENV_DIR/server.env"
  fi

  if [[ ! -f "$ENV_DIR/dart_define.production.json" ]]; then
    install -m 0640 -o root -g "$APP_USER" "$REPO_DIR/app/tool/dart_define.production.example.json" "$ENV_DIR/dart_define.production.json"
  fi

  if [[ -n "$APP_DOMAIN" ]]; then
    sed "s/__APP_DOMAIN__/$APP_DOMAIN/g" "$deploy_dir/caddy/Caddyfile.example" > /etc/caddy/Caddyfile
  fi

  systemctl daemon-reload
  systemctl enable agents-chat-backup.timer

  if [[ -n "$APP_DOMAIN" ]]; then
    systemctl restart caddy
  elif [[ ! -f /etc/caddy/Caddyfile ]]; then
    echo "No domain provided, so /etc/caddy/Caddyfile was not generated yet." >&2
    echo "Set the domain and install the Caddy template before exposing the server publicly." >&2
  fi
}

main() {
  install_base_packages
  install_node
  install_docker
  install_caddy
  install_flutter
  ensure_users_and_dirs
  ensure_repo
  install_templates
}

main "$@"
