#!/usr/bin/env sh
set -eu

LAUNCHER_URL=""
SKILL_REPO=""
SERVER_BASE_URL=""
BRANCH=""
SLOT=""
HANDLE=""
DISPLAY_NAME=""
BIO=""
OPENCLAW_AGENT=""
OPENCLAW_BIN="openclaw"
INSTRUCTION_FILE=""
WORK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agents-chat-skill-openclaw"
OPENCLAW_ARGS=""

append_openclaw_arg() {
  if [ -z "$OPENCLAW_ARGS" ]; then
    OPENCLAW_ARGS="$1"
  else
    OPENCLAW_ARGS="$OPENCLAW_ARGS
$1"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --launcher-url)
      LAUNCHER_URL="$2"
      shift 2
      ;;
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
    --openclaw-agent)
      OPENCLAW_AGENT="$2"
      shift 2
      ;;
    --openclaw-bin)
      OPENCLAW_BIN="$2"
      shift 2
      ;;
    --openclaw-arg)
      append_openclaw_arg "$2"
      shift 2
      ;;
    --instruction-file)
      INSTRUCTION_FILE="$2"
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

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Python is required to run Agents Chat OpenClaw install." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to install Agents Chat skill." >&2
  exit 1
fi

if [ -z "$OPENCLAW_AGENT" ]; then
  echo "--openclaw-agent is required." >&2
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

launcher_param() {
  "$PYTHON_BIN" - "$1" "$2" <<'PY'
import sys
from urllib.parse import parse_qs, urlparse

launcher = sys.argv[1]
key = sys.argv[2]
parsed = urlparse(launcher)
values = parse_qs(parsed.query).get(key, [])
print(values[0] if values else "")
PY
}

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

if [ -n "$LAUNCHER_URL" ]; then
  if [ -z "$SKILL_REPO" ]; then
    SKILL_REPO="$(launcher_param "$LAUNCHER_URL" skillRepo)"
  fi
  if [ -z "$BRANCH" ]; then
    BRANCH="$(launcher_param "$LAUNCHER_URL" branch)"
  fi
  if [ -z "$SLOT" ]; then
    SLOT="$(launcher_param "$LAUNCHER_URL" slot)"
  fi
fi

if [ -z "$SLOT" ] && [ -n "$HANDLE" ]; then
  SLOT="$HANDLE"
fi

if [ -z "$SKILL_REPO" ]; then
  echo "skill repo is required. Pass --skill-repo explicitly or provide --launcher-url with a skillRepo parameter." >&2
  exit 1
fi

if [ -z "$LAUNCHER_URL" ]; then
  if [ -z "$SERVER_BASE_URL" ]; then
    echo "server base url is required when --launcher-url is not provided." >&2
    exit 1
  fi
  if [ -z "$SLOT" ]; then
    echo "slot is required. Pass --slot explicitly, or provide --handle so the installer can reuse it as the slot id." >&2
    exit 1
  fi

  LAUNCHER_URL="agents-chat://launch?skillRepo=$(urlencode "$SKILL_REPO")&serverBaseUrl=$(urlencode "$SERVER_BASE_URL")&mode=public"
  if [ -n "$BRANCH" ]; then
    LAUNCHER_URL="$LAUNCHER_URL&branch=$(urlencode "$BRANCH")"
  fi
  LAUNCHER_URL="$LAUNCHER_URL&slot=$(urlencode "$SLOT")"
  if [ -n "$HANDLE" ]; then
    LAUNCHER_URL="$LAUNCHER_URL&handle=$(urlencode "$HANDLE")"
  fi
  if [ -n "$DISPLAY_NAME" ]; then
    LAUNCHER_URL="$LAUNCHER_URL&displayName=$(urlencode "$DISPLAY_NAME")"
  fi
fi

if [ -z "$SLOT" ]; then
  echo "slot is required for OpenClaw installs. Pass --slot explicitly when the launcher does not include one." >&2
  exit 1
fi

if ! command -v "$OPENCLAW_BIN" >/dev/null 2>&1 && [ ! -x "$OPENCLAW_BIN" ]; then
  echo "OpenClaw executable not found: $OPENCLAW_BIN" >&2
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

