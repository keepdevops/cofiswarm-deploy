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
export RAG_DSN="${RAG_DSN:-postgresql://matrix:matrix@127.0.0.1:5433/matrix_rag}"

"${ROOT}/scripts/render-config.sh"

pg_reuse_ok() {
  if ! lsof -iTCP:5433 -sTCP:LISTEN >/dev/null 2>&1; then
    return 1
  fi
  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -h 127.0.0.1 -p 5433 -U matrix -d matrix_rag >/dev/null 2>&1 && return 0
  fi
  local c
  for c in matrix-pgvector cofiswarm-pgvector; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$c"; then
      docker exec "$c" pg_isready -U matrix -d matrix_rag >/dev/null 2>&1 && return 0
    fi
  done
  return 1
}

echo "==> docker compose profile ${PROFILE}"
export COFISWARM_FHS_ROOT="$FHS"
export COFISWARM_REPOS_ROOT="$REPOS"
docker rm -f cofiswarm-ui-stub 2>/dev/null || true
COMPOSE=(docker compose -f compose/stack.yml -f "compose/profiles/${PROFILE}.yml" --profile "$PROFILE")
if pg_reuse_ok; then
  echo "==> pgvector: reusing Postgres on :5433 (skip cofiswarm-pgvector)"
  docker rm -f cofiswarm-pgvector 2>/dev/null || true
  "${COMPOSE[@]}" up -d --scale pgvector=0
else
  "${COMPOSE[@]}" up -d
fi

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
  nohup "$bin" "$@" >>"${LOGDIR}/${name}.log" 2>&1 &
  local pid=$!
  disown -h "$pid" 2>/dev/null || true
  echo "$pid" > "${COFISWARM_RUN_ROOT}/${name}.pid"
  echo "started: $name pid=$pid"
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

start_svc dispatch "${REPOS}/cofiswarm-dispatch/bin/cofiswarm-dispatch" \
  -listen :8010 -state "${FHS}/var/lib/cofiswarm/dispatch"
start_svc agent-registry "${REPOS}/cofiswarm-agent-registry/bin/cofiswarm-agent-registry" \
  -swarm-config "${COFISWARM_SWARM_CONFIG}" -state "${FHS}/var/lib/cofiswarm/agent-registry/overrides.json"
start_svc slot-manager "${REPOS}/cofiswarm-slot-manager/bin/cofiswarm-slot-manager" \
  -config "${FHS}/etc/cofiswarm/slot-manager/endpoints.json"
start_svc kvpool "${REPOS}/cofiswarm-kvpool/bin/cofiswarm-kvpool"
start_svc observer "${REPOS}/cofiswarm-observer/bin/cofiswarm-observer" -listen :8016
start_svc zmq-bridge "${REPOS}/cofiswarm-zmq-bridge/bin/cofiswarm-zmq-bridge" \
  -topics "${REPOS}/cofiswarm-zmq-bridge/spec/topics.yaml"
for m in mode-flat:8021 mode-pipeline:8022 mode-cascade:8023 mode-router:8024; do
  role="${m%%:*}"
  start_svc "$role" "${REPOS}/cofiswarm-${role}/bin/cofiswarm-${role}" \
    -config "${FHS}/etc/cofiswarm/${role}/${role}.yaml"
done

start_py_svc rag env \
  COFISWARM_COORDINATOR_CONFIG="${COFISWARM_COORDINATOR_CONFIG}" \
  RAG_DSN="${RAG_DSN}" \
  RAG_INGEST_HOST=0.0.0.0 \
  PYTHONPATH="${REPOS}/cofiswarm-rag/src" \
  python3 "${REPOS}/cofiswarm-rag/scripts/ingest-server.py"
wait_port 8001 rag || true
start_py_svc orchestrate env \
  COFISWARM_CONFIG_ROOT="${FHS}/etc/cofiswarm/config" \
  COFISWARM_COORDINATOR_CONFIG="${COFISWARM_COORDINATOR_CONFIG}" \
  ORCH_SIDECAR_HOST=0.0.0.0 \
  ORCH_SIDECAR_PORT=3003 \
  PYTHONPATH="${REPOS}/cofiswarm-orchestrate/src" \
  python3 "${REPOS}/cofiswarm-orchestrate/scripts/run-sidecar.py"
wait_port 3003 orchestrate || true

echo "==> stack up complete (profile=${PROFILE})"
