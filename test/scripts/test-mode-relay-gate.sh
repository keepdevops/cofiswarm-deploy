#!/usr/bin/env bash
# Sprint 20: dispatch → mode plugin relay (8021–8024, flat may fall back e.g. 8121).
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
PORTS_FILE="${FHS}/run/cofiswarm/mode-ports.env"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
HOST="${COFISWARM_MODE_HOST:-http://127.0.0.1}"
FLAT="${COFISWARM_MODE_FLAT_PORT:-8021}"
PIPE="${COFISWARM_MODE_PIPELINE_PORT:-8022}"
CASC="${COFISWARM_MODE_CASCADE_PORT:-8023}"
ROUT="${COFISWARM_MODE_ROUTER_PORT:-8024}"

curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null || {
  echo "fail: dispatch not reachable at ${DISPATCH} (run make up; wait for ready: dispatch)" >&2
  exit 1
}

for port in "$FLAT" "$PIPE" "$CASC" "$ROUT"; do
  curl -sf --max-time 5 "${HOST}:${port}/healthz" >/dev/null || {
    echo "fail: mode plugin :${port} not reachable (see ${FHS}/var/log/cofiswarm/host-services/mode-*.log)" >&2
    exit 1
  }
done

resp="$(curl -sf --max-time 30 -X POST "${DISPATCH}/api/architect" \
  -H 'Content-Type: application/json' \
  -d "{\"prompt\":\"relay gate\",\"mode\":\"flat\"}")"
echo "$resp" | python3 -c "
import json, sys
r = json.load(sys.stdin)
assert r.get('meta', {}).get('relay'), r
print('ok: dispatch relay flat meta.relay=true (flat port ${FLAT})')
"
