#!/usr/bin/env bash
# Sprint 33: architect SSE streams via UI nginx :3000 (all four modes + mlx compat).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/scripts/lib-ui-sse.sh
source "${ROOT}/lib-ui-sse.sh"
UI="${UI_URL:-http://127.0.0.1:3000}"

curl -sf "${UI}/api/health" >/dev/null || {
  echo "fail: UI gateway not reachable at ${UI}" >&2
  exit 1
}

stream_case() {
  local label="$1" timeout="$2" expect="$3" payload="$4"
  local out
  out="$(mktemp)"
  trap 'rm -f "$out"' RETURN
  ui_sse_post "${UI}/api/architect/stream" "$out" "$timeout" "$payload" || true
  local pat
  for pat in $expect; do
    if [[ "$pat" == 'event:done' ]]; then
      grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out" || {
        echo "fail: ${label} — missing done" >&2
        head -15 "$out" >&2
        return 1
      }
      continue
    fi
    grep -q "$pat" "$out" || {
      echo "fail: ${label} — missing ${pat}" >&2
      head -15 "$out" >&2
      return 1
    }
  done
  echo "ok: ${label}"
}

stream_case flat 120 'event: token event:done' \
  '{"prompt":"UI flat stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":32}}'

stream_case pipeline 180 'event: stage event: token event:done' \
  '{"prompt":"UI pipeline stream smoke","mode":"pipeline","mode_config":{"agents":["architect","programmer"],"max_tokens":32}}'

stream_case router 180 'event: selected event: token event:done' \
  '{"prompt":"UI router stream smoke","mode":"router","mode_config":{"max_tokens":32,"max_select":2}}'

stream_case cascade 300 'event: synthesis_start event: token event:done' \
  '{"prompt":"UI cascade stream smoke","mode":"cascade","mode_config":{"agents":["architect","programmer"],"max_tokens":32}}'

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
ui_sse_post "${UI}/api/mlx/stream" "$out" 120 \
  '{"prompt":"UI mlx stream smoke","mode":"flat","mode_config":{"agents":["architect"],"max_tokens":16}}' || true
if ! ui_sse_ok "$out"; then
  echo "fail: /api/mlx/stream via UI" >&2
  head -10 "$out" >&2
  exit 1
fi
echo "ok: mlx/stream (via UI :3000)"

echo "ok: ui stream gateway — flat, pipeline, router, cascade, mlx"
