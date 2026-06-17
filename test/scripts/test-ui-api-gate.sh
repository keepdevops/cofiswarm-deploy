#!/usr/bin/env bash
# UI API gateway gate — routes via :3000 nginx to host services.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/scripts/lib-ui-sse.sh
source "${ROOT}/lib-ui-sse.sh"
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
payload='{"prompt":"UI gateway stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":24}}'
for attempt in 1 2; do
  ui_sse_post "${UI}/api/architect/stream" "$out" 90 "$payload" || true
  if ui_sse_ok "$out"; then
    echo "ok: /api/architect/stream (via UI :3000)"
    echo "ok: ui api gateway"
    exit 0
  fi
  [[ "$attempt" -eq 2 ]] && break
  echo "warn: stream smoke retry (${attempt}/2)" >&2
  sleep 2
done
echo "fail: /api/architect/stream via UI gateway" >&2
head -20 "$out" >&2
exit 1
