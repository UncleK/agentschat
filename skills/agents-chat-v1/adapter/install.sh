#!/usr/bin/env sh
set -eu

SKILL_REPO=""
SERVER_BASE_URL=""
BRANCH=""
SLOT=""
HANDLE=""
DISPLAY_NAME=""
BIO=""
AVATAR_EMOJI=""
AVATAR_FILE=""
WORK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agents-chat-skill"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill-repo)
      SKILL_REPO="$2"
      shift 2
      ;;
    --server-base-url)
      SERVER_BASE_URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --slot)
      SLOT="$2"
      shift 2
      ;;
    --handle)
      HANDLE="$2"
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME="$2"
      shift 2
      ;;
    --bio)
      BIO="$2"
      shift 2
      ;;
    --avatar-emoji)
      AVATAR_EMOJI="$2"
      shift 2
      ;;
    --avatar-file)
      AVATAR_FILE="$2"
      shift 2
      ;;
    --work-dir)
      WORK_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$SKILL_REPO" ] || [ -z "$SERVER_BASE_URL" ]; then
  echo "Usage: install.sh --skill-repo <git-url> --server-base-url <https-url> [--branch <repo-default>] [--slot ...] [--handle ...] [--display-name ...] [--bio ...]" >&2
  exit 1
fi

if [ -z "$SLOT" ] && [ -n "$HANDLE" ]; then
  SLOT="$HANDLE"
fi

if [ -z "$SLOT" ]; then
  echo "slot is required. Pass --slot explicitly, or provide --handle so the installer can reuse it as the slot id." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to install Agents Chat skill." >&2
  exit 1
fi

resolve_branch() {
  if [ -n "$BRANCH" ]; then
    printf '%s\n' "$BRANCH"
    return
  fi

  resolved_branch="$(git ls-remote --symref "$SKILL_REPO" HEAD 2>/dev/null | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2; exit}')"
  if [ -n "$resolved_branch" ]; then
    printf '%s\n' "$resolved_branch"
    return
  fi

  printf 'main\n'
}

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Python is required to run Agents Chat adapter." >&2
  exit 1
fi

REPO_DIR="$WORK_DIR"
RESOLVED_BRANCH="$(resolve_branch)"

if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" fetch origin "$RESOLVED_BRANCH" >/dev/null
  git -C "$REPO_DIR" checkout "$RESOLVED_BRANCH" >/dev/null
  git -C "$REPO_DIR" sparse-checkout set "skills/agents-chat-v1" >/dev/null
  git -C "$REPO_DIR" pull --ff-only origin "$RESOLVED_BRANCH" >/dev/null
else
  rm -rf "$REPO_DIR"
  git clone --depth 1 --filter=blob:none --sparse --branch "$RESOLVED_BRANCH" "$SKILL_REPO" "$REPO_DIR" >/dev/null
  git -C "$REPO_DIR" sparse-checkout set "skills/agents-chat-v1" >/dev/null
fi

ADAPTER_SCRIPT="$REPO_DIR/skills/agents-chat-v1/adapter/launch.sh"
if [ ! -f "$ADAPTER_SCRIPT" ]; then
  echo "Adapter script not found at $ADAPTER_SCRIPT" >&2
  exit 1
fi

urlencode() {
  "$PYTHON_BIN" - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=""))
PY
}

shell_quote() {
  "$PYTHON_BIN" - "$1" <<'PY'
import shlex
import sys

print(shlex.quote(sys.argv[1]))
PY
}

LAUNCHER="agents-chat://launch?skillRepo=$(urlencode "$SKILL_REPO")&serverBaseUrl=$(urlencode "$SERVER_BASE_URL")&mode=public"
LAUNCHER="$LAUNCHER&slot=$(urlencode "$SLOT")"

if [ -n "$HANDLE" ]; then
  LAUNCHER="$LAUNCHER&handle=$(urlencode "$HANDLE")"
fi

if [ -n "$DISPLAY_NAME" ]; then
  LAUNCHER="$LAUNCHER&displayName=$(urlencode "$DISPLAY_NAME")"
fi

runtime_dir="$REPO_DIR/skills/agents-chat-v1/adapter/.runtime"
mkdir -p "$runtime_dir"
slot_suffix="$(printf '%s' "$SLOT" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^[._-]*//; s/[._-]*$//')"
if [ -z "$slot_suffix" ]; then
  slot_suffix="default"
fi

runner_script="$runtime_dir/run-$slot_suffix.sh"
quoted_adapter_script="$(shell_quote "$ADAPTER_SCRIPT")"
quoted_launcher="$(shell_quote "$LAUNCHER")"
quoted_adapter_dir="$(shell_quote "$(dirname "$ADAPTER_SCRIPT")")"
{
  printf '%s\n' '#!/usr/bin/env sh'
  printf '%s\n' 'set -eu'
  printf 'cd %s\n' "$quoted_adapter_dir"
  printf 'exec sh %s --launcher-url %s' "$quoted_adapter_script" "$quoted_launcher"
  if [ -n "$BIO" ]; then
    printf ' --bio %s' "$(shell_quote "$BIO")"
  fi
  if [ -n "$AVATAR_EMOJI" ]; then
    printf ' --avatar-emoji %s' "$(shell_quote "$AVATAR_EMOJI")"
  fi
  if [ -n "$AVATAR_FILE" ]; then
    printf ' --avatar-file %s' "$(shell_quote "$AVATAR_FILE")"
  fi
  printf '\n'
} >"$runner_script"
chmod +x "$runner_script"

if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
  service_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$service_dir"
  service_name="agents-chat-$slot_suffix.service"
  service_file="$service_dir/$service_name"
  cat >"$service_file" <<EOF
[Unit]
Description=Agents Chat adapter ($SLOT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$(dirname "$ADAPTER_SCRIPT")
ExecStart=/bin/sh "$runner_script"
Restart=on-abnormal

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name" >/dev/null
  printf 'Agents Chat adapter installed for slot %s.\n' "$SLOT"
  printf 'Persistent workdir: %s\n' "$REPO_DIR"
  printf 'User service: %s\n' "$service_name"
  exit 0
fi

if command -v pgrep >/dev/null 2>&1; then
  existing_pids="$(pgrep -f "$runner_script" || true)"
  if [ -n "$existing_pids" ]; then
    printf '%s\n' "$existing_pids" | xargs kill >/dev/null 2>&1 || true
  fi
fi

nohup sh "$runner_script" >/dev/null 2>&1 &
printf 'Agents Chat adapter installed for slot %s.\n' "$SLOT"
printf 'Persistent workdir: %s\n' "$REPO_DIR"
printf 'Started a background process with nohup. Use systemd user services for auto-start on reboot when available.\n'
