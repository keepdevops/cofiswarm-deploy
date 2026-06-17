#!/usr/bin/env bash
# Shared UI SSE curl helpers (curl 18/28 common on closed streams).
# Expect patterns are pipe-separated: 'event: selected|event: token|event:done'

ui_sse_each_pattern() {
  local expect="$1" callback="$2"
  local IFS='|'
  local pat
  for pat in $expect; do
    [[ -n "$pat" ]] || continue
    "$callback" "$pat" || return 1
  done
  return 0
}

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

ui_sse_gateway_error() {
  local out="$1"
  grep -qiE '502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out' "$out" && return 0
  grep -qi '<title>502 Bad Gateway</title>' "$out" && return 0
  return 1
}

ui_sse_wait_stack() {
  local ui="${UI_URL:-http://127.0.0.1:3000}"
  local host="${COFISWARM_SERVICE_HOST:-127.0.0.1}"
  local wait="${UI_SSE_WAIT_STACK_SECS:-45}"
  local ports_file="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}/run/cofiswarm/mode-ports.env"
  ports_file="${ports_file/#\~/$HOME}"
  local router_port=8024
  if [[ -f "$ports_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ports_file"
    set +a
  fi
  router_port="${COFISWARM_MODE_ROUTER_PORT:-8024}"
  local deadline=$((SECONDS + wait))
  while (( SECONDS < deadline )); do
    if curl -sf --max-time 3 "${ui}/api/health" >/dev/null \
      && curl -sf --max-time 3 "http://${host}:8010/api/health" >/dev/null \
      && curl -sf --max-time 3 "http://${host}:${router_port}/healthz" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

ui_sse_breathe() {
  sleep "${UI_SSE_STREAM_GAP:-2}"
  ui_sse_wait_stack || true
}

ui_sse_has_patterns() {
  local out="$1" expect="$2"
  ui_sse_has_patterns_out="$out"
  ui_sse_each_pattern "$expect" ui_sse_match_pattern
}

ui_sse_match_pattern() {
  local pat="$1" out="${ui_sse_has_patterns_out:?}"
  if [[ "$pat" == 'event:done' ]]; then
    grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out"
    return $?
  fi
  grep -qF "$pat" "$out"
}

ui_sse_first_missing() {
  local out="$1" expect="$2" pat
  ui_sse_has_patterns_out="$out"
  local IFS='|'
  for pat in $expect; do
    [[ -n "$pat" ]] || continue
    if [[ "$pat" == 'event:done' ]]; then
      grep -q 'event: done' "$out" || grep -q '\[DONE\]' "$out" || { echo "$pat"; return 0; }
      continue
    fi
    grep -qF "$pat" "$out" || { echo "$pat"; return 0; }
  done
  return 1
}

ui_sse_diagnose() {
  local out="$1" expect="$2"
  if ui_sse_gateway_error "$out"; then
    echo "nginx 502 (dispatch unreachable — retry after stack settles)"
    return 0
  fi
  local missing
  missing="$(ui_sse_first_missing "$out" "$expect" || true)"
  echo "missing ${missing:-SSE events}"
}

# POST SSE smoke (token or done) with retries — for test-ui-api-gate.sh.
ui_sse_smoke() {
  local url="$1" payload="$2" label="${3:-stream smoke}"
  local max="${UI_SSE_RETRIES:-5}" attempt out reason
  ui_sse_wait_stack || true
  for attempt in $(seq 1 "$max"); do
    out="$(mktemp)"
    ui_sse_post "$url" "$out" "${UI_SSE_SMOKE_TIMEOUT:-90}" "$payload" || true
    if ui_sse_ok "$out"; then
      rm -f "$out"
      return 0
    fi
    reason="$(ui_sse_diagnose "$out" 'event: token|event:done')"
    if [[ "$attempt" -lt "$max" ]]; then
      echo "warn: ${label} — ${reason}, retry (${attempt}/${max})" >&2
      if ui_sse_gateway_error "$out"; then
        ui_sse_wait_stack || true
      else
        sleep "${UI_SSE_RETRY_SLEEP:-3}"
      fi
    else
      echo "fail: ${label} — ${reason}" >&2
      head -20 "$out" >&2
    fi
    rm -f "$out"
  done
  return 1
}

# POST SSE and assert event patterns; retries on curl 18 truncation or nginx 502.
ui_sse_expect() {
  local url="$1" timeout="$2" expect="$3" payload="$4" label="${5:-stream}"
  local max="${6:-${UI_SSE_RETRIES:-3}}" attempt out reason
  for attempt in $(seq 1 "$max"); do
    out="$(mktemp)"
    ui_sse_post "$url" "$out" "$timeout" "$payload" || true
    if ui_sse_has_patterns "$out" "$expect"; then
      rm -f "$out"
      echo "ok: ${label}"
      return 0
    fi
    reason="$(ui_sse_diagnose "$out" "$expect")"
    if [[ "$attempt" -lt "$max" ]]; then
      echo "warn: ${label} — ${reason}, retry (${attempt}/${max})" >&2
      if ui_sse_gateway_error "$out"; then
        ui_sse_wait_stack || true
      else
        sleep "${UI_SSE_RETRY_SLEEP:-3}"
      fi
    else
      echo "fail: ${label} — ${reason}" >&2
      head -20 "$out" >&2
    fi
    rm -f "$out"
  done
  return 1
}
