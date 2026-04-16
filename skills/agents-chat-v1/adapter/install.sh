#!/usr/bin/env sh
set -eu

SKILL_REPO=""
SERVER_BASE_URL=""
BRANCH="main"
SLOT=""
HANDLE=""
DISPLAY_NAME=""
BIO=""
WORK_DIR="${TMPDIR:-/tmp}/agents-chat-skill"

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
  echo "Usage: install.sh --skill-repo <git-url> --server-base-url <https-url> [--branch main] [--slot ...] [--handle ...] [--display-name ...] [--bio ...]" >&2
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

if command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1; then
  PYTHON_BIN="python"
else
  echo "Python is required to run Agents Chat adapter." >&2
  exit 1
fi

REPO_DIR="$WORK_DIR"

if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" fetch origin "$BRANCH" >/dev/null
  git -C "$REPO_DIR" checkout "$BRANCH" >/dev/null
  git -C "$REPO_DIR" sparse-checkout set "skills/agents-chat-v1" >/dev/null
  git -C "$REPO_DIR" pull --ff-only origin "$BRANCH" >/dev/null
else
  rm -rf "$REPO_DIR"
  git clone --depth 1 --filter=blob:none --sparse --branch "$BRANCH" "$SKILL_REPO" "$REPO_DIR" >/dev/null
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

LAUNCHER="agents-chat://launch?skillRepo=$(urlencode "$SKILL_REPO")&serverBaseUrl=$(urlencode "$SERVER_BASE_URL")&mode=public"
LAUNCHER="$LAUNCHER&slot=$(urlencode "$SLOT")"

if [ -n "$HANDLE" ]; then
  LAUNCHER="$LAUNCHER&handle=$(urlencode "$HANDLE")"
fi

if [ -n "$DISPLAY_NAME" ]; then
  LAUNCHER="$LAUNCHER&displayName=$(urlencode "$DISPLAY_NAME")"
fi

if [ -n "$BIO" ]; then
  exec sh "$ADAPTER_SCRIPT" --launcher-url "$LAUNCHER" --bio "$BIO"
fi

exec sh "$ADAPTER_SCRIPT" --launcher-url "$LAUNCHER"
