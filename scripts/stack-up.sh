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
PROFILE="${COFISWARM_PROFILE:-16gb}"
export COFISWARM_FHS_ROOT="$FHS"
export COFISWARM_VAR_LIB="${FHS}/var/lib"
export COFISWARM_ETC="${FHS}/etc"
export COFISWARM_VAR_LOG="${FHS}/var/log"
export COFISWARM_RUN_ROOT="${FHS}/run/cofiswarm"
export COFISWARM_SWARM_CONFIG="${FHS}/etc/cofiswarm/config/swarm-config.json"
export COFISWARM_COORDINATOR_CONFIG="${FHS}/etc/cofiswarm/config/coordinator.json"
export RAG_DSN="${RAG_DSN:-postgresql://matrix:matrix@127.0.0.1:5433/matrix_rag}"

"${ROOT}/scripts/render-config.sh"

echo "==> docker compose profile ${PROFILE}"
export COFISWARM_FHS_ROOT="$FHS"
docker compose -f compose/stack.yml -f "compose/profiles/${PROFILE}.yml" --profile "$PROFILE" up -d

LOGDIR="${FHS}/var/log/cofiswarm/host-services"
mkdir -p "$LOGDIR" "${COFISWARM_RUN_ROOT}"

start_svc() {
  local name="$1" bin="$2" args="${3:-}"
  [[ -x "$bin" ]] || { echo "skip: $name (no binary $bin)"; return 0; }
  if [[ -f "${COFISWARM_RUN_ROOT}/${name}.pid" ]] && kill -0 "$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")" 2>/dev/null; then
    echo "running: $name"
    return 0
  fi
  nohup "$bin" $args >>"${LOGDIR}/${name}.log" 2>&1 &
  echo $! > "${COFISWARM_RUN_ROOT}/${name}.pid"
  echo "started: $name pid=$(cat "${COFISWARM_RUN_ROOT}/${name}.pid")"
}

start_svc dispatch    "${REPOS}/cofiswarm-dispatch/bin/cofiswarm-dispatch" \
  "-listen :8010 -state ${FHS}/var/lib/cofiswarm/dispatch"
start_svc agent-registry "${REPOS}/cofiswarm-agent-registry/bin/cofiswarm-agent-registry" \
  "-swarm-config ${COFISWARM_SWARM_CONFIG} -state ${FHS}/var/lib/cofiswarm/agent-registry/overrides.json"
start_svc slot-manager "${REPOS}/cofiswarm-slot-manager/bin/cofiswarm-slot-manager" \
  "-config ${FHS}/etc/cofiswarm/slot-manager/endpoints.json"
start_svc kvpool      "${REPOS}/cofiswarm-kvpool/bin/cofiswarm-kvpool"
start_svc zmq-bridge  "${REPOS}/cofiswarm-zmq-bridge/bin/cofiswarm-zmq-bridge" \
  "-topics ${REPOS}/cofiswarm-zmq-bridge/spec/topics.yaml"
for m in mode-flat:8021 mode-pipeline:8022 mode-cascade:8023 mode-router:8024; do
  role="${m%%:*}"; port="${m##*:}"
  start_svc "$role" "${REPOS}/cofiswarm-${role}/bin/cofiswarm-${role}" \
    "-config ${FHS}/etc/cofiswarm/${role}/${role}.yaml"
done

echo "==> stack up complete (profile=${PROFILE})"
