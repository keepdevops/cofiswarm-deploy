#!/usr/bin/env bash
# Sprint 35: control-plane health — all host services from well-known ports.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
PORTS_FILE="${FHS}/run/cofiswarm/mode-ports.env"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
HOST="${COFISWARM_SERVICE_HOST:-127.0.0.1}"
UI="${UI_URL:-http://${HOST}:3000}"

probe() {
  local label="$1" url="$2"
  case "$url" in
    http://*|https://*) ;;
    *) url="http://${url}" ;;
  esac
  curl -sf --max-time 5 "$url" >/dev/null || {
    echo "fail: ${label} (${url})" >&2
    exit 1
  }
  echo "ok: ${label}"
}

probe dispatch "${HOST}:8010/api/health"
probe agent-registry "${HOST}:8012/healthz"
probe slot-manager "${HOST}:8013/healthz"
probe kvpool "${HOST}:8014/healthz"
probe observer "${HOST}:8016/healthz"
probe configure "${HOST}:8017/healthz"
probe zmq-bridge "${HOST}:5555/healthz"
probe rag "${HOST}:8001/health"
probe convert "${HOST}:8015/healthz"
probe rag-worker "${HOST}:8018/healthz"

for spec in \
  "mode-flat:${COFISWARM_MODE_FLAT_PORT:-8021}" \
  "mode-pipeline:${COFISWARM_MODE_PIPELINE_PORT:-8022}" \
  "mode-cascade:${COFISWARM_MODE_CASCADE_PORT:-8023}" \
  "mode-router:${COFISWARM_MODE_ROUTER_PORT:-8024}"; do
  name="${spec%%:*}"
  port="${spec##*:}"
  probe "$name" "${HOST}:${port}/healthz"
done

if lsof -iTCP:3003 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "ok: orchestrate :3003"
else
  echo "fail: orchestrate :3003 not listening" >&2
  exit 1
fi

probe ui-gateway "${UI}/api/health"

# RAG store health is covered by the rag /health probe above (sqlite-vec,
# no Postgres container to check).

echo "ok: stack health"
