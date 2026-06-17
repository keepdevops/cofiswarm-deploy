#!/usr/bin/env bash
# Sprint 39: full observability sign-off — host metrics + optional Prometheus/Grafana.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

"${ROOT}/test/scripts/test-observer-ops-gate.sh"
"${ROOT}/test/scripts/test-grafana-layout-gate.sh"
"${ROOT}/test/scripts/test-prometheus-metrics-gate.sh"
"${ROOT}/test/scripts/test-zmq-bridge-gate.sh"

PROM="${PROMETHEUS_URL:-http://127.0.0.1:9090}"
if ! curl -sf --max-time 3 "${PROM}/-/healthy" >/dev/null 2>&1; then
  echo "==> starting optional observability stack"
  (cd "$ROOT" && make observability-up)
  for _ in $(seq 1 30); do
    curl -sf --max-time 2 "${PROM}/-/healthy" >/dev/null 2>&1 && break
    sleep 2
  done
fi
"${ROOT}/test/scripts/test-prometheus-up-gate.sh"
echo "ok: observability signoff"
