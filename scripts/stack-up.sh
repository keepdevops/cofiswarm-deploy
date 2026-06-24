#!/usr/bin/env bash
# Start compose profile + host control-plane binaries (FHS paths).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && set -a && source .env && set +a
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
MONO="${MONOREPO:-$HOME/cofiswarmdev}"
MONO="${MONO/#\~/$HOME}"
PROFILE="${COFISWARM_PROFILE:-16gb}"
export COFISWARM_FHS_ROOT="$FHS"
export COFISWARM_REPOS_ROOT="$REPOS"
export COFISWARM_VAR_LIB="${FHS}/var/lib"
export COFISWARM_ETC="${FHS}/etc"
export COFISWARM_VAR_LOG="${FHS}/var/log/cofiswarm"
export COFISWARM_RUN_ROOT="${FHS}/run/cofiswarm"
export COFISWARM_SWARM_CONFIG="${FHS}/etc/cofiswarm/config/swarm-config.json"
export COFISWARM_COORDINATOR_CONFIG="${FHS}/etc/cofiswarm/config/coordinator.json"
export COFISWARM_MODELS_MANIFEST="${REPOS}/cofiswarm-models/catalog/manifest.json"
export COFISWARM_RAG_URL="http://127.0.0.1:8001"
export COFISWARM_SLOT_MANAGER_URL="http://127.0.0.1:8013"
# RAG is serverless (sqlite-vec) — a file under FHS, no Postgres container.
export RAG_STORE="${RAG_STORE:-sqlite}"
export RAG_SQLITE_PATH="${RAG_SQLITE_PATH:-${FHS}/var/lib/cofiswarm/rag/index/rag.db}"
export MATRIX_LLAMA_SERVER="${MATRIX_LLAMA_SERVER:-}"

"${ROOT}/scripts/render-config.sh"

echo "==> docker compose profile ${PROFILE}"
export COFISWARM_FHS_ROOT="$FHS"
export COFISWARM_REPOS_ROOT="$REPOS"
docker rm -f cofiswarm-ui-stub 2>/dev/null || true
COMPOSE=(docker compose -f compose/stack.yml -f "compose/profiles/${PROFILE}.yml" --profile "$PROFILE")
"${COMPOSE[@]}" up -d

LOGDIR="${FHS}/var/log/cofiswarm/host-services"
mkdir -p "$LOGDIR" "${COFISWARM_RUN_ROOT}"

wait_port() {
  local port="$1" name="$2" tries="${3:-40}"
  for _ in $(seq 1 "$tries"); do
    if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "ready: $name :$port"
      return 0
    fi
    sleep 0.25
  done
  echo "warn: $name :$port not listening (check ${LOGDIR}/${name}.log)" >&2
  return 1
}

port_bindable() {
  local port="$1"
  python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
try:
    s.bind(("::", port))
    s.close()
    sys.exit(0)
except OSError:
    sys.exit(1)
PY
}

pick_mode_port() {
  local default="$1"
  shift
  local p
  for p in "$default" "$@"; do
    if port_bindable "$p"; then
      echo "$p"
      return 0
    fi
  done
  echo "$default"
}

MODE_PORTS_FILE="${COFISWARM_RUN_ROOT}/mode-ports.env"
pick_and_export_mode_ports() {
  local flat pipeline cascade router new
  flat="$(pick_mode_port 8021 8121 8221)"
  pipeline="$(pick_mode_port 8022)"
  cascade="$(pick_mode_port 8023)"
  router="$(pick_mode_port 8024)"
  if [[ "$flat" != "8021" ]]; then
    echo "warn: :8021 in use (macOS launchd?) — mode-flat on :${flat}" >&2
  fi
  new=$(printf 'COFISWARM_MODE_FLAT_PORT=%s\nCOFISWARM_MODE_PIPELINE_PORT=%s\nCOFISWARM_MODE_CASCADE_PORT=%s\nCOFISWARM_MODE_ROUTER_PORT=%s\n' \
    "$flat" "$pipeline" "$cascade" "$router")
  if [[ ! -f "$MODE_PORTS_FILE" ]] || [[ "$(cat "$MODE_PORTS_FILE")" != "$new" ]]; then
    printf '%s' "$new" >"$MODE_PORTS_FILE"
  fi
  set -a
  # shellcheck source=/dev/null
  source "$MODE_PORTS_FILE"
  set +a
  export COFISWARM_MODE_FLAT_PORT COFISWARM_MODE_PIPELINE_PORT \
    COFISWARM_MODE_CASCADE_PORT COFISWARM_MODE_ROUTER_PORT
}

