#!/usr/bin/env bash
# Cascade mode live SSE stream (synthesis_start + token events).
set -euo pipefail
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
PORTS_FILE="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/run/cofiswarm/mode-ports.env"
PORTS_FILE="${PORTS_FILE/#\~/$HOME}"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
CASC="${COFISWARM_MODE_CASCADE_PORT:-8023}"

curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null || {
  echo "fail: dispatch not reachable" >&2; exit 1;
}

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
curl -sS -N --max-time 300 -X POST "${DISPATCH}/api/architect/stream" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Cascade stream: design a minimal REST API for todos.","mode":"cascade","mode_config":{"agents":["architect","programmer"],"max_tokens":48}}' \
  >"$out" || true

grep -q 'event: synthesis_start' "$out" || { echo "fail: no synthesis_start" >&2; head -25 "$out"; exit 1; }
grep -q 'event: token' "$out" || { echo "fail: no token events" >&2; exit 1; }
grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out" || { echo "fail: no done" >&2; exit 1; }
echo "ok: architect stream cascade (mode-cascade :${CASC}) — synthesis_start + token + done"
