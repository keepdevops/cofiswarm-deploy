#!/bin/bash
# kv-defrag-bench.sh - measure throughput under slot churn across --defrag-thold values.
#
# Your production server runs parallel=4 with --defrag-thold unset. Slots that
# finish at different times leave holes in the unified KV buffer; defragmentation
# compacts them when the free fraction exceeds the threshold. This launches a
# throwaway server per threshold, drives a fragmenting concurrent workload, and
# reports prefill latency + generation throughput so you can pick a value.
#
# Each server is started fresh on its own port and killed after; the production
# 8095 server is never touched.
#
# Usage:
#   ./kv-defrag-bench.sh            # sweep THOLDS below
#   WAVES=8 ./kv-defrag-bench.sh    # more churn per threshold

set -euo pipefail

# ====================== PATHS ======================
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-server"
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

# ====================== CONFIG ======================
THOLDS=(-1 0.1 0.5)        # -1 = defrag disabled; sweep these --defrag-thold values
CTX_SIZE=8192
PARALLEL_SLOTS=4
GPU_LAYERS=99
CPU_THREADS=8
KV_TYPE_K="q8_0"
KV_TYPE_V="q8_0"
BASE_PORT="${BASE_PORT:-8110}"   # first throwaway server port; increments per thold
WAVES="${WAVES:-6}"              # workload waves (concurrency = PARALLEL_SLOTS per wave)
REPORT="$(dirname "$0")/kv-defrag-results.md"

command -v python3 >/dev/null 2>&1 || { echo "❌ Error: python3 is required." >&2; exit 1; }

# ====================== PREFLIGHT ======================
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-server not found at $BINARY_PATH" >&2
    exit 1
fi
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH" >&2
    ls -lh "$MODEL_DIR/" 2>/dev/null >&2 || echo "   (models folder empty)" >&2
    exit 1
fi

SERVER_PID=""
# Always clean up the throwaway server, even on error/Ctrl-C.
cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    SERVER_PID=""
}
trap 'cleanup; echo; echo "interrupted."; exit 1' INT TERM

# Launch a throwaway server with a given defrag threshold; sets SERVER_PID.
launch_server() {
    local thold="$1" port="$2" log="$3"
    "$BINARY_PATH" \
        -m "$MODEL_PATH" -c "$CTX_SIZE" --n-gpu-layers "$GPU_LAYERS" \
        --parallel "$PARALLEL_SLOTS" --cont-batching -fa on --kv-unified \
        -ctk "$KV_TYPE_K" -ctv "$KV_TYPE_V" --defrag-thold "$thold" \
        --slots -t "$CPU_THREADS" --no-mmap --port "$port" > "$log" 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 1 90); do
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo "❌ Error: server (thold=$thold) died on startup. Log:" >&2
            tail -15 "$log" >&2
            return 1
        fi
        if curl -sS -f -o /dev/null "http://127.0.0.1:$port/health" 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    echo "❌ Error: server (thold=$thold) never became healthy on port $port." >&2
    return 1
}

# Drive a fragmenting workload; echo "<avg_prompt_ms> <avg_gen_tps> <n_ok>".
run_workload() {
    local port="$1" tmp; tmp="$(mktemp -d)"
    local w slot len pred body
    for w in $(seq 1 "$WAVES"); do
        local pids=()
        for slot in $(seq 0 $((PARALLEL_SLOTS-1))); do
            # Varying prompt/gen lengths => slots free at different times => holes.
            len=$(( (RANDOM % 700) + 60 ))
            pred=$(( (RANDOM % 120) + 16 ))
            body="$(python3 -c "import json;print(json.dumps({'prompt':'token '*$len,'n_predict':$pred,'id_slot':$slot,'cache_prompt':False}))")"
            curl -sS -X POST "http://127.0.0.1:$port/completion" \
                -H "Content-Type: application/json" -d "$body" \
                -o "$tmp/$w-$slot.json" 2>/dev/null &
            pids+=($!)
        done
        # Fail loudly if any request errors out.
        for p in "${pids[@]}"; do
            if ! wait "$p"; then echo "⚠️  a /completion request failed (wave $w)." >&2; fi
        done
    done
    python3 - "$tmp"/*.json <<'PY'
import sys, json, statistics as st
pm, tps = [], []
for f in sys.argv[1:]:
    try:
        d = json.load(open(f)); t = d.get("timings", {})
        if "prompt_ms" in t: pm.append(t["prompt_ms"])
        if "predicted_per_second" in t: tps.append(t["predicted_per_second"])
    except Exception as e:
        print(f"WARN: could not parse {f}: {e}", file=sys.stderr)
if pm:
    print(f"{st.mean(pm):.1f} {st.mean(tps) if tps else 0:.1f} {len(pm)}")
else:
    print("n/a n/a 0")
PY
    rm -rf "$tmp"
}

echo "=== --defrag-thold sweep ==="
echo "Model : $MODEL_NAME"
echo "Server: ctx=$CTX_SIZE parallel=$PARALLEL_SLOTS KV=$KV_TYPE_K/$KV_TYPE_V fa=on unified"
echo "Load  : $WAVES waves x $PARALLEL_SLOTS concurrent reqs, varying lengths, cache off"
echo "Tholds: ${THOLDS[*]}"
echo "==========================="

{
    echo "# --defrag-thold sweep"
    echo
    echo "Model: \`$MODEL_NAME\`  •  ctx=$CTX_SIZE parallel=$PARALLEL_SLOTS KV=$KV_TYPE_K/$KV_TYPE_V  •  $WAVES waves"
    echo "Date: $(date +%Y-%m-%d)"
    echo
    echo "| defrag-thold | avg prefill ms | avg gen t/s | reqs |"
    echo "|-------------:|---------------:|------------:|-----:|"
} | tee "$REPORT"

port=$BASE_PORT
for thold in "${THOLDS[@]}"; do
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        echo "❌ Error: port $port already in use; set BASE_PORT to a free port." >&2
        exit 1
    fi
    log="$(mktemp)"
    echo "▶ thold=$thold on port $port ..." >&2
    if ! launch_server "$thold" "$port" "$log"; then cleanup; rm -f "$log"; exit 1; fi
    read -r pm tps n < <(run_workload "$port")
    cleanup
    rm -f "$log"
    printf "| %12s | %14s | %11s | %4s |\n" "$thold" "$pm" "$tps" "$n" | tee -a "$REPORT"
    port=$((port+1))
done

echo
echo "✅ Sweep complete. Table written to $REPORT"
echo "Pick the thold with the best gen t/s and stable prefill; set it in start-kvquant.sh."
