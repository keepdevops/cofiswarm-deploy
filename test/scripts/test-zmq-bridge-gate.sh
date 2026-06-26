#!/usr/bin/env bash
# zmq-bridge ops gate. The stack runs the bridge with COFISWARM_BUS=zmq (compose/stack.yml):
# HTTP control plane on :5555, ingress SUB :5556, egress PUB :5557, ROUTER :5558. This gate
# checks the control plane (topics + publish) AND the real ZMQ egress wire end-to-end — a
# native ZMQ SUB on :5557 must receive a frame published via /v1/publish, proving the carrier
# actually forwards over the socket and not just that the HTTP endpoint returns 200.
set -euo pipefail
HOST="${COFISWARM_SERVICE_HOST:-127.0.0.1}"
BASE="http://${HOST}:5555"
EGRESS_PORT="${COFISWARM_ZMQ_EGRESS_PORT:-5557}"

# --- Control plane: reachable, declares topics, accepts publish -------------------------
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

# --- Real ZMQ egress wire: native SUB on :5557 receives a published frame ----------------
# The probe is the egress-probe helper from the sibling cofiswarm-zmq-bridge repo (it carries
# the zmq4 dep). If the Go toolchain or that source is unavailable the wire check is skipped
# with an explicit, loud reason rather than silently passing — the HTTP checks above still ran.
REPOS="${COFISWARM_REPOS_ROOT:-$HOME/cofiswarm/repos}"
BRIDGE_SRC="${REPOS}/cofiswarm-zmq-bridge"
PROBE="${COFISWARM_EGRESS_PROBE:-}"

if [ -z "$PROBE" ]; then
  if ! command -v go >/dev/null 2>&1; then
    echo "skip: real-wire egress check — no go toolchain (set COFISWARM_EGRESS_PROBE to a prebuilt egress-probe)" >&2
    exit 0
  fi
  if [ ! -d "${BRIDGE_SRC}/test/cmd/egress-probe" ]; then
    echo "skip: real-wire egress check — egress-probe source not found at ${BRIDGE_SRC} (set COFISWARM_REPOS_ROOT or COFISWARM_EGRESS_PROBE)" >&2
    exit 0
  fi
  PROBE="$(mktemp -t egress-probe.XXXXXX)"
  trap 'rm -f "$PROBE" 2>/dev/null || true' EXIT
  ( cd "$BRIDGE_SRC" && go build -o "$PROBE" ./test/cmd/egress-probe ) || {
    echo "fail: could not build egress-probe from ${BRIDGE_SRC}" >&2
    exit 1
  }
fi

echo "== real-wire: native SUB on ${HOST}:${EGRESS_PORT} <- /v1/publish =="
"$PROBE" "tcp://${HOST}:${EGRESS_PORT}" 8 >/tmp/zmq-bridge-egress.out 2>&1 &
SUB=$!
sleep 0.8
# Resend our frame: PUB->SUB is a slow joiner, so inject until the probe receives or we give up.
for _ in $(seq 1 20); do
  kill -0 "$SUB" 2>/dev/null || break
  curl -sf --max-time 5 -X POST "${BASE}/v1/publish" \
    -H 'Content-Type: application/json' \
    -d '{"topic":"swarm.kvpool.pressure","payload":{"egress_probe":true}}' >/dev/null || true
  sleep 0.3
done
wait "$SUB" || {
  echo "fail: no frame received on egress wire ${HOST}:${EGRESS_PORT} — carrier not forwarding" >&2
  cat /tmp/zmq-bridge-egress.out >&2
  exit 1
}
grep -q '^GOT swarm\.' /tmp/zmq-bridge-egress.out || {
  echo "fail: unexpected egress probe output" >&2
  cat /tmp/zmq-bridge-egress.out >&2
  exit 1
}
echo "ok: zmq-bridge real wire — egress SUB received $(cat /tmp/zmq-bridge-egress.out)"
