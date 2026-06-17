#!/usr/bin/env bash
# Sprint 33: architect SSE streams via UI nginx :3000 (all four modes + mlx compat).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/scripts/lib-ui-sse.sh
source "${ROOT}/lib-ui-sse.sh"
UI="${UI_URL:-http://127.0.0.1:3000}"
STREAM="${UI}/api/architect/stream"

curl -sf "${UI}/api/health" >/dev/null || {
  echo "fail: UI gateway not reachable at ${UI}" >&2
  exit 1
}

ui_sse_expect "$STREAM" 120 'event: token|event:done' \
  '{"prompt":"UI flat stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":32}}' \
  flat

ui_sse_breathe

ui_sse_expect "$STREAM" 180 'event: stage|event: token|event:done' \
  '{"prompt":"UI pipeline stream smoke","mode":"pipeline","mode_config":{"agents":["architect","programmer"],"max_tokens":32}}' \
  pipeline

ui_sse_breathe

ui_sse_expect "$STREAM" 240 'event: selected|event: token|event:done' \
  '{"prompt":"UI router stream smoke","mode":"router","mode_config":{"max_tokens":32,"max_select":2}}' \
  router 5

ui_sse_breathe

ui_sse_expect "$STREAM" 300 'event: synthesis_start|event: token|event:done' \
  '{"prompt":"UI cascade stream smoke","mode":"cascade","mode_config":{"agents":["architect","programmer"],"max_tokens":32}}' \
  cascade 5

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
max="${UI_SSE_RETRIES:-3}"
for attempt in $(seq 1 "$max"); do
  ui_sse_post "${UI}/api/mlx/stream" "$out" 120 \
    '{"prompt":"UI mlx stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":16}}' || true
  if ui_sse_ok "$out"; then
    echo "ok: mlx/stream (via UI :3000)"
    echo "ok: ui stream gateway — flat, pipeline, router, cascade, mlx"
    exit 0
  fi
  [[ "$attempt" -lt "$max" ]] && echo "warn: mlx/stream — retry (${attempt}/${max})" >&2 && ui_sse_breathe
done
echo "fail: /api/mlx/stream via UI" >&2
head -10 "$out" >&2
exit 1
