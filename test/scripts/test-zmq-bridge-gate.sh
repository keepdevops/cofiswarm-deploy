#!/usr/bin/env bash
# Sprint 39: zmq-bridge topic registry on :5555.
set -euo pipefail
HOST="${COFISWARM_SERVICE_HOST:-127.0.0.1}"
BASE="http://${HOST}:5555"

curl -sf --max-time 5 "${BASE}/healthz" >/dev/null || {
  echo "fail: zmq-bridge not reachable at ${BASE}" >&2
  exit 1
}

for topic in swarm.kvpool.evict swarm.dispatch.session swarm.infer.llama.metrics; do
  curl -sf --max-time 5 "${BASE}/v1/topics" | grep -q "$topic" || {
    echo "fail: missing topic $topic" >&2
    exit 1
  }
done

out="$(curl -sf --max-time 5 -X POST "${BASE}/v1/publish" \
  -H 'Content-Type: application/json' \
  -d '{"topic":"swarm.kvpool.pressure","payload":{"probe":true}}')"
echo "$out" | grep -q '"ok"' || {
  echo "fail: /v1/publish" >&2
  echo "$out" >&2
  exit 1
}
echo "ok: zmq-bridge ops — topics + publish"
