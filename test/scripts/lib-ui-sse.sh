#!/usr/bin/env bash
# Shared UI SSE curl helpers (curl 18/28 common on closed streams).
ui_sse_post() {
  local url="$1" out="$2" timeout="$3" payload="$4"
  local rc=0
  curl -sS -N --max-time "$timeout" -X POST "$url" \
    -H 'Content-Type: application/json' \
    -d "$payload" >"$out" || rc=$?
  case "$rc" in
    0|18|28) return 0 ;;
    *) echo "warn: curl exit ${rc} for ${url}" >&2; return "$rc" ;;
  esac
}

ui_sse_ok() {
  local out="$1"
  if grep -q 'event: error' "$out" && ! grep -q 'event: token' "$out"; then
    return 1
  fi
  grep -q 'event: token' "$out" || grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out"
}
