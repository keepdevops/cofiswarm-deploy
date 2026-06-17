#!/bin/bash
# start-bench.sh - Launcher for llama-bench (throughput benchmark)

# Paths
BINARY_PATH="/Users/Shared/llama/llama.cpp/build/bin/llama-bench"
MODEL_DIR="/Users/caribou/test-llama/models"

# ====================== CONFIG ======================
MODEL_NAME="Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"   # ← Change this
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"

N_PROMPT=512        # prompt (prefill) tokens to benchmark
N_GEN=128           # generation tokens to benchmark
GPU_LAYERS=99
REPETITIONS=5       # runs per test, results are averaged
OUTPUT_FORMAT=md    # csv | json | jsonl | md | sql

echo "=== llama.cpp Benchmark Launcher ==="
echo "Binary     : $BINARY_PATH"
echo "Model      : $MODEL_PATH"
echo "Prompt     : $N_PROMPT tokens (prefill)"
echo "Generate   : $N_GEN tokens"
echo "Reps       : $REPETITIONS"
echo "===================================="

# Check binary exists
if [ ! -f "$BINARY_PATH" ]; then
    echo "❌ Error: llama-bench not found at $BINARY_PATH"
    echo "Make sure it is built in /Users/Shared/llama/llama.cpp/build/bin/"
    exit 1
fi

# Check model exists
if [ ! -f "$MODEL_PATH" ]; then
    echo "❌ Error: Model not found at $MODEL_PATH"
    echo "Available models:"
    ls -lh "$MODEL_DIR/" 2>/dev/null || echo "   (models folder empty)"
    echo "Please copy your .gguf model into $MODEL_DIR/"
    exit 1
fi

# Run the benchmark
"$BINARY_PATH" \
  -m "$MODEL_PATH" \
  -p $N_PROMPT \
  -n $N_GEN \
  --n-gpu-layers $GPU_LAYERS \
  -r $REPETITIONS \
  -o $OUTPUT_FORMAT \
  --progress
