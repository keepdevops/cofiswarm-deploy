#!/usr/bin/env bash
# One-command cold-start of the live cofiswarm stack (option-B topology), in order:
#   1. host llama/MLX inference servers (Metal, outside compose)
#   2. Docker control plane: launcher compose + the option-B overlay
#   3. broker-free responder presence announcer
# Idempotent and health-gated; safe to re-run. The Docker containers carry
# restart: unless-stopped (so they self-heal across reboots) — this is for cold starts
# and manual bring-up. Host inference reboot survival is the com.cofiswarm.host-inference
# LaunchAgent; see install-host-inference-launchd.sh.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="$(cd "$ROOT/.." && pwd)"
LAUNCHER="${COFISWARM_LAUNCHER_COMPOSE:-$REPOS/cofiswarm-launcher/compose}"
OVERRIDE="$ROOT/compose/dispatch-host-infer.override.yml"
LOGDIR="${COFISWARM_INFER_LOGDIR:-$HOME/Library/Logs/cofiswarm}"
mkdir -p "$LOGDIR"

echo "==> 1/3 host inference servers"
"$ROOT/scripts/start-host-inference.sh"

echo "==> 2/3 Docker control plane (launcher + option-B overlay)"
# --no-deps + explicit list: the observability plane (observer/zmq-bridge/gateway from
# stack.yml) is already running; nats is intentionally skipped (zmq plan, no request/reply).
( cd "$LAUNCHER" && docker compose -f docker-compose.yml -f "$OVERRIDE" up -d --no-build --no-deps \
    agent-registry kvpool slot-manager dispatch \
    mode-flat mode-pipeline mode-cascade mode-router )

echo "==> 3/3 responder presence announcer"
if pgrep -f announce-responders.sh >/dev/null 2>&1; then
  echo "ok: announcer already running"
else
  nohup "$ROOT/compose/announce-responders.sh" >"$LOGDIR/announce-responders.log" 2>&1 &
  disown
  echo "started: announcer pid $!"
fi

echo "==> health gate"
fail=0
for hp in 18021:mode-flat 8022:mode-pipeline 8023:mode-cascade 8024:mode-router \
          8010:dispatch 8016:observer; do
  port="${hp%%:*}"; name="${hp##*:}"
  path="/healthz"; [[ "$name" == dispatch ]] && path="/api/health"
  code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:${port}${path}" 2>/dev/null)
  if [[ "$code" == "200" ]]; then echo "  ok: $name :$port"; else echo "  DOWN: $name :$port ($code)"; fail=1; fi
done
for p in 8083 8084 8085 8086 8087; do
  code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$p/v1/models" 2>/dev/null)
  [[ "$code" == "200" ]] && echo "  ok: llama/mlx :$p" || { echo "  DOWN: inference :$p ($code)"; fail=1; }
done
[[ "$fail" == 0 ]] && echo "==> stack UP" || { echo "==> stack came up with failures (see above)" >&2; exit 1; }
