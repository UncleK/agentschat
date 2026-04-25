#!/usr/bin/env bash
set -euo pipefail

APP_USER="agentschat"
APP_ROOT="/opt/agents-chat"
SHARED_DIR="$APP_ROOT/shared"
VENV_DIR="$SHARED_DIR/stt-venv"
MODEL_DIR="$SHARED_DIR/models/faster-whisper"
MODEL_SIZE="small"
PYTHON_BIN="python3"

usage() {
  cat <<'EOF'
Usage:
  install-stt-runtime.sh [--python-bin PATH] [--venv-dir PATH] [--model-dir PATH] [--model-size NAME]

Options:
  --python-bin PATH   Python executable used to create the venv. Default: python3
  --venv-dir PATH     Virtualenv directory. Default: /opt/agents-chat/shared/stt-venv
  --model-dir PATH    Model cache directory. Default: /opt/agents-chat/shared/models/faster-whisper
  --model-size NAME   faster-whisper model name or path. Default: small
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python-bin)
      PYTHON_BIN="$2"
      shift 2
      ;;
    --venv-dir)
      VENV_DIR="$2"
      shift 2
      ;;
    --model-dir)
      MODEL_DIR="$2"
      shift 2
      ;;
    --model-size)
      MODEL_SIZE="$2"
      shift 2
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

if ! id "$APP_USER" >/dev/null 2>&1; then
  echo "App user '$APP_USER' does not exist yet. Run bootstrap-server.sh first." >&2
  exit 1
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python executable '$PYTHON_BIN' was not found." >&2
  exit 1
fi

install -d -o "$APP_USER" -g "$APP_USER" "$SHARED_DIR"
install -d -o "$APP_USER" -g "$APP_USER" "$(dirname "$MODEL_DIR")"
install -d -o "$APP_USER" -g "$APP_USER" "$MODEL_DIR"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  install -d -o "$APP_USER" -g "$APP_USER" "$(dirname "$VENV_DIR")"
  sudo -u "$APP_USER" "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

sudo -u "$APP_USER" "$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
sudo -u "$APP_USER" "$VENV_DIR/bin/python" -m pip install --upgrade faster-whisper

sudo -u "$APP_USER" "$VENV_DIR/bin/python" - <<PY
from faster_whisper import WhisperModel

WhisperModel(
    "${MODEL_SIZE}",
    device="cpu",
    compute_type="int8",
    download_root="${MODEL_DIR}",
)
print("faster-whisper runtime ready")
PY

echo "STT runtime installed."
echo "Python: $VENV_DIR/bin/python"
echo "Model cache: $MODEL_DIR"
echo "Model: $MODEL_SIZE"
