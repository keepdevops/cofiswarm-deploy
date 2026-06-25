#!/usr/bin/env bash
# Broker-free presence announcer (zmq plan): the bus-responders are NATS-only, but the running
# zmq-bridge is COFISWARM_BUS=zmq and carries no NATS — so we register each responder's presence
# directly via the bridge's HTTP /v1/publish, exactly like dispatch/agent-registry do. Re-announce
# faster than the observer's 45s liveness TTL so the roster keeps them ONLINE. Ctrl-C / SIGTERM
# publishes a clean offline goodbye for each.
set -uo pipefail
BRIDGE="${COFISWARM_BRIDGE_URL:-http://127.0.0.1:5555}"
INTERVAL="${ANNOUNCE_INTERVAL:-15}"

# component_id : model-name (roster's "model" column = info.name)
RESPONDERS=(
  "responder-coder7b:coder7b"
  "responder-llama8b:llama8b"
  "responder-gemma9b:gemma9b"
  "responder-gemma2b:gemma2b"
  "responder-mlx1b:mlx1b"
  "responder-flat:flat"
  "responder-pipeline:pipeline"
  "responder-cascade:cascade"
  "responder-router:router"
  # cofiswarm-ui is an nginx-served React frontend (:3000) — it can't self-announce, so we
  # publish its presence here too (broker-free), same as the NATS-only responders.
  "ui:web-ui"
)

publish() { # id status name
  curl -s -o /dev/null -w "" -X POST "$BRIDGE/v1/publish" -H 'content-type: application/json' \
    -d "{\"topic\":\"swarm.observer.presence\",\"payload\":{\"component_id\":\"$1\",\"status\":\"$2\",\"info\":{\"name\":\"$3\"}}}" \
    || echo "[announce] WARN: publish failed for $1" >&2
}

goodbye() {
  for r in "${RESPONDERS[@]}"; do publish "${r%%:*}" offline "${r##*:}"; done
  echo "[announce] sent offline goodbye for ${#RESPONDERS[@]} responders"
  exit 0
}
trap goodbye INT TERM

echo "[announce] announcing ${#RESPONDERS[@]} responders to $BRIDGE every ${INTERVAL}s"
while true; do
  for r in "${RESPONDERS[@]}"; do publish "${r%%:*}" online "${r##*:}"; done
  sleep "$INTERVAL"
done
