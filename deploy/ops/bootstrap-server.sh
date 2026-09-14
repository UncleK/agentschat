#!/usr/bin/env bash
set -euo pipefail
APP_ROOT=/opt/agents-chat
APP_USER=agentschat
ENV_DIR=/etc/agents-chat
REPO_DIR="$APP_ROOT/repo"
OPS_DIR="$APP_ROOT/ops"
REPO_URL=''
APP_DOMAIN=''
PROXY_SERVER=nginx
NODE_VERSION=24.21.0
while (( $# )); do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2;;
    --repo-url) REPO_URL="$2"; shift 2;;
    --domain) APP_DOMAIN="$2"; shift 2;;
    --proxy) PROXY_SERVER="$2"; shift 2;;
    --skip-flutter) shift;;
    -h|--help) echo 'bootstrap-server.sh --repo-url URL --domain DOMAIN [--proxy nginx|caddy] [--repo-dir PATH]'; exit 0;;
    *) echo "Unknown argument: $1" >&2; exit 1;;
  esac
done
[[ "$(id -u)" == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ "$APP_DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || { echo 'A DNS hostname is required.' >&2; exit 1; }
[[ "$PROXY_SERVER" == nginx || "$PROXY_SERVER" == caddy ]] || exit 1
. /etc/os-release
[[ "$ID" == ubuntu || "$ID" == debian ]] || { echo 'This bootstrap supports Ubuntu and Debian.' >&2; exit 1; }
# Reuse the selected ingress, never install a competing web server on occupied ports.
command -v "$PROXY_SERVER" >/dev/null || { echo "Install/configure $PROXY_SERVER before bootstrap; existing ingress is not replaced." >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l
apt-get update
apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends ca-certificates curl ffmpeg git jq python3 python3-venv tar xz-utils util-linux
if ! command -v docker >/dev/null; then
  apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends docker.io
fi
if ! docker compose version >/dev/null 2>&1; then
  compose_package=docker-compose-v2
  [[ "$ID" != debian ]] || compose_package=docker-compose
  apt-get -o DPkg::Lock::Timeout=120 install -y --no-install-recommends "$compose_package"
fi
docker compose version >/dev/null
systemctl enable --now docker
id "$APP_USER" >/dev/null 2>&1 || useradd --system --create-home --shell /bin/bash "$APP_USER"
install -d -o root -g "$APP_USER" -m 0755 "$APP_ROOT" "$APP_ROOT/runtime" "$APP_ROOT/runtime/bin"
install -d -o "$APP_USER" -g "$APP_USER" "$APP_ROOT/releases" "$APP_ROOT/shared" "$REPO_DIR"
install -d -o root -g root -m 0755 "$OPS_DIR"
install -d -o root -g "$APP_USER" -m 0750 "$ENV_DIR"
install -d -o root -g root -m 0700 "$ENV_DIR/tls" "$APP_ROOT/backups"
arch="$(uname -m)"
case "$arch" in x86_64) arch=x64;; aarch64) arch=arm64;; *) echo 'Unsupported architecture.' >&2; exit 1;; esac
node_dir="node-v$NODE_VERSION-linux-$arch"
if [[ ! -x "$APP_ROOT/runtime/$node_dir/bin/node" ]]; then
  temporary="$(mktemp -d)"
  trap 'rm -rf -- "$temporary"' EXIT
  curl -fsS --retry 3 "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt" -o "$temporary/SHASUMS256.txt"
  curl -fsS --retry 3 "https://nodejs.org/dist/v$NODE_VERSION/$node_dir.tar.xz" -o "$temporary/$node_dir.tar.xz"
  (cd "$temporary"; grep " $node_dir.tar.xz$" SHASUMS256.txt | sha256sum --check -)
  tar -xJf "$temporary/$node_dir.tar.xz" --no-same-owner -C "$APP_ROOT/runtime"
  rm -rf -- "$temporary"
  trap - EXIT
fi
for command in node npm npx; do ln -sfn "$APP_ROOT/runtime/$node_dir/bin/$command" "$APP_ROOT/runtime/bin/$command"; done
export PATH="$APP_ROOT/runtime/bin:$PATH"
if [[ ! -x "$APP_ROOT/runtime/tools/node_modules/.bin/pnpm" ]]; then
  npm install --prefix "$APP_ROOT/runtime/tools" --no-audit --no-fund pnpm@10.33.0
fi
ln -sfn "$APP_ROOT/runtime/tools/node_modules/.bin/pnpm" "$APP_ROOT/runtime/bin/pnpm"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  [[ -n "$REPO_URL" ]] || { echo 'Set --repo-url or provide a checkout.' >&2; exit 1; }
  sudo -u "$APP_USER" git clone "$REPO_URL" "$REPO_DIR"
fi
install -m 0755 "$REPO_DIR/deploy/ops/"*.sh "$OPS_DIR/"
if [[ ! -f "$ENV_DIR/server.env" ]]; then
  install -m 0640 -o root -g "$APP_USER" "$REPO_DIR/server/.env.example" "$ENV_DIR/server.env"
  sed -i -e 's/^NODE_ENV=.*/NODE_ENV=production/' -e 's/^PORT=.*/PORT=3200/' \
    -e 's/^MAIL_DELIVERY_MODE=.*/MAIL_DELIVERY_MODE=disabled/' \
    -e 's/^MINIO_ENDPOINT=.*/MINIO_ENDPOINT=127.0.0.1/' -e 's/^MINIO_PORT=.*/MINIO_PORT=59000/' "$ENV_DIR/server.env"
fi
if [[ ! -f "$ENV_DIR/web.env" ]]; then
  install -m 0640 -o root -g "$APP_USER" "$REPO_DIR/deploy/web.env.example" "$ENV_DIR/web.env"
  sed -i -e "s|^NEXT_PUBLIC_SITE_URL=.*|NEXT_PUBLIC_SITE_URL=https://$APP_DOMAIN|" \
    -e 's|^API_ORIGIN=.*|API_ORIGIN=http://127.0.0.1:3200|' "$ENV_DIR/web.env"
  printf '\nPORT=3201\n' >> "$ENV_DIR/web.env"
fi
if [[ ! -f "$ENV_DIR/deploy.env" ]]; then
  install -m 0640 -o root -g "$APP_USER" "$REPO_DIR/deploy/deploy.env.example" "$ENV_DIR/deploy.env"
  if [[ "$PROXY_SERVER" == caddy ]]; then
    sed -i -e 's/^PROXY_SERVER=.*/PROXY_SERVER=caddy/' \
      -e 's|^PROXY_CONFIG_FILE=.*|PROXY_CONFIG_FILE=/etc/caddy/sites/agents-chat.caddy|' \
      -e 's|^ORIGIN_CA_FILE=.*|ORIGIN_CA_FILE=|' "$ENV_DIR/deploy.env"
    install -d /etc/caddy/sites
    grep -Eq '^import /etc/caddy/sites/\*' /etc/caddy/Caddyfile || { echo 'Add import /etc/caddy/sites/* to the existing Caddy main config first.' >&2; exit 1; }
  fi
fi
printf '%s\n' "$APP_DOMAIN" > "$ENV_DIR/domain"
echo 'Bootstrap ready. Configure production secrets, loopback ports, immutable images, TLS and Cloudflare CIDRs before release.'
