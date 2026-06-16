#!/usr/bin/env bash
# Router mode live SSE stream (selected + token events).
set -euo pipefail
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
PORTS_FILE="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/run/cofiswarm/mode-ports.env"
PORTS_FILE="${PORTS_FILE/#\~/$HOME}"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
ROUT="${COFISWARM_MODE_ROUTER_PORT:-8024}"

curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null || {
  echo "fail: dispatch not reachable" >&2; exit 1;
}

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
curl -sS -N --max-time 180 -X POST "${DISPATCH}/api/architect/stream" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Router stream: fix a Python off-by-one in a for-loop over a list.","mode":"router","mode_config":{"max_tokens":64,"max_select":2}}' \
  >"$out" || true

grep -q 'event: selected' "$out" || { echo "fail: no selected event" >&2; head -25 "$out"; exit 1; }
grep -q 'event: token' "$out" || { echo "fail: no token events" >&2; exit 1; }
grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out" || { echo "fail: no done" >&2; exit 1; }
echo "ok: architect stream router (mode-router :${ROUT}) — selected + token + done"
