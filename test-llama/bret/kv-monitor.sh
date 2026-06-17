#!/bin/bash
# kv-monitor.sh - live per-slot KV-cache usage for a running llama-server.
#
# Polls /slots (and /metrics if the server was started with --metrics) and prints
# a refreshing table: each slot's state, prompt/cached/decoded tokens, and KV
# occupancy as used/ctx with a bar. Gives you visibility into the parallel=4
# server that the raw JSON endpoints don't.
#
# Note: /slots reports the ACTIVE request per slot; an idle slot shows 0 used even
# if its KV is retained for prompt-cache reuse. Busy slots show true occupancy.
#
# Usage:
#   ./kv-monitor.sh                 # refresh every 2s until Ctrl-C
#   INTERVAL=1 ./kv-monitor.sh      # faster refresh
#   ITERS=1 ./kv-monitor.sh         # print once and exit (for scripting)

set -euo pipefail

# ====================== CONFIG ======================
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8095}"
API_KEY="${API_KEY:-}"        # must match the server's --api-key, if any
INTERVAL="${INTERVAL:-2}"     # seconds between refreshes
ITERS="${ITERS:-0}"           # 0 = loop forever; N = print N times then exit

BASE="http://$HOST:$PORT"

command -v python3 >/dev/null 2>&1 || { echo "❌ Error: python3 is required." >&2; exit 1; }
command -v curl    >/dev/null 2>&1 || { echo "❌ Error: curl is required." >&2; exit 1; }

# curl wrapper: attach auth when configured.
fetch() {
    local url="$1"
    if [ -n "$API_KEY" ]; then
        curl -sS -f -H "Authorization: Bearer $API_KEY" "$url"
    else
        curl -sS -f "$url"
    fi
}

# Fail loudly if the server is not reachable.
if ! fetch "$BASE/health" >/dev/null 2>&1; then
    echo "❌ Error: server not reachable at $BASE/health" >&2
    echo "   Start it first: ./start-kvquant.sh" >&2
    exit 1
fi

render() {
    local slots metrics
    if ! slots="$(fetch "$BASE/slots" 2>/dev/null)"; then
        echo "❌ Error: GET $BASE/slots failed (start the server with --slots)." >&2
        return 1
    fi
    metrics="$(fetch "$BASE/metrics" 2>/dev/null || true)"

    # Program fed via a single-quoted heredoc so it can use both quote styles;
    # data is passed through env vars (never the bash command line).
    KVM_SLOTS="$slots" KVM_METRICS="$metrics" KVM_BASE="$BASE" python3 - <<'PY'
import os, json, sys

try:
    slots = json.loads(os.environ["KVM_SLOTS"])
except Exception as e:
    print("Error: could not parse /slots JSON:", e, file=sys.stderr); sys.exit(1)

def bar(pct, width=24):
    fill = int(round(pct / 100 * width))
    return "#" * fill + "." * (width - fill)

print("=== KV monitor — {} === (Ctrl-C to stop)".format(os.environ.get("KVM_BASE", "")))
print("{:>4} {:<5} {:>7} {:>7} {:>7} {:>12} {:>5}  occupancy".format(
    "slot", "state", "prompt", "cached", "decode", "used/ctx", "%"))
print("-" * 84)

tot_used = tot_cap = 0
for s in slots:
    nctx  = s.get("n_ctx", 0) or 0
    ptok  = s.get("n_prompt_tokens", 0) or 0
    cache = s.get("n_prompt_tokens_cache", 0) or 0
    nt    = s.get("next_token") or [{}]
    dec   = (nt[0] or {}).get("n_decoded", 0) or 0
    used  = ptok + dec
    pct   = (100 * used / nctx) if nctx else 0
    state = "BUSY" if s.get("is_processing") else "idle"
    tot_used += used; tot_cap += nctx
    print("{:>4} {:<5} {:>7} {:>7} {:>7} {:>5}/{:<6} {:>4.0f}%  {}".format(
        s.get("id", "?"), state, ptok, cache, dec, used, nctx, pct, bar(pct)))

opct = (100 * tot_used / tot_cap) if tot_cap else 0
print("-" * 84)
print("{:>4} {:<5} {:>7} {:>7} {:>7} {:>5}/{:<6} {:>4.0f}%  {}".format(
    "ALL", "", "", "", "", tot_used, tot_cap, opct, bar(opct)))

# Surface server-wide KV metrics when --metrics is enabled.
wanted = {
    "llamacpp:kv_cache_usage_ratio": "kv usage ratio",
    "llamacpp:kv_cache_tokens": "kv tokens",
    "llamacpp:requests_processing": "requests processing",
    "llamacpp:requests_deferred": "requests deferred",
}
found = {}
for line in os.environ.get("KVM_METRICS", "").splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = line.split()
    if len(parts) == 2 and parts[0] in wanted:
        found[wanted[parts[0]]] = parts[1]
print()
if found:
    print("metrics:", "  ".join("{}={}".format(k, v) for k, v in found.items()))
else:
    print("metrics: (enable ENABLE_METRICS=1 in start-kvquant.sh for server-wide KV stats)")
PY
}

# Clear screen between frames only when looping interactively.
clear_screen() { printf '\033[H\033[2J'; }

trap 'echo; echo "stopped."; exit 0' INT

count=0
while :; do
    [ "$ITERS" != "1" ] && clear_screen
    if ! render; then exit 1; fi
    count=$((count+1))
    if [ "$ITERS" != "0" ] && [ "$count" -ge "$ITERS" ]; then break; fi
    sleep "$INTERVAL"
done
