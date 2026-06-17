#!/usr/bin/env bash
# Sprint 38: observer /metrics exports pressure series from slot-manager.
set -euo pipefail
HOST="${COFISWARM_SERVICE_HOST:-127.0.0.1}"
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
REPOS="${REPOS/#\~/$HOME}"
BIN="${REPOS}/cofiswarm-observer/bin/cofiswarm-observer"

[[ -x "$BIN" ]] || { echo "fail: build observer first (make build-observer)" >&2; exit 1; }

out="$(curl -sf --max-time 10 "http://${HOST}:8016/metrics")"
echo "$out" | grep -q 'cofiswarm_kv_pressure_usage' || {
  echo "fail: missing cofiswarm_kv_pressure_usage" >&2
  head -20 <<<"$out" >&2
  exit 1
}
echo "$out" | grep -q 'cofiswarm_endpoint_up' || {
  echo "fail: missing cofiswarm_endpoint_up" >&2
  exit 1
}
echo "$out" | grep -q 'TYPE cofiswarm_kv_pressure_usage gauge' || {
  echo "fail: missing TYPE line" >&2
  exit 1
}
n="$(echo "$out" | grep -c '^cofiswarm_kv_pressure_usage{' || true)"
[[ "$n" -ge 1 ]] || { echo "fail: no pressure samples" >&2; exit 1; }
echo "ok: prometheus metrics — ${n} endpoint(s) on :8016"
