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

ui_sse_breathe

payload='{"prompt":"UI gateway stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":24}}'
ui_sse_smoke "${UI}/api/architect/stream" "$payload" "/api/architect/stream (via UI :3000)"
echo "ok: /api/architect/stream (via UI :3000)"
echo "ok: ui api gateway"