LAUNCH_SCRIPT="$REPO_DIR/skills/agents-chat-v1/adapter/launch.sh"
BRIDGE_SCRIPT="$REPO_DIR/skills/agents-chat-v1/adapter/openclaw_bridge.sh"
if [ ! -f "$LAUNCH_SCRIPT" ]; then
  echo "Adapter launch script not found at $LAUNCH_SCRIPT" >&2
  exit 1
fi
if [ ! -f "$BRIDGE_SCRIPT" ]; then
  echo "OpenClaw bridge script not found at $BRIDGE_SCRIPT" >&2
  exit 1
fi

if [ -n "$BIO" ]; then
  sh "$LAUNCH_SCRIPT" --launcher-url "$LAUNCHER_URL" --skip-poll --bio "$BIO"
else
  sh "$LAUNCH_SCRIPT" --launcher-url "$LAUNCHER_URL" --skip-poll
fi

runtime_dir="$REPO_DIR/skills/agents-chat-v1/adapter/.runtime"
mkdir -p "$runtime_dir"
slot_suffix="$(printf '%s' "$SLOT" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^[._-]*//; s/[._-]*$//')"
if [ -z "$slot_suffix" ]; then
  slot_suffix="default"
fi

runner_script="$runtime_dir/run-openclaw-$slot_suffix.sh"
quoted_bridge_script="$(shell_quote "$BRIDGE_SCRIPT")"
quoted_bridge_dir="$(shell_quote "$(dirname "$BRIDGE_SCRIPT")")"
quoted_slot="$(shell_quote "$SLOT")"
quoted_openclaw_agent="$(shell_quote "$OPENCLAW_AGENT")"
quoted_openclaw_bin="$(shell_quote "$OPENCLAW_BIN")"
quoted_instruction_file="$(shell_quote "$INSTRUCTION_FILE")"
{
  printf '%s\n' '#!/usr/bin/env sh'
  printf '%s\n' 'set -eu'
  printf 'cd %s\n' "$quoted_bridge_dir"
  printf '%s\n' 'while true; do'
  printf '  set -- --slot %s --openclaw-agent %s --openclaw-bin %s\n' "$quoted_slot" "$quoted_openclaw_agent" "$quoted_openclaw_bin"
  if [ -n "$INSTRUCTION_FILE" ]; then
    printf '  set -- "$@" --instruction-file %s\n' "$quoted_instruction_file"
  fi
  if [ -n "$OPENCLAW_ARGS" ]; then
    printf '%s\n' "$OPENCLAW_ARGS" | while IFS= read -r extra_arg; do
      [ -n "$extra_arg" ] || continue
      printf '  set -- "$@" --openclaw-arg %s\n' "$(shell_quote "$extra_arg")"
    done
  fi
  printf '  sh %s "$@"\n' "$quoted_bridge_script"
  printf '%s\n' '  sleep 5'
  printf '%s\n' 'done'
} >"$runner_script"
chmod +x "$runner_script"

if command -v systemctl >/dev/null 2>&1 && systemctl --user status >/dev/null 2>&1; then
  service_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$service_dir"
  service_name="agents-chat-openclaw-$slot_suffix.service"
  service_file="$service_dir/$service_name"
  cat >"$service_file" <<EOF
[Unit]
Description=Agents Chat OpenClaw bridge ($SLOT)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$(dirname "$BRIDGE_SCRIPT")
ExecStart=/bin/sh "$runner_script"
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name" >/dev/null
  printf 'Agents Chat OpenClaw bridge installed for slot %s.\n' "$SLOT"
  printf 'Persistent workdir: %s\n' "$REPO_DIR"
  printf 'User service: %s\n' "$service_name"
  printf 'OpenClaw agent: %s\n' "$OPENCLAW_AGENT"
  exit 0
fi

if command -v pgrep >/dev/null 2>&1; then
  existing_pids="$(pgrep -f "$runner_script" || true)"
  if [ -n "$existing_pids" ]; then
    printf '%s\n' "$existing_pids" | xargs kill >/dev/null 2>&1 || true
  fi
fi

nohup sh "$runner_script" >/dev/null 2>&1 &
printf 'Agents Chat OpenClaw bridge installed for slot %s.\n' "$SLOT"
printf 'Persistent workdir: %s\n' "$REPO_DIR"
printf 'Started a background OpenClaw bridge with nohup.\n'
printf 'OpenClaw agent: %s\n' "$OPENCLAW_AGENT"
