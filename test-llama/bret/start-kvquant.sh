#!/bin/bash
# start-kvquant.sh - llama-server with unified KV cache + quantized KV cache.
#
# "kv unified"  -> --kv-unified : single KV buffer shared across all sequences.
# "polarquant"  -> there is NO "polarquant" type in llama.cpp. This script
#                  interprets it as KV-cache quantization via -ctk/-ctv.
#                  Valid types: f32 f16 bf16 q8_0 q4_0 q4_1 iq4_nl q5_0 q5_1
#                  q8_0 = near-lossless, ~half the KV memory of f16 (recommended).
#                  Flash Attention (-fa on) is required for quantized KV cache.

set -euo pipefail

# ====================== PATHS ======================
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-server"
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

# ====================== CONFIG ======================
CTX_SIZE=8192
PARALLEL_SLOTS=4
GPU_LAYERS=99
PORT=8095
CPU_THREADS=8

# KV cache quantization type (the "polarquant" knob).
KV_TYPE_K="q8_0"
KV_TYPE_V="q8_0"

# KV token recycling: reuse cached KV blocks across requests by shifting
# matching token chunks instead of recomputing them (--cache-reuse).
# Value = min chunk size (tokens) to attempt reusing; 0 disables.
CACHE_REUSE=256

# KV-cache defragmentation threshold (--defrag-thold). -1 disables defrag.
# kv-defrag-bench.sh found -1 wins here (lowest prefill, highest gen t/s):
# with --kv-unified, defrag adds overhead without payoff. (-dt is DEPRECATED.)
DEFRAG_THOLD=-1

# Persistent KV cache: directory where slots can save/restore their KV state to
# disk (survives restarts). Enables /slots?action=save|restore|erase, driven by
# slot-cache.sh. --slots exposes per-slot status for slot-cache.sh status/list.
SLOT_SAVE_PATH="/Users/caribou/test-llama/kv-slots"

# ================= SERVING HARDENING (opt-in) =================
# All disabled by default so localhost dev keeps working untouched.
# Set BIND_HOST to 0.0.0.0 + an API_KEY together before exposing on a network.
BIND_HOST=""          # e.g. "0.0.0.0" to listen on the LAN; "" = localhost only
API_KEY=""            # require this Bearer token; "" = no auth (localhost only!)
ENABLE_METRICS=0      # 1 = expose Prometheus /metrics endpoint
USE_MLOCK=0           # 1 = pin model in RAM (no swap) for steadier latency
PROC_PRIO=""          # process priority: low(-1) normal(0) medium(1) high(2); "" = default

# Refuse to bind a non-localhost address without an API key (fail loudly).
if [ -n "$BIND_HOST" ] && [ "$BIND_HOST" != "127.0.0.1" ] && [ "$BIND_HOST" != "localhost" ] && [ -z "$API_KEY" ]; then
    echo "❌ Error: BIND_HOST=$BIND_HOST exposes the server but API_KEY is empty." >&2
    echo "   Set API_KEY before binding a non-localhost address." >&2
    exit 1
fi

echo "=== llama.cpp Server (KV-unified + quantized KV) ==="
echo "Binary   : $BINARY_PATH"
echo "Model    : $MODEL_PATH"
echo "Port     : $PORT"
echo "KV cache : unified, K=$KV_TYPE_K V=$KV_TYPE_V (flash-attn on)"
echo "Recycling: --cache-reuse $CACHE_REUSE"
echo "Slot save: $SLOT_SAVE_PATH (persistent KV via slot-cache.sh)"
echo "Hardening: host=${BIND_HOST:-127.0.0.1} auth=$([ -n "$API_KEY" ] && echo on || echo off)" \
     "metrics=$ENABLE_METRICS mlock=$USE_MLOCK prio=${PROC_PRIO:-default}"
echo "===================================================="

# Fail loudly on missing binary / model.
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-server not found at $BINARY_PATH" >&2
    exit 1
fi
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH" >&2
    echo "Available models:" >&2
    ls -lh "$MODEL_DIR/" 2>/dev/null >&2 || echo "   (models folder empty)" >&2
    exit 1
fi

# Fail loudly on an already-bound port.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "❌ Error: port $PORT is already in use:" >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2
    exit 1
fi

# Ensure the slot-save directory exists (fail loudly if it can't be created).
if ! mkdir -p "$SLOT_SAVE_PATH"; then
    echo "❌ Error: could not create slot-save directory $SLOT_SAVE_PATH" >&2
    exit 1
fi

# Stamp this server's KV config so slot-cache.sh can verify provenance on restore.
# The KV-quant type is not exposed via the server API, so it must be recorded here.
if ! cat > "$SLOT_SAVE_PATH/.server-kv.env" <<EOF
KV_TYPE_K=$KV_TYPE_K
KV_TYPE_V=$KV_TYPE_V
MODEL_NAME=$MODEL_NAME
CTX_SIZE=$CTX_SIZE
EOF
then
    echo "❌ Error: could not write KV descriptor to $SLOT_SAVE_PATH/.server-kv.env" >&2
    exit 1
fi

# Base arguments.
ARGS=(
  -m "$MODEL_PATH"
  -c "$CTX_SIZE"
  --n-gpu-layers "$GPU_LAYERS"
  --parallel "$PARALLEL_SLOTS"
  --cont-batching
  -fa on
  --kv-unified
  -ctk "$KV_TYPE_K"
  -ctv "$KV_TYPE_V"
  --cache-reuse "$CACHE_REUSE"
  --defrag-thold "$DEFRAG_THOLD"
  --slot-save-path "$SLOT_SAVE_PATH"
  --slots
  --port "$PORT"
  -t "$CPU_THREADS"
  --no-mmap
)

# Opt-in hardening flags appended only when configured.
[ -n "$BIND_HOST" ]   && ARGS+=( --host "$BIND_HOST" )
[ -n "$API_KEY" ]     && ARGS+=( --api-key "$API_KEY" )
[ "$ENABLE_METRICS" = "1" ] && ARGS+=( --metrics )
[ "$USE_MLOCK" = "1" ]      && ARGS+=( --mlock )
[ -n "$PROC_PRIO" ]   && ARGS+=( --prio "$PROC_PRIO" )

exec "$BINARY_PATH" "${ARGS[@]}"
