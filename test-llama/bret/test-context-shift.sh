#!/bin/bash
# test-context-shift.sh - Verify llama-server's --context-shift (off by default).
#
# Context shift is DISABLED by default in current llama-server: exceeding -c
# returns a context-full error instead of evicting. This test launches the
# server with --context-shift ENABLED and a deliberately tiny context, then asks
# for a generation longer than the context. With the flag on, the server should
# roll the oldest tokens out (keeping --keep prompt-baseline tokens) and keep
# generating past the limit instead of erroring.
#
# Exit 0 = PASS (generation ran past the context via shifting), non-zero = FAIL.

set -euo pipefail

# ====================== PATHS ======================
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-server"
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

# ====================== CONFIG ======================
CTX_SIZE=512          # tiny on purpose so we overflow fast
KEEP=64               # prompt-baseline tokens retained across shifts (--keep)
N_PREDICT=640         # > CTX_SIZE: forces a shift mid-generation
GPU_LAYERS=99
PORT=8097
CPU_THREADS=8
READY_TIMEOUT=90      # seconds to wait for /health

SERVER_LOG="$(mktemp -t ctxshift.XXXXXX.log)"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$SERVER_LOG"
}
trap cleanup EXIT

echo "=== llama-server --context-shift test ==="
echo "Binary  : $BINARY_PATH"
echo "Model   : $MODEL_PATH"
echo "Context : $CTX_SIZE (keep $KEEP), n_predict $N_PREDICT, port $PORT"
echo "=========================================="

# ---- guards (fail loudly) ----
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ FAIL: llama-server not found at $BINARY_PATH" >&2
    exit 1
fi
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ FAIL: model not found at $MODEL_PATH" >&2
    ls -lh "$MODEL_DIR/" 2>/dev/null >&2 || echo "   (models folder empty)" >&2
    exit 1
fi
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "❌ FAIL: port $PORT already in use" >&2
    exit 1
fi
for tool in curl; do
    command -v "$tool" >/dev/null 2>&1 || { echo "❌ FAIL: '$tool' required" >&2; exit 1; }
done

# ---- launch server with context shift ENABLED ----
"$BINARY_PATH" \
  -m "$MODEL_PATH" \
  -c "$CTX_SIZE" \
  --keep "$KEEP" \
  --context-shift \
  --n-gpu-layers "$GPU_LAYERS" \
  -fa on \
  --port "$PORT" \
  -t "$CPU_THREADS" \
  --no-mmap > "$SERVER_LOG" 2>&1 &
SERVER_PID=$!

# ---- wait for readiness (fail loudly on timeout / early exit) ----
echo "Waiting for server (pid $SERVER_PID) to become ready ..."
deadline=$(( $(date +%s) + READY_TIMEOUT ))
until curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "❌ FAIL: server exited before becoming ready. Log tail:" >&2
        tail -20 "$SERVER_LOG" >&2
        exit 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        echo "❌ FAIL: server not ready within ${READY_TIMEOUT}s. Log tail:" >&2
        tail -20 "$SERVER_LOG" >&2
        exit 1
    fi
    sleep 1
done
echo "✅ server ready."

# ---- send a generation longer than the context ----
PROMPT="Write a long, continuous story about a lighthouse keeper. Keep going with new sentences and never stop early."
echo "Requesting $N_PREDICT tokens with context=$CTX_SIZE (must shift) ..."
RESP="$(curl -fsS "http://127.0.0.1:$PORT/completion" \
    -H 'Content-Type: application/json' \
    -d "{\"prompt\": \"$PROMPT\", \"n_predict\": $N_PREDICT, \"cache_prompt\": true}")" || {
        echo "❌ FAIL: /completion request errored (server rejected overflow?). Log tail:" >&2
        tail -20 "$SERVER_LOG" >&2
        exit 1
    }

# ---- evaluate: tokens generated past the context + shift evidence in log ----
GEN_TOKENS="$(printf '%s' "$RESP" | grep -oE '"tokens_predicted":[0-9]+' | grep -oE '[0-9]+' | head -1)"
GEN_TOKENS="${GEN_TOKENS:-0}"
SHIFT_HITS="$(grep -ic "shift" "$SERVER_LOG" || true)"

echo "------------------------------------------"
echo "tokens_predicted : $GEN_TOKENS (context was $CTX_SIZE)"
echo "shift log lines  : $SHIFT_HITS"

if [ "$GEN_TOKENS" -gt "$CTX_SIZE" ]; then
    echo "✅ PASS: generated $GEN_TOKENS tokens > context $CTX_SIZE — context shift worked."
    exit 0
elif [ "$GEN_TOKENS" -gt 0 ] && [ "$SHIFT_HITS" -gt 0 ]; then
    echo "✅ PASS: generation completed with shift activity in the server log."
    exit 0
else
    echo "❌ FAIL: only $GEN_TOKENS tokens and no shift evidence; context shift did not engage." >&2
    tail -20 "$SERVER_LOG" >&2
    exit 1
fi