restart_if_stale() {
  local name="$1" marker="$2"
  local pidfile="${COFISWARM_RUN_ROOT}/${name}.pid"
  [[ -f "$pidfile" && -f "$marker" && "$marker" -nt "$pidfile" ]] || return 0
  kill "$(cat "$pidfile")" 2>/dev/null || true
  rm -f "$pidfile"
  echo "restarted: $name (stale after ${marker##*/})"
}

start_svc() {
  local name="$1" bin="$2"
  shift 2
  [[ -x "$bin" ]] || { echo "skip: $name (no binary $bin)"; return 0; }
  if [[ -f "${COFISWARM_RUN_ROOT}/${name}.pid" ]] && kill -0 "$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")" 2>/dev/null; then
    if [[ "$bin" -nt "${COFISWARM_RUN_ROOT}/${name}.pid" ]]; then
      kill "$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")" 2>/dev/null || true
      rm -f "${COFISWARM_RUN_ROOT}/${name}.pid"
    else
      echo "running: $name"
      return 0
    fi
  fi
  local -a run_env=()
  if [[ "$name" == mode-* ]]; then
    run_env=(env "COFISWARM_SWARM_CONFIG=${COFISWARM_SWARM_CONFIG:-}")
  fi
  if ((${#run_env[@]} > 0)); then
    nohup "${run_env[@]}" "$bin" "$@" >>"${LOGDIR}/${name}.log" 2>&1 &
  else
    nohup "$bin" "$@" >>"${LOGDIR}/${name}.log" 2>&1 &
  fi
  local pid=$!
  disown -h "$pid" 2>/dev/null || true
  echo "$pid" > "${COFISWARM_RUN_ROOT}/${name}.pid"
  echo "started: $name pid=$pid"
  sleep 0.15
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "warn: $name exited immediately (see ${LOGDIR}/${name}.log)" >&2
    rm -f "${COFISWARM_RUN_ROOT}/${name}.pid"
  fi
}

start_py_svc() {
  local name="$1"
  shift
  [[ $# -gt 0 ]] || { echo "skip: $name (no command)"; return 0; }
  if [[ -f "${COFISWARM_RUN_ROOT}/${name}.pid" ]] && kill -0 "$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")" 2>/dev/null; then
    echo "running: $name"
    return 0
  fi
  nohup "$@" >>"${LOGDIR}/${name}.log" 2>&1 &
  local pid=$!
  disown -h "$pid" 2>/dev/null || true
  echo "$pid" > "${COFISWARM_RUN_ROOT}/${name}.pid"
  echo "started: $name pid=$pid"
}

pick_and_export_mode_ports
restart_if_stale dispatch "$MODE_PORTS_FILE"

start_dispatch() {
  local name=dispatch bin="${REPOS}/cofiswarm-dispatch/bin/cofiswarm-dispatch"
  [[ -x "$bin" ]] || { echo "skip: $name (no binary $bin)"; return 0; }
  if [[ -f "${COFISWARM_RUN_ROOT}/${name}.pid" ]] && kill -0 "$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")" 2>/dev/null; then
    if [[ "$bin" -nt "${COFISWARM_RUN_ROOT}/${name}.pid" ]]; then
      kill "$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")" 2>/dev/null || true
      rm -f "${COFISWARM_RUN_ROOT}/${name}.pid"
    else
      echo "running: $name"
      return 0
    fi
  fi
  nohup env \
    COFISWARM_MODE_FLAT_PORT="${COFISWARM_MODE_FLAT_PORT}" \
    COFISWARM_MODE_PIPELINE_PORT="${COFISWARM_MODE_PIPELINE_PORT}" \
    COFISWARM_MODE_CASCADE_PORT="${COFISWARM_MODE_CASCADE_PORT}" \
    COFISWARM_MODE_ROUTER_PORT="${COFISWARM_MODE_ROUTER_PORT}" \
    "$bin" -listen :8010 -state "${FHS}/var/lib/cofiswarm/dispatch" \
    >>"${LOGDIR}/${name}.log" 2>&1 &
  local pid=$!
  disown -h "$pid" 2>/dev/null || true
  echo "$pid" > "${COFISWARM_RUN_ROOT}/${name}.pid"
  echo "started: $name pid=$pid"
  sleep 0.15
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "warn: $name exited immediately (see ${LOGDIR}/${name}.log)" >&2
    rm -f "${COFISWARM_RUN_ROOT}/${name}.pid"
  fi
}
start_dispatch
wait_port 8010 dispatch || true
start_svc agent-registry "${REPOS}/cofiswarm-agent-registry/bin/cofiswarm-agent-registry" \
  -swarm-config "${COFISWARM_SWARM_CONFIG}" -state "${FHS}/var/lib/cofiswarm/agent-registry/overrides.json"
start_svc slot-manager "${REPOS}/cofiswarm-slot-manager/bin/cofiswarm-slot-manager" \
  -config "${FHS}/etc/cofiswarm/slot-manager/endpoints.json"
start_svc kvpool "${REPOS}/cofiswarm-kvpool/bin/cofiswarm-kvpool"
start_svc configure "${REPOS}/cofiswarm-launcher/bin/cofiswarm-configure" -listen :8017
wait_port 8017 configure || true
start_svc observer "${REPOS}/cofiswarm-observer/bin/cofiswarm-observer" -listen :8016
start_svc convert "${REPOS}/cofiswarm-convert/bin/cofiswarm-convert" -listen :8015
wait_port 8015 convert || true
start_svc zmq-bridge "${REPOS}/cofiswarm-zmq-bridge/bin/cofiswarm-zmq-bridge" \
  -topics "${REPOS}/cofiswarm-zmq-bridge/spec/topics.yaml"
for spec in \
  "mode-flat:${COFISWARM_MODE_FLAT_PORT}" \
  "mode-pipeline:${COFISWARM_MODE_PIPELINE_PORT}" \
  "mode-cascade:${COFISWARM_MODE_CASCADE_PORT}" \
  "mode-router:${COFISWARM_MODE_ROUTER_PORT}"; do
  role="${spec%%:*}"
  port="${spec##*:}"
  restart_if_stale "$role" "$MODE_PORTS_FILE"
  start_svc "$role" "${REPOS}/cofiswarm-${role}/bin/cofiswarm-${role}" \
    -config "${FHS}/etc/cofiswarm/${role}/${role}.yaml" -listen ":${port}"
  wait_port "$port" "$role" || true
done

start_py_svc rag env \
  COFISWARM_COORDINATOR_CONFIG="${COFISWARM_COORDINATOR_CONFIG}" \
  RAG_STORE="${RAG_STORE}" \
  RAG_SQLITE_PATH="${RAG_SQLITE_PATH}" \
  RAG_INGEST_HOST=0.0.0.0 \
  PYTHONPATH="${REPOS}/cofiswarm-rag/src" \
  python3 "${REPOS}/cofiswarm-rag/scripts/ingest-server.py"
wait_port 8001 rag || true
start_py_svc rag-worker env \
  COFISWARM_VAR_LIB="${FHS}/var/lib/cofiswarm" \
  RAG_WORKER_PORT=8018 \
  PYTHONPATH="${REPOS}/cofiswarm-rag-worker/src" \
  python3 "${REPOS}/cofiswarm-rag-worker/scripts/run-worker.py"
wait_port 8018 rag-worker || true
start_py_svc orchestrate env \
  COFISWARM_CONFIG_ROOT="${FHS}/etc/cofiswarm/config" \
  COFISWARM_COORDINATOR_CONFIG="${COFISWARM_COORDINATOR_CONFIG}" \
  ORCH_SIDECAR_HOST=0.0.0.0 \
  ORCH_SIDECAR_PORT=3003 \
  PYTHONPATH="${REPOS}/cofiswarm-orchestrate/src" \
  python3 "${REPOS}/cofiswarm-orchestrate/scripts/run-sidecar.py"
wait_port 3003 orchestrate || true

echo "==> stack up complete (profile=${PROFILE})"
