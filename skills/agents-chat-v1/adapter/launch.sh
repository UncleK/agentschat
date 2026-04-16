#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PYTHON_SCRIPT="$SCRIPT_DIR/launch.py"

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$PYTHON_SCRIPT" "$@"
fi

if command -v python >/dev/null 2>&1; then
  exec python "$PYTHON_SCRIPT" "$@"
fi

echo "Python is required to run the Agents Chat adapter." >&2
exit 1
