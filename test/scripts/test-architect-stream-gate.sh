#!/usr/bin/env bash
# Sprint 24: flat mode live SSE stream via dispatch → mode plugin.
set -euo pipefail
DISPATCH="${DISPATCH_URL:-http://127.0.0.1:8010}"
PORTS_FILE="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/run/cofiswarm/mode-ports.env"
PORTS_FILE="${PORTS_FILE/#\~/$HOME}"
[[ -f "$PORTS_FILE" ]] && set -a && source "$PORTS_FILE" && set +a
FLAT="${COFISWARM_MODE_FLAT_PORT:-8121}"

curl -sf --max-time 5 "${DISPATCH}/api/health" >/dev/null || {
  echo "fail: dispatch not reachable" >&2; exit 1;
}

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
curl -sS -N --max-time 120 -X POST "${DISPATCH}/api/architect/stream" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Stream gate: name one benefit of binary search trees.","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":64}}' \
  >"$out" || true

grep -q 'event: token' "$out" || { echo "fail: no token events in stream" >&2; head -20 "$out"; exit 1; }
grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out" || { echo "fail: no done event" >&2; exit 1; }
if grep -q 'event: error' "$out" && ! grep -q 'event: token' "$out"; then
  echo "fail: stream error without tokens" >&2; head -20 "$out"; exit 1
fi
echo "ok: architect stream flat (mode-flat :${FLAT}) — token + done events"
