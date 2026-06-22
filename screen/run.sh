#!/usr/bin/env bash
# Launch the Cofiswarm Observer. Creates a venv on first run, installs pyzmq
# (optional — server runs without it), then starts the SSE server.
set -euo pipefail
cd "$(dirname "$0")"

VENV=".venv"
if [ ! -d "$VENV" ]; then
  echo "[observer] creating venv…"
  python3 -m venv "$VENV"
  # shellcheck disable=SC1091
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet -r requirements.txt || \
    echo "[observer] WARN: pyzmq install failed; ZMQ signals will be 'unavailable'"
fi

export OBSERVER_HOST="${OBSERVER_HOST:-127.0.0.1}"
export OBSERVER_PORT="${OBSERVER_PORT:-8800}"

echo "[observer] starting on http://${OBSERVER_HOST}:${OBSERVER_PORT}"
exec "$VENV/bin/python" -m observer.server
