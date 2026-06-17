#!/usr/bin/env bash
# Sprint 37: observer plugins + metrics on :8016.
set -euo pipefail
FHS="${COFISWARM_FHS_ROOT:-$HOME/cofiswarm/fhs}"
FHS="${FHS/#\~/$HOME}"
HOST="${COFISWARM_SERVICE_HOST:-127.0.0.1}"
PLUGINS="${FHS}/var/lib/cofiswarm/observer/plugins"
LOGS="${FHS}/var/log/cofiswarm/agent_logs"

[[ -d "$PLUGINS" ]] || { echo "fail: missing $PLUGINS (run make render-config)" >&2; exit 1; }
count="$(find "$PLUGINS" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')"
[[ "$count" -ge 3 ]] || { echo "fail: expected >=3 observer plugins, got $count" >&2; exit 1; }
[[ -d "$LOGS" ]] || { echo "fail: missing $LOGS" >&2; exit 1; }

curl -sf --max-time 5 "http://${HOST}:8016/healthz" >/dev/null || {
  echo "fail: observer :8016 not healthy" >&2; exit 1
}
curl -sf --max-time 5 "http://${HOST}:8016/v1/plugins" | grep -q metrics.yaml || {
  echo "fail: /v1/plugins missing metrics.yaml" >&2; exit 1
}
curl -sf --max-time 5 "http://${HOST}:8016/metrics" | grep -q cofiswarm || {
  echo "fail: /metrics stub missing" >&2; exit 1
}

echo "ok: observer ops — ${count} plugins, metrics :8016"
