#!/usr/bin/env bash
# Router mode live SSE stream (selected + token events).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/scripts/lib-ui-sse.sh
source "${ROOT}/lib-ui-sse.sh"
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
PORTS_FILE="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/run/cofiswarm/mode-ports.env"
PORTS_FILE="${PORTS_FILE/#\~/$HOME}"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
ROUT="${COFISWARM_MODE_ROUTER_PORT:-8024}"

curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null || {
  echo "fail: dispatch not reachable" >&2; exit 1;
}

ui_sse_expect "${DISPATCH}/api/architect/stream" 240 \
  'event: selected|event: token|event:done' \
  '{"prompt":"Router stream: fix a Python off-by-one in a for-loop over a list.","mode":"router","mode_config":{"max_tokens":64,"max_select":2}}' \
  "architect stream router (mode-router :${ROUT})"
