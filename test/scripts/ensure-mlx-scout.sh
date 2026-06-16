#!/usr/bin/env bash
# Start mlx-scout on :8083 if not already healthy (SCALE-6/7).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
SWARM="${COFISWARM_SWARM_CONFIG:-${FHS}/etc/cofiswarm/config/swarm-config.json}"
PORT="${MLX_SCOUT_PORT:-8083}"
LOGDIR="${FHS}/var/log/cofiswarm/launcher"
RUN="${FHS}/run/cofiswarm"
PYTHON="${MATRIX_MLX_PYTHON:-python3}"

mlx_up() {
  curl -sf --max-time 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 \
    || curl -sf --max-time 3 "http://127.0.0.1:${PORT}/v1/models" >/dev/null 2>&1
}

if mlx_up; then
  echo "ok: mlx-scout already up :${PORT}"
  exit 0
fi

[[ "${SCALE7_START_MLX:-1}" == "1" ]] || {
  echo "fail: mlx-scout down on :${PORT} (set SCALE7_START_MLX=1 to auto-start)" >&2
  exit 1
}

[[ -f "$SWARM" ]] || { echo "fail: missing $SWARM" >&2; exit 1; }

MODEL="$(python3 - "$SWARM" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
scout = next(a for a in doc["agents"] if a["name"] == "mlx-scout")
print(scout["model"])
PY
)"

mkdir -p "$LOGDIR" "$RUN"
if [[ -f "${RUN}/mlx-scout.pid" ]] && kill -0 "$(cat "${RUN}/mlx-scout.pid")" 2>/dev/null; then
  echo "note: mlx-scout pid present but not healthy — waiting"
else
  echo "==> starting mlx_lm.server on :${PORT}"
  nohup "$PYTHON" -m mlx_lm.server --model "$MODEL" --port "$PORT" --host 127.0.0.1 \
    >>"${LOGDIR}/mlx-${PORT}.log" 2>&1 &
  echo $! > "${RUN}/mlx-scout.pid"
fi

for _ in $(seq 1 90); do
  if mlx_up; then
    echo "ok: mlx-scout ready :${PORT}"
    exit 0
  fi
  sleep 2
done
echo "fail: mlx-scout not healthy on :${PORT} (see ${LOGDIR}/mlx-${PORT}.log)" >&2
exit 1
