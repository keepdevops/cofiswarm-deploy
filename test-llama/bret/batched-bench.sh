#!/bin/bash
# batched-bench.sh - Launcher for llama-batched-bench (server throughput scaling)
# Measures how throughput scales with parallel sequences — informs the
# --parallel slot count in start-server.sh.

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-batched-bench"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"   # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

N_PROMPT="128,512"        # prompt-token counts to test (-npp)
N_GEN="128"               # generation-token counts to test (-ntg)
N_PARALLEL="1,2,4,8"      # parallel sequence counts to test (-npl)

CTX_SIZE=8192             # must be >= max(N_PROMPT + N_GEN) * max(N_PARALLEL)
BATCH_SIZE=2048
UBATCH_SIZE=512
GPU_LAYERS=99
OUTPUT_FORMAT=md          # md | jsonl

echo "=== llama.cpp Batched-Bench Launcher ==="
echo "Binary     : $BINARY_PATH"
echo "Model      : $MODEL_PATH"
echo "Prompt     : $N_PROMPT  Gen: $N_GEN"
echo "Parallel   : $N_PARALLEL sequences"
echo "Context    : $CTX_SIZE"
echo "========================================"

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-batched-bench not found at $BINARY_PATH"
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/"
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH"
    echo "Available models:"
    ls -lh "$MODEL_DIR/" 2>/dev/null || echo "   (models folder empty)"
    exit 1
fi

# Run the batched benchmark
"$BINARY_PATH" \
  -m "$MODEL_PATH" \
  -c $CTX_SIZE \
  -b $BATCH_SIZE \
  -ub $UBATCH_SIZE \
  -npp "$N_PROMPT" \
  -ntg "$N_GEN" \
  -npl "$N_PARALLEL" \
  --n-gpu-layers $GPU_LAYERS \
  --output-format $OUTPUT_FORMAT
