#!/bin/bash
# start-tpquant.sh - llama-server with "TurboQuant" / "PolarQuant" KV-cache profiles.
#
# IMPORTANT - read this before assuming magic:
#   TurboQuant and PolarQuant are research KV-cache quantization algorithms
#   (2025 papers). They are NOT native quant types in llama.cpp. llama.cpp only
#   ships these real KV types via -ctk/-ctv:
#       f32 f16 bf16 q8_0 q4_0 q4_1 iq4_nl q5_0 q5_1
#   This script therefore APPROXIMATES each named method by mapping it onto the
#   nearest real llama.cpp KV types. It is an honest stand-in, not the actual
#   algorithm. The mapping rationale per profile:
#
#   turboquant : TurboQuant targets near-optimal MSE distortion at low bit-width
#                with symmetric treatment of K and V -> balanced q5_1 / q5_1
#                (~5.5 bits/elem, good error at ~2/3 the f16 KV memory).
#   polarquant : PolarQuant protects the RoPE-rotated KEY vectors (the outlier-
#                heavy ones) and tolerates coarser values -> keep K at q8_0
#                (near-lossless) and push V to q4_0 (aggressive).
#   q8_0       : near-lossless baseline, ~half the f16 KV memory.
#   f16        : reference, no KV quantization (for A/B perplexity comparison).
#
#   Flash Attention (-fa on) is REQUIRED for any quantized KV cache.
#
# Usage:
#   ./start-tpquant.sh                 # default profile (turboquant)
#   ./start-tpquant.sh polarquant      # pick a profile by name
#   PROFILE=q8_0 ./start-tpquant.sh    # or via env var

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
PORT=8096
CPU_THREADS=8

# Profile selection: arg 1 wins, then $PROFILE env, then default.
PROFILE="${1:-${PROFILE:-turboquant}}"

# ============ PROFILE -> REAL KV TYPE MAPPING ============
# Set K/V quant types and a human-readable note per named profile.
case "$PROFILE" in
  turboquant)
    KV_TYPE_K="q5_1"; KV_TYPE_V="q5_1"
    PROFILE_NOTE="approx of TurboQuant: balanced low-bit MSE-optimal (K=V=q5_1)"
    ;;
  polarquant)
    KV_TYPE_K="q8_0"; KV_TYPE_V="q4_0"
    PROFILE_NOTE="approx of PolarQuant: protect keys (K=q8_0), coarse values (V=q4_0)"
    ;;
  q8_0)
    KV_TYPE_K="q8_0"; KV_TYPE_V="q8_0"
    PROFILE_NOTE="near-lossless baseline (K=V=q8_0)"
    ;;
  f16)
    KV_TYPE_K="f16"; KV_TYPE_V="f16"
    PROFILE_NOTE="unquantized reference (K=V=f16)"
    ;;
  *)
    echo "❌ Error: unknown profile '$PROFILE'." >&2
    echo "   Valid profiles: turboquant | polarquant | q8_0 | f16" >&2
    exit 1
    ;;
esac

# f16 KV does not require/benefit from flash-attn quant path; quantized KV does.
FLASH_ATTN="on"
[ "$KV_TYPE_K" = "f16" ] && [ "$KV_TYPE_V" = "f16" ] && FLASH_ATTN="auto"

echo "=== llama.cpp Server (TurboQuant/PolarQuant KV profiles) ==="
echo "Binary   : $BINARY_PATH"
echo "Model    : $MODEL_PATH"
echo "Port     : $PORT"
echo "Profile  : $PROFILE"
echo "Mapping  : $PROFILE_NOTE"
echo "KV cache : K=$KV_TYPE_K V=$KV_TYPE_V (flash-attn $FLASH_ATTN, kv-unified)"
echo "NOTE     : profiles approximate the named research methods using real"
echo "           llama.cpp KV quant types; they are not the actual algorithms."
echo "==========================================================="

# ====================== GUARDS (fail loudly) ======================
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
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "❌ Error: port $PORT is already in use:" >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2
    exit 1
fi

# ====================== LAUNCH ======================
ARGS=(
  -m "$MODEL_PATH"
  -c "$CTX_SIZE"
  --n-gpu-layers "$GPU_LAYERS"
  --parallel "$PARALLEL_SLOTS"
  --cont-batching
  -fa "$FLASH_ATTN"
  --kv-unified
  -ctk "$KV_TYPE_K"
  -ctv "$KV_TYPE_V"
  --slots
  --port "$PORT"
  -t "$CPU_THREADS"
  --no-mmap
)

exec "$BINARY_PATH" "${ARGS[@]}"
