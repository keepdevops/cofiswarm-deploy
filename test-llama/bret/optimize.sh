#!/bin/bash
# optimize.sh - performance-tuned llama-server launcher (Apple Silicon / M3 Max).
#
# Bundles the optimization flags that actually move the needle (see the CLI help
# breakdown): all layers on Metal, flash-attn on, near-lossless half-size KV,
# tuned batch/threads, auto memory fit, and OPT-IN speculative decoding. Every
# knob is a variable below; advanced/opt-in features default OFF so this stays a
# safe drop-in. Verified against the installed binary's supported flags.

set -euo pipefail

# ====================== PATHS ======================
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-server"
MODEL_DIR="/Users/caribou/test-llama/models"
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

# ====================== CORE TUNING ======================
CTX_SIZE=8192
GPU_LAYERS="all"      # all layers on Metal (biggest single lever)
KV_TYPE_K="q8_0"      # near-lossless, ~half the KV memory of f16
KV_TYPE_V="q8_0"
BATCH=2048            # logical batch (prefill throughput)
UBATCH=512            # physical ubatch; raise if memory allows
CPU_THREADS=12        # M3 Max performance cores
PARALLEL_SLOTS=4      # concurrent sequences
PORT=8098
FIT="on"             # auto-shrink unset args to fit device memory

# ================= OPT-IN PERF FEATURES (default OFF) =================
USE_MLOCK=0           # 1 = pin model in RAM (steadier latency, no swap)
USE_NO_WARMUP=0       # 1 = skip warmup (faster start, slower first token)
USE_DIRECT_IO=0       # 1 = DirectIO model load (faster load if supported)
CACHE_RAM_MIB=""      # e.g. 16384 to cap prompt-cache RAM; "" = default

# Speculative decoding (decode-speed win). Two mutually-exclusive options:
#   A) draft model:  set DRAFT_MODEL + SPEC_TYPE=draft-simple (or draft-eagle3)
#   B) n-gram (no draft model): SPEC_TYPE=ngram-simple
SPEC_TYPE=""          # "" = off; e.g. "ngram-simple" or "draft-simple"
DRAFT_MODEL=""        # path to a small draft .gguf (only for draft-* spec types)

echo "=== llama-server (optimized) ==="
echo "Binary : $BINARY_PATH"
echo "Model  : $MODEL_PATH"
echo "Perf   : ngl=$GPU_LAYERS fa=on KV=$KV_TYPE_K/$KV_TYPE_V b=$BATCH ub=$UBATCH t=$CPU_THREADS fit=$FIT"
echo "Serve  : ctx=$CTX_SIZE parallel=$PARALLEL_SLOTS port=$PORT"
echo "Opt-in : mlock=$USE_MLOCK no-warmup=$USE_NO_WARMUP direct-io=$USE_DIRECT_IO spec=${SPEC_TYPE:-off}"
echo "================================"

# ---- guards (fail loudly) ----
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-server not found at $BINARY_PATH" >&2
    exit 1
fi
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: model not found at $MODEL_PATH" >&2
    ls -lh "$MODEL_DIR/" 2>/dev/null >&2 || echo "   (models folder empty)" >&2
    exit 1
fi
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "❌ Error: port $PORT already in use" >&2
    exit 1
fi
# Speculative sanity: draft-* needs a draft model; ngram-* must not have one.
if [ -n "$SPEC_TYPE" ]; then
    case "$SPEC_TYPE" in
        draft-*)
            if [ -z "$DRAFT_MODEL" ] || [ ! -f "$DRAFT_MODEL" ]; then
                echo "❌ Error: SPEC_TYPE=$SPEC_TYPE requires a valid DRAFT_MODEL" >&2
                exit 1
            fi ;;
        ngram-*) : ;;  # no draft model needed
        *) echo "❌ Error: unknown SPEC_TYPE '$SPEC_TYPE'" >&2; exit 1 ;;
    esac
fi

# ---- assemble args ----
ARGS=(
  -m "$MODEL_PATH"
  -c "$CTX_SIZE"
  --n-gpu-layers "$GPU_LAYERS"
  -fa on
  -ctk "$KV_TYPE_K"
  -ctv "$KV_TYPE_V"
  -b "$BATCH"
  -ub "$UBATCH"
  -t "$CPU_THREADS"
  --parallel "$PARALLEL_SLOTS"
  --cont-batching
  --fit "$FIT"
  --port "$PORT"
)

# opt-in flags
[ "$USE_MLOCK" = "1" ]     && ARGS+=( --mlock )
[ "$USE_NO_WARMUP" = "1" ] && ARGS+=( --no-warmup )
[ "$USE_DIRECT_IO" = "1" ] && ARGS+=( --direct-io )
[ -n "$CACHE_RAM_MIB" ]    && ARGS+=( --cache-ram "$CACHE_RAM_MIB" )
if [ -n "$SPEC_TYPE" ]; then
    ARGS+=( --spec-type "$SPEC_TYPE" )
    [ -n "$DRAFT_MODEL" ] && ARGS+=( --model-draft "$DRAFT_MODEL" )
fi

exec "$BINARY_PATH" "${ARGS[@]}"
