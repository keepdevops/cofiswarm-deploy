#!/usr/bin/env bash
# Pipeline mode live SSE stream (stage + token events).
set -euo pipefail
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
PORTS_FILE="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/run/cofiswarm/mode-ports.env"
PORTS_FILE="${PORTS_FILE/#\~/$HOME}"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
PIPE="${COFISWARM_MODE_PIPELINE_PORT:-8022}"

curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null || {
  echo "fail: dispatch not reachable" >&2; exit 1;
}

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
curl -sS -N --max-time 180 -X POST "${DISPATCH}/api/architect/stream" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Pipeline stream: outline steps to add a health check endpoint.","mode":"pipeline","mode_config":{"agents":["architect","programmer"],"max_tokens":48}}' \
  >"$out" || true

grep -q 'event: stage' "$out" || { echo "fail: no stage events" >&2; head -20 "$out"; exit 1; }
grep -q 'event: token' "$out" || { echo "fail: no token events" >&2; exit 1; }
grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out" || { echo "fail: no done" >&2; exit 1; }
echo "ok: architect stream pipeline (mode-pipeline :${PIPE}) — stage + token + done"
