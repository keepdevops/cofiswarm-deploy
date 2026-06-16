#!/usr/bin/env bash
# UI API gateway gate — routes via :3000 nginx to host services.
set -euo pipefail
UI="${UI_URL:-http://127.0.0.1:3000}"

check() {
  local path="$1"
  curl -sf "${UI}${path}" >/dev/null
  echo "ok: ${path}"
}

check /api/health
check /api/swarm-config
check /api/models
check /api/modes
check /api/pressure
check /api/mlx/pressure
check /api/configure/status
check /rag/health

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
curl -sS -N --max-time 30 -X POST "${UI}/api/architect/stream" \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"UI gateway stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":8}}' \
  >"$out" || true
grep -q 'event: token' "$out" || grep -q '\[DONE\]' "$out" || {
  echo "fail: /api/architect/stream via UI gateway" >&2
  head -10 "$out" >&2
  exit 1
}
echo "ok: /api/architect/stream (via UI :3000)"

echo "ok: ui api gateway"
